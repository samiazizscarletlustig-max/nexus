// ============================================================================
//  NEXUS v12.5 — market_state.dart
//  ChangeNotifier state manager bridging NexusApiClient and the UI.
//
//  v12.5 additions over v12.0:
//  ─────────────────────────────────────────────────────────────────────────
//  FAST-TRACK TICK NOTIFIER
//  • `final ValueNotifier<TickEntry?> liveTickNotifier` is now a public
//    field.  It carries the most recent TickEntry for the SELECTED symbol
//    and is updated directly from the WebSocket price_tick handler —
//    bypassing notifyListeners() and all throttle logic.
//  • NexusCandleChart subscribes to this notifier directly so the chart HUD
//    and the last-candle close update at WebSocket cadence (~3 s) with zero
//    widget-tree rebuilds outside the chart subtree.
//
//  IN-PLACE LAST-CANDLE MUTATION
//  • When a price_tick arrives for the selected symbol, _onPriceTick() now:
//      1. Fires liveTickNotifier immediately (zero-rebuild fast path).
//      2. Mutates the last OhlcPoint in _candles in-place using
//         OhlcPoint.withLiveTick() — adjusting close, high, low — so the
//         Syncfusion SeriesController.updateDataSource() call in the chart
//         reads updated values without a global notifyListeners().
//  • _candles is promoted from `const []` to a `List<OhlcPoint>` grow-able
//    list so mutations are possible.  REST-loaded bars are converted via
//    List.of() on assignment.
//
//  LIFECYCLE SAFETY
//  • liveTickNotifier.value is reset to null in selectSymbol() deep flush so
//    the chart never shows a stale ticker for the new symbol.
//  • liveTickNotifier is disposed in dispose() after _disconnectWebSocket().
//
//  ALL v12.0 BEHAVIOURS RETAINED UNCHANGED:
//  • Sequence validation, throttled notifyListeners, watchdog reconnect,
//    exception boundary, wsDebugLog, selectSymbol deep flush, REST paths,
//    Gold logic, bootstrap smart routing.
//  ─────────────────────────────────────────────────────────────────────────
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/market_models.dart';
import '../services/nexus_api_client.dart';

class MarketState extends ChangeNotifier {
  final NexusApiClient _api = NexusApiClient();

  // ── Core state ────────────────────────────────────────────────────────────

  bool                      _online         = false;
  List<WatchlistItem>       _watchlist       = const [];
  String                    _selected        = 'XAUUSD';

  // Mutable list — candle tail is mutated in-place by live ticks.
  // Never assigned const [] after the first REST load.
  List<OhlcPoint>           _candles         = [];

  bool                          _loadingCandles  = false;
  final Map<String, AnalysisResult> _analyses   = {};
  bool                          _scanning        = false;
  String?                       _error;
  String                        _lastSignalKey   = '';
  int                           _scanGeneration  = 0;

  // ── v12.0 — WebSocket state ───────────────────────────────────────────────

  /// Most recent live price per symbol — keyed by symbol string.
  /// Used for watchlist price badges and multi-asset overlays.
  final Map<String, TickEntry>  _liveTicks       = {};

  StreamSubscription<WsFrame>?  _wsSub;

  /// Last seq number processed on the current connection.
  /// Reset to 0 on every new connection.
  int                           _lastSeq         = 0;

  // ── v12.5 — Fast-track tick notifier ─────────────────────────────────────
  //
  // Carries the most recent TickEntry for the SELECTED symbol only.
  // Updated directly in _onPriceTick() — no notifyListeners(), no throttle.
  // NexusCandleChart subscribes to this notifier via addListener() so the
  // chart HUD + last-candle SeriesController update fires at WS cadence
  // with zero widget-tree rebuilds outside the chart subtree.

  final ValueNotifier<TickEntry?> liveTickNotifier = ValueNotifier<TickEntry?>(null);

  // ── Throttle gate for notifyListeners() ──────────────────────────────────

