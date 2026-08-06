// ============================================================================
//  NEXUS v13.0 — market_models.dart
//  Complete data models matching every field emitted by engine.py + main.py.
//
//  v13.0 additions over v12.5:
//  ─────────────────────────────────────────────────────────────────────────
//  • ChartMetadata        — decimalPlaces, tickSize, marketStatus, etc.
//  • WsFrameType enum     — price_tick | metric_shift | heartbeat | …
//  • TickEntry            — per-symbol slice inside a price_tick frame
//  • MetricShift          — field change event from metric_shift frame
//  • WsFrameParseException— structural parse failure carrier
//  • WsFrame              — root WebSocket message model with seq validation
//  • NewsItem enriched    — imageUrl, sourceLogoUrl, impactPercentage,
//                           sentimentLabel (all injected by main.py v12.0)
//  • TradePlan getters    — bool get valid, String get direction (computed)
//  • OhlcPoint.withLiveTick — in-place last-candle mutation helper
//  All pre-existing models are fully retained.
// ============================================================================

// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'package:flutter/material.dart' show Color;

// ─── Scalar helpers ──────────────────────────────────────────────────────────

double _d(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

int _i(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

String _s(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

bool _b(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  return v.toString().toLowerCase() == 'true';
}

List<T> _list<T>(dynamic v, T Function(dynamic) mapper) {
  if (v == null || v is! List) return [];
  return v.map((e) => mapper(e)).whereType<T>().toList();
}

// ─── ChartMetadata ───────────────────────────────────────────────────────────
/// Injected per-symbol in /api/analyze and /api/ohlcv responses.
/// Drives Syncfusion axis configuration.

class ChartMetadata {
  final int    decimalPlaces;
  final double tickSize;
  final double rightViewportPaddingPct;
  final String marketStatus;   // "OPEN" | "CLOSED" | "PRE-MARKET"
  final String sessionLabel;
  final bool   is24h;
  final String assetColor;
  final String priceFormat;

  const ChartMetadata({
    this.decimalPlaces            = 2,
    this.tickSize                 = 0.01,
    this.rightViewportPaddingPct  = 20.0,
    this.marketStatus             = 'UNKNOWN',
    this.sessionLabel             = '',
    this.is24h                    = false,
    this.assetColor               = '#FFFFFF',
    this.priceFormat              = '#,##0.00',
  });

  factory ChartMetadata.fromJson(Map<String, dynamic> j) => ChartMetadata(
        decimalPlaces:           _i(j['decimalPlaces'],           2),
        tickSize:                _d(j['tickSize'],                0.01),
        rightViewportPaddingPct: _d(j['rightViewportPaddingPct'], 20.0),
        marketStatus:            _s(j['marketStatus'],            'UNKNOWN'),
        sessionLabel:            _s(j['sessionLabel']),
        is24h:                   _b(j['is24h'],                   false),
        assetColor:              _s(j['assetColor'],              '#FFFFFF'),
        priceFormat:             _s(j['priceFormat'],             '#,##0.00'),
      );
}

// ─── WatchlistItem ───────────────────────────────────────────────────────────

class WatchlistItem {
  final String          symbol;
  final String?         name;
  final String?         type;
  final double?         price;
  final double?         changePct;
  final String?         emoji;
  final String?         color;
  final bool            is24h;
  final ChartMetadata?  chartMetadata;

  const WatchlistItem({
    required this.symbol,
    this.name,
    this.type,
    this.price,
    this.changePct,
    this.emoji,
    this.color,
    this.is24h         = false,
    this.chartMetadata,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> j) {
    final cmRaw = j['chartMetadata'];
    return WatchlistItem(
      symbol:        _s(j['symbol']),
      name:          _s(j['name'],      ''),
      type:          _s(j['type'],      ''),
      price:         j['price']     != null ? _d(j['price'])     : null,
      changePct:     j['changePct'] != null ? _d(j['changePct']) : null,
      emoji:         _s(j['emoji'],     ''),
      color:         _s(j['color'],     ''),
      is24h:         _b(j['is24h'],     false),
      chartMetadata: cmRaw is Map<String, dynamic>
          ? ChartMetadata.fromJson(cmRaw)
          : null,
    );
  }

  bool get isCrypto =>
      type?.toLowerCase() == 'crypto' ||
      type?.toLowerCase() == 'cryptocurrency';

  bool get isForex => type?.toLowerCase() == 'forex';
}

// ─── OhlcPoint ───────────────────────────────────────────────────────────────

class OhlcPoint {
  final DateTime time;
  final double   open;
  final double   high;
  final double   low;
  final double   close;
  final double   volume;
  final int      decimalPlaces;
  final String   assetType;

  const OhlcPoint({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.decimalPlaces = 2,
    this.assetType     = '',
  });

  factory OhlcPoint.fromJson(Map<String, dynamic> j) {
    DateTime parseTime() {
      final raw = j['timestamp'] ?? j['t'];
      if (raw == null) return DateTime.now().toUtc();
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        return parsed != null ? parsed.toUtc() : DateTime.now().toUtc();
      }
      if (raw is int) {
        final ms = raw > 9999999999 ? raw : raw * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
      return DateTime.now().toUtc();
    }

    return OhlcPoint(
      time:          parseTime(),
      open:          _d(j['open']          ?? j['o']),
      high:          _d(j['high']          ?? j['h']),
      low:           _d(j['low']           ?? j['l']),
      close:         _d(j['close']         ?? j['c']),
      volume:        _d(j['volume']        ?? j['v']),
      decimalPlaces: _i(j['decimalPlaces'] ?? j['decimal_places'], 2),
      assetType:     _s(j['assetType']     ?? j['asset_type'],     ''),
    );
  }

  bool get isCrypto =>
      assetType.toLowerCase() == 'crypto' ||
      assetType.toLowerCase() == 'cryptocurrency';

  /// Returns a new [OhlcPoint] with updated close / high / low for in-place
  /// last-candle mutation from a WebSocket price tick.
  OhlcPoint withLiveTick({
    required double close,
    required double high,
    required double low,
  }) =>
      OhlcPoint(
        time:          time,
        open:          open,
        high:          high,
        low:           low,
        close:         close,
        volume:        volume,
        decimalPlaces: decimalPlaces,
        assetType:     assetType,
      );
}

// ─── CryptoMetrics ───────────────────────────────────────────────────────────

class CryptoMetrics {
  final bool   is24hMarket;
  final String sessionNote;
  final bool   isWeekend;
  final double change24hPct;
  final double buyVolume;
  final double sellVolume;
  final double volumeDelta;
  final double volumeDeltaPct;
  final String volumeDeltaSignal;
  final double cavbUpper;
  final double cavbMid;
  final double cavbLower;
  final double cavbWidth;
  final double normalizedBandwidth;
  final String cavbSignal;
  final String cavbPosition;

  const CryptoMetrics({
    this.is24hMarket         = true,
    this.sessionNote         = '',
    this.isWeekend           = false,
    this.change24hPct        = 0,
    this.buyVolume           = 0,
    this.sellVolume          = 0,
    this.volumeDelta         = 0,
    this.volumeDeltaPct      = 0,
    this.volumeDeltaSignal   = 'NEUTRAL',
    this.cavbUpper           = 0,
    this.cavbMid             = 0,
    this.cavbLower           = 0,
    this.cavbWidth           = 0,
    this.normalizedBandwidth = 0,
    this.cavbSignal          = 'NORMAL',
    this.cavbPosition        = 'MIDDLE',
  });

  factory CryptoMetrics.fromJson(Map<String, dynamic> j) => CryptoMetrics(
        is24hMarket:         _b(j['is24hMarket'],         true),
        sessionNote:         _s(j['sessionNote']),
        isWeekend:           _b(j['isWeekend'],           false),
        change24hPct:        _d(j['change24hPct']),
        buyVolume:           _d(j['buyVolume']),
        sellVolume:          _d(j['sellVolume']),
        volumeDelta:         _d(j['volumeDelta']),
        volumeDeltaPct:      _d(j['volumeDeltaPct']),
        volumeDeltaSignal:   _s(j['volumeDeltaSignal'],   'NEUTRAL'),
        cavbUpper:           _d(j['cavbUpper']),
        cavbMid:             _d(j['cavbMid']),
        cavbLower:           _d(j['cavbLower']),
        cavbWidth:           _d(j['cavbWidth']),
        normalizedBandwidth: _d(j['normalizedBandwidth']),
        cavbSignal:          _s(j['cavbSignal'],          'NORMAL'),
        cavbPosition:        _s(j['cavbPosition'],        'MIDDLE'),
      );
}

// ─── ForexMetrics ────────────────────────────────────────────────────────────

class ForexMetrics {
  final double pipSize;
  final bool   isJpyPair;
  final String sessionOverlap;
  final bool   isOverlapSession;
  final double change24hPct;

  const ForexMetrics({
    this.pipSize          = 0.0001,
    this.isJpyPair        = false,
    this.sessionOverlap   = 'OFF-HOURS',
    this.isOverlapSession = false,
    this.change24hPct     = 0,
  });

  factory ForexMetrics.fromJson(Map<String, dynamic> j) => ForexMetrics(
        pipSize:          _d(j['pipSize'],          0.0001),
        isJpyPair:        _b(j['isJpyPair'],        false),
        sessionOverlap:   _s(j['sessionOverlap'],   'OFF-HOURS'),
        isOverlapSession: _b(j['isOverlapSession'], false),
        change24hPct:     _d(j['change24hPct']),
      );
}

// ─── TradePlan ───────────────────────────────────────────────────────────────

class TradePlan {
  final double entry;
  final double sl;
  final double tp1;
  final double tp2;
  final double tp3;
  final double riskPerUnit;
  final double riskPips;
  final double rr1;
  final double rr2;
  final double confidence;
  final String quality;
  final String reasoning;
  final String invalidation;
  final String session;
  final String regime;
  final String newsRisk;
  final double probScore;
  final String mtf;
  final String positionNote;

  const TradePlan({
    this.entry        = 0,
    this.sl           = 0,
    this.tp1          = 0,
    this.tp2          = 0,
    this.tp3          = 0,
    this.riskPerUnit  = 0,
    this.riskPips     = 0,
    this.rr1          = 0,
    this.rr2          = 0,
    this.confidence   = 0,
    this.quality      = 'POOR',
    this.reasoning    = '',
    this.invalidation = '',
    this.session      = '',
    this.regime       = '',
    this.newsRisk     = 'NORMAL',
    this.probScore    = 50,
    this.mtf          = '',
    this.positionNote = '',
  });

  factory TradePlan.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const TradePlan();
    return TradePlan(
      entry:        _d(j['entry']),
      sl:           _d(j['sl']),
      tp1:          _d(j['tp1']),
      tp2:          _d(j['tp2']),
      tp3:          _d(j['tp3']),
      riskPerUnit:  _d(j['riskPerUnit']  ?? j['risk_per_unit']),
      riskPips:     _d(j['riskPips']     ?? j['risk_pips']),
      rr1:          _d(j['rr1']),
      rr2:          _d(j['rr2']),
      confidence:   _d(j['confidence']),
      quality:      _s(j['quality'],      'POOR'),
      reasoning:    _s(j['reasoning']),
      invalidation: _s(j['invalidation']),
      session:      _s(j['session']),
      regime:       _s(j['regime']),
      newsRisk:     _s(j['newsRisk']      ?? j['news_risk'], 'NORMAL'),
      probScore:    _d(j['probScore']     ?? j['prob_score'], 50),
      mtf:          _s(j['mtf']),
      positionNote: _s(j['positionNote']  ?? j['position_note']),
    );
  }

  /// True when the engine produced an actionable trade plan (entry > 0).
  bool get valid => entry > 0.0;

  /// Directional bias computed from reasoning text, with geometric fallback.
  String get direction {
    final r = reasoning.toUpperCase();
    if (r.contains('BUY') || r.contains('BULL') || r.contains('LONG'))  return 'BULLISH';
    if (r.contains('SELL') || r.contains('BEAR') || r.contains('SHORT')) return 'BEARISH';
    if (entry > 0.0) return tp1 > entry ? 'BULLISH' : 'BEARISH';
    return 'NEUTRAL';
  }
}

// ─── MarketIntelligence ──────────────────────────────────────────────────────

class MarketIntelligence {
  // Identity
  final String assetName;
  final String assetType;
  final String lastUpdate;
  final String dataSource;
  // Price
  final double currentPrice;
  final double priceChange;
  final double priceChangePct;
  // Master Signal
  final String safetySignal;
  final String signalColor;
  final int    signalStrength;
  final String direction;
  final int    bullScore;
  final int    bearScore;
  final String entryQuality;
  final String entryExplanation;
  // Probability
  final double probabilityBull;
  final String probabilityLabel;
  // EMAs
  final double ema9;
  final double ema21;
  final double ema50;
  final double ema200;
  final String emaAlignment;
  // RSI
  final double rsi;
  final String rsiSignal;
  final String rsiExplanation;
  // MACD
  final double macdLine;
  final double macdSignal;
  final double macdHist;
  final String macdCross;
  // Stochastic
  final double stochK;
  final double stochD;
  final String stochSignal;
  // Bollinger Bands
  final double bbUpper;
  final double bbMid;
  final double bbLower;
  final double bbWidth;
  final String bbPosition;
  final bool   bbSqueeze;
  // Keltner Channels
  final double kcUpper;
  final double kcMid;
  final double kcLower;
  // TTM Squeeze
  final bool   ttmSqueezeActive;
  final String ttmSqueezeLabel;
  final double ttmMomentum;
  // Supertrend
  final double supertrendValue;
  final String supertrendSignal;
  final String supertrendDirection;
  // VWAP
  final double vwap;
  final double vwapUpper;
  final double vwapLower;
  final String vwapSignal;
  // Pivots
  final Map<String, dynamic> pivotPoints;
  final String nearestPivotLevel;
  final double nearestPivotDist;
  // Z-Score
  final double zscore;
  final String zscoreSignal;
  // ADX
  final double adxValue;
  final String adxSignal;
  final double adxDiPlus;
  final double adxDiMinus;
  // Williams %R
  final double williamsR;
  final String williamsSignal;
  // CCI
  final double cciValue;
  final String cciSignal;
  // OBV
  final String obvTrend;
  final double obvValue;
  // Ichimoku
  final String ichimokuSignal;
  final double tenkan;
  final double kijun;
  // ATR & Stops
  final double  atr14;
  final double? slBuy;
  final double? slSell;
  final double? tpBuy;
  final double? tpSell;
  final double  slPips;
  final String  atrExplanation;
  final double  atrMultiplier;
  final double  rrRatio;
  // Quantum Metrics
  final double hurst;
  final String regime;
  final String regimeAdvanced;
  final double shannonEntropy;
  final double kaufmanEr;
  final double fractalDim;
  final double realizedVol;
  final String volRegime;
  final double kurtosis;
  final double skewness;
  final String tailRisk;
  final double autocorrLag1;
  final int    stabilityIndex;
  // Support / Resistance
  final List<double> supports;
  final List<double> resistances;
  final double nearestSupport;
  final double nearestResist;
  final String srZone;
  // Elliott Wave
  final String  wavePosition;
  final double  waveConfidence;
  final double? waveTarget;
  final String  waveTrend;
  // Fibonacci
  final Map<String, dynamic> fibRetracements;
  final Map<String, dynamic> fibExtensions;
  final String fibZone;
  final double fibStrength;
  final String fibExplanation;
  // Smart Money
  final List<dynamic> orderBlocks;
  final List<dynamic> fairValueGaps;
  final List<dynamic> liquiditySweeps;
  final String smcBias;
  final String smcExplanation;
  // Divergence
  final String rsiDivergence;
  final String macdDivergence;
  final String obvDivergence;
  final String divergenceSignal;
  final double divergenceStrength;
  // Candlestick Pattern
  final String candlePattern;
  final double candleStrength;
  final String candleDirection;
  final String candleExplanation;
  // Kelly
  final double kellyFraction;
  final String kellyRecommendation;
  // Session
  final String tradingSession;
  final String sessionLiquidity;
  final String sessionWarning;
  final String sessionExplanation;
  // News Lock
  final bool   newsLockActive;
  final String newsLockEvent;
  final String newsLockReason;
  // Macro Sentiment
  final int    macroSentimentScore;
  final String macroSentimentLabel;
  final int    macroBullHits;
  final int    macroBearHits;
  // MTF
  final Map<String, dynamic> mtfSignals;
  final String mtfConfluence;
  final int    mtfBullCount;
  final int    mtfBearCount;
  // Trade Plan
  final TradePlan tradePlan;
  // Lot Calculator
  final double riskDollars;
  final double recommendedLots;
  final String lotExplanation;
  final double requiredMargin;
  // Asset-type-specific
  final CryptoMetrics?  cryptoMetrics;
  final ForexMetrics?   forexMetrics;
  // v13.0: chart metadata injected per-symbol
  final ChartMetadata?  chartMetadata;

  const MarketIntelligence({
    this.assetName            = '',
    this.assetType            = '',
    this.lastUpdate           = '',
    this.dataSource           = '',
    this.currentPrice         = 0,
    this.priceChange          = 0,
    this.priceChangePct       = 0,
    this.safetySignal         = 'WAIT',
    this.signalColor          = '#FFD600',
    this.signalStrength       = 0,
    this.direction            = 'NEUTRAL',
    this.bullScore            = 0,
    this.bearScore            = 0,
    this.entryQuality         = 'POOR',
    this.entryExplanation     = '',
    this.probabilityBull      = 50,
    this.probabilityLabel     = 'NEUTRAL',
    this.ema9                 = 0,
    this.ema21                = 0,
    this.ema50                = 0,
    this.ema200               = 0,
    this.emaAlignment         = 'NEUTRAL',
    this.rsi                  = 50,
    this.rsiSignal            = 'NEUTRAL',
    this.rsiExplanation       = '',
    this.macdLine             = 0,
    this.macdSignal           = 0,
    this.macdHist             = 0,
    this.macdCross            = 'NEUTRAL',
    this.stochK               = 50,
    this.stochD               = 50,
    this.stochSignal          = 'NEUTRAL',
    this.bbUpper              = 0,
    this.bbMid                = 0,
    this.bbLower              = 0,
    this.bbWidth              = 0,
    this.bbPosition           = 'MIDDLE',
    this.bbSqueeze            = false,
    this.kcUpper              = 0,
    this.kcMid                = 0,
    this.kcLower              = 0,
    this.ttmSqueezeActive     = false,
    this.ttmSqueezeLabel      = 'SQUEEZE OFF',
    this.ttmMomentum          = 0,
    this.supertrendValue      = 0,
    this.supertrendSignal     = 'NEUTRAL',
    this.supertrendDirection  = 'NEUTRAL',
    this.vwap                 = 0,
    this.vwapUpper            = 0,
    this.vwapLower            = 0,
    this.vwapSignal           = 'NEUTRAL',
    this.pivotPoints          = const {},
    this.nearestPivotLevel    = '',
    this.nearestPivotDist     = 0,
    this.zscore               = 0,
    this.zscoreSignal         = 'NEUTRAL',
    this.adxValue             = 0,
    this.adxSignal            = 'WEAK',
    this.adxDiPlus            = 0,
    this.adxDiMinus           = 0,
    this.williamsR            = -50,
    this.williamsSignal       = 'NEUTRAL',
    this.cciValue             = 0,
    this.cciSignal            = 'NEUTRAL',
    this.obvTrend             = 'NEUTRAL',
    this.obvValue             = 0,
    this.ichimokuSignal       = 'NEUTRAL',
    this.tenkan               = 0,
    this.kijun                = 0,
    this.atr14                = 0,
    this.slBuy,
    this.slSell,
    this.tpBuy,
    this.tpSell,
    this.slPips               = 0,
    this.atrExplanation       = '',
    this.atrMultiplier        = 1.5,
    this.rrRatio              = 2.5,
    this.hurst                = 0.5,
    this.regime               = 'RANDOM',
    this.regimeAdvanced       = 'CHOPPY',
    this.shannonEntropy       = 0,
    this.kaufmanEr            = 0,
    this.fractalDim           = 1.5,
    this.realizedVol          = 0,
    this.volRegime            = 'NORMAL',
    this.kurtosis             = 0,
    this.skewness             = 0,
    this.tailRisk             = 'NORMAL',
    this.autocorrLag1         = 0,
    this.stabilityIndex       = 50,
    this.supports             = const [],
    this.resistances          = const [],
    this.nearestSupport       = 0,
    this.nearestResist        = 0,
    this.srZone               = 'MIDDLE',
    this.wavePosition         = 'UNKNOWN',
    this.waveConfidence       = 0,
    this.waveTarget,
    this.waveTrend            = 'NEUTRAL',
    this.fibRetracements      = const {},
    this.fibExtensions        = const {},
    this.fibZone              = 'NEUTRAL',
    this.fibStrength          = 0,
    this.fibExplanation       = '',
    this.orderBlocks          = const [],
    this.fairValueGaps        = const [],
    this.liquiditySweeps      = const [],
    this.smcBias              = 'NEUTRAL',
    this.smcExplanation       = '',
    this.rsiDivergence        = 'NONE',
    this.macdDivergence       = 'NONE',
    this.obvDivergence        = 'NEUTRAL',
    this.divergenceSignal     = 'NONE',
    this.divergenceStrength   = 0,
    this.candlePattern        = 'NONE',
    this.candleStrength       = 0,
    this.candleDirection      = 'NEUTRAL',
    this.candleExplanation    = '',
    this.kellyFraction        = 0,
    this.kellyRecommendation  = '',
    this.tradingSession       = 'OFF-HOURS',
    this.sessionLiquidity     = 'LOW',
    this.sessionWarning       = '',
    this.sessionExplanation   = '',
    this.newsLockActive       = false,
    this.newsLockEvent        = '',
    this.newsLockReason       = '',
    this.macroSentimentScore  = 50,
    this.macroSentimentLabel  = 'NEUTRAL',
    this.macroBullHits        = 0,
    this.macroBearHits        = 0,
    this.mtfSignals           = const {},
    this.mtfConfluence        = 'NEUTRAL',
    this.mtfBullCount         = 0,
    this.mtfBearCount         = 0,
    this.tradePlan            = const TradePlan(),
    this.riskDollars          = 0,
    this.recommendedLots      = 0,
    this.lotExplanation       = '',
    this.requiredMargin       = 0,
    this.cryptoMetrics,
    this.forexMetrics,
    this.chartMetadata,
  });

  factory MarketIntelligence.fromJson(Map<String, dynamic> j) {
    final tp    = j['tradePlan'];
    final cmRaw = j['cryptoMetrics'];
    final fmRaw = j['forexMetrics'];
    final mdRaw = j['chartMetadata'];

    return MarketIntelligence(
      assetName:            _s(j['assetName']),
      assetType:            _s(j['assetType']),
      lastUpdate:           _s(j['lastUpdate']),
      dataSource:           _s(j['dataSource']),
      currentPrice:         _d(j['currentPrice']),
      priceChange:          _d(j['priceChange']),
      priceChangePct:       _d(j['priceChangePct']),
      safetySignal:         _s(j['safetySignal'],        'WAIT'),
      signalColor:          _s(j['signalColor'],         '#FFD600'),
      signalStrength:       _i(j['signalStrength']),
      direction:            _s(j['direction'],           'NEUTRAL'),
      bullScore:            _i(j['bullScore']),
      bearScore:            _i(j['bearScore']),
      entryQuality:         _s(j['entryQuality'],        'POOR'),
      entryExplanation:     _s(j['entryExplanation']),
      probabilityBull:      _d(j['probabilityBull'],     50),
      probabilityLabel:     _s(j['probabilityLabel'],    'NEUTRAL'),
      ema9:                 _d(j['ema9']),
      ema21:                _d(j['ema21']),
      ema50:                _d(j['ema50']),
      ema200:               _d(j['ema200']),
      emaAlignment:         _s(j['emaAlignment'],        'NEUTRAL'),
      rsi:                  _d(j['rsi'],                 50),
      rsiSignal:            _s(j['rsiSignal'],           'NEUTRAL'),
      rsiExplanation:       _s(j['rsiExplanation']),
      macdLine:             _d(j['macdLine']),
      macdSignal:           _d(j['macdSignal']),
      macdHist:             _d(j['macdHist']),
      macdCross:            _s(j['macdCross'],           'NEUTRAL'),
      stochK:               _d(j['stochK'],              50),
      stochD:               _d(j['stochD'],              50),
      stochSignal:          _s(j['stochSignal'],         'NEUTRAL'),
      bbUpper:              _d(j['bbUpper']),
      bbMid:                _d(j['bbMid']),
      bbLower:              _d(j['bbLower']),
      bbWidth:              _d(j['bbWidth']),
      bbPosition:           _s(j['bbPosition'],          'MIDDLE'),
      bbSqueeze:            _b(j['bbSqueeze']),
      kcUpper:              _d(j['kcUpper']),
      kcMid:                _d(j['kcMid']),
      kcLower:              _d(j['kcLower']),
      ttmSqueezeActive:     _b(j['ttmSqueezeActive']),
      ttmSqueezeLabel:      _s(j['ttmSqueezeLabel'],     'SQUEEZE OFF'),
      ttmMomentum:          _d(j['ttmMomentum']),
      supertrendValue:      _d(j['supertrendValue']),
      supertrendSignal:     _s(j['supertrendSignal'],    'NEUTRAL'),
      supertrendDirection:  _s(j['supertrendDirection'], 'NEUTRAL'),
      vwap:                 _d(j['vwap']),
      vwapUpper:            _d(j['vwapUpper']),
      vwapLower:            _d(j['vwapLower']),
      vwapSignal:           _s(j['vwapSignal'],          'NEUTRAL'),
      pivotPoints:          (j['pivotPoints'] as Map<String, dynamic>?) ?? {},
      nearestPivotLevel:    _s(j['nearestPivotLevel']),
      nearestPivotDist:     _d(j['nearestPivotDist']),
      zscore:               _d(j['zscore']),
      zscoreSignal:         _s(j['zscoreSignal'],        'NEUTRAL'),
      adxValue:             _d(j['adxValue']),
      adxSignal:            _s(j['adxSignal'],           'WEAK'),
      adxDiPlus:            _d(j['adxDiPlus']),
      adxDiMinus:           _d(j['adxDiMinus']),
      williamsR:            _d(j['williamsR'],           -50),
      williamsSignal:       _s(j['williamsSignal'],      'NEUTRAL'),
      cciValue:             _d(j['cciValue']),
      cciSignal:            _s(j['cciSignal'],           'NEUTRAL'),
      obvTrend:             _s(j['obvTrend'],            'NEUTRAL'),
      obvValue:             _d(j['obvValue']),
      ichimokuSignal:       _s(j['ichimokuSignal'],      'NEUTRAL'),
      tenkan:               _d(j['tenkan']),
      kijun:                _d(j['kijun']),
      atr14:                _d(j['atr14']),
      slBuy:                j['slBuy']  != null ? _d(j['slBuy'])  : null,
      slSell:               j['slSell'] != null ? _d(j['slSell']) : null,
      tpBuy:                j['tpBuy']  != null ? _d(j['tpBuy'])  : null,
      tpSell:               j['tpSell'] != null ? _d(j['tpSell']) : null,
      slPips:               _d(j['slPips']),
      atrExplanation:       _s(j['atrExplanation']),
      atrMultiplier:        _d(j['atrMultiplier'],       1.5),
      rrRatio:              _d(j['rrRatio'],             2.5),
      hurst:                _d(j['hurst'],               0.5),
      regime:               _s(j['regime'],              'RANDOM'),
      regimeAdvanced:       _s(j['regimeAdvanced'],      'CHOPPY'),
      shannonEntropy:       _d(j['shannonEntropy']),
      kaufmanEr:            _d(j['kaufmanEr']),
      fractalDim:           _d(j['fractalDim'],          1.5),
      realizedVol:          _d(j['realizedVol']),
      volRegime:            _s(j['volRegime'],           'NORMAL'),
      kurtosis:             _d(j['kurtosis']),
      skewness:             _d(j['skewness']),
      tailRisk:             _s(j['tailRisk'],            'NORMAL'),
      autocorrLag1:         _d(j['autocorrLag1']),
      stabilityIndex:       _i(j['stabilityIndex'],      50),
      supports:             _list(j['supports'],     (e) => _d(e)),
      resistances:          _list(j['resistances'],  (e) => _d(e)),
      nearestSupport:       _d(j['nearestSupport']),
      nearestResist:        _d(j['nearestResist']),
      srZone:               _s(j['srZone'],              'MIDDLE'),
      wavePosition:         _s(j['wavePosition'],        'UNKNOWN'),
      waveConfidence:       _d(j['waveConfidence']),
      waveTarget:           j['waveTarget'] != null ? _d(j['waveTarget']) : null,
      waveTrend:            _s(j['waveTrend'],           'NEUTRAL'),
      fibRetracements:      (j['fibRetracements'] as Map<String, dynamic>?) ?? {},
      fibExtensions:        (j['fibExtensions']   as Map<String, dynamic>?) ?? {},
      fibZone:              _s(j['fibZone'],             'NEUTRAL'),
      fibStrength:          _d(j['fibStrength']),
      fibExplanation:       _s(j['fibExplanation']),
      orderBlocks:          (j['orderBlocks']     as List?) ?? [],
      fairValueGaps:        (j['fairValueGaps']   as List?) ?? [],
      liquiditySweeps:      (j['liquiditySweeps'] as List?) ?? [],
      smcBias:              _s(j['smcBias'],             'NEUTRAL'),
      smcExplanation:       _s(j['smcExplanation']),
      rsiDivergence:        _s(j['rsiDivergence'],       'NONE'),
      macdDivergence:       _s(j['macdDivergence'],      'NONE'),
      obvDivergence:        _s(j['obvDivergence'],       'NEUTRAL'),
      divergenceSignal:     _s(j['divergenceSignal'],    'NONE'),
      divergenceStrength:   _d(j['divergenceStrength']),
      candlePattern:        _s(j['candlePattern'],       'NONE'),
      candleStrength:       _d(j['candleStrength']),
      candleDirection:      _s(j['candleDirection'],     'NEUTRAL'),
      candleExplanation:    _s(j['candleExplanation']),
      kellyFraction:        _d(j['kellyFraction']),
      kellyRecommendation:  _s(j['kellyRecommendation']),
      tradingSession:       _s(j['tradingSession'],      'OFF-HOURS'),
      sessionLiquidity:     _s(j['sessionLiquidity'],    'LOW'),
      sessionWarning:       _s(j['sessionWarning']),
      sessionExplanation:   _s(j['sessionExplanation']),
      newsLockActive:       _b(j['newsLockActive']),
      newsLockEvent:        _s(j['newsLockEvent']),
      newsLockReason:       _s(j['newsLockReason']),
      macroSentimentScore:  _i(j['macroSentimentScore'], 50),
      macroSentimentLabel:  _s(j['macroSentimentLabel'], 'NEUTRAL'),
      macroBullHits:        _i(j['macroBullHits']),
      macroBearHits:        _i(j['macroBearHits']),
      mtfSignals:           (j['mtfSignals'] as Map<String, dynamic>?) ?? {},
      mtfConfluence:        _s(j['mtfConfluence'],       'NEUTRAL'),
      mtfBullCount:         _i(j['mtfBullCount']),
      mtfBearCount:         _i(j['mtfBearCount']),
      tradePlan:            TradePlan.fromJson(tp is Map<String, dynamic> ? tp : null),
      riskDollars:          _d(j['riskDollars']),
      recommendedLots:      _d(j['recommendedLots']),
      lotExplanation:       _s(j['lotExplanation']),
      requiredMargin:       _d(j['requiredMargin']),
      cryptoMetrics: cmRaw is Map<String, dynamic> && cmRaw.isNotEmpty
          ? CryptoMetrics.fromJson(cmRaw) : null,
      forexMetrics:  fmRaw is Map<String, dynamic> && fmRaw.isNotEmpty
          ? ForexMetrics.fromJson(fmRaw)  : null,
      chartMetadata: mdRaw is Map<String, dynamic>
          ? ChartMetadata.fromJson(mdRaw) : null,
    );
  }

  bool get isCrypto =>
      assetType.toLowerCase() == 'crypto' ||
      assetType.toLowerCase() == 'cryptocurrency';

  bool get isForex => assetType.toLowerCase() == 'forex';
}

// ─── NewsItem ────────────────────────────────────────────────────────────────
/// v13.0: added imageUrl, sourceLogoUrl, impactPercentage, sentimentLabel
/// injected by main.py v12.0 _enrich_news_item().

class NewsItem {
  final String title;
  final String source;
  final String published;
  final String url;
  final String category;
  final String nexusComment;
  final String quantAction;
  final double sentimentScore;
  final List<String> affectedAssets;
  // v13.0 enriched fields — always non-null (CDN fallback in backend)
  final String imageUrl;
  final String sourceLogoUrl;
  final double impactPercentage;
  final String sentimentLabel;

  const NewsItem({
    required this.title,
    required this.source,
    required this.published,
    required this.url,
    required this.category,
    required this.nexusComment,
    required this.quantAction,
    this.sentimentScore    = 0,
    this.affectedAssets    = const [],
    this.imageUrl          = '',
    this.sourceLogoUrl     = '',
    this.impactPercentage  = 50.0,
    this.sentimentLabel    = 'NEUTRAL',
  });

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        title:            _s(j['title']),
        source:           _s(j['source']),
        published:        _s(j['published']),
        url:              _s(j['url']),
        category:         _s(j['category']),
        nexusComment:     _s(j['nexusComment']    ?? j['nexus_comment']),
        quantAction:      _s(j['quantAction']     ?? j['quant_action']),
        sentimentScore:   _d(j['sentimentScore']  ?? j['sentiment_score']),
        affectedAssets:   _list(j['affectedAssets'] ?? j['affected_assets'],
                                (e) => e.toString()),
        imageUrl:         _s(j['imageUrl']         ?? j['image_url']),
        sourceLogoUrl:    _s(j['sourceLogoUrl']    ?? j['source_logo_url']),
        impactPercentage: _d(j['impactPercentage'] ?? j['impact_percentage'], 50.0),
        sentimentLabel:   _s(j['sentimentLabel']   ?? j['sentiment_label'], 'NEUTRAL'),
      );

  Color get categoryColor {
    switch (category.toUpperCase()) {
      case 'CRITICAL': return const Color(0xFFFF3131);
      case 'HIGH':     return const Color(0xFFFF9800);
      case 'MEDIUM':   return const Color(0xFFFFD600);
      default:         return const Color(0xFF6B6B6B);
    }
  }
}

// ─── AnalysisResult ──────────────────────────────────────────────────────────

class AnalysisResult {
  final String             symbol;
  final MarketIntelligence intelligence;
  final List<NewsItem>     news;
  final String             source;

  const AnalysisResult({
    required this.symbol,
    required this.intelligence,
    this.news   = const [],
    this.source = '',
  });

  factory AnalysisResult.fromJson(String symbol, Map<String, dynamic> data) {
    final intelRaw = data['intelligence'];
    final newsRaw  = data['news'];
    return AnalysisResult(
      symbol:       symbol,
      intelligence: intelRaw is Map<String, dynamic>
          ? MarketIntelligence.fromJson(intelRaw)
          : const MarketIntelligence(),
      news: newsRaw is List
          ? newsRaw.whereType<Map<String, dynamic>>()
              .map(NewsItem.fromJson).toList()
          : [],
      source: _s(data['source']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  v13.0 — WEBSOCKET FRAME MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// All frame types emitted by main.py /ws/live.
enum WsFrameType {
  connected,
  priceTick,
  metricShift,
  heartbeat,
  filterAck,
  unknown,
}

WsFrameType _parseFrameType(dynamic raw) {
  switch (raw?.toString()) {
    case 'connected':    return WsFrameType.connected;
    case 'price_tick':   return WsFrameType.priceTick;
    case 'metric_shift': return WsFrameType.metricShift;
    case 'heartbeat':    return WsFrameType.heartbeat;
    case 'filter_ack':   return WsFrameType.filterAck;
    default:             return WsFrameType.unknown;
  }
}

/// One symbol's price slice inside a price_tick or connected frame.
class TickEntry {
  final String symbol;
  final double price;
  final double changePct;
  final String direction;    // "UP" | "DOWN" | "FLAT"
  final double glowIntensity; // 0.0–1.0 for AnimationController

  const TickEntry({
    required this.symbol,
    required this.price,
    this.changePct     = 0.0,
    this.direction     = 'FLAT',
    this.glowIntensity = 0.0,
  });

  factory TickEntry.fromJson(String symbol, Map<String, dynamic> j) {
    double price = 0.0;
    double changePct = 0.0;
    String direction = 'FLAT';
    double glowIntensity = 0.0;
    try { price         = _d(j['price']); }         catch (_) {}
    try { changePct     = _d(j['changePct']); }     catch (_) {}
    try { direction     = _s(j['direction'], 'FLAT'); } catch (_) {}
    try { glowIntensity = _d(j['glowIntensity']); } catch (_) {}
    return TickEntry(
      symbol:        symbol,
      price:         price,
      changePct:     changePct,
      direction:     direction,
      glowIntensity: glowIntensity,
    );
  }
}

/// Payload of a metric_shift frame.
class MetricShift {
  final String symbol;
  final String field;
  final String previous;
  final String current;
  final String ts;

  const MetricShift({
    required this.symbol,
    required this.field,
    required this.previous,
    required this.current,
    this.ts = '',
  });

  factory MetricShift.fromJson(Map<String, dynamic> j) => MetricShift(
        symbol:   _s(j['symbol']),
        field:    _s(j['field']),
        previous: _s(j['previous']),
        current:  _s(j['current']),
        ts:       _s(j['ts']),
      );
}

/// Thrown when a WebSocket frame is structurally unrecoverable.
class WsFrameParseException implements Exception {
  final String message;
  final String rawPayload;
  const WsFrameParseException(this.message, this.rawPayload);

  @override
  String toString() =>
      'WsFrameParseException: $message\n  payload: '
      '${rawPayload.length > 200 ? "${rawPayload.substring(0, 200)}…" : rawPayload}';
}

/// Root model for every message arriving from /ws/live.
class WsFrame {
  final WsFrameType            type;
  final String                 ts;
  final int                    seq;
  final Map<String, TickEntry> ticks;
  final MetricShift?           shift;
  final Map<String, dynamic>   raw;

  const WsFrame({
    required this.type,
    required this.ts,
    required this.seq,
    required this.raw,
    this.ticks = const {},
    this.shift,
  });

  factory WsFrame.fromRaw(String rawText) {
    if (rawText.isEmpty) throw WsFrameParseException('Empty frame', rawText);

    Map<String, dynamic> j;
    try {
      final dynamic decoded = jsonDecode(rawText);
      if (decoded is! Map<String, dynamic>) {
        throw WsFrameParseException(
            'Expected JSON object, got ${decoded.runtimeType}', rawText);
      }
      j = decoded;
    } catch (e) {
      if (e is WsFrameParseException) rethrow;
      throw WsFrameParseException('JSON decode failed: $e', rawText);
    }

    final type = _parseFrameType(j['type']);

    int seq = 0;
    try { seq = _i(j['seq'], 0); } catch (_) {}

    String ts = '';
    try { ts = _s(j['ts']); } catch (_) {}

    final ticks = <String, TickEntry>{};
    if (type == WsFrameType.priceTick || type == WsFrameType.connected) {
      try {
        final dataRaw = j['data'];
        if (dataRaw is Map<String, dynamic>) {
          dataRaw.forEach((sym, val) {
            try {
              if (val is Map<String, dynamic>) {
                ticks[sym] = TickEntry.fromJson(sym, val);
              }
            } catch (_) {}
          });
        }
      } catch (_) {}
    }

    MetricShift? shift;
    if (type == WsFrameType.metricShift) {
      try { shift = MetricShift.fromJson(j); } catch (_) {}
    }

    return WsFrame(type: type, ts: ts, seq: seq, raw: j, ticks: ticks, shift: shift);
  }
}