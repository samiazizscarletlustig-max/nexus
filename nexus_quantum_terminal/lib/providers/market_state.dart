// ============================================================================
//  NEXUS v13.10 — market_state.dart
//  ChangeNotifier state manager bridging NexusApiClient and the UI.
//
//  v13.10 changes:
//  ─────────────────────────────────────────────────────────────────────────
//  ✅ ULTRA-FAST WS: Seamlessly integrates with main.py LIVE_PRICES RAM cache.
//  ✅ IN-PLACE MUTATION: Updates the last candle at 60fps without full rebuilds.
//
//  v13.4 (retained): TIMEFRAME SELECTOR (M1/M5/M15/H1/H4/D1)
//  v13.3 (retained): Instant chart, Stale-While-Revalidate, AI Planner
//  v13.2 (retained): AI Scenario Planner auto-refresh
//  v13.1 (retained): Auth, News cache, Calendar, Rate limiting
//  v12.5 (retained): liveTickNotifier, watchdog, exception boundary
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/market_models.dart';
import '../services/nexus_api_client.dart';

// ─── News cache entry ────────────────────────────────────────────────────────
class _CachedNews {
  final List<NewsItem> items;
  final DateTime fetchedAt;
  const _CachedNews(this.items, this.fetchedAt);

  bool isStale({Duration ttl = const Duration(minutes: 5)}) =>
      DateTime.now().difference(fetchedAt) > ttl;
}

// ─── Main state class ────────────────────────────────────────────────────────
class MarketState extends ChangeNotifier {
  final NexusApiClient _api = NexusApiClient();

  // ════════════════════════════════════════════════════════════════════════════
  //  CORE STATE
  // ════════════════════════════════════════════════════════════════════════════
  bool                      _online         = false;
  List<WatchlistItem>       _watchlist      = const [];
  String                    _selected       = 'XAUUSD';

  // Mutable list — candle tail is mutated in-place by live ticks.
  List<OhlcPoint>           _candles        = [];

  // v13.3: per-symbol candle cache for INSTANT chart rendering.
  final Map<String, List<OhlcPoint>> _candlesCache = {};

  bool                          _loadingCandles = false;
  final Map<String, AnalysisResult> _analyses   = {};
  bool                          _scanning       = false;
  String?                       _error;
  String                        _lastSignalKey  = '';
  int                           _scanGeneration = 0;

  // ════════════════════════════════════════════════════════════════════════════
  //  v13.4 — TIMEFRAME STATE
  // ════════════════════════════════════════════════════════════════════════════
  String _timeframe = 'M15';

  static const Map<String, String> _tfToInterval = {
    'M1': '1m', 'M5': '5m', 'M15': '15m',
    'H1': '1h', 'H4': '4h', 'D1': '1d',
  };