  static const Duration _kNotifyThrottle = Duration(milliseconds: 250);
  DateTime _lastNotify    = DateTime(0);
  bool     _pendingNotify = false;

  // ── Watchdog timer ────────────────────────────────────────────────────────

  static const Duration _kWatchdogTimeout = Duration(seconds: 35);
  Timer? _watchdogTimer;

  // ── Exception boundary debug log ─────────────────────────────────────────

  static const int _kDebugLogMax = 50;
  final List<Map<String, dynamic>> _wsDebugLog = [];

  /// Read-only view of the WS exception boundary log.
  List<Map<String, dynamic>> get wsDebugLog => List.unmodifiable(_wsDebugLog);

  // ── Public getters ────────────────────────────────────────────────────────

  bool                get online         => _online;
  List<WatchlistItem> get watchlist      => _watchlist;
  String              get selectedSymbol => _selected;
  List<OhlcPoint>     get candles        => _candles;
  bool                get loadingCandles => _loadingCandles;
  AnalysisResult?     get lastAnalysis   => _analyses[_selected];
  bool                get scanning       => _scanning;
  String?             get error          => _error;
  int                 get scanGeneration => _scanGeneration;

  /// Live price ticks keyed by symbol — for animated price ticker widgets.
  Map<String, TickEntry> get liveTicks => Map.unmodifiable(_liveTicks);

  /// True when the WebSocket subscription is active.
  bool get isLive => _wsSub != null;

  WatchlistItem? get selectedItem =>
      _watchlist.cast<WatchlistItem?>().firstWhere(
        (w) => w?.symbol == _selected,
        orElse: () => null,
      );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> bootstrap() async {
    _online    = await _api.ping();
    _watchlist = await _api.fetchWatchlist();

    if (_watchlist.isNotEmpty) {
      final now     = DateTime.now();
      final weekend = now.weekday == DateTime.saturday ||
                      now.weekday == DateTime.sunday;

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
    await refreshCandles();
    _connectWebSocket();
  }

  // ── Symbol selection — deep flush ─────────────────────────────────────────

  void selectSymbol(String sym) {
    if (sym == _selected) return;

    // ── 1. Deep flush ───────────────────────────────────────────────────────
    _selected       = sym;
    _candles        = [];          // grow-able empty list, NOT const
    _error          = null;
    _lastSignalKey  = '';
    _scanGeneration = 0;
    _analyses.remove(sym);

    // ── 1a. v12.5: Clear the fast-track notifier immediately so the chart
    //        never shows a stale ticker value from the previous symbol.
    liveTickNotifier.value = null;

    // ── 2. Notify synchronously — widgets rebuild to loading/shimmer state ──
    _notifyNow();

    // ── 3. Load candles for the new symbol via REST ─────────────────────────
    refreshCandles();
  }

  // ── OHLCV ─────────────────────────────────────────────────────────────────

  Future<void> refreshCandles() async {
    _loadingCandles = true;
    _error          = null;
    _notifyNow();
    try {
      final item     = selectedItem;
      final interval = _defaultInterval(item?.type);
      final loaded   = await _api.fetchOhlcv(_selected, interval: interval);
      // Assign as a grow-able (non-const) list so in-place mutation works.
      _candles = List<OhlcPoint>.of(loaded);
    } catch (e) {
      _error   = '$e';
      _candles = [];
    } finally {
      _loadingCandles = false;
      _notifyNow();
    }
  }

  String _defaultInterval(String? type) {
    switch (type?.toLowerCase()) {
      case 'crypto':
      case 'cryptocurrency':
        return '5m';
      case 'forex':
        return '5m';
      default:
        return '15m'; // Gold / equities — IMMUTABLE
    }
  }

  // ── Analysis ──────────────────────────────────────────────────────────────

  Future<void> runQuantumScan() async {
    if (_scanning) return;
    _scanning = true;
    _error    = null;
    _notifyNow();
    try {
      final res = await _api.analyze([_selected]);
      _analyses.addAll(res);

      final current = _analyses[_selected];
      if (current != null) {
        final newKey =
            '${current.intelligence.safetySignal}|${current.intelligence.signalStrength}';
        if (newKey != _lastSignalKey && _lastSignalKey.isNotEmpty) {
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
            await HapticFeedback.mediumImpact();
          }
        }
        _lastSignalKey = newKey;
      }
      _scanGeneration++;
    } catch (e) {
      _error = '$e';
    } finally {
      _scanning = false;
      _notifyNow();
    }
  }

  // ── v12.0 — WebSocket connection management ───────────────────────────────

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

  // ── Exception Boundary ────────────────────────────────────────────────────

  void _handleFrameSafe(WsFrame frame) {
    if (frame.type == WsFrameType.unknown) {
      final err = frame.raw['_parseError']?.toString() ?? 'unknown error';
      final raw = frame.raw['_rawPayload']?.toString() ?? '{}';
      _debugLog('Transport parse error: $err', raw);
      return;
    }

    try {
      _handleFrame(frame);
    } catch (e, stack) {
      String rawJson = '{}';
      try { rawJson = frame.raw.toString(); } catch (_) {}
      _debugLog('Frame handler error: $e\n$stack', rawJson);
    }
  }

  void _handleFrame(WsFrame frame) {
    // ── Sequence validation ─────────────────────────────────────────────────
    if (frame.seq > 0 && frame.seq <= _lastSeq) return;
    if (frame.seq > 0) _lastSeq = frame.seq;

    switch (frame.type) {
      case WsFrameType.priceTick:
        _onPriceTick(frame);
        break;
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
        break;
      case WsFrameType.unknown:
        break;
    }
  }

  // ── Frame handlers ────────────────────────────────────────────────────────

  void _onPriceTick(WsFrame frame) {
    if (frame.ticks.isEmpty) return;

    // ── 1. Merge all ticks into the global map (watchlist badges) ──────────
    _liveTicks.addAll(frame.ticks);

    // ── 2. Fast-track path for the currently selected symbol ────────────────
    final tick = frame.ticks[_selected];
    if (tick != null && tick.price > 0) {

      // ── 2a. Fire the ValueNotifier — NexusCandleChart receives this
      //        directly, updates SeriesController and HUD with zero rebuilds
      //        outside the chart subtree.
      liveTickNotifier.value = tick;

      // ── 2b. Mutate the last OhlcPoint in-place so SeriesController reads
      //        the updated OHLC when it calls updateDataSource().
      //        Guard: only mutate if candles is non-empty and grow-able.
      if (_candles.isNotEmpty) {
        final last  = _candles.last;
        final price = tick.price;

        // Only replace the candle object when at least one field actually
        // changed — avoids a needless allocation on identical ticks.
        final newHigh  = price > last.high  ? price : last.high;
        final newLow   = price < last.low   ? price : last.low;

        if (price != last.close || newHigh != last.high || newLow != last.low) {
          _candles[_candles.length - 1] = last.withLiveTick(
            close: price,
            high:  newHigh,
            low:   newLow,
          );
        }
      }
    }

    // ── 3. Throttled global notify for watchlist / price badges ────────────
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

  // ── Watchdog timer ────────────────────────────────────────────────────────

  void _resetWatchdog() {
    _stopWatchdog();
    _watchdogTimer = Timer(_kWatchdogTimeout, () {
      _debugLog(
        'Watchdog fired — no heartbeat in ${_kWatchdogTimeout.inSeconds}s. '
        'Reconnecting.',
        '{}',
      );
      _connectWebSocket();
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  // ── Notify helpers ────────────────────────────────────────────────────────

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

  // ── Debug log ─────────────────────────────────────────────────────────────

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
      'raw':   rawPayload.length > 500
                  ? '${rawPayload.substring(0, 500)}…'
                  : rawPayload,
    });
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disconnectWebSocket();
    // Dispose the fast-track notifier AFTER disconnecting so no dangling
    // listener callback fires into a disposed ValueNotifier.
    liveTickNotifier.dispose();
    _api.close();
    super.dispose();
  }
}