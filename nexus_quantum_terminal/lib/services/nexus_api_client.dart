// ============================================================================
//  NEXUS v13.4 — nexus_api_client.dart
//  HTTP + WebSocket transport layer between Flutter and the FastAPI backend.
//  All JSON parsing delegated to market_models.dart.
//
//  v13.4 changes over v13.2:
//  ─────────────────────────────────────────────────────────────────────────
//  ✅ analyze() now passes `timeframe` to backend for matched analysis
//  ✅ Supports M1/M5/M15/H1/H4/D1 timeframe codes
//
//  v13.2 (retained):
//  ✅ ApiPaths.aiPlan(symbol, force) — Gemini AI plan endpoint
//  ✅ fetchAiPlan(symbol, {force}) → AiPlan? with 45s timeout
//  ✅ Graceful fallback — returns null on any failure (never throws)
//
//  v13.1 (retained):
//  ✅ analyze() takes single symbol (matches backend v13.1)
//  ✅ _fallbackWatchlist contains all 10 supported assets
//  ✅ Token management via SharedPreferences (Bearer auth)
//  ✅ login() / register() / logout() / currentUser()
//  ✅ fetchNews() / fetchCalendar() / fetchMacroEvents() / fetchAssets()
//  ✅ calculatePositionSize() / fetchArchive()
//  ✅ Automatic Authorization header injection
//  ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/market_models.dart';

// ─── Base URL ─────────────────────────────────────────────────────────────────

/// Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
///
/// Platform defaults:
///   - Windows / macOS / Linux / Web → 127.0.0.1:8000
///   - Android Emulator            → 10.0.2.2:8000 (host machine proxy)
///   - iOS Simulator               → 127.0.0.1:8000
///   - Real device                 → your LAN IP (e.g. 192.168.1.10:8000)
///   - Production (after Railway)  → your public URL
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

// ─── Route helpers ────────────────────────────────────────────────────────────

abstract final class ApiPaths {
  // ── Public ──────────────────────────────────────────────────────────────
  static String get health        => '$kApiBaseUrl/api/health';
  static String get assets        => '$kApiBaseUrl/api/assets';
  static String get watchlist     => '$kApiBaseUrl/api/watchlist';
  static String get analyze       => '$kApiBaseUrl/api/analyze';
  static String get positionSize  => '$kApiBaseUrl/api/position-size';
  static String get correlation   => '$kApiBaseUrl/api/correlation';
  static String get macroEvents   => '$kApiBaseUrl/api/macro-events';
  static String get calendar      => '$kApiBaseUrl/api/calendar';

  static String news(String symbol) =>
      '$kApiBaseUrl/api/news/${Uri.encodeComponent(symbol)}';

  // ── v13.2 NEW: AI Scenario Planner ─────────────────────────────────────
  /// Gemini AI plan endpoint. `force=true` bypasses the backend cache (45 min).
  static String aiPlan(String symbol, {bool force = false}) =>
      '$kApiBaseUrl/api/ai-plan'
      '?symbol=${Uri.encodeComponent(symbol)}'
      '&force=$force';

  // ── Auth ────────────────────────────────────────────────────────────────
  static String get register      => '$kApiBaseUrl/auth/register';
  static String get login         => '$kApiBaseUrl/auth/login';
  static String get me            => '$kApiBaseUrl/auth/me';

  // ── Archive ─────────────────────────────────────────────────────────────
  static String archive({int page = 1, int pageSize = 20, String? symbol}) {
    final q = StringBuffer(
        '$kApiBaseUrl/api/v1/archive?page=$page&pageSize=$pageSize');
    if (symbol != null && symbol.isNotEmpty) {
      q.write('&symbol=${Uri.encodeComponent(symbol)}');
    }
    return q.toString();
  }

  // ── OHLCV ───────────────────────────────────────────────────────────────
  static String ohlcv(String symbol, {String interval = '15m'}) =>
      '$kApiBaseUrl/api/ohlcv'
      '?symbol=${Uri.encodeComponent(symbol)}'
      '&interval=${Uri.encodeComponent(interval)}';

  // ── WebSocket ───────────────────────────────────────────────────────────
  static Uri get wsLive {
    final base = kApiBaseUrl
        .replaceFirst(RegExp(r'^http://'),  'ws://')
        .replaceFirst(RegExp(r'^https://'), 'wss://');
    return Uri.parse('$base/ws/live');
  }
}

// ─── Token Storage (SharedPreferences wrapper) ───────────────────────────────

class TokenStorage {
  static const String _keyToken = 'nexus_auth_token';
  static const String _keyUser  = 'nexus_user_json';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
  }

  static Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode(user.toJson()));
  }

  static Future<User?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUser);
  }
}

// ─── Client ───────────────────────────────────────────────────────────────────

class NexusApiClient {
  NexusApiClient({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  // ── In-memory cache for the current user (avoids reading prefs on every call)
  User? _cachedUser;

  // ── WebSocket channel state ─────────────────────────────────────────────
  WebSocketChannel? _wsChannel;
  StreamController<WsFrame>? _wsController;

  bool get isWsConnected =>
      _wsChannel != null && _wsController != null && !_wsController!.isClosed;

  // ── Auth headers builder (auto-injects Bearer token when available) ──────

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await TokenStorage.loadToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  AUTH
  // ════════════════════════════════════════════════════════════════════════════

  /// Tries to restore a previously logged-in user from local storage.
  Future<User?> restoreSession() async {
    _cachedUser ??= await TokenStorage.loadUser();
    return _cachedUser;
  }

  Future<User> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    final r = await _client.post(
      Uri.parse(ApiPaths.register),
      headers: await _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'name': name,
      }),
    ).timeout(const Duration(seconds: 15));

    if (r.statusCode != 200 && r.statusCode != 201) {
      throw ApiException(r.statusCode, r.body);
    }

    return _handleAuthResponse(r.body);
  }

  Future<User> login({
    required String email,
    required String password,
  }) async {
    final r = await _client.post(
      Uri.parse(ApiPaths.login),
      headers: await _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    ).timeout(const Duration(seconds: 15));

    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, r.body);
    }

    return _handleAuthResponse(r.body);
  }

  Future<void> logout() async {
    _cachedUser = null;
    await TokenStorage.clear();
  }

  User? get currentUser => _cachedUser;

  /// Helper: parses `{token, user}` response, persists both, and returns user.
  Future<User> _handleAuthResponse(String body) async {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(-1, 'Invalid auth response shape');
    }
    final token = decoded['access_token']?.toString() ??
                  decoded['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException(-1, 'No token in auth response');
    }
    await TokenStorage.saveToken(token);

    final userRaw = decoded['user'];
    final user = userRaw is Map<String, dynamic>
        ? User.fromJson(userRaw)
        : User(id: 'local', email: '', tier: 'free');

    await TokenStorage.saveUser(user);
    _cachedUser = user;
    return user;
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  HEALTH / METADATA
  // ════════════════════════════════════════════════════════════════════════════

  Future<bool> ping() async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.health))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Returns the full list of supported assets + their instrument specs.
  Future<List<Map<String, dynamic>>> fetchAssets() async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.assets),
               headers: await _headers(json: false))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return [];
      final decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['assets'];
        if (list is List) {
          return list.whereType<Map<String, dynamic>>().toList();
        }
      }
      return [];
    } catch (e) {
      _debugPrint('fetchAssets error: $e');
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  WATCHLIST
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<WatchlistItem>> fetchWatchlist() async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.watchlist),
               headers: await _headers(json: false))
          .timeout(const Duration(seconds: 20));

      if (r.statusCode != 200) return _fallbackWatchlist();

      final decoded = jsonDecode(r.body);
      if (decoded is! List) return _fallbackWatchlist();

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WatchlistItem.fromJson)
          .toList();
    } catch (e) {
      _debugPrint('fetchWatchlist error: $e');
      return _fallbackWatchlist();
    }
  }

  /// Updated to all 10 supported assets (v13.1).
  List<WatchlistItem> _fallbackWatchlist() => const [
        WatchlistItem(symbol: 'XAUUSD', name: 'Gold',        emoji: '⚡', type: 'commodity'),
        WatchlistItem(symbol: 'XAGUSD', name: 'Silver',      emoji: '🥈', type: 'commodity'),
        WatchlistItem(symbol: 'BTCUSD', name: 'Bitcoin',     emoji: '₿',  type: 'crypto',   is24h: true),
        WatchlistItem(symbol: 'ETHUSD', name: 'Ethereum',    emoji: 'Ξ',  type: 'crypto',   is24h: true),
        WatchlistItem(symbol: 'SOLUSD', name: 'Solana',      emoji: '💜', type: 'crypto',   is24h: true),
        WatchlistItem(symbol: 'SPX500', name: 'S&P 500',     emoji: '📊', type: 'index'),
        WatchlistItem(symbol: 'NAS100', name: 'NASDAQ 100',  emoji: '🚀', type: 'index'),
        WatchlistItem(symbol: 'EURUSD', name: 'EUR/USD',     emoji: '💱', type: 'forex'),
        WatchlistItem(symbol: 'GBPUSD', name: 'GBP/USD',     emoji: '💷', type: 'forex'),
        WatchlistItem(symbol: 'USDJPY', name: 'USD/JPY',     emoji: '💴', type: 'forex'),
      ];

  // ════════════════════════════════════════════════════════════════════════════
  //  OHLCV
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<OhlcPoint>> fetchOhlcv(
    String symbol, {
    String interval = '15m',
  }) async {
    try {
      final uri = Uri.parse(ApiPaths.ohlcv(symbol, interval: interval));
      final r = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(const Duration(seconds: 30));

      if (r.statusCode != 200) return [];
      final decoded = jsonDecode(r.body);

      List<dynamic> candleList;
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['candles'];
        if (raw is! List) return [];
        candleList = raw;
      } else if (decoded is List) {
        candleList = decoded;
      } else {
        return [];
      }

      return candleList
          .whereType<Map<String, dynamic>>()
          .map(OhlcPoint.fromJson)
          .toList();
    } catch (e) {
      _debugPrint('fetchOhlcv error [$symbol/$interval]: $e');
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  ANALYSIS (v13.4 — single-symbol, passes timeframe for matched analysis)
  // ════════════════════════════════════════════════════════════════════════════

  /// Runs full quantum analysis for ONE symbol and returns the result.
  ///
  /// **v13.4:** `timeframe` parameter (M1/M5/M15/H1/H4/D1) is sent to backend
  /// so all indicators are calculated on the matching timeframe.
  ///
  /// Backend response shape (v13.1+):
  /// ```json
  /// {
  ///   "success": true,
  ///   "data": {
  ///     "symbol": "XAUUSD",
  ///     "source": "Twelve Data (Real Broker)",
  ///     "intelligence": {...},
  ///     "news": [...],
  ///     "chartMetadata": {...}
  ///   }
  /// }
  /// ```
  Future<AnalysisResult?> analyze({
    required String symbol,
    double balance = 10000.0,
    double riskPercentage = 1.0,
    String timeframe = 'M15',  // v13.4: default changed to M15 (matches backend default)
    bool runMtf = false,
    double atrMult = 1.5,
    double rrRatio = 2.5,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse(ApiPaths.analyze),
        headers: await _headers(),
        body: jsonEncode({
          'symbol': symbol,
          'balance': balance,
          'risk_percentage': riskPercentage,
          'timeframe': timeframe,   // v13.4: sent to backend for matched analysis
          'run_mtf': runMtf,
          'atr_mult': atrMult,
          'rr_ratio': rrRatio,
        }),
      ).timeout(const Duration(seconds: 90));

      if (r.statusCode != 200) {
        _debugPrint('analyze HTTP ${r.statusCode}: ${r.body}');
        return null;
      }

      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return null;

      final success = decoded['success'] == true;
      if (!success) return null;

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;

      return AnalysisResult.fromJson(symbol, data);
    } catch (e) {
      _debugPrint('analyze error [$symbol]: $e');
      return null;
    }
  }

  /// Convenience: analyze multiple symbols in parallel.
  Future<Map<String, AnalysisResult>> analyzeMany(
    List<String> symbols, {
    double balance = 10000.0,
    double riskPercentage = 1.0,
    String timeframe = 'M15',  // v13.4
  }) async {
    final results = <String, AnalysisResult>{};
    await Future.wait(symbols.map((s) async {
      final res = await analyze(
        symbol: s,
        balance: balance,
        riskPercentage: riskPercentage,
        timeframe: timeframe,  // v13.4
      );
      if (res != null) results[s] = res;
    }));
    return results;
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  NEWS + CALENDAR (v13.1 — Finnhub integration)
  // ════════════════════════════════════════════════════════════════════════════

  /// Fetches live news for a symbol from Finnhub (via backend).
  Future<List<NewsItem>> fetchNews(String symbol, {int days = 7}) async {
    try {
      final uri = Uri.parse('${ApiPaths.news(symbol)}?days=$days');
      final r = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(const Duration(seconds: 15));

      if (r.statusCode != 200) return [];

      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return [];

      final newsList = decoded['news'];
      if (newsList is! List) return [];

      return newsList
          .whereType<Map<String, dynamic>>()
          .map(NewsItem.fromJson)
          .toList();
    } catch (e) {
      _debugPrint('fetchNews error [$symbol]: $e');
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  AI SCENARIO PLANNER (v13.2 NEW — Gemini AI)
  // ════════════════════════════════════════════════════════════════════════════

  /// Fetches the Gemini AI scenario plan (4 probable scenarios + explanations)
  /// for a symbol.
  ///
  /// **Backend behavior:**
  /// - Caches result for 45 min → repeated calls are instant.
  /// - Falls back to quantitative rule-based plan if Gemini is unavailable.
  /// - `force=true` bypasses the cache (for manual regeneration).
  ///
  /// **Backend response shape (v13.2):**
  /// ```json
  /// {
  ///   "success": true,
  ///   "symbol": "XAUUSD",
  ///   "used_cached_analysis": false,
  ///   "data": {
  ///     "source": "gemini" | "quant-fallback",
  ///     "horizon": "next ~3 sessions",
  ///     "summary": "...",
  ///     "scenarios": [
  ///       { "rank": 1, "title": "...", "probability": 40, ... }
  ///     ],
  ///     "risk_note": "..."
  ///   },
  ///   "disclaimer": "AI-generated educational analysis. Not financial advice."
  /// }
  /// ```
  ///
  /// Returns `null` on any failure (HTTP error, parse error, timeout).
  /// Never throws — UI should handle null gracefully.
  Future<AiPlan?> fetchAiPlan(String symbol, {bool force = false}) async {
    try {
      final uri = Uri.parse(ApiPaths.aiPlan(symbol, force: force));
      // Gemini can take up to ~30s on first call (no cache)
      final r = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(const Duration(seconds: 45));

      if (r.statusCode != 200) {
        _debugPrint('fetchAiPlan HTTP ${r.statusCode}: ${r.body}');
        return null;
      }

      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) {
        _debugPrint('fetchAiPlan: unexpected root type '
            '${decoded.runtimeType}');
        return null;
      }

      final success = decoded['success'] == true;
      if (!success) {
        _debugPrint('fetchAiPlan: success=false — '
            '${decoded['error'] ?? decoded['detail'] ?? 'unknown'}');
        return null;
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        _debugPrint('fetchAiPlan: data field is not a Map '
            '(got ${data.runtimeType})');
        return null;
      }

      return AiPlan.fromJson(data);
    } on TimeoutException {
      _debugPrint('fetchAiPlan timeout [$symbol] (45s exceeded)');
      return null;
    } catch (e) {
      _debugPrint('fetchAiPlan error [$symbol]: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  CALENDAR + MACRO
  // ════════════════════════════════════════════════════════════════════════════

  /// Fetches the economic calendar (high-impact events like NFP, CPI, FOMC).
  Future<List<EconomicEvent>> fetchCalendar({int days = 7}) async {
    try {
      final uri = Uri.parse('${ApiPaths.calendar}?days=$days');
      final r = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(const Duration(seconds: 15));

      if (r.statusCode != 200) return [];

      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return [];

      final events = decoded['events'];
      if (events is! List) return [];

      return events
          .whereType<Map<String, dynamic>>()
          .map(EconomicEvent.fromJson)
          .toList();
    } catch (e) {
      _debugPrint('fetchCalendar error: $e');
      return [];
    }
  }

  /// Backup: macro events from Twelve Data.
  Future<List<Map<String, dynamic>>> fetchMacroEvents({int days = 7}) async {
    try {
      final uri = Uri.parse('${ApiPaths.macroEvents}?days=$days');
      final r = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return [];
      final decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['events'];
        if (list is List) {
          return list.whereType<Map<String, dynamic>>().toList();
        }
      }
      return [];
    } catch (e) {
      _debugPrint('fetchMacroEvents error: $e');
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  POSITION SIZE (P0)
  // ════════════════════════════════════════════════════════════════════════════

  /// Calculates optimal lot size based on account, risk%, and SL distance.
  Future<Map<String, dynamic>> calculatePositionSize({
    required String symbol,
    required double balance,
    required double riskPercentage,
    required double entryPrice,
    required double stopLossPrice,
  }) async {
    try {
      final r = await _client.post(
        Uri.parse(ApiPaths.positionSize),
        headers: await _headers(),
        body: jsonEncode({
          'symbol': symbol,
          'balance': balance,
          'risk_percentage': riskPercentage,
          'entry_price': entryPrice,
          'stop_loss_price': stopLossPrice,
        }),
      ).timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(r.body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      _debugPrint('calculatePositionSize error: $e');
      return {'error': e.toString()};
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  CORRELATION + ARCHIVE
  // ════════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchCorrelation() async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.correlation),
               headers: await _headers(json: false))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return {};
      final decoded = jsonDecode(r.body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      _debugPrint('fetchCorrelation error: $e');
      return {};
    }
  }

  /// Fetches paginated signal archive.
  Future<Map<String, dynamic>> fetchArchive({
    int page = 1,
    int pageSize = 20,
    String? symbol,
  }) async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.archive(
            page: page, pageSize: pageSize, symbol: symbol)),
               headers: await _headers(json: false))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return {};
      final decoded = jsonDecode(r.body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      _debugPrint('fetchArchive error: $e');
      return {};
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  WEBSOCKET LIVE STREAM
  // ════════════════════════════════════════════════════════════════════════════

  Stream<WsFrame> wsFrameStream() {
    _closeWs();

    final channel = WebSocketChannel.connect(ApiPaths.wsLive);
    _wsChannel = channel;
    _wsController = StreamController<WsFrame>.broadcast(onCancel: _closeWs);

    channel.stream.listen(
      (dynamic raw) {
        if (raw is! String) return;
        WsFrame frame;
        try {
          final Map<String, dynamic> decoded = _decodeJsonObject(raw);
          frame = _buildFrameFromDecoded(decoded, raw);
        } catch (e) {
          _debugPrint('WS frame parse error: $e\n  payload: '
              '${raw.length > 200 ? raw.substring(0, 200) : raw}');
          frame = WsFrame(
            type: WsFrameType.unknown,
            ts: '',
            seq: 0,
            raw: {'_parseError': e.toString(), '_rawPayload': raw},
          );
        }
        if (!_wsController!.isClosed) {
          _wsController!.add(frame);
        }
      },
      onError: (dynamic err) {
        _debugPrint('WS channel error: $err');
        if (!_wsController!.isClosed) {
          _wsController!.addError(err);
        }
      },
      onDone: () {
        _debugPrint('WS channel closed by server.');
        if (!_wsController!.isClosed) _wsController!.close();
      },
      cancelOnError: false,
    );

    return _wsController!.stream;
  }

  void sendFilter(List<String> symbols) {
    if (_wsChannel == null) return;
    try {
      _wsChannel!.sink.add(jsonEncode({'symbols': symbols}));
    } catch (e) {
      _debugPrint('sendFilter error: $e');
    }
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  Map<String, dynamic> _decodeJsonObject(String text) {
    final dynamic decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw WsFrameParseException(
          'Expected JSON object, got ${decoded.runtimeType}', text);
    }
    return decoded;
  }

  WsFrame _buildFrameFromDecoded(Map<String, dynamic> j, String rawText) {
    try {
      return WsFrame.fromRaw(jsonEncode(j));
    } catch (e) {
      throw WsFrameParseException('Frame construction failed: $e', rawText);
    }
  }

  void _closeWs() {
    try { _wsChannel?.sink.close(); } catch (_) {}
    try { _wsController?.close(); } catch (_) {}
    _wsChannel = null;
    _wsController = null;
  }

  // ── Disposal ────────────────────────────────────────────────────────────

  void close() {
    _closeWs();
    _client.close();
  }
}

// ─── Exception type ───────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int statusCode;
  final String body;
  const ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

// ─── Debug print shim ────────────────────────────────────────────────────────

void _debugPrint(String msg) {
  assert(() {
    // ignore: avoid_print
    print('[NEXUS-CLIENT] $msg');
    return true;
  }());
}