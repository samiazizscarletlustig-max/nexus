// ============================================================================
//  NEXUS v13.8 — market_models.dart
//  Complete data models matching every field emitted by engine.py v13.8
//  + main.py v13.8 + ai_planner.py v13.8 (Institutional Grade).
// ============================================================================

// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Color, IconData, Icons;

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  SCALAR HELPERS — bulletproof JSON extraction
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

double _d(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is double) return v.isFinite ? v : fallback;
  if (v is int) return v.toDouble();
  if (v is num) return v.isFinite ? v.toDouble() : fallback;
  final parsed = double.tryParse(v.toString());
  return (parsed != null && parsed.isFinite) ? parsed : fallback;
}

int _i(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.round();
  final parsed = int.tryParse(v.toString());
  if (parsed != null) return parsed;
  final d = double.tryParse(v.toString());
  return d != null ? d.round() : fallback;
}

String _s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

bool _b(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return fallback;
}

Map<String, dynamic> _map(dynamic v) {
  if (v == null) return const <String, dynamic>{};
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return const <String, dynamic>{};
}

List<T> _listSafe<T>(dynamic v, T Function(dynamic) mapper) {
  if (v == null || v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    try {
      final mapped = mapper(e);
      out.add(mapped);
    } catch (_) {}
  }
  return out;
}

List<T> _list<T>(dynamic v, T Function(dynamic) mapper) =>
    _listSafe<T>(v, mapper);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ChartMetadata
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class ChartMetadata {
  final int decimalPlaces;
  final double tickSize;
  final double rightViewportPaddingPct;
  final String marketStatus;
  final String sessionLabel;
  final bool is24h;
  final String assetColor;
  final String priceFormat;

  const ChartMetadata({
    this.decimalPlaces = 2,
    this.tickSize = 0.01,
    this.rightViewportPaddingPct = 20.0,
    this.marketStatus = 'UNKNOWN',
    this.sessionLabel = '',
    this.is24h = false,
    this.assetColor = '#FFFFFF',
    this.priceFormat = '#,##0.00',
  });

  factory ChartMetadata.fromJson(Map<String, dynamic> j) => ChartMetadata(
        decimalPlaces: _i(j['decimalPlaces'] ?? j['decimal_places'], 2),
        tickSize: _d(j['tickSize'] ?? j['tick_size'], 0.01),
        rightViewportPaddingPct: _d(
            j['rightViewportPaddingPct'] ?? j['right_viewport_padding_pct'],
            20.0),
        marketStatus: _s(j['marketStatus'] ?? j['market_status'], 'UNKNOWN'),
        sessionLabel: _s(j['sessionLabel'] ?? j['session_label']),
        is24h: _b(j['is24h'] ?? j['is_24h'] ?? j['is24_7'], false),
        assetColor: _s(j['assetColor'] ?? j['asset_color'], '#FFFFFF'),
        priceFormat: _s(j['priceFormat'] ?? j['price_format'], '#,##0.00'),
      );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  WatchlistItem
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class WatchlistItem {
  final String symbol;
  final String name;
  final String type;
  final double? price;
  final double? changePct;
  final String emoji;
  final String color;
  final bool is24h;
  final ChartMetadata? chartMetadata;

  const WatchlistItem({
    required this.symbol,
    this.name = '',
    this.type = '',
    this.price,
    this.changePct,
    this.emoji = '',
    this.color = '',
    this.is24h = false,
    this.chartMetadata,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> j) {
    final cmRaw = j['chartMetadata'] ?? j['chart_metadata'];
    return WatchlistItem(
      symbol: _s(j['symbol'], '???'),
      name: _s(j['name']),
      type: _s(j['type']),
      price: j['price'] != null ? _d(j['price']) : null,
      changePct: j['changePct'] != null
          ? _d(j['changePct'] ?? j['change_pct'])
          : null,
      emoji: _s(j['emoji']),
      color: _s(j['color']),
      is24h: _b(j['is24h'] ?? j['is_24h'] ?? j['is24_7'], false),
      chartMetadata:
          cmRaw is Map ? ChartMetadata.fromJson(_map(cmRaw)) : null,
    );
  }

  bool get isCrypto =>
      type.toLowerCase() == 'crypto' ||
      type.toLowerCase() == 'cryptocurrency' ||
      type.toLowerCase() == 'digital';

  bool get isForex => type.toLowerCase() == 'forex';
  bool get isCommodity => type.toLowerCase() == 'commodity' || type.toLowerCase() == 'metal';
  bool get isIndex => type.toLowerCase() == 'index';
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  OhlcPoint
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class OhlcPoint {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final int decimalPlaces;
  final String assetType;

  const OhlcPoint({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.decimalPlaces = 2,
    this.assetType = '',
  });

  factory OhlcPoint.fromJson(Map<String, dynamic> j) {
    DateTime parseTime() {
      final raw = j['timestamp'] ?? j['time'] ?? j['t'] ?? j['date'];
      if (raw == null) return DateTime.now().toUtc();
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        return parsed != null ? parsed.toUtc() : DateTime.now().toUtc();
      }
      if (raw is num) {
        final ms = raw > 9999999999 ? raw.toInt() : (raw * 1000).toInt();
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
      return DateTime.now().toUtc();
    }

    return OhlcPoint(
      time: parseTime(),
      open: _d(j['open'] ?? j['o']),
      high: _d(j['high'] ?? j['h']),
      low: _d(j['low'] ?? j['l']),
      close: _d(j['close'] ?? j['c']),
      volume: _d(j['volume'] ?? j['v']),
      decimalPlaces: _i(j['decimalPlaces'] ?? j['decimal_places'], 2),
      assetType: _s(j['assetType'] ?? j['asset_type']),
    );
  }

  bool get isCrypto => assetType.toLowerCase() == 'crypto' || assetType.toLowerCase() == 'cryptocurrency';
  bool get isForex => assetType.toLowerCase() == 'forex';

  OhlcPoint withLiveTick({required double close, required double high, required double low}) =>
      OhlcPoint(
        time: time, open: open, high: high, low: low, close: close,
        volume: volume, decimalPlaces: decimalPlaces, assetType: assetType,
      );

  double get change => close - open;
  double get changePct => open != 0 ? (change / open) * 100 : 0;
  double get range => high - low;
  double get bodySize => change.abs();
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  CryptoMetrics
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class CryptoMetrics {
  final bool is24hMarket;
  final String sessionNote;
  final bool isWeekend;
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
    this.is24hMarket = true, this.sessionNote = '', this.isWeekend = false,
    this.change24hPct = 0, this.buyVolume = 0, this.sellVolume = 0,
    this.volumeDelta = 0, this.volumeDeltaPct = 0, this.volumeDeltaSignal = 'NEUTRAL',
    this.cavbUpper = 0, this.cavbMid = 0, this.cavbLower = 0, this.cavbWidth = 0,
    this.normalizedBandwidth = 0, this.cavbSignal = 'NORMAL', this.cavbPosition = 'MIDDLE',
  });

  factory CryptoMetrics.fromJson(Map<String, dynamic> j) => CryptoMetrics(
    is24hMarket: _b(j['is24hMarket'] ?? j['is_24h_market'], true),
    sessionNote: _s(j['sessionNote'] ?? j['session_note']),
    isWeekend: _b(j['isWeekend'] ?? j['is_weekend'], false),
    change24hPct: _d(j['change24hPct'] ?? j['change_24h_pct']),
    buyVolume: _d(j['buyVolume'] ?? j['buy_volume']),
    sellVolume: _d(j['sellVolume'] ?? j['sell_volume']),
    volumeDelta: _d(j['volumeDelta'] ?? j['volume_delta']),
    volumeDeltaPct: _d(j['volumeDeltaPct'] ?? j['volume_delta_pct']),
    volumeDeltaSignal: _s(j['volumeDeltaSignal'] ?? j['volume_delta_signal'], 'NEUTRAL'),
    cavbUpper: _d(j['cavbUpper'] ?? j['cavb_upper']),
    cavbMid: _d(j['cavbMid'] ?? j['cavb_mid']),
    cavbLower: _d(j['cavbLower'] ?? j['cavb_lower']),
    cavbWidth: _d(j['cavbWidth'] ?? j['cavb_width']),
    normalizedBandwidth: _d(j['normalizedBandwidth'] ?? j['normalized_bandwidth']),
    cavbSignal: _s(j['cavbSignal'] ?? j['cavb_signal'], 'NORMAL'),
    cavbPosition: _s(j['cavbPosition'] ?? j['cavb_position'], 'MIDDLE'),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ForexMetrics
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class ForexMetrics {
  final double pipSize;
  final bool isJpyPair;
  final String sessionOverlap;
  final bool isOverlapSession;
  final double change24hPct;

  const ForexMetrics({
    this.pipSize = 0.0001, this.isJpyPair = false,
    this.sessionOverlap = 'OFF-HOURS', this.isOverlapSession = false,
    this.change24hPct = 0,
  });

  factory ForexMetrics.fromJson(Map<String, dynamic> j) => ForexMetrics(
    pipSize: _d(j['pipSize'] ?? j['pip_size'], 0.0001),
    isJpyPair: _b(j['isJpyPair'] ?? j['is_jpy_pair'], false),
    sessionOverlap: _s(j['sessionOverlap'] ?? j['session_overlap'], 'OFF-HOURS'),
    isOverlapSession: _b(j['isOverlapSession'] ?? j['is_overlap_session'], false),
    change24hPct: _d(j['change24hPct'] ?? j['change_24h_pct']),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  TradePlan
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
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
  final bool valid;
  final String directionRaw;
  final Map<String, double> layerScores;
  final Map<String, dynamic> proxyOrderFlow;
  final double expectancyPerDollar;
  final double volatilityAdjustedRiskPct;
  final int bullLayers;
  final int bearLayers;
  final double estimatedWinRate;
  final List<String> reasons;

  const TradePlan({
    this.entry = 0, this.sl = 0, this.tp1 = 0, this.tp2 = 0, this.tp3 = 0,
    this.riskPerUnit = 0, this.riskPips = 0, this.rr1 = 0, this.rr2 = 0,
    this.confidence = 0, this.quality = 'POOR', this.reasoning = '',
    this.invalidation = '', this.session = '', this.regime = '',
    this.newsRisk = 'NORMAL', this.probScore = 50, this.mtf = '',
    this.positionNote = '', this.valid = false, this.directionRaw = 'NEUTRAL',
    this.layerScores = const {}, this.proxyOrderFlow = const {},
    this.expectancyPerDollar = 0, this.volatilityAdjustedRiskPct = 1.0,
    this.bullLayers = 0, this.bearLayers = 0, this.estimatedWinRate = 0.5,
    this.reasons = const [],
  });

  factory TradePlan.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const TradePlan();
    final rawLayers = _map(j['layerScores'] ?? j['layer_scores']);
    final layers = <String, double>{};
    rawLayers.forEach((k, v) { layers[k] = _d(v); });

    return TradePlan(
      entry: _d(j['entry']), sl: _d(j['sl']), tp1: _d(j['tp1']),
      tp2: _d(j['tp2']), tp3: _d(j['tp3']),
      riskPerUnit: _d(j['riskPerUnit'] ?? j['risk_per_unit']),
      riskPips: _d(j['riskPips'] ?? j['risk_pips']),
      rr1: _d(j['rr1']), rr2: _d(j['rr2']), confidence: _d(j['confidence']),
      quality: _s(j['quality'], 'POOR'), reasoning: _s(j['reasoning']),
      invalidation: _s(j['invalidation']), session: _s(j['session']),
      regime: _s(j['regime']), newsRisk: _s(j['newsRisk'] ?? j['news_risk'], 'NORMAL'),
      probScore: _d(j['probScore'] ?? j['prob_score'], 50), mtf: _s(j['mtf']),
      positionNote: _s(j['positionNote'] ?? j['position_note']), valid: _b(j['valid']),
      directionRaw: _s(j['direction'], 'NEUTRAL'), layerScores: layers,
      proxyOrderFlow: _map(j['proxyOrderFlow'] ?? j['proxy_order_flow']),
      expectancyPerDollar: _d(j['expectancyPerDollar'] ?? j['expectancy_per_dollar']),
      volatilityAdjustedRiskPct: _d(j['volatilityAdjustedRiskPct'] ?? j['volatility_adjusted_risk_pct'], 1.0),
      bullLayers: _i(j['bullLayers'] ?? j['bull_layers']),
      bearLayers: _i(j['bearLayers'] ?? j['bear_layers']),
      estimatedWinRate: _d(j['estimatedWinRate'] ?? j['estimated_win_rate'], 0.5),
      reasons: _listSafe<String>(j['reasons'], (e) => e.toString()),
    );
  }

  String get direction {
    if (directionRaw.isNotEmpty && directionRaw != 'NEUTRAL') return directionRaw.toUpperCase();
    final r = reasoning.toUpperCase();
    if (r.contains('BUY') || r.contains('BULL') || r.contains('LONG')) return 'BULLISH';
    if (r.contains('SELL') || r.contains('BEAR') || r.contains('SHORT')) return 'BEARISH';
    if (entry > 0.0) return tp1 > entry ? 'BULLISH' : 'BEARISH';
    return 'NEUTRAL';
  }

  bool get isBuy => direction.contains('BUY') || direction.contains('BULL');
  bool get isSell => direction.contains('SELL') || direction.contains('BEAR');

  String get deltaSignal => (proxyOrderFlow['deltaSignal'] ?? proxyOrderFlow['delta_signal'] ?? 'NEUTRAL').toString();
  double get buyingPressure => _d(proxyOrderFlow['buyingPressure'] ?? proxyOrderFlow['buying_pressure']);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  MonteCarloStats
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class MonteCarloStats {
  final double expectedFinalBalance;
  final double var95;
  final double var99;
  final double expectedMaxDrawdown;
  final double probabilityOfRuin;
  final int simulationsRun;

  const MonteCarloStats({
    this.expectedFinalBalance = 0, this.var95 = 0, this.var99 = 0,
    this.expectedMaxDrawdown = 0, this.probabilityOfRuin = 0, this.simulationsRun = 1000,
  });

  factory MonteCarloStats.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const MonteCarloStats();
    return MonteCarloStats(
      expectedFinalBalance: _d(j['expectedFinalBalance'] ?? j['expected_final_balance']),
      var95: _d(j['var95']), var99: _d(j['var99']),
      expectedMaxDrawdown: _d(j['expectedMaxDrawdown'] ?? j['expected_max_drawdown']),
      probabilityOfRuin: _d(j['probabilityOfRuin'] ?? j['probability_of_ruin']),
      simulationsRun: _i(j['simulationsRun'] ?? j['simulations_run'], 1000),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  VolumeProfileStats
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class VolumeProfileStats {
  final double pocPrice;
  final double valueAreaHigh;
  final double valueAreaLow;
  final double? bullishOrderBlock;
  final double? bearishOrderBlock;

  const VolumeProfileStats({
    this.pocPrice = 0, this.valueAreaHigh = 0, this.valueAreaLow = 0,
    this.bullishOrderBlock, this.bearishOrderBlock,
  });

  factory VolumeProfileStats.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const VolumeProfileStats();
    return VolumeProfileStats(
      pocPrice: _d(j['pocPrice'] ?? j['poc_price']),
      valueAreaHigh: _d(j['valueAreaHigh'] ?? j['value_area_high']),
      valueAreaLow: _d(j['valueAreaLow'] ?? j['value_area_low']),
      bullishOrderBlock: (j['bullishOrderBlock'] ?? j['bullish_order_block']) != null ? _d(j['bullishOrderBlock'] ?? j['bullish_order_block']) : null,
      bearishOrderBlock: (j['bearishOrderBlock'] ?? j['bearish_order_block']) != null ? _d(j['bearishOrderBlock'] ?? j['bearish_order_block']) : null,
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  MarketIntelligence
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class MarketIntelligence {
  final String assetName; final String assetType; final String lastUpdate; final String dataSource;
  final double currentPrice; final double priceChange; final double priceChangePct;
  final String safetySignal; final String signalColor; final int signalStrength;
  final String direction; final int bullScore; final int bearScore;
  final String entryQuality; final String entryExplanation;
  final double probabilityBull; final String probabilityLabel;
  final double ema9; final double ema21; final double ema50; final double ema200; final String emaAlignment;
  final double rsi; final String rsiSignal; final String rsiExplanation;
  final double macdLine; final double macdSignal; final double macdHist; final String macdCross;
  final double stochK; final double stochD; final String stochSignal;
  final double bbUpper; final double bbMid; final double bbLower; final double bbWidth; final String bbPosition; final bool bbSqueeze;
  final double kcUpper; final double kcMid; final double kcLower;
  final bool ttmSqueezeActive; final String ttmSqueezeLabel; final double ttmMomentum;
  final double supertrendValue; final String supertrendSignal; final String supertrendDirection;
  final double vwap; final double vwapUpper; final double vwapLower; final String vwapSignal;
  final Map<String, dynamic> pivotPoints; final String nearestPivotLevel; final double nearestPivotDist;
  final double zscore; final String zscoreSignal;
  final double adxValue; final String adxSignal; final double adxDiPlus; final double adxDiMinus;
  final double williamsR; final String williamsSignal;
  final double cciValue; final String cciSignal;
  final String obvTrend; final double obvValue;
  final String ichimokuSignal; final double tenkan; final double kijun;
  final double atr14; final double? slBuy; final double? slSell; final double? tpBuy; final double? tpSell;
  final double slPips; final String atrExplanation; final double atrMultiplier; final double rrRatio;
  final double hurst; final String regime; final String regimeAdvanced;
  final double shannonEntropy; final double kaufmanEr; final double fractalDim;
  final double realizedVol; final String volRegime; final double kurtosis; final double skewness;
  final String tailRisk; final double autocorrLag1; final int stabilityIndex;
  final List<double> supports; final List<double> resistances; final double nearestSupport; final double nearestResist; final String srZone;
  final String wavePosition; final double waveConfidence; final double? waveTarget; final String waveTrend;
  final Map<String, dynamic> fibRetracements; final Map<String, dynamic> fibExtensions; final String fibZone; final double fibStrength; final String fibExplanation;
  final List<dynamic> orderBlocks; final List<dynamic> fairValueGaps; final List<dynamic> liquiditySweeps; final String smcBias; final String smcExplanation;
  final String rsiDivergence; final String macdDivergence; final String obvDivergence; final String divergenceSignal; final double divergenceStrength;
  final String candlePattern; final double candleStrength; final String candleDirection; final String candleExplanation;
  final double kellyFraction; final String kellyRecommendation;
  final String tradingSession; final String sessionLiquidity; final String sessionWarning; final String sessionExplanation;
  final bool newsLockActive; final String newsLockEvent; final String newsLockReason;
  final int macroSentimentScore; final String macroSentimentLabel; final int macroBullHits; final int macroBearHits;
  final Map<String, dynamic> mtfSignals; final String mtfConfluence; final int mtfBullCount; final int mtfBearCount;
  final TradePlan tradePlan;
  final double riskDollars; final double recommendedLots; final String lotExplanation; final double requiredMargin;
  final CryptoMetrics? cryptoMetrics; final ForexMetrics? forexMetrics; final ChartMetadata? chartMetadata;
  final List<String> signalReasons; final MonteCarloStats? monteCarlo; final VolumeProfileStats? volumeProfile;
  final List<dynamic> upcomingNews; final int volatilityPercentile; final double estimatedWinRate;

  const MarketIntelligence({
    this.assetName = '', this.assetType = '', this.lastUpdate = '', this.dataSource = '',
    this.currentPrice = 0, this.priceChange = 0, this.priceChangePct = 0,
    this.safetySignal = 'WAIT', this.signalColor = '#FFD600', this.signalStrength = 0,
    this.direction = 'NEUTRAL', this.bullScore = 0, this.bearScore = 0,
    this.entryQuality = 'POOR', this.entryExplanation = '',
    this.probabilityBull = 50, this.probabilityLabel = 'NEUTRAL',
    this.ema9 = 0, this.ema21 = 0, this.ema50 = 0, this.ema200 = 0, this.emaAlignment = 'NEUTRAL',
    this.rsi = 50, this.rsiSignal = 'NEUTRAL', this.rsiExplanation = '',
    this.macdLine = 0, this.macdSignal = 0, this.macdHist = 0, this.macdCross = 'NEUTRAL',
    this.stochK = 50, this.stochD = 50, this.stochSignal = 'NEUTRAL',
    this.bbUpper = 0, this.bbMid = 0, this.bbLower = 0, this.bbWidth = 0, this.bbPosition = 'MIDDLE', this.bbSqueeze = false,
    this.kcUpper = 0, this.kcMid = 0, this.kcLower = 0,
    this.ttmSqueezeActive = false, this.ttmSqueezeLabel = 'SQUEEZE OFF', this.ttmMomentum = 0,
    this.supertrendValue = 0, this.supertrendSignal = 'NEUTRAL', this.supertrendDirection = 'NEUTRAL',
    this.vwap = 0, this.vwapUpper = 0, this.vwapLower = 0, this.vwapSignal = 'NEUTRAL',
    this.pivotPoints = const {}, this.nearestPivotLevel = '', this.nearestPivotDist = 0,
    this.zscore = 0, this.zscoreSignal = 'NEUTRAL',
    this.adxValue = 0, this.adxSignal = 'WEAK', this.adxDiPlus = 0, this.adxDiMinus = 0,
    this.williamsR = -50, this.williamsSignal = 'NEUTRAL',
    this.cciValue = 0, this.cciSignal = 'NEUTRAL',
    this.obvTrend = 'NEUTRAL', this.obvValue = 0,
    this.ichimokuSignal = 'NEUTRAL', this.tenkan = 0, this.kijun = 0,
    this.atr14 = 0, this.slBuy, this.slSell, this.tpBuy, this.tpSell,
    this.slPips = 0, this.atrExplanation = '', this.atrMultiplier = 1.5, this.rrRatio = 2.5,
    this.hurst = 0.5, this.regime = 'RANDOM', this.regimeAdvanced = 'CHOPPY',
    this.shannonEntropy = 0, this.kaufmanEr = 0, this.fractalDim = 1.5,
    this.realizedVol = 0, this.volRegime = 'NORMAL', this.kurtosis = 0, this.skewness = 0,
    this.tailRisk = 'NORMAL', this.autocorrLag1 = 0, this.stabilityIndex = 50,
    this.supports = const [], this.resistances = const [], this.nearestSupport = 0, this.nearestResist = 0, this.srZone = 'MIDDLE',
    this.wavePosition = 'UNKNOWN', this.waveConfidence = 0, this.waveTarget, this.waveTrend = 'NEUTRAL',
    this.fibRetracements = const {}, this.fibExtensions = const {}, this.fibZone = 'NEUTRAL', this.fibStrength = 0, this.fibExplanation = '',
    this.orderBlocks = const [], this.fairValueGaps = const [], this.liquiditySweeps = const [], this.smcBias = 'NEUTRAL', this.smcExplanation = '',
    this.rsiDivergence = 'NONE', this.macdDivergence = 'NONE', this.obvDivergence = 'NEUTRAL', this.divergenceSignal = 'NONE', this.divergenceStrength = 0,
    this.candlePattern = 'NONE', this.candleStrength = 0, this.candleDirection = 'NEUTRAL', this.candleExplanation = '',
    this.kellyFraction = 0, this.kellyRecommendation = '',
    this.tradingSession = 'OFF-HOURS', this.sessionLiquidity = 'LOW', this.sessionWarning = '', this.sessionExplanation = '',
    this.newsLockActive = false, this.newsLockEvent = '', this.newsLockReason = '',
    this.macroSentimentScore = 50, this.macroSentimentLabel = 'NEUTRAL', this.macroBullHits = 0, this.macroBearHits = 0,
    this.mtfSignals = const {}, this.mtfConfluence = 'NEUTRAL', this.mtfBullCount = 0, this.mtfBearCount = 0,
    this.tradePlan = const TradePlan(),
    this.riskDollars = 0, this.recommendedLots = 0, this.lotExplanation = '', this.requiredMargin = 0,
    this.cryptoMetrics, this.forexMetrics, this.chartMetadata,
    this.signalReasons = const [], this.monteCarlo, this.volumeProfile,
    this.upcomingNews = const [], this.volatilityPercentile = 50, this.estimatedWinRate = 0.5,
  });

  factory MarketIntelligence.fromJson(Map<String, dynamic> j) {
    final tpRaw = j['tradePlan'] ?? j['trade_plan'];
    final cmRaw = j['cryptoMetrics'] ?? j['crypto_metrics'];
    final fmRaw = j['forexMetrics'] ?? j['forex_metrics'];
    final mdRaw = j['chartMetadata'] ?? j['chart_metadata'];
    final mcRaw = j['monteCarlo'] ?? j['monte_carlo'];
    final vpRaw = j['volumeProfile'] ?? j['volume_profile'];
    final upcomingRaw = j['upcomingNews'] ?? j['upcoming_news'];

    return MarketIntelligence(
      assetName: _s(j['assetName'] ?? j['asset_name']), assetType: _s(j['assetType'] ?? j['asset_type']),
      lastUpdate: _s(j['lastUpdate'] ?? j['last_update']), dataSource: _s(j['dataSource'] ?? j['data_source']),
      currentPrice: _d(j['currentPrice'] ?? j['current_price']), priceChange: _d(j['priceChange'] ?? j['price_change']), priceChangePct: _d(j['priceChangePct'] ?? j['price_change_pct']),
      safetySignal: _s(j['safetySignal'] ?? j['safety_signal'], 'WAIT'), signalColor: _s(j['signalColor'] ?? j['signal_color'], '#FFD600'),
      signalStrength: _i(j['signalStrength'] ?? j['signal_strength'] ?? j['signalConfidence'] ?? j['signal_confidence']),
      direction: _s(j['direction'], 'NEUTRAL'), bullScore: _i(j['bullScore'] ?? j['bull_score']), bearScore: _i(j['bearScore'] ?? j['bear_score']),
      entryQuality: _s(j['entryQuality'] ?? j['entry_quality'], 'POOR'), entryExplanation: _s(j['entryExplanation'] ?? j['entry_explanation']),
      probabilityBull: _d(j['probabilityBull'] ?? j['probability_bull'], 50), probabilityLabel: _s(j['probabilityLabel'] ?? j['probability_label'], 'NEUTRAL'),
      ema9: _d(j['ema9']), ema21: _d(j['ema21']), ema50: _d(j['ema50']), ema200: _d(j['ema200']), emaAlignment: _s(j['emaAlignment'] ?? j['ema_alignment'], 'NEUTRAL'),
      rsi: _d(j['rsi'], 50), rsiSignal: _s(j['rsiSignal'] ?? j['rsi_signal'], 'NEUTRAL'), rsiExplanation: _s(j['rsiExplanation'] ?? j['rsi_explanation']),
      macdLine: _d(j['macdLine'] ?? j['macd_line']), macdSignal: _d(j['macdSignal'] ?? j['macd_signal']), macdHist: _d(j['macdHist'] ?? j['macd_hist']), macdCross: _s(j['macdCross'] ?? j['macd_cross'], 'NEUTRAL'),
      stochK: _d(j['stochK'] ?? j['stoch_k'], 50), stochD: _d(j['stochD'] ?? j['stoch_d'], 50), stochSignal: _s(j['stochSignal'] ?? j['stoch_signal'], 'NEUTRAL'),
      bbUpper: _d(j['bbUpper'] ?? j['bb_upper']), bbMid: _d(j['bbMid'] ?? j['bb_mid']), bbLower: _d(j['bbLower'] ?? j['bb_lower']), bbWidth: _d(j['bbWidth'] ?? j['bb_width']), bbPosition: _s(j['bbPosition'] ?? j['bb_position'], 'MIDDLE'), bbSqueeze: _b(j['bbSqueeze'] ?? j['bb_squeeze']),
      kcUpper: _d(j['kcUpper'] ?? j['kc_upper']), kcMid: _d(j['kcMid'] ?? j['kc_mid']), kcLower: _d(j['kcLower'] ?? j['kc_lower']),
      ttmSqueezeActive: _b(j['ttmSqueezeActive'] ?? j['ttm_squeeze_active']), ttmSqueezeLabel: _s(j['ttmSqueezeLabel'] ?? j['ttm_squeeze_label'], 'SQUEEZE OFF'), ttmMomentum: _d(j['ttmMomentum'] ?? j['ttm_momentum']),
      supertrendValue: _d(j['supertrendValue'] ?? j['supertrend_value']), supertrendSignal: _s(j['supertrendSignal'] ?? j['supertrend_signal'], 'NEUTRAL'), supertrendDirection: _s(j['supertrendDirection'] ?? j['supertrend_direction'], 'NEUTRAL'),
      vwap: _d(j['vwap']), vwapUpper: _d(j['vwapUpper'] ?? j['vwap_upper']), vwapLower: _d(j['vwapLower'] ?? j['vwap_lower']), vwapSignal: _s(j['vwapSignal'] ?? j['vwap_signal'], 'NEUTRAL'),
      pivotPoints: _map(j['pivotPoints'] ?? j['pivot_points']), nearestPivotLevel: _s(j['nearestPivotLevel'] ?? j['nearest_pivot_level']), nearestPivotDist: _d(j['nearestPivotDist'] ?? j['nearest_pivot_dist']),
      zscore: _d(j['zscore'] ?? j['z_score']), zscoreSignal: _s(j['zscoreSignal'] ?? j['z_score_signal'], 'NEUTRAL'),
      adxValue: _d(j['adxValue'] ?? j['adx_value']), adxSignal: _s(j['adxSignal'] ?? j['adx_signal'], 'WEAK'), adxDiPlus: _d(j['adxDiPlus'] ?? j['adx_di_plus']), adxDiMinus: _d(j['adxDiMinus'] ?? j['adx_di_minus']),
      williamsR: _d(j['williamsR'] ?? j['williams_r'], -50), williamsSignal: _s(j['williamsSignal'] ?? j['williams_signal'], 'NEUTRAL'),
      cciValue: _d(j['cciValue'] ?? j['cci_value']), cciSignal: _s(j['cciSignal'] ?? j['cci_signal'], 'NEUTRAL'),
      obvTrend: _s(j['obvTrend'] ?? j['obv_trend'], 'NEUTRAL'), obvValue: _d(j['obvValue'] ?? j['obv_value']),
      ichimokuSignal: _s(j['ichimokuSignal'] ?? j['ichimoku_signal'], 'NEUTRAL'), tenkan: _d(j['tenkan']), kijun: _d(j['kijun']),
      atr14: _d(j['atr14'] ?? j['atr_14']),
      slBuy: j['slBuy'] != null || j['sl_buy'] != null ? _d(j['slBuy'] ?? j['sl_buy']) : null,
      slSell: j['slSell'] != null || j['sl_sell'] != null ? _d(j['slSell'] ?? j['sl_sell']) : null,
      tpBuy: j['tpBuy'] != null || j['tp_buy'] != null ? _d(j['tpBuy'] ?? j['tp_buy']) : null,
      tpSell: j['tpSell'] != null || j['tp_sell'] != null ? _d(j['tpSell'] ?? j['tp_sell']) : null,
      slPips: _d(j['slPips'] ?? j['sl_pips']), atrExplanation: _s(j['atrExplanation'] ?? j['atr_explanation']), atrMultiplier: _d(j['atrMultiplier'] ?? j['atr_multiplier'], 1.5), rrRatio: _d(j['rrRatio'] ?? j['rr_ratio'], 2.5),
      hurst: _d(j['hurst'], 0.5), regime: _s(j['regime'], 'RANDOM'), regimeAdvanced: _s(j['regimeAdvanced'] ?? j['regime_advanced'], 'CHOPPY'),
      shannonEntropy: _d(j['shannonEntropy'] ?? j['shannon_entropy']), kaufmanEr: _d(j['kaufmanEr'] ?? j['kaufman_er']), fractalDim: _d(j['fractalDim'] ?? j['fractal_dim'], 1.5),
      realizedVol: _d(j['realizedVol'] ?? j['realized_vol']), volRegime: _s(j['volRegime'] ?? j['vol_regime'], 'NORMAL'), kurtosis: _d(j['kurtosis']), skewness: _d(j['skewness']),
      tailRisk: _s(j['tailRisk'] ?? j['tail_risk'], 'NORMAL'), autocorrLag1: _d(j['autocorrLag1'] ?? j['autocorr_lag_1']), stabilityIndex: _i(j['stabilityIndex'] ?? j['stability_index'], 50),
      supports: _listSafe<double>(j['supports'], (e) => _d(e)), resistances: _listSafe<double>(j['resistances'], (e) => _d(e)), nearestSupport: _d(j['nearestSupport'] ?? j['nearest_support']), nearestResist: _d(j['nearestResist'] ?? j['nearest_resist']), srZone: _s(j['srZone'] ?? j['sr_zone'], 'MIDDLE'),
      wavePosition: _s(j['wavePosition'] ?? j['wave_position'], 'UNKNOWN'), waveConfidence: _d(j['waveConfidence'] ?? j['wave_confidence']),
      waveTarget: j['waveTarget'] != null || j['wave_target'] != null ? _d(j['waveTarget'] ?? j['wave_target']) : null, waveTrend: _s(j['waveTrend'] ?? j['wave_trend'], 'NEUTRAL'),
      fibRetracements: _map(j['fibRetracements'] ?? j['fib_retracements']), fibExtensions: _map(j['fibExtensions'] ?? j['fib_extensions']), fibZone: _s(j['fibZone'] ?? j['fib_zone'], 'NEUTRAL'), fibStrength: _d(j['fibStrength'] ?? j['fib_strength']), fibExplanation: _s(j['fibExplanation'] ?? j['fib_explanation']),
      orderBlocks: _listSafe<dynamic>(j['orderBlocks'] ?? j['order_blocks'], (e) => e), fairValueGaps: _listSafe<dynamic>(j['fairValueGaps'] ?? j['fair_value_gaps'], (e) => e), liquiditySweeps: _listSafe<dynamic>(j['liquiditySweeps'] ?? j['liquidity_sweeps'], (e) => e), smcBias: _s(j['smcBias'] ?? j['smc_bias'], 'NEUTRAL'), smcExplanation: _s(j['smcExplanation'] ?? j['smc_explanation']),
      rsiDivergence: _s(j['rsiDivergence'] ?? j['rsi_divergence'], 'NONE'), macdDivergence: _s(j['macdDivergence'] ?? j['macd_divergence'], 'NONE'), obvDivergence: _s(j['obvDivergence'] ?? j['obv_divergence'], 'NEUTRAL'), divergenceSignal: _s(j['divergenceSignal'] ?? j['divergence_signal'], 'NONE'), divergenceStrength: _d(j['divergenceStrength'] ?? j['divergence_strength']),
      candlePattern: _s(j['candlePattern'] ?? j['candle_pattern'], 'NONE'), candleStrength: _d(j['candleStrength'] ?? j['candle_strength']), candleDirection: _s(j['candleDirection'] ?? j['candle_direction'], 'NEUTRAL'), candleExplanation: _s(j['candleExplanation'] ?? j['candle_explanation']),
      kellyFraction: _d(j['kellyFraction'] ?? j['kelly_fraction']), kellyRecommendation: _s(j['kellyRecommendation'] ?? j['kelly_recommendation']),
      tradingSession: _s(j['tradingSession'] ?? j['trading_session'], 'OFF-HOURS'), sessionLiquidity: _s(j['sessionLiquidity'] ?? j['session_liquidity'], 'LOW'), sessionWarning: _s(j['sessionWarning'] ?? j['session_warning']), sessionExplanation: _s(j['sessionExplanation'] ?? j['session_explanation']),
      newsLockActive: _b(j['newsLockActive'] ?? j['news_lock_active']), newsLockEvent: _s(j['newsLockEvent'] ?? j['news_lock_event']), newsLockReason: _s(j['newsLockReason'] ?? j['news_lock_reason']),
      macroSentimentScore: _i(j['macroSentimentScore'] ?? j['macro_sentiment_score'], 50), macroSentimentLabel: _s(j['macroSentimentLabel'] ?? j['macro_sentiment_label'], 'NEUTRAL'), macroBullHits: _i(j['macroBullHits'] ?? j['macro_bull_hits']), macroBearHits: _i(j['macroBearHits'] ?? j['macro_bear_hits']),
      mtfSignals: _map(j['mtfSignals'] ?? j['mtf_signals']), mtfConfluence: _s(j['mtfConfluence'] ?? j['mtf_confluence'], 'NEUTRAL'), mtfBullCount: _i(j['mtfBullCount'] ?? j['mtf_bull_count']), mtfBearCount: _i(j['mtfBearCount'] ?? j['mtf_bear_count']),
      tradePlan: TradePlan.fromJson(tpRaw is Map ? _map(tpRaw) : null),
      riskDollars: _d(j['riskDollars'] ?? j['risk_dollars']), recommendedLots: _d(j['recommendedLots'] ?? j['recommended_lots']), lotExplanation: _s(j['lotExplanation'] ?? j['lot_explanation']), requiredMargin: _d(j['requiredMargin'] ?? j['required_margin']),
      cryptoMetrics: cmRaw is Map && _map(cmRaw).isNotEmpty ? CryptoMetrics.fromJson(_map(cmRaw)) : null,
      forexMetrics: fmRaw is Map && _map(fmRaw).isNotEmpty ? ForexMetrics.fromJson(_map(fmRaw)) : null,
      chartMetadata: mdRaw is Map ? ChartMetadata.fromJson(_map(mdRaw)) : null,
      signalReasons: _listSafe<String>(j['signalReasons'] ?? j['signal_reasons'], (e) => e.toString()),
      monteCarlo: mcRaw is Map ? MonteCarloStats.fromJson(_map(mcRaw)) : null,
      volumeProfile: vpRaw is Map ? VolumeProfileStats.fromJson(_map(vpRaw)) : null,
      upcomingNews: _listSafe<dynamic>(upcomingRaw, (e) => e),
      volatilityPercentile: _i(j['volatilityPercentile'] ?? j['volatility_percentile'], 50),
      estimatedWinRate: _d(j['estimatedWinRate'] ?? j['estimated_win_rate'], 0.5),
    );
  }

  bool get isCrypto => assetType.toLowerCase() == 'crypto' || assetType.toLowerCase() == 'cryptocurrency';
  bool get isForex => assetType.toLowerCase() == 'forex';
  bool get isCommodity => assetType.toLowerCase() == 'commodity' || assetType.toLowerCase() == 'metal';
  bool get isIndex => assetType.toLowerCase() == 'index';
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  NewsItem
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class NewsItem {
  final String title; final String source; final String published; final String url; final String category;
  final String nexusComment; final String quantAction; final double sentimentScore; final List<String> affectedAssets;
  final String imageUrl; final String sourceLogoUrl; final double impactPercentage; final String sentimentLabel;

  const NewsItem({
    required this.title, required this.source, required this.published, required this.url, required this.category,
    required this.nexusComment, required this.quantAction, this.sentimentScore = 0, this.affectedAssets = const [],
    this.imageUrl = '', this.sourceLogoUrl = '', this.impactPercentage = 50.0, this.sentimentLabel = 'NEUTRAL',
  });

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
    title: _s(j['title'] ?? j['headline']), source: _s(j['source']), published: _s(j['published'] ?? j['datetime']), url: _s(j['url']), category: _s(j['category']),
    nexusComment: _s(j['nexusComment'] ?? j['nexus_comment']), quantAction: _s(j['quantAction'] ?? j['quant_action']),
    sentimentScore: _d(j['sentimentScore'] ?? j['sentiment_score']),
    affectedAssets: _listSafe<String>(j['affectedAssets'] ?? j['affected_assets'], (e) => e.toString()),
    imageUrl: _s(j['imageUrl'] ?? j['image_url'] ?? j['image']), sourceLogoUrl: _s(j['sourceLogoUrl'] ?? j['source_logo_url']),
    impactPercentage: _d(j['impactPercentage'] ?? j['impact_percentage'], 50.0), sentimentLabel: _s(j['sentimentLabel'] ?? j['sentiment_label'], 'NEUTRAL'),
  );

  Color get categoryColor {
    switch (category.toUpperCase()) {
      case 'CRITICAL': return const Color(0xFFFF3131);
      case 'HIGH': return const Color(0xFFFF9800);
      case 'MEDIUM': return const Color(0xFFFFD600);
      default: return const Color(0xFF6B6B6B);
    }
  }

  bool get isBullish => sentimentScore > 0.3;
  bool get isBearish => sentimentScore < -0.3;
  bool get isNeutral => !isBullish && !isBearish;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  AnalysisResult
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class AnalysisResult {
  final String symbol; final MarketIntelligence intelligence; final List<NewsItem> news; final String source;

  const AnalysisResult({required this.symbol, required this.intelligence, this.news = const [], this.source = ''});

  factory AnalysisResult.fromJson(String symbol, Map<String, dynamic> data) {
    final intelRaw = data['intelligence'];
    final newsRaw = data['news'];
    return AnalysisResult(
      symbol: symbol,
      intelligence: intelRaw is Map ? MarketIntelligence.fromJson(_map(intelRaw)) : const MarketIntelligence(),
      news: newsRaw is List ? newsRaw.whereType<Map>().map((e) => NewsItem.fromJson(_map(e))).toList() : const [],
      source: _s(data['source']),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  EconomicEvent
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class EconomicEvent {
  final String event; final String datetime; final String country; final String actual; final String estimate; final String prev; final int impact;

  const EconomicEvent({required this.event, this.datetime = '', this.country = '', this.actual = '', this.estimate = '', this.prev = '', this.impact = 0});

  factory EconomicEvent.fromJson(Map<String, dynamic> j) => EconomicEvent(
    event: _s(j['event'] ?? j['title'] ?? j['name']), datetime: _s(j['datetime'] ?? j['date'] ?? j['time']), country: _s(j['country']),
    actual: _s(j['actual']), estimate: _s(j['estimate'] ?? j['forecast']), prev: _s(j['prev'] ?? j['previous']), impact: _i(j['impact'] ?? j['importance']),
  );

  bool get isHighImpact => impact >= 2 || ['NFP', 'CPI', 'FOMC', 'GDP', 'FED', 'NON-FARM', 'NONFARM'].any((k) => event.toUpperCase().contains(k));

  DateTime? get parsedTime {
    if (datetime.isEmpty) return null;
    return DateTime.tryParse(datetime);
  }

  bool get isUpcoming => parsedTime?.isAfter(DateTime.now()) ?? false;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  User
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class User {
  final String id; final String email; final String name; final String tier;
  final DateTime? expiresAt; final String? stripeSubId; final int tradesRemaining;

  const User({required this.id, required this.email, this.name = '', this.tier = 'free', this.expiresAt, this.stripeSubId, this.tradesRemaining = 2});

  bool get isPro => tier == 'pro' && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
  bool get isFree => !isPro;
  bool get isEnterprise => tier == 'enterprise';

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: _s(j['id'] ?? j['sub'] ?? j['user_id']), email: _s(j['email']), name: _s(j['name']), tier: _s(j['tier'], 'free'),
    expiresAt: (j['expiresAt'] ?? j['expires_at']) != null ? DateTime.tryParse((j['expiresAt'] ?? j['expires_at']).toString()) : null,
    stripeSubId: _s(j['stripeSubId'] ?? j['stripe_sub_id'] ?? j['subscription_id']),
    tradesRemaining: _i(j['tradesRemaining'] ?? j['trades_remaining'], 2),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'email': email, 'name': name, 'tier': tier,
    'expiresAt': expiresAt?.toIso8601String(), 'stripeSubId': stripeSubId, 'tradesRemaining': tradesRemaining,
  };
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  AI PLANNER MODELS (v13.8 Institutional Grade)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@immutable
class KeyLevel {
  final double price;
  final String label;
  final String type; // 'support', 'resistance', 'liquidity_pool', 'neutral'
  final String strength; // 'strong', 'moderate', 'weak'

  const KeyLevel({
    required this.price,
    required this.label,
    required this.type,
    this.strength = 'moderate',
  });

  factory KeyLevel.fromJson(Map<String, dynamic> j) => KeyLevel(
    price: _d(j['price']),
    label: _s(j['label']),
    type: _s(j['type'], 'neutral'),
    strength: _s(j['strength'], 'moderate'),
  );
}

@immutable
class EntryZone {
  final double low;
  final double high;
  final String label;

  const EntryZone({required this.low, required this.high, required this.label});

  factory EntryZone.fromJson(Map<String, dynamic> j) => EntryZone(
    low: _d(j['low']),
    high: _d(j['high']),
    label: _s(j['label']),
  );
}

@immutable
class IndicatorUsed {
  final String name;
  final String reading;
  final String signal;
  final String weight; // 'HIGH', 'MEDIUM', 'LOW'
  final String why;

  const IndicatorUsed({
    required this.name,
    required this.reading,
    required this.signal,
    required this.weight,
    required this.why,
  });

  factory IndicatorUsed.fromJson(Map<String, dynamic> j) => IndicatorUsed(
    name: _s(j['name']),
    reading: _s(j['reading']),
    signal: _s(j['signal'], 'NEUTRAL'),
    weight: _s(j['weight'], 'MEDIUM'),
    why: _s(j['why']),
  );

  Color get signalColor {
    final s = signal.toUpperCase();
    if (s.contains('BULL')) return const Color(0xFF00FF88);
    if (s.contains('BEAR')) return const Color(0xFFFF3131);
    return const Color(0xFF888888);
  }
}

@immutable
class AiScenario {
  final int rank;
  final String title;
  final int probability;
  final String bias;
  final int confidence;
  final String setupType;
  final EntryZone entryZone;
  final double stopLoss;
  final double takeProfit1;
  final double takeProfit2;
  final double takeProfit3;
  final double riskReward;
  final String timeframe;
  final String tradeManagement;
  final String institutionalLogic;
  final String invalidation;
  final List<IndicatorUsed> indicatorsUsed;

  const AiScenario({
    required this.rank,
    required this.title,
    required this.probability,
    required this.bias,
    required this.confidence,
    required this.setupType,
    required this.entryZone,
    required this.stopLoss,
    required this.takeProfit1,
    required this.takeProfit2,
    required this.takeProfit3,
    required this.riskReward,
    required this.timeframe,
    required this.tradeManagement,
    required this.institutionalLogic,
    required this.invalidation,
    required this.indicatorsUsed,
  });

  factory AiScenario.fromJson(Map<String, dynamic> j) {
    final ezRaw = j['entry_zone'] ?? j['entryZone'];
    final indRaw = j['indicators_used'] ?? j['indicatorsUsed'] ?? [];
    
    return AiScenario(
      rank: _i(j['rank'], 1),
      title: _s(j['title'], 'Scenario'),
      probability: _i(j['probability'], 25),
      bias: _s(j['bias'], 'NEUTRAL'),
      confidence: _i(j['confidence'], 50),
      setupType: _s(j['setup_type'] ?? j['setupType'], ''),
      entryZone: ezRaw is Map ? EntryZone.fromJson(_map(ezRaw)) : const EntryZone(low: 0, high: 0, label: ''),
      stopLoss: _d(j['stop_loss'] ?? j['stopLoss']),
      takeProfit1: _d(j['take_profit_1'] ?? j['takeProfit1']),
      takeProfit2: _d(j['take_profit_2'] ?? j['takeProfit2']),
      takeProfit3: _d(j['take_profit_3'] ?? j['takeProfit3']),
      riskReward: _d(j['risk_reward'] ?? j['riskReward'], 1.0),
      timeframe: _s(j['timeframe'], 'H1-H4'),
      tradeManagement: _s(j['trade_management'] ?? j['tradeManagement'] ?? j['management'], ''),
      institutionalLogic: _s(j['institutional_logic'] ?? j['institutionalLogic'] ?? j['explanation'], ''),
      invalidation: _s(j['invalidation'], ''),
      indicatorsUsed: _listSafe<IndicatorUsed>(indRaw, (e) => IndicatorUsed.fromJson(_map(e))),
    );
  }

  Color get biasColor {
    final b = bias.toUpperCase();
    if (b.contains('BULL')) return const Color(0xFF00FF88);
    if (b.contains('BEAR')) return const Color(0xFFFF3131);
    if (b.contains('RANGE')) return const Color(0xFFFFD600);
    return const Color(0xFF888888);
  }

  IconData get biasIcon {
    final b = bias.toUpperCase();
    if (b.contains('BULL')) return Icons.trending_up;
    if (b.contains('BEAR')) return Icons.trending_down;
    if (b.contains('RANGE')) return Icons.swap_horiz;
    return Icons.remove;
  }
}

@immutable
class AiPlan {
  final String source;
  final String executiveSummary;
  final String marketRegimeNarrative;
  final String psychologyAndRisk;
  final List<KeyLevel> keyLevels;
  final List<AiScenario> scenarios;
  final DateTime fetchedAt;

  const AiPlan({
    this.source = 'quant-fallback',
    this.executiveSummary = '',
    this.marketRegimeNarrative = '',
    this.psychologyAndRisk = '',
    this.keyLevels = const [],
    this.scenarios = const [],
    required this.fetchedAt,
  });

  factory AiPlan.fromJson(Map<String, dynamic> j) {
    return AiPlan(
      source: _s(j['source'], 'quant-fallback'),
      executiveSummary: _s(j['executive_summary'] ?? j['executiveSummary'] ?? j['summary'], ''),
      marketRegimeNarrative: _s(j['market_regime_narrative'] ?? j['marketRegimeNarrative'], ''),
      psychologyAndRisk: _s(j['psychology_and_risk'] ?? j['psychologyAndRisk'] ?? j['riskNote'] ?? j['risk_note'], ''),
      keyLevels: _listSafe<KeyLevel>(j['key_levels'] ?? j['keyLevels'], (e) => KeyLevel.fromJson(_map(e))),
      scenarios: _listSafe<AiScenario>(j['scenarios'], (e) => AiScenario.fromJson(_map(e))),
      fetchedAt: DateTime.now(),
    );
  }

  bool get isFromGemini => source.toLowerCase().contains('gemini');
  bool get isFresh => DateTime.now().difference(fetchedAt) < const Duration(minutes: 45);
  AiScenario? get topScenario => scenarios.isEmpty ? null : scenarios.first;
  int get totalProbability => scenarios.fold(0, (sum, s) => sum + s.probability);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  WEBSOCKET FRAME MODELS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum WsFrameType { connected, priceTick, metricShift, heartbeat, filterAck, unknown }

WsFrameType _parseFrameType(dynamic raw) {
  switch (raw?.toString()) {
    case 'connected': return WsFrameType.connected;
    case 'price_tick': return WsFrameType.priceTick;
    case 'metric_shift': return WsFrameType.metricShift;
    case 'heartbeat': return WsFrameType.heartbeat;
    case 'filter_ack': return WsFrameType.filterAck;
    default: return WsFrameType.unknown;
  }
}

@immutable
class TickEntry {
  final String symbol; final double price; final double changePct; final String direction; final double glowIntensity;

  const TickEntry({required this.symbol, required this.price, this.changePct = 0.0, this.direction = 'FLAT', this.glowIntensity = 0.0});

  factory TickEntry.fromJson(String symbol, Map<String, dynamic> j) => TickEntry(
    symbol: symbol, price: _d(j['price']), changePct: _d(j['changePct'] ?? j['change_pct']),
    direction: _s(j['direction'], 'FLAT'), glowIntensity: _d(j['glowIntensity'] ?? j['glow_intensity']),
  );
}

@immutable
class MetricShift {
  final String symbol; final String field; final String previous; final String current; final String ts;

  const MetricShift({required this.symbol, required this.field, required this.previous, required this.current, this.ts = ''});

  factory MetricShift.fromJson(Map<String, dynamic> j) => MetricShift(
    symbol: _s(j['symbol']), field: _s(j['field']), previous: _s(j['previous']), current: _s(j['current']), ts: _s(j['ts']),
  );
}

class WsFrameParseException implements Exception {
  final String message; final String rawPayload;
  const WsFrameParseException(this.message, this.rawPayload);
  @override
  String toString() => 'WsFrameParseException: $message\n  payload: ${rawPayload.length > 200 ? "${rawPayload.substring(0, 200)}…" : rawPayload}';
}

@immutable
class WsFrame {
  final WsFrameType type; final String ts; final int seq;
  final Map<String, TickEntry> ticks; final MetricShift? shift; final Map<String, dynamic> raw;

  const WsFrame({required this.type, required this.ts, required this.seq, required this.raw, this.ticks = const {}, this.shift});

  factory WsFrame.fromRaw(String rawText) {
    if (rawText.isEmpty) throw WsFrameParseException('Empty frame', rawText);
    Map<String, dynamic> j;
    try {
      final dynamic decoded = jsonDecode(rawText);
      if (decoded is! Map<String, dynamic>) throw WsFrameParseException('Expected JSON object, got ${decoded.runtimeType}', rawText);
      j = decoded;
    } catch (e) {
      if (e is WsFrameParseException) rethrow;
      throw WsFrameParseException('JSON decode failed: $e', rawText);
    }

    final type = _parseFrameType(j['type']);
    final seq = _i(j['seq'], 0);
    final ts = _s(j['ts']);

    final ticks = <String, TickEntry>{};
    if (type == WsFrameType.priceTick || type == WsFrameType.connected) {
      final dataRaw = j['data'];
      if (dataRaw is Map<String, dynamic>) {
        dataRaw.forEach((sym, val) {
          if (val is Map<String, dynamic>) {
            try { ticks[sym] = TickEntry.fromJson(sym, val); } catch (_) {}
          }
        });
      }
    }

    MetricShift? shift;
    if (type == WsFrameType.metricShift) {
      try { shift = MetricShift.fromJson(j); } catch (_) {}
    }

    return WsFrame(type: type, ts: ts, seq: seq, raw: j, ticks: ticks, shift: shift);
  }
}