  void setTimeframe(String tf) {
    if (tf == _timeframe) return;
    _timeframe = tf;
    _candles = [];                  // Show skeleton while new TF loads
    _loadingCandles = true;
    _notifyNow();
    refreshCandles();               // Data matched to selected TF
    runQuantumScan();               // Analysis matched to selected TF
    loadAiPlan(force: true);        // AI plan refreshed for new TF context
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  v13.1 — NEWS + CALENDAR + AUTH STATE
  // ════════════════════════════════════════════════════════════════════════════
  final Map<String, _CachedNews>  _newsCache      = {};
  List<NewsItem>                  _currentNews    = const [];
  bool                            _loadingNews    = false;

  List<EconomicEvent>             _calendarEvents = const [];
  bool                            _loadingCalendar= false;

  User?                           _currentUser;
  bool                            _authRestored   = false;

  // ════════════════════════════════════════════════════════════════════════════
  //  v13.2 — AI SCENARIO PLANNER STATE
  // ════════════════════════════════════════════════════════════════════════════
  AiPlan?                         _aiPlan;
  bool                            _loadingAiPlan  = false;

  // ── v12.0 — WebSocket state ───────────────────────────────────────────────
  final Map<String, TickEntry>    _liveTicks      = {};
  StreamSubscription<WsFrame>?    _wsSub;
  int                             _lastSeq        = 0;

  // ── v12.5 — Fast-track tick notifier ─────────────────────────────────────
  final ValueNotifier<TickEntry?> liveTickNotifier = ValueNotifier<TickEntry?>(null);

  // ── Throttle gate (Ensures smooth 60fps UI updates) ──────────────────────
  static const Duration _kNotifyThrottle = Duration(milliseconds: 250);
  DateTime _lastNotify    = DateTime(0);
  bool     _pendingNotify = false;

  // ── Watchdog timer ────────────────────────────────────────────────────────
  static const Duration _kWatchdogTimeout = Duration(seconds: 35);
  Timer? _watchdogTimer;

  // ── Exception boundary debug log ─────────────────────────────────────────
  static const int _kDebugLogMax = 50;
  final List<Map<String, dynamic>> _wsDebugLog = [];
  List<Map<String, dynamic>> get wsDebugLog => List.unmodifiable(_wsDebugLog);

  // ════════════════════════════════════════════════════════════════════════════
  //  PUBLIC GETTERS
  // ════════════════════════════════════════════════════════════════════════════
  bool                get online         => _online;
  List<WatchlistItem> get watchlist      => _watchlist;
  String              get selectedSymbol => _selected;
  List<OhlcPoint>     get candles        => _candles;
  bool                get loadingCandles => _loadingCandles;
  AnalysisResult?     get lastAnalysis   => _analyses[_selected];
  bool                get scanning       => _scanning;
  String?             get error          => _error;
  int                 get scanGeneration => _scanGeneration;
  String              get timeframe      => _timeframe;
  Map<String, TickEntry> get liveTicks   => Map.unmodifiable(_liveTicks);
  bool get isLive                        => _wsSub != null;

  List<NewsItem>      get currentNews    => _currentNews;
  bool                get loadingNews    => _loadingNews;
  List<EconomicEvent> get calendarEvents => _calendarEvents;
  bool                get loadingCalendar=> _loadingCalendar;
  User?               get currentUser    => _currentUser;
  bool                get isPro          => _currentUser?.isPro ?? false;
  bool                get isAuthenticated=> _currentUser != null;
  AiPlan?             get aiPlan         => _aiPlan;
  bool                get loadingAiPlan  => _loadingAiPlan;

  List<NewsItem> get newsForSelected {
    if (_selected.isEmpty) return const [];
    final cached = _newsCache[_selected];
    if (cached == null) return const [];
    return cached.items;
  }

  WatchlistItem? get selectedItem =>
      _watchlist.cast<WatchlistItem?>().firstWhere(
        (w) => w?.symbol == _selected,
        orElse: () => null,
      );

  // ════════════════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ════════════════════════════════════════════════════════════════════════════
  Future<void> bootstrap() async {
    await _restoreAuth();

    _online    = await _api.ping();
    _watchlist = await _api.fetchWatchlist();

    if (_watchlist.isNotEmpty) {
      final now     = DateTime.now();
      final weekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

      if (weekend) {
        final cryptoItem = _watchlist.cast<WatchlistItem?>().firstWhere(
          (w) => w != null && (w.is24h || w.isCrypto),
          orElse: () => null,
        );
        _selected = cryptoItem?.symbol ?? _watchlist.first.symbol;
      } else {
        _selected = _watchlist.first.symbol;
      }
    }

    notifyListeners();

    // v13.3 PERF: load candles + news + calendar IN PARALLEL
    await Future.wait([
      refreshCandles(),
      loadNews(force: false),
      loadCalendar(),
    ]);

    // AI plan + WebSocket start immediately (fire-and-forget)
    loadAiPlan();
    _connectWebSocket();
  }

  Future<void> _restoreAuth() async {
    if (_authRestored) return;
    _currentUser  = await _api.restoreSession();
    _authRestored = true;
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  AUTH
  // ════════════════════════════════════════════════════════════════════════════
  Future<bool> login({required String email, required String password}) async {
    try {
      _currentUser = await _api.login(email: email, password: password);
      _error = null;
      _notifyNow();
      return true;
    } catch (e) {
      _error = 'Login failed: $e';
      _notifyNow();
      return false;
    }
  }

  Future<bool> register({required String email, required String password, String name = ''}) async {
    try {
      _currentUser = await _api.register(email: email, password: password, name: name);
      _error = null;
      _notifyNow();
      return true;
    } catch (e) {
      _error = 'Registration failed: $e';
      _notifyNow();
      return false;
    }
  }

  Future<void> logout() async {
    await _api.logout();
    _currentUser = null;
    _notifyNow();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  SYMBOL SELECTION — DEEP FLUSH + INSTANT CHART
  // ════════════════════════════════════════════════════════════════════════════
  void selectSymbol(String sym) {
    if (sym == _selected) return;

    _selected       = sym;
    _error          = null;
    _lastSignalKey  = '';
    _scanGeneration = 0;

    // v13.4: reset timeframe based on asset type
    final newItem = _watchlist.cast<WatchlistItem?>().firstWhere(
        (w) => w?.symbol == sym, orElse: () => null);
    _timeframe = (newItem?.isCrypto == true || newItem?.isForex == true) ? 'M5' : 'M15';

    // v13.3 INSTANT CHART: render cached candles immediately
    _candles        = List<OhlcPoint>.of(_candlesCache['${sym}_$_timeframe'] ?? const []);
    _loadingCandles = _candles.isEmpty; 

    _aiPlan = null;
    liveTickNotifier.value = null; // Clear fast-track notifier

    final cached = _newsCache[sym];
    _currentNews = cached?.items ?? const [];

    _notifyNow(); // Synchronous notify (chart paints NOW from cache)

    // Silent background refresh (stale-while-revalidate)
    refreshCandles();
    loadNews(force: false);
    loadAiPlan();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  OHLCV — with candle cache + timeframe support
  // ════════════════════════════════════════════════════════════════════════════
  Future<void> refreshCandles() async {
    if (_candles.isEmpty) _loadingCandles = true;
    _error = null;
    _notifyNow();
    
    try {
      final interval = _tfToInterval[_timeframe] ?? '15m';
      final loaded   = await _api.fetchOhlcv(_selected, interval: interval);
      if (loaded.isNotEmpty) {
        _candles = List<OhlcPoint>.of(loaded);
        _candlesCache['${_selected}_$_timeframe'] = List<OhlcPoint>.of(loaded);
      }
    } catch (e) {
      if (_candles.isEmpty) {
        _error   = '$e';
        _candles = [];
      }
    } finally {
      _loadingCandles = false;
      _notifyNow();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  ANALYSIS
  // ════════════════════════════════════════════════════════════════════════════
  Future<void> runQuantumScan() async {
    if (_scanning) return;

    final user = _currentUser;
    if (user != null && user.isFree && user.tradesRemaining <= 0) {
      _error = 'Daily analysis limit reached. Upgrade to Pro for unlimited scans.';
      _notifyNow();
      return;
    }

    _scanning = true;
    _error    = null;
    _notifyNow();

    try {
      final result = await _api.analyze(symbol: _selected, timeframe: _timeframe);

      if (result != null) {
        _analyses[_selected] = result;

        final newKey = '${result.intelligence.safetySignal}|${result.intelligence.signalStrength}';
        if (newKey != _lastSignalKey && _lastSignalKey.isNotEmpty) {
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
            await HapticFeedback.mediumImpact();
          }
        }
        _lastSignalKey = newKey;

        if (user != null && user.isFree && _currentUser != null) {
          final remaining = (_currentUser!.tradesRemaining - 1).clamp(0, 999);
          _currentUser = User(
            id: _currentUser!.id, email: _currentUser!.email, name: _currentUser!.name,
            tier: _currentUser!.tier, expiresAt: _currentUser!.expiresAt,
            stripeSubId: _currentUser!.stripeSubId, tradesRemaining: remaining,
          );
        }

        loadAiPlan(force: true);
      } else {
        _error = 'Analysis returned no data';
      }
      _scanGeneration++;
    } catch (e) {
      _error = '$e';
    } finally {
      _scanning = false;
      _notifyNow();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  NEWS & CALENDAR
  // ════════════════════════════════════════════════════════════════════════════
  Future<void> loadNews({bool force = false}) async {
    final sym = _selected;
    if (sym.isEmpty) return;

    final cached = _newsCache[sym];
    if (cached != null && !cached.isStale() && !force) {
      _currentNews = cached.items;
      _notifyNow();
      return;
    }

    _loadingNews = true;
    _notifyNow();
    try {
      final items = await _api.fetchNews(sym, days: 7);
      if (items.isNotEmpty) {
        _newsCache[sym] = _CachedNews(items, DateTime.now());
        _currentNews    = items;
      }
    } catch (e) {
      _debugLog('loadNews error: $e', sym);
    } finally {
      _loadingNews = false;
      _notifyNow();
    }
  }

  Future<void> loadCalendar({bool force = false}) async {
    if (_calendarEvents.isNotEmpty && !force) return;

    _loadingCalendar = true;
    _notifyNow();
    try {
      _calendarEvents = await _api.fetchCalendar(days: 14);
    } catch (e) {
      _debugLog('loadCalendar error: $e', '{}');
    } finally {
      _loadingCalendar = false;
      _notifyNow();
    }
  }

  List<EconomicEvent> get upcomingEvents {
    final now = DateTime.now().toUtc();
    return _calendarEvents
        .where((e) => e.parsedTime?.isAfter(now) ?? false)
        .toList()
      ..sort((a, b) => (a.parsedTime ?? DateTime(3000)).compareTo(b.parsedTime ?? DateTime(3000)));
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  AI SCENARIO PLANNER
  // ════════════════════════════════════════════════════════════════════════════
  Future<void> loadAiPlan({bool force = false}) async {
    final sym = _selected;
    if (sym.isEmpty) return;

    if (!force && _aiPlan != null && _aiPlan!.isFresh) return;

    _loadingAiPlan = true;
    _notifyNow();

    try {
      final plan = await _api.fetchAiPlan(sym, force: force);
      if (plan != null) _aiPlan = plan;
    } catch (e) {
      _debugLog('loadAiPlan error: $e', sym);
    } finally {
      _loadingAiPlan = false;
      _notifyNow();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  CORRELATION + ARCHIVE
  // ════════════════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> loadCorrelation() async {
    try { return await _api.fetchCorrelation(); } 
    catch (e) { _debugLog('loadCorrelation error: $e', '{}'); return {}; }
  }

  Future<Map<String, dynamic>> loadArchive({int page = 1, int pageSize = 20, String? symbol}) async {
    try { return await _api.fetchArchive(page: page, pageSize: pageSize, symbol: symbol); } 
    catch (e) { _debugLog('loadArchive error: $e', '{}'); return {}; }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  WEBSOCKET CONNECTION MANAGEMENT
  // ════════════════════════════════════════════════════════════════════════════
  void _connectWebSocket() {
    _disconnectWebSocket();
    _lastSeq = 0;

    final stream = _api.wsFrameStream();
    _wsSub = stream.listen(
      _handleFrameSafe,
      onError: (dynamic err) {
        _debugLog('WS stream error: $err', '{}');
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      },
      onDone: () {
        _debugLog('WS stream done — scheduling reconnect.', '{}');
        _disconnectWebSocket();
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      },
      cancelOnError: false,
    );
    _resetWatchdog();
  }

  void _disconnectWebSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    _stopWatchdog();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  EXCEPTION BOUNDARY
  // ════════════════════════════════════════════════════════════════════════════
  void _handleFrameSafe(WsFrame frame) {
    if (frame.type == WsFrameType.unknown) {
      final err = frame.raw['_parseError']?.toString() ?? 'unknown error';
      final raw = frame.raw['_rawPayload']?.toString() ?? '{}';
      _debugLog('Transport parse error: $err', raw);
      return;
    }
    try { _handleFrame(frame); } 
    catch (e, stack) {
      String rawJson = '{}';
      try { rawJson = frame.raw.toString(); } catch (_) {}
      _debugLog('Frame handler error: $e\n$stack', rawJson);
    }
  }

  void _handleFrame(WsFrame frame) {
    if (frame.seq > 0 && frame.seq <= _lastSeq) return;
    if (frame.seq > 0) _lastSeq = frame.seq;

    switch (frame.type) {
      case WsFrameType.priceTick:
      case WsFrameType.connected:
        _onPriceTick(frame);
        break;
      case WsFrameType.metricShift:
        _onMetricShift(frame);
        break;
      case WsFrameType.heartbeat:
        _resetWatchdog();
        break;
      case WsFrameType.filterAck:
      case WsFrameType.unknown:
        break;
    }
  }

  // 🚀 ULTRA-FAST TICK HANDLER (v13.10 Optimized)
  void _onPriceTick(WsFrame frame) {
    if (frame.ticks.isEmpty) return;

    _liveTicks.addAll(frame.ticks);

    final tick = frame.ticks[_selected];
    if (tick != null && tick.price > 0) {
      // 1. Notify UI components listening to live price (e.g., header)
      liveTickNotifier.value = tick;

      // 2. Mutate the last candle IN-PLACE for 60fps chart rendering
      if (_candles.isNotEmpty) {
        final last  = _candles.last;
        final price = tick.price;
        final newHigh = price > last.high ? price : last.high;
        final newLow  = price < last.low  ? price : last.low;

        if (price != last.close || newHigh != last.high || newLow != last.low) {
          _candles[_candles.length - 1] = last.withLiveTick(
            close: price, high: newHigh, low: newLow);
        }
      }
    }
    _notifyThrottled();
  }

  void _onMetricShift(WsFrame frame) {
    final shift = frame.shift;
    if (shift == null) return;

    if (shift.symbol == _selected) {
      if (shift.field == 'safetySignal' || shift.field == 'direction') {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          HapticFeedback.lightImpact();
        }
        _analyses.remove(_selected);
      }
    }
    _notifyNow();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  WATCHDOG + NOTIFY HELPERS
  // ════════════════════════════════════════════════════════════════════════════
  void _resetWatchdog() {
    _stopWatchdog();
    _watchdogTimer = Timer(_kWatchdogTimeout, () {
      _debugLog('Watchdog fired — no heartbeat in ${_kWatchdogTimeout.inSeconds}s. Reconnecting.', '{}');
      _connectWebSocket();
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  void _notifyNow() {
    _lastNotify    = DateTime.now();
    _pendingNotify = false;
    notifyListeners();
  }

  void _notifyThrottled() {
    final now     = DateTime.now();
    final elapsed = now.difference(_lastNotify);

    if (elapsed >= _kNotifyThrottle) {
      _notifyNow();
    } else if (!_pendingNotify) {
      _pendingNotify = true;
      final remaining = _kNotifyThrottle - elapsed;
      Future.delayed(remaining, () {
        if (_pendingNotify) _notifyNow();
      });
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  DEBUG LOG
  // ════════════════════════════════════════════════════════════════════════════
  void _debugLog(String error, String rawPayload) {
    assert(() {
      // ignore: avoid_print
      print('[NEXUS-WS] $error');
      return true;
    }());

    if (_wsDebugLog.length >= _kDebugLogMax) _wsDebugLog.removeAt(0);
    _wsDebugLog.add({
      'ts':    DateTime.now().toIso8601String(),
      'error': error,
      'raw':   rawPayload.length > 500 ? '${rawPayload.substring(0, 500)}…' : rawPayload,
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  DISPOSAL
  // ════════════════════════════════════════════════════════════════════════════
  @override
  void dispose() {
    _disconnectWebSocket();
    liveTickNotifier.dispose();
    _api.close();
    super.dispose();
  }
}