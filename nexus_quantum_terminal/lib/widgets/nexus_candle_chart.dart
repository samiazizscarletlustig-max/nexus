// ============================================================================
//  NEXUS v13.10 — nexus_candle_chart.dart (ULTIMATE BROKER-GRADE)
//  Syncfusion candlestick chart — Institutional Grade & Ultra-Fast.
//  ✅ Strongly-typed AiScenario fields (no more 'raw' maps)
//  ✅ Instant rendering (animationDuration: 0)
//  ✅ Advanced TradingView-style overlays & HUD with perfect alignment
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../models/market_models.dart';
import '../theme/app_theme.dart';

class _OhlcSnapshot {
  final double open;
  final double high;
  final double low;
  final double close;
  final DateTime? time;
  
  const _OhlcSnapshot({
    required this.open, 
    required this.high, 
    required this.low, 
    required this.close, 
    this.time
  });
  
  _OhlcSnapshot copyWith({double? open, double? high, double? low, double? close, DateTime? time}) =>
      _OhlcSnapshot(
        open: open ?? this.open, 
        high: high ?? this.high, 
        low: low ?? this.low, 
        close: close ?? this.close, 
        time: time ?? this.time
      );
}

class NexusCandleChart extends StatefulWidget {
  const NexusCandleChart({
    super.key, 
    required this.data, 
    required this.liveTickNotifier,
    this.height = 420, 
    this.assetType = '', 
    this.is24h = false,
    this.decimalPlaces = 2, 
    this.intelligence, 
    this.aiScenario,
  });

  final List<OhlcPoint> data;
  final ValueNotifier<TickEntry?> liveTickNotifier;
  final double height;
  final String assetType;
  final bool is24h;
  final int decimalPlaces;
  final MarketIntelligence? intelligence;
  final AiScenario? aiScenario;

  @override
  State<NexusCandleChart> createState() => _NexusCandleChartState();
}

class _NexusCandleChartState extends State<NexusCandleChart> {
  ChartSeriesController? _seriesCtrl;
  final ValueNotifier<_OhlcSnapshot?> _hudNotifier = ValueNotifier<_OhlcSnapshot?>(null);
  bool _trackballActive = false;
  
  static const double _kRightPaddingFactor = 0.20;
  static const int _kMaxVisible = 300; // Optimized for speed

  List<OhlcPoint> get _visibleData {
    if (widget.data.length <= _kMaxVisible) return widget.data;
    return widget.data.sublist(widget.data.length - _kMaxVisible);
  }

  bool get _isCrypto => widget.assetType.toLowerCase().contains('crypto') || 
      (widget.data.isNotEmpty && widget.data.first.assetType.toLowerCase().contains('crypto'));
  bool get _isForex => widget.assetType.toLowerCase() == 'forex';

  int get _resolvedDp {
    if (widget.data.isNotEmpty && widget.data.first.decimalPlaces > 0) return widget.data.first.decimalPlaces;
    return widget.decimalPlaces;
  }

  NumberFormat _smartFormat([double? sample]) {
    if (_isForex) return NumberFormat('#,##0.00000');
    if (_isCrypto) {
      final ref = sample ?? (widget.data.isNotEmpty ? widget.data.last.close : 0.0);
      if (ref >= 1000) return NumberFormat('#,##0.00');
      if (ref >= 1) return NumberFormat('#,##0.0000');
      return NumberFormat('#,##0.000000');
    }
    final dp = _resolvedDp;
    if (dp <= 0) return NumberFormat('#,##0');
    if (dp == 2) return NumberFormat('#,##0.00');
    return NumberFormat('#,##0.${'0' * dp}');
  }

  DateTime? _xAxisMax(List<OhlcPoint> visible) {
    if (visible.isEmpty) return null;
    final first = visible.first.time;
    final last = visible.last.time;
    if (first == null || last == null) return null;
    final rangeMs = last.difference(first).inMilliseconds;
    if (rangeMs <= 0) return null;
    final paddingMs = (rangeMs * _kRightPaddingFactor / (1.0 - _kRightPaddingFactor)).round();
    return last.add(Duration(milliseconds: paddingMs));
  }

  List<PlotBand> _buildPlotBands(double samplePrice, Color lastPriceColor) {
    final bands = <PlotBand>[];
    
    // Current price line
    bands.add(PlotBand(
      start: samplePrice, end: samplePrice, borderWidth: 1, 
      borderColor: lastPriceColor.withOpacity(0.45), 
      dashArray: const <double>[4, 4], shouldRenderAboveSeries: true
    ));
    
    // ✅ FIX: Use new strongly-typed AiScenario fields
    if (widget.aiScenario != null) {
      final ai = widget.aiScenario!;
      if (ai.entryZone.low > 0 && ai.entryZone.high > 0) {
        bands.add(PlotBand(
          start: ai.entryZone.low, end: ai.entryZone.high, 
          color: AppTheme.gold.withOpacity(0.12), borderColor: AppTheme.gold.withOpacity(0.6), 
          borderWidth: 1, text: 'AI ENTRY', 
          textStyle: const TextStyle(color: AppTheme.gold, fontSize: 9, fontWeight: FontWeight.bold), 
          shouldRenderAboveSeries: false
        ));
      }
      if (ai.stopLoss > 0) {
        bands.add(PlotBand(
          start: ai.stopLoss, end: ai.stopLoss, borderWidth: 1.5, 
          borderColor: AppTheme.signalSell, dashArray: const <double>[5, 3], 
          text: 'AI SL', textStyle: const TextStyle(color: AppTheme.signalSell, fontSize: 9, fontWeight: FontWeight.bold), 
          shouldRenderAboveSeries: true
        ));
      }
      if (ai.takeProfit1 > 0) {
        bands.add(PlotBand(
          start: ai.takeProfit1, end: ai.takeProfit1, borderWidth: 1.5, 
          borderColor: AppTheme.signalBuy, dashArray: const <double>[5, 3], 
          text: 'AI TP1', textStyle: const TextStyle(color: AppTheme.signalBuy, fontSize: 9, fontWeight: FontWeight.bold), 
          shouldRenderAboveSeries: true
        ));
      }
      if (ai.takeProfit2 > 0) {
        bands.add(PlotBand(
          start: ai.takeProfit2, end: ai.takeProfit2, borderWidth: 1.5, 
          borderColor: AppTheme.signalBuy.withOpacity(0.7), dashArray: const <double>[5, 3], 
          text: 'AI TP2', textStyle: TextStyle(color: AppTheme.signalBuy.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.bold), 
          shouldRenderAboveSeries: true
        ));
      }
      if (ai.takeProfit3 > 0) {
        bands.add(PlotBand(
          start: ai.takeProfit3, end: ai.takeProfit3, borderWidth: 1.5, 
          borderColor: AppTheme.gold, dashArray: const <double>[5, 3], 
          text: 'AI TP3', textStyle: const TextStyle(color: AppTheme.gold, fontSize: 9, fontWeight: FontWeight.bold), 
          shouldRenderAboveSeries: true
        ));
      }
    } else if (widget.intelligence?.tradePlan.valid == true) {
      final tp = widget.intelligence!.tradePlan;
      if (tp.entry > 0) {
        bands.add(PlotBand(start: tp.entry, end: tp.entry, borderWidth: 1, borderColor: AppTheme.gold, text: 'ENTRY', textStyle: const TextStyle(color: AppTheme.gold, fontSize: 8), shouldRenderAboveSeries: true));
      }
      if (tp.sl > 0) {
        bands.add(PlotBand(start: tp.sl, end: tp.sl, borderWidth: 1, borderColor: AppTheme.signalSell, dashArray: const <double>[4, 4], text: 'SL', textStyle: const TextStyle(color: AppTheme.signalSell, fontSize: 8), shouldRenderAboveSeries: true));
      }
      if (tp.tp1 > 0) {
        bands.add(PlotBand(start: tp.tp1, end: tp.tp1, borderWidth: 1, borderColor: AppTheme.signalBuy, dashArray: const <double>[4, 4], text: 'TP1', textStyle: const TextStyle(color: AppTheme.signalBuy, fontSize: 8), shouldRenderAboveSeries: true));
      }
    }
    return bands;
  }

  @override
  void initState() { 
    super.initState(); 
    _syncHudToLast(); 
    widget.liveTickNotifier.addListener(_tickListener); 
  }

  @override
  void didUpdateWidget(covariant NexusCandleChart old) {
    super.didUpdateWidget(old);
    if (old.liveTickNotifier != widget.liveTickNotifier) { 
      old.liveTickNotifier.removeListener(_tickListener); 
      widget.liveTickNotifier.addListener(_tickListener); 
    }
    if (_seriesCtrl != null && widget.data.length == old.data.length + 1) {
      final lastIdx = _visibleData.length - 1;
      _seriesCtrl!.updateDataSource(addedDataIndexes: [lastIdx]);
      if (!_trackballActive) _syncHudToLast();
      return;
    }
    if (widget.data.length != old.data.length || (widget.data.isNotEmpty && old.data.isNotEmpty && widget.data.first.time != old.data.first.time)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHudToLast());
    }
  }

  @override
  void dispose() { 
    widget.liveTickNotifier.removeListener(_tickListener); 
    _hudNotifier.dispose(); 
    super.dispose(); 
  }

  void _tickListener() {
    if (!mounted) return;
    final tick = widget.liveTickNotifier.value;
    if (tick == null || tick.price <= 0) return;
    if (_seriesCtrl != null && _visibleData.isNotEmpty) {
      final lastIdx = _visibleData.length - 1;
      _seriesCtrl!.updateDataSource(updatedDataIndexes: [lastIdx]);
    }
    if (!_trackballActive) {
      final current = _hudNotifier.value;
      if (current != null) _hudNotifier.value = current.copyWith(close: tick.price);
      else _syncHudToLast();
    }
  }

  void _syncHudToLast() {
    final d = _visibleData;
    if (d.isEmpty) { _hudNotifier.value = null; return; }
    final last = d.last;
    final close = widget.liveTickNotifier.value?.price ?? last.close;
    _hudNotifier.value = _OhlcSnapshot(open: last.open, high: last.high, low: last.low, close: close, time: last.time);
  }

  @override
  Widget build(BuildContext context) {
    final visibleData = _visibleData;
    if (visibleData.isEmpty) return _ChartShimmer(height: widget.height);
    
    final samplePrice = widget.liveTickNotifier.value?.price ?? visibleData.last.close;
    final priceFormat = _smartFormat(samplePrice);
    final xMax = _xAxisMax(visibleData);
    final lastCandle = visibleData.last;
    final lastPriceColor = (samplePrice >= lastCandle.open) ? AppTheme.signalBuy : AppTheme.signalSell;
    
    final zoom = ZoomPanBehavior(
      enablePinching: true, enablePanning: true, enableDoubleTapZooming: true, 
      enableMouseWheelZooming: true, zoomMode: ZoomMode.x
    );
    final crosshair = CrosshairBehavior(
      enable: true, activationMode: ActivationMode.singleTap, lineType: CrosshairLineType.both, 
      lineColor: AppTheme.gold.withOpacity(0.30), lineWidth: 1.0, shouldAlwaysShow: false
    );

    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          child: Theme(
            data: Theme.of(context).copyWith(brightness: Brightness.dark),
            child: SfCartesianChart(
              plotAreaBorderWidth: 0, 
              backgroundColor: Colors.transparent, 
              margin: const EdgeInsets.fromLTRB(0, 8, 4, 8),
              primaryXAxis: DateTimeAxis(
                maximum: xMax, 
                majorGridLines: const MajorGridLines(width: 0), 
                minorGridLines: const MinorGridLines(width: 0),
                axisLine: const AxisLine(color: AppTheme.border, width: 1), 
                labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
                intervalType: DateTimeIntervalType.auto, 
                labelIntersectAction: _isCrypto ? AxisLabelIntersectAction.rotate45 : AxisLabelIntersectAction.hide,
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  final localDate = DateTime.fromMillisecondsSinceEpoch((details.value as num).toInt()).toLocal();
                  final isWide = visibleData.length > 1 && visibleData.last.time != null && visibleData.first.time != null && visibleData.last.time!.difference(visibleData.first.time!).inDays > 2;
                  final format = isWide ? DateFormat('MMM dd') : DateFormat('HH:mm');
                  return ChartAxisLabel(format.format(localDate), details.textStyle);
                },
              ),
              primaryYAxis: NumericAxis(
                opposedPosition: true, 
                anchorRangeToVisiblePoints: true, 
                enableAutoIntervalOnZooming: true, 
                rangePadding: ChartRangePadding.round,
                majorGridLines: MajorGridLines(width: 0.5, color: Colors.white.withOpacity(0.04), dashArray: const <double>[4, 4]),
                minorGridLines: const MinorGridLines(width: 0), 
                axisLine: const AxisLine(color: AppTheme.border, width: 1),
                labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
                numberFormat: priceFormat, 
                plotBands: _buildPlotBands(samplePrice, lastPriceColor),
              ),
              zoomPanBehavior: zoom, 
              crosshairBehavior: crosshair,
              trackballBehavior: TrackballBehavior(
                enable: true, 
                activationMode: ActivationMode.longPress, 
                tooltipDisplayMode: TrackballDisplayMode.none,
                lineType: TrackballLineType.vertical, 
                lineColor: AppTheme.gold.withOpacity(0.40), 
                lineWidth: 1.0, 
                shouldAlwaysShow: false,
                builder: (BuildContext ctx, TrackballDetails details) {
                  final pt = details.point;
                  if (pt != null) {
                    _trackballActive = true;
                    _hudNotifier.value = _OhlcSnapshot(
                      open: (pt.open as num?)?.toDouble() ?? 0, 
                      high: (pt.high as num?)?.toDouble() ?? 0, 
                      low: (pt.low as num?)?.toDouble() ?? 0, 
                      close: (pt.close as num?)?.toDouble() ?? 0
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              onTrackballPositionChanging: (TrackballArgs args) {
                final pt = args.chartPointInfo.dataPointIndex;
                if (pt == null || pt < 0) { 
                  _trackballActive = false; 
                  _syncHudToLast(); 
                }
              },
              series: <CartesianSeries<OhlcPoint, DateTime>>[
                CandleSeries<OhlcPoint, DateTime>(
                  name: 'OHLC', 
                  dataSource: visibleData,
                  xValueMapper: (OhlcPoint d, _) => d.time, 
                  openValueMapper: (OhlcPoint d, _) => d.open,
                  highValueMapper: (OhlcPoint d, _) => d.high, 
                  lowValueMapper: (OhlcPoint d, _) => d.low, 
                  closeValueMapper: (OhlcPoint d, _) => d.close,
                  bullColor: AppTheme.signalBuy, 
                  bearColor: AppTheme.signalSell, 
                  enableSolidCandles: true, 
                  borderWidth: 0.5, 
                  animationDuration: 0, // ✅ 0 for instant rendering
                  onRendererCreated: (ChartSeriesController ctrl) { _seriesCtrl = ctrl; },
                ),
              ],
            ),
          ),
        ),
        
        // HUD & Badges
        Positioned(top: 12, left: _isCrypto || widget.is24h ? 86 : 12, child: _OhlcHud(hudNotifier: _hudNotifier, tickNotifier: widget.liveTickNotifier, fmt: priceFormat)),
        if (widget.is24h || _isCrypto) const Positioned(top: 12, left: 12, child: _Live24hBadge()),
        if (widget.data.length > _kMaxVisible) Positioned(bottom: 12, left: 12, child: _DenseDataHint(total: widget.data.length, visible: _kMaxVisible)),
        Positioned(right: 8, bottom: 28, child: Opacity(opacity: 0.28, child: Text('▶', style: TextStyle(color: lastPriceColor, fontSize: 9)))),
        
        // Analysis Overlay
        if (widget.intelligence != null)
          Positioned.fill(
            child: AnalysisOverlay(
              intelligence: widget.intelligence,
              aiScenario: widget.aiScenario,
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CHART SHIMMER (Loading Animation)
// ════════════════════════════════════════════════════════════════════════════

class _ChartShimmer extends StatefulWidget {
  const _ChartShimmer({required this.height});
  final double height;
  @override
  State<_ChartShimmer> createState() => _ChartShimmerState();
}

class _ChartShimmerState extends State<_ChartShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;
  static final List<double> _candleHeights = List.generate(28, (i) => 0.30 + 0.55 * (math.sin(i * 1.37 + 0.4).abs()));
  
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (_, __) => CustomPaint(painter: _ShimmerBarPainter(heights: _candleHeights, progress: _shimmer.value), child: const SizedBox.expand()),
      ),
    );
  }
}

class _ShimmerBarPainter extends CustomPainter {
  const _ShimmerBarPainter({required this.heights, required this.progress});
  final List<double> heights;
  final double progress;
  
  @override
  void paint(Canvas canvas, Size size) {
    final totalBars = heights.length;
    final barWidth = (size.width - 24) / totalBars;
    final bodyWidth = barWidth * 0.55;
    final wickWidth = 1.2;
    final chartH = size.height - 32;
    final baseY = size.height - 16;
    final shimmerShader = LinearGradient(begin: Alignment(-1.0 + progress, 0), end: Alignment(0.0 + progress, 0), colors: const [Color(0x00FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final basePaint = Paint()..color = AppTheme.border.withOpacity(0.35)..style = PaintingStyle.fill;
    final shimmerPaint = Paint()..shader = shimmerShader..style = PaintingStyle.fill;
    
    for (int i = 0; i < totalBars; i++) {
      final x = 12.0 + i * barWidth + (barWidth - bodyWidth) / 2;
      final h = chartH * heights[i];
      final wickH = h * 0.25;
      final bodyRect = RRect.fromRectAndRadius(Rect.fromLTWH(x, baseY - h, bodyWidth, h), const Radius.circular(1.5));
      canvas.drawRRect(bodyRect, basePaint);
      canvas.drawRRect(bodyRect, shimmerPaint);
      final cx = x + bodyWidth / 2;
      canvas.drawRect(Rect.fromLTWH(cx - wickWidth / 2, baseY - h - wickH, wickWidth, wickH), basePaint);
    }
    canvas.drawRect(Rect.fromLTWH(0, baseY + 2, size.width, 0.5), Paint()..color = AppTheme.border.withOpacity(0.4));
  }
  @override
  bool shouldRepaint(_ShimmerBarPainter old) => old.progress != progress;
}

// ════════════════════════════════════════════════════════════════════════════
//  OHLC HUD (Top-Left Price Display)
// ════════════════════════════════════════════════════════════════════════════

class _OhlcHud extends StatelessWidget {
  const _OhlcHud({required this.hudNotifier, required this.tickNotifier, required this.fmt});
  final ValueNotifier<_OhlcSnapshot?> hudNotifier;
  final ValueNotifier<TickEntry?> tickNotifier;
  final NumberFormat fmt;
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_OhlcSnapshot?>(
      valueListenable: hudNotifier,
      builder: (_, snap, __) {
        if (snap == null) return const SizedBox.shrink();
        return ValueListenableBuilder<TickEntry?>(
          valueListenable: tickNotifier,
          builder: (_, tick, __) {
            final liveClose = (tick != null && tick.price > 0) ? tick.price : snap.close;
            final effectiveSnap = snap.copyWith(close: liveClose);
            final barColor = effectiveSnap.close >= effectiveSnap.open ? AppTheme.signalBuy : AppTheme.signalSell;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey('${effectiveSnap.open.toStringAsFixed(5)}${effectiveSnap.close.toStringAsFixed(5)}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.panel.withOpacity(0.88), 
                  borderRadius: BorderRadius.circular(5), 
                  border: Border.all(color: barColor.withOpacity(0.30), width: 0.8), 
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6)]
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  _hudRow('O', effectiveSnap.open, Colors.white60, fmt), 
                  _hudRow('H', effectiveSnap.high, AppTheme.signalBuy, fmt),
                  _hudRow('L', effectiveSnap.low, AppTheme.signalSell, fmt), 
                  _hudRow('C', effectiveSnap.close, barColor, fmt),
                ]),
              ),
            );
          },
        );
      },
    );
  }
  
  static Widget _hudRow(String label, double val, Color color, NumberFormat fmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 10, child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w700))),
        const SizedBox(width: 5),
        Text(fmt.format(val), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  24/7 LIVE BADGE
// ════════════════════════════════════════════════════════════════════════════

class _Live24hBadge extends StatefulWidget {
  const _Live24hBadge();
  @override
  State<_Live24hBadge> createState() => _Live24hBadgeState();
}

class _Live24hBadgeState extends State<_Live24hBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.signalBuy.withOpacity(0.10), 
          borderRadius: BorderRadius.circular(4), 
          border: Border.all(color: AppTheme.signalBuy.withOpacity(0.45 * _pulse.value), width: 1), 
          boxShadow: [BoxShadow(color: AppTheme.signalBuy.withOpacity(0.12 * _pulse.value), blurRadius: 6, spreadRadius: 0)]
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.signalBuy.withOpacity(_pulse.value))),
          const SizedBox(width: 5),
          Text('24/7 LIVE', style: TextStyle(color: AppTheme.signalBuy.withOpacity(0.7 + 0.3 * _pulse.value), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
        ]),
      ),
    );
  }
}

class _DenseDataHint extends StatelessWidget {
  const _DenseDataHint({required this.total, required this.visible});
  final int total;
  final int visible;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.60), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.border)),
      child: Text('SHOWING $visible / $total BARS  ·  PINCH TO ZOOM', style: const TextStyle(color: AppTheme.textMuted, fontSize: 8, letterSpacing: 0.8)),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ANALYSIS OVERLAY (Draws AI Levels on Chart)
// ════════════════════════════════════════════════════════════════════════════

class AnalysisOverlay extends StatelessWidget {
  const AnalysisOverlay({
    super.key,
    required this.intelligence,
    this.aiScenario,
    this.showTradePlan = true,
    this.showSR = true,
    this.showOB = true,
  });
  final MarketIntelligence? intelligence;
  final AiScenario? aiScenario;
  final bool showTradePlan;
  final bool showSR;
  final bool showOB;

  @override
  Widget build(BuildContext context) {
    if (intelligence == null) return const SizedBox.shrink();
    final mi = intelligence!;
    final tp = mi.tradePlan;
    return IgnorePointer(
      child: CustomPaint(
        painter: _AnalysisOverlayPainter(
          mi: mi,
          aiScenario: aiScenario,
          showTradePlan: showTradePlan && tp.valid,
          showSR: showSR,
          showOB: showOB,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AnalysisOverlayPainter extends CustomPainter {
  _AnalysisOverlayPainter({
    required this.mi,
    this.aiScenario,
    required this.showTradePlan,
    required this.showSR,
    required this.showOB,
  });
  final MarketIntelligence mi;
  final AiScenario? aiScenario;
  final bool showTradePlan;
  final bool showSR;
  final bool showOB;

  @override
  void paint(Canvas canvas, Size size) {
    final rightX = size.width; // Align to the right edge
    double y = 40; // Start below the top HUD
    
    // 1. Draw AI Scenario Levels (Strongly-typed, no 'raw' maps)
    if (showTradePlan && aiScenario != null) {
      final ai = aiScenario!;
      if (ai.entryZone.low > 0 && ai.entryZone.high > 0) {
        _drawLabel(canvas, rightX, y, (ai.entryZone.low + ai.entryZone.high) / 2, AppTheme.gold, 'AI ENTRY');
        y += 18;
      }
      if (ai.stopLoss > 0) {
        _drawLabel(canvas, rightX, y, ai.stopLoss, AppTheme.signalSell, 'AI SL');
        y += 18;
      }
      if (ai.takeProfit1 > 0) { _drawLabel(canvas, rightX, y, ai.takeProfit1, AppTheme.signalBuy, 'AI TP1'); y += 18; }
      if (ai.takeProfit2 > 0) { _drawLabel(canvas, rightX, y, ai.takeProfit2, AppTheme.signalBuy.withOpacity(0.7), 'AI TP2'); y += 18; }
      if (ai.takeProfit3 > 0) { _drawLabel(canvas, rightX, y, ai.takeProfit3, AppTheme.gold, 'AI TP3 🚀'); y += 18; }
    } 
    // 2. Fallback to Engine TradePlan
    else if (showTradePlan && mi.tradePlan.valid) {
      final tp = mi.tradePlan;
      if (tp.entry > 0) { _drawLabel(canvas, rightX, y, tp.entry, AppTheme.gold, 'ENTRY'); y += 18; }
      if (tp.sl > 0) { _drawLabel(canvas, rightX, y, tp.sl, AppTheme.signalSell, 'SL'); y += 18; }
      if (tp.tp1 > 0) { _drawLabel(canvas, rightX, y, tp.tp1, AppTheme.signalBuy, 'TP1'); y += 18; }
    }

    // 3. Draw Support / Resistance
    if (showSR) {
      if (mi.nearestSupport > 0 && mi.nearestSupport != mi.currentPrice) {
        _drawLabel(canvas, rightX, y, mi.nearestSupport, AppTheme.signalBuy.withOpacity(0.8), 'S'); y += 16;
      }
      if (mi.nearestResist > 0 && mi.nearestResist != mi.currentPrice) {
        _drawLabel(canvas, rightX, y, mi.nearestResist, AppTheme.signalSell.withOpacity(0.8), 'R'); y += 16;
      }
    }

    // 4. Draw Order Blocks
    if (showOB && mi.orderBlocks.isNotEmpty) {
      for (final ob in mi.orderBlocks.take(2)) {
        final type = (ob['type'] ?? '').toString().toUpperCase();
        final high = (ob['high'] as num?)?.toDouble() ?? 0;
        final low = (ob['low'] as num?)?.toDouble() ?? 0;
        final color = type.contains('BULL') ? AppTheme.signalBuy.withOpacity(0.7) : AppTheme.signalSell.withOpacity(0.7);
        _drawLabel(canvas, rightX, y, (low + high) / 2, color, type.contains('BULL') ? 'OB↑' : 'OB↓');
        y += 16;
      }
    }
  }

  void _drawLabel(Canvas canvas, double rightX, double y, double value, Color color, String label) {
    final text = '$label @ ${_dp(value)}';
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace')), 
      textAlign: TextAlign.right, 
      textDirection: ui.TextDirection.ltr
    )..layout(maxWidth: 160);
    
    // Ensure it doesn't draw off-screen
    final rectWidth = tp.width + 16;
    final startX = (rightX - rectWidth).clamp(0.0, rightX - 8);
    
    // Background
    final bg = Paint()..color = AppTheme.panel.withOpacity(0.90)..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(startX, y - 2, rectWidth, tp.height + 4), const Radius.circular(4)), 
      bg
    );
    
    // Border
    final border = Paint()..color = color.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(startX, y - 2, rectWidth, tp.height + 4), const Radius.circular(4)), 
      border
    );
    
    // Text
    tp.paint(canvas, Offset(startX + 8, y));
    
    // Small horizontal line connecting label to the edge
    final linePaint = Paint()
      ..color = color.withOpacity(0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(rightX, y + tp.height / 2), Offset(startX + rectWidth, y + tp.height / 2), linePaint);
  }

  String _dp(double v) {
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    if (v >= 0.01) return v.toStringAsFixed(5);
    return v.toStringAsFixed(6);
  }

  @override
  bool shouldRepaint(_AnalysisOverlayPainter old) => old.mi != mi || old.aiScenario != aiScenario || old.showTradePlan != showTradePlan || old.showSR != showSR || old.showOB != showOB;
}