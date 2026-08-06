// ============================================================================
//  NEXUS v13.0 — nexus_api_client.dart
//  HTTP + WebSocket transport layer between Flutter and the FastAPI backend.
//  All JSON parsing delegated to market_models.dart.
//
//  v13.0 fix over v12.0:
//  • fetchOhlcv() now unwraps the {"candles":[…],"chartMetadata":{…}} envelope
//    that main.py v12.0 wraps OHLCV responses in.  The previous implementation
//    checked `decoded is! List` which always failed against this shape,
//    silently returning [] for all OHLCV calls.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart'             as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/market_models.dart';

// ─── Base URL ─────────────────────────────────────────────────────────────────

/// Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

// ─── Route helpers ────────────────────────────────────────────────────────────

abstract final class ApiPaths {
  static String get health      => '$kApiBaseUrl/api/health';
  static String get watchlist   => '$kApiBaseUrl/api/watchlist';
  static String get analyze     => '$kApiBaseUrl/api/analyze';
  static String get correlation => '$kApiBaseUrl/api/correlation';

  // v11.2: interval forwarded so the backend serves 5m for crypto.
  static String ohlcv(String symbol, {String interval = '15m'}) =>
      '$kApiBaseUrl/api/ohlcv'
      '?symbol=${Uri.encodeComponent(symbol)}'
      '&interval=${Uri.encodeComponent(interval)}';

  // v12.0: WebSocket endpoint.
  // Derives ws:// or wss:// from the HTTP base URL automatically.
  static Uri get wsLive {
    final base = kApiBaseUrl
        .replaceFirst(RegExp(r'^http://'),  'ws://')
        .replaceFirst(RegExp(r'^https://'), 'wss://');
    return Uri.parse('$base/ws/live');
  }
}

// ─── Client ───────────────────────────────────────────────────────────────────

class NexusApiClient {
  NexusApiClient({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  // ── v12.0: WebSocket channel state ────────────────────────────────────────

  WebSocketChannel?                   _wsChannel;
  StreamController<WsFrame>?          _wsController;

  /// Whether the WebSocket is currently open.
  bool get isWsConnected =>
      _wsChannel != null && _wsController != null && !_wsController!.isClosed;

  // ── Health ────────────────────────────────────────────────────────────────

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

  // ── Watchlist ─────────────────────────────────────────────────────────────

  Future<List<WatchlistItem>> fetchWatchlist() async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.watchlist))
          .timeout(const Duration(seconds: 15));

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

  List<WatchlistItem> _fallbackWatchlist() => const [
        WatchlistItem(symbol: 'XAUUSD', name: 'Gold',      emoji: '⚡',  type: 'commodity'),
        WatchlistItem(symbol: 'BTCUSD', name: 'Bitcoin',   emoji: '₿',   type: 'crypto',   is24h: true),
        WatchlistItem(symbol: 'ETHUSD', name: 'Ethereum',  emoji: 'Ξ',   type: 'crypto',   is24h: true),
        WatchlistItem(symbol: 'SPX500', name: 'S&P 500',   emoji: '📊',  type: 'equity'),
        WatchlistItem(symbol: 'EURUSD', name: 'EUR/USD',   emoji: '💱',  type: 'forex'),
      ];

  // ── OHLCV ──────────────────────────────────────────────────────────────────
  //
  // v13.0 fix: main.py v12.0 wraps the OHLCV response in an envelope:
  //   { "candles": [...], "chartMetadata": {...} }
  // The previous code checked `decoded is! List` which always failed,
  // silently returning [].  We now unwrap the "candles" key first, then
  // fall back to treating the decoded value directly as a List for older
  // backend compatibility.

  Future<List<OhlcPoint>> fetchOhlcv(
    String symbol, {
    String interval = '15m',
  }) async {
    try {
      final uri = Uri.parse(ApiPaths.ohlcv(symbol, interval: interval));
      final r   = await _client
          .get(uri)
          .timeout(const Duration(seconds: 30));

      if (r.statusCode != 200) return [];

      final decoded = jsonDecode(r.body);

      // Handle envelope shape: {"candles": [...], "chartMetadata": {...}}
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

  // ── Analysis ───────────────────────────────────────────────────────────────

  Future<Map<String, AnalysisResult>> analyze(
    List<String> symbols, {
    bool runMtf    = true,
    double atrMult = 1.5,
    double rrRatio = 2.5,
  }) async {
    try {
      final r = await _client
          .post(
            Uri.parse(ApiPaths.analyze),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'symbols':  symbols,
              'run_mtf':  runMtf,
              'atr_mult': atrMult,
              'rr_ratio': rrRatio,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (r.statusCode != 200) {
        _debugPrint('analyze HTTP ${r.statusCode}: ${r.body}');
        return {};
      }

      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return {};

      final results = <String, AnalysisResult>{};
      decoded.forEach((symbol, data) {
        if (data is Map<String, dynamic>) {
          results[symbol] = AnalysisResult.fromJson(symbol, data);
        }
      });
      return results;
    } catch (e) {
      _debugPrint('analyze error: $e');
      return {};
    }
  }

  // ── Correlation ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchCorrelation() async {
    try {
      final r = await _client
          .get(Uri.parse(ApiPaths.correlation))
          .timeout(const Duration(seconds: 15));

      if (r.statusCode != 200) return {};

      final decoded = jsonDecode(r.body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      _debugPrint('fetchCorrelation error: $e');
      return {};
    }
  }

  // ── v12.0 — WebSocket live stream ─────────────────────────────────────────

  /// Opens (or re-opens) the WebSocket to /ws/live and returns a broadcast
  /// [Stream<WsFrame>].
  ///
  /// **Transport-level exception boundary:**
  /// Every incoming text message is independently decoded inside a try-catch.
  /// If [WsFrame.fromRaw] throws a [WsFrameParseException] or any other error,
  /// the client emits a sentinel [WsFrame] of type [WsFrameType.unknown] with
  /// the error details stored in [WsFrame.raw] under the key `_parseError`.
  /// This allows [MarketState] to log the problem without the stream closing.
  ///
  /// **Reconnection is the caller's responsibility.**
  /// When the backend closes the connection (stream done event), the stream
  /// simply ends.  [MarketState]'s watchdog timer handles reconnection by
  /// calling this method again.
  ///
  /// Call [sendFilter] after the stream is open to filter by symbols.
  Stream<WsFrame> wsFrameStream() {
    // Close any pre-existing channel before opening a new one.
    _closeWs();

    final channel    = WebSocketChannel.connect(ApiPaths.wsLive);
    _wsChannel       = channel;
    _wsController    = StreamController<WsFrame>.broadcast(
      onCancel: _closeWs,
    );

    channel.stream.listen(
      (dynamic raw) {
        // ── Per-message exception boundary ─────────────────────────────
        if (raw is! String) {
          // Binary frames are not expected from main.py; skip silently.
          return;
        }
        WsFrame frame;
        try {
          // NexusApiClient owns the JSON decode step here.
          // WsFrame.fromRaw receives the raw text and calls jsonDecode
          // internally only for the _jsonDecodeObject path; in practice
          // we pre-decode here to keep the transport layer explicit.
          final Map<String, dynamic> decoded = _decodeJsonObject(raw);
          frame = _buildFrameFromDecoded(decoded, raw);
        } catch (e) {
          // Emit a sentinel unknown frame so MarketState can log it.
          _debugPrint('WS frame parse error: $e\n  payload: '
              '${raw.length > 200 ? raw.substring(0, 200) : raw}');
          frame = WsFrame(
            type: WsFrameType.unknown,
            ts:   '',
            seq:  0,
            raw:  {'_parseError': e.toString(), '_rawPayload': raw},
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
        if (!_wsController!.isClosed) {
          _wsController!.close();
        }
      },
      cancelOnError: false,
    );

    return _wsController!.stream;
  }

  /// Sends a symbol-filter message to the server:
  ///   {"symbols": ["BTCUSD", "XAUUSD"]}
  /// Pass an empty list to subscribe to all assets (the backend default).
  /// No-op if the channel is not open.
  void sendFilter(List<String> symbols) {
    if (_wsChannel == null) return;
    try {
      _wsChannel!.sink.add(jsonEncode({'symbols': symbols}));
    } catch (e) {
      _debugPrint('sendFilter error: $e');
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Decodes a JSON string into a [Map<String, dynamic>].
  /// Throws [WsFrameParseException] when the input is not a JSON object.
  Map<String, dynamic> _decodeJsonObject(String text) {
    final dynamic decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw WsFrameParseException(
        'Expected JSON object, got ${decoded.runtimeType}',
        text,
      );
    }
    return decoded;
  }

  /// Constructs a [WsFrame] from a pre-decoded map.
  /// Any per-field error is absorbed by the model layer; this wrapper
  /// catches any residual throw and re-wraps it as a parse exception.
  WsFrame _buildFrameFromDecoded(Map<String, dynamic> j, String rawText) {
    try {
      return _wsFrameFromDecoded(j);
    } catch (e) {
      throw WsFrameParseException('Frame construction failed: $e', rawText);
    }
  }

  /// Builds a [WsFrame] from a decoded JSON map without requiring the
  /// raw string (already validated by [_decodeJsonObject]).
  WsFrame _wsFrameFromDecoded(Map<String, dynamic> j) {
    // Reuse the same parsing logic as WsFrame.fromRaw, but skip the
    // internal jsonDecode since we already have the decoded map.
    // We call WsFrame.fromRaw with a re-serialized string to keep the
    // single source of truth in the model layer.
    // Note: jsonEncode → fromRaw is safe but adds one encode/decode cycle.
    // For performance-critical production builds, refactor WsFrame to
    // accept a Map<String,dynamic> directly via a named constructor.
    return WsFrame.fromRaw(jsonEncode(j));
  }

  void _closeWs() {
    try { _wsChannel?.sink.close(); }   catch (_) {}
    try { _wsController?.close(); }     catch (_) {}
    _wsChannel    = null;
    _wsController = null;
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  void close() {
    _closeWs();
    _client.close();
  }
}

// ─── Debug print shim ─────────────────────────────────────────────────────────

void _debugPrint(String msg) {
  assert(() {
    // ignore: avoid_print
    print('[NEXUS-CLIENT] $msg');
    return true;
  }());
}