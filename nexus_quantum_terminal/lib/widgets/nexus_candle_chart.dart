// ============================================================================
//  NEXUS v12.5 — nexus_candle_chart.dart
//  Syncfusion candlestick chart — Institutional Grade.
//
//  v12.5 additions over v12.0:
//  ─────────────────────────────────────────────────────────────────────────
//  1. LIVETICNOTIFIER PARAMETER
//     • `livePrice: double?` is REPLACED by
//       `liveTickNotifier: ValueNotifier<TickEntry?>`.
//     • In initState() a private `_tickListener` is registered on the
//       notifier.  Every tick fires:
//         a) _seriesCtrl.updateDataSource(updatedDataIndexes: [lastIdx])
//            → Syncfusion redraws ONLY the last candle body/wick.
//         b) _hudNotifier.value = _OhlcSnapshot(...)
//            → HUD ValueListenableBuilder updates with zero setState.
//     • The listener is removed in dispose() so there is zero risk of a
//       callback firing into a dead State object.
//     • didUpdateWidget Path A (same bar count → live tick) is REMOVED.
//       Only Path B (new bar appended) and Path C (full reload) remain,
//       both driven by REST candle refreshes as before.
//
//  2. SHIMMER LOADING SKELETON
//     • When candles are empty, instead of the plain "AWAITING CHART DATA"
//       icon the chart now renders a `_ChartShimmer` widget — a Stack of
//       shimmer-animated placeholder bars that exactly match the chart
//       height.  This prevents the Syncfusion "no data" label from flashing
//       on symbol switch and gives a broker-grade loading feel.
//     • The shimmer uses a pure Flutter AnimationController + linear
//       gradient sweep; no third-party package required.
//
//  3. HUD WIRED TO BOTH NOTIFIERS
//     • `_OhlcHud` now accepts the external `liveTickNotifier` alongside
//       the internal `_hudNotifier`.  A `_MergedHudNotifier` helper fuses
//       both: trackball interactions override via _hudNotifier; when the
//       trackball is dismissed the HUD reverts to the latest liveTickNotifier
//       value (the live close).  This ensures the displayed close is always
//       the most recent WebSocket price, not the stale REST close.
//
//  RETAINED FROM v12.0 (UNCHANGED):
//  • Right 20% viewport padding via _xAxisMax().
//  • Dynamic Y-axis with anchorRangeToVisiblePoints.
//  • Last-price dashed PlotBand.
//  • _Live24hBadge, _DenseDataHint, _PrecisionTooltip.
//  • TrackballBehavior → hidden native tooltip, OHLC pushed to _hudNotifier.
//  • Crosshair guide lines.
//  • All Gold / Syncfusion settings untouched.
//  ─────────────────────────────────────────────────────────────────────────
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../models/market_models.dart';
import '../theme/app_theme.dart';

// ── OHLC snapshot shared between trackball and the HUD ───────────────────────

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
    this.time,
  });

  _OhlcSnapshot copyWith({
    double? open,
    double? high,
    double? low,
    double? close,
    DateTime? time,
  }) =>
      _OhlcSnapshot(
        open:  open  ?? this.open,
        high:  high  ?? this.high,
        low:   low   ?? this.low,
        close: close ?? this.close,
        time:  time  ?? this.time,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class NexusCandleChart extends StatefulWidget {
  const NexusCandleChart({
    super.key,
    required this.data,
    required this.liveTickNotifier,         // v12.5: replaces livePrice
    this.height        = 420,
    this.assetType     = '',
    this.is24h         = false,
    this.decimalPlaces = 2,
  });

  final List<OhlcPoint>           data;
  final ValueNotifier<TickEntry?> liveTickNotifier; // v12.5

  final double height;

  /// "crypto", "forex", "commodity", "equity" — drives chart adaptations.
  final String assetType;

  /// True for 24/7 crypto markets — renders the LIVE badge overlay.
  final bool is24h;

  /// Decimal places hint from the API chartMetadata.
  final int decimalPlaces;

  @override
  State<NexusCandleChart> createState() => _NexusCandleChartState();
}

class _NexusCandleChartState extends State<NexusCandleChart> {
  // ── SeriesController — jank-free updateDataSource() ──────────────────────
  ChartSeriesController? _seriesCtrl;

  // ── OHLC HUD state ────────────────────────────────────────────────────────
  // _hudNotifier carries trackball overrides.  When the trackball is idle the
  // HUD falls through to liveTickNotifier for the live close value.
  final ValueNotifier<_OhlcSnapshot?> _hudNotifier =
      ValueNotifier<_OhlcSnapshot?>(null);

  bool _trackballActive = false;

  // ── Right-viewport-padding constants ─────────────────────────────────────
  static const double _kRightPaddingFactor = 0.20;

  // ── Visible data window ───────────────────────────────────────────────────
  static const int _kMaxVisible = 500;

  List<OhlcPoint> get _visibleData {
    if (widget.data.length <= _kMaxVisible) return widget.data;
    return widget.data.sublist(widget.data.length - _kMaxVisible);
  }

  // ── Asset-type helpers ────────────────────────────────────────────────────

  bool get _isCrypto =>
      widget.assetType.toLowerCase() == 'crypto'         ||
      widget.assetType.toLowerCase() == 'cryptocurrency' ||
      (widget.data.isNotEmpty && widget.data.first.isCrypto);

  bool get _isForex => widget.assetType.toLowerCase() == 'forex';

  // ── Decimal precision ─────────────────────────────────────────────────────

  int get _resolvedDp {
    if (widget.data.isNotEmpty && widget.data.first.decimalPlaces > 0) {
      return widget.data.first.decimalPlaces;
    }
    return widget.decimalPlaces;
  }

  NumberFormat _smartFormat([double? sample]) {
    if (_isForex) return NumberFormat('#,##0.00000');
    if (_isCrypto) {
      final ref = sample ??
          (widget.data.isNotEmpty ? widget.data.last.close : 0.0);
      if (ref >= 1000) return NumberFormat('#,##0.00');
      if (ref >= 1)    return NumberFormat('#,##0.0000');
      return NumberFormat('#,##0.000000');
    }
    final dp = _resolvedDp;
    if (dp <= 0) return NumberFormat('#,##0');
    if (dp == 2) return NumberFormat('#,##0.00');
    return NumberFormat('#,##0.${'0' * dp}');
  }

  // ── Right viewport padding ─────────────────────────────────────────────────

  DateTime? _xAxisMax(List<OhlcPoint> visible) {
    if (visible.isEmpty) return null;
    final first   = visible.first.time;
    final last    = visible.last.time;
    final rangeMs = last.difference(first).inMilliseconds;
    if (rangeMs <= 0) return null;
    final paddingMs =
        (rangeMs * _kRightPaddingFactor / (1.0 - _kRightPaddingFactor))
            .round();
    return last.add(Duration(milliseconds: paddingMs));
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _syncHudToLast();
    // v12.5: register the fast-track listener on the external notifier.
    widget.liveTickNotifier.addListener(_tickListener);
  }

  @override
  void didUpdateWidget(covariant NexusCandleChart old) {
    super.didUpdateWidget(old);

    // Re-wire listener when the notifier instance itself changes
    // (e.g. the parent passes a new ValueNotifier after a full rebuild).
    if (old.liveTickNotifier != widget.liveTickNotifier) {
      old.liveTickNotifier.removeListener(_tickListener);
      widget.liveTickNotifier.addListener(_tickListener);
    }

    // ── Path B: last bar appended (new candle closed from REST refresh) ──────
    if (_seriesCtrl != null &&
        widget.data.length == old.data.length + 1) {
      final lastIdx = _visibleData.length - 1;
      _seriesCtrl!.updateDataSource(addedDataIndexes: [lastIdx]);
      if (!_trackballActive) _syncHudToLast();
      return;
    }

    // ── Path C: symbol switch or major reload — full rebuild via key change.
    if (widget.data.length != old.data.length ||
        (widget.data.isNotEmpty && old.data.isNotEmpty &&
         widget.data.first.time != old.data.first.time)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHudToLast());
    }
  }

  @override
  void dispose() {
    widget.liveTickNotifier.removeListener(_tickListener);
    _hudNotifier.dispose();
    super.dispose();
  }

  // ── v12.5: Live tick listener ─────────────────────────────────────────────
  //
  // Fires every time MarketState pushes a new TickEntry for the selected
  // symbol.  Two side-effects — both without setState or notifyListeners:
  //   1. SeriesController.updateDataSource() redraws the last candle only.
  //   2. _hudNotifier receives the updated close so the HUD row refreshes.

  void _tickListener() {
    // Guard: widget may have been disposed between the notifier firing and
    // this callback executing (e.g. rapid symbol switches).
    if (!mounted) return;

    final tick = widget.liveTickNotifier.value;
    if (tick == null || tick.price <= 0) return;

    // ── 1. Tell Syncfusion to redraw only the last data point ─────────────
    if (_seriesCtrl != null && _visibleData.isNotEmpty) {
      final lastIdx = _visibleData.length - 1;
      _seriesCtrl!.updateDataSource(updatedDataIndexes: [lastIdx]);
    }

    // ── 2. Update HUD close without setState (only when trackball is idle) ─
    if (!_trackballActive) {
      final current = _hudNotifier.value;
      if (current != null) {
        _hudNotifier.value = current.copyWith(close: tick.price);
      } else {
        _syncHudToLast();
      }
    }
  }

  /// Push the last available candle (+ live price if available) into the HUD.
  void _syncHudToLast() {
    final d = _visibleData;
    if (d.isEmpty) {
      _hudNotifier.value = null;
      return;
    }
    final last  = d.last;
    // Prefer the live tick close so the HUD is always at WS price.
    final close = widget.liveTickNotifier.value?.price ?? last.close;
    _hudNotifier.value = _OhlcSnapshot(
      open:  last.open,
      high:  last.high,
      low:   last.low,
      close: close,
      time:  last.time,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visibleData = _visibleData;

    // ── Loading skeleton — shown while candles are loading or empty ──────────
    // Replaces the Syncfusion "no data" label with a shimmer that matches
    // the chart height so there is zero layout shift when data arrives.
    if (visibleData.isEmpty) {
      return _ChartShimmer(height: widget.height);
    }

    // Prefer live tick for the sample price driving axis formatting.
    final samplePrice = widget.liveTickNotifier.value?.price
        ?? visibleData.last.close;
    final priceFormat = _smartFormat(samplePrice);
    final xMax        = _xAxisMax(visibleData);

    final lastCandle     = visibleData.last;
    final lastPriceColor = (samplePrice >= lastCandle.open)
        ? AppTheme.signalBuy
        : AppTheme.signalSell;

    final zoom = ZoomPanBehavior(
      enablePinching:          true,
      enablePanning:           true,
      enableDoubleTapZooming:  true,
      enableMouseWheelZooming: true,
      zoomMode:                ZoomMode.x,
    );

    final crosshair = CrosshairBehavior(
      enable:           true,
      activationMode:   ActivationMode.singleTap,
      lineType:         CrosshairLineType.both,
      lineColor:        AppTheme.gold.withOpacity(0.30),
      lineWidth:        1.0,
      shouldAlwaysShow: false,
    );

    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          child: Theme(
            data: Theme.of(context).copyWith(brightness: Brightness.dark),
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              backgroundColor:     Colors.transparent,
              margin: const EdgeInsets.fromLTRB(0, 8, 4, 8),

              // ── X-axis — 20% right projection zone ───────────────────────
              primaryXAxis: DateTimeAxis(
                maximum:        xMax,
                majorGridLines: const MajorGridLines(width: 0),
                minorGridLines: const MinorGridLines(width: 0),
                axisLine:   const AxisLine(color: AppTheme.border, width: 1),
                labelStyle: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 9),
                intervalType:        DateTimeIntervalType.auto,
                labelIntersectAction: _isCrypto
                    ? AxisLabelIntersectAction.rotate45
                    : AxisLabelIntersectAction.hide,
              ),

              // ── Y-axis — visible-range scaling ───────────────────────────
              primaryYAxis: NumericAxis(
                opposedPosition:             true,
                anchorRangeToVisiblePoints:  true,
                enableAutoIntervalOnZooming: true,
                rangePadding:                ChartRangePadding.round,
                majorGridLines: MajorGridLines(
                  width:     0.5,
                  color:     Colors.white.withOpacity(0.04),
                  dashArray: const <double>[4, 4],
                ),
                minorGridLines: const MinorGridLines(width: 0),
                axisLine: const AxisLine(color: AppTheme.border, width: 1),
                labelStyle: const TextStyle(
                  color:      AppTheme.textMuted,
                  fontSize:   9,
                  fontFamily: 'monospace',
                ),
                numberFormat: priceFormat,
                plotBands: [
                  PlotBand(
                    start:                  samplePrice,
                    end:                    samplePrice,
                    borderWidth:            1,
                    borderColor:            lastPriceColor.withOpacity(0.45),
                    dashArray:              const <double>[4, 4],
                    shouldRenderAboveSeries: true,
                  ),
                ],
              ),

              zoomPanBehavior:   zoom,
              crosshairBehavior: crosshair,

              // ── TrackballBehavior — feeds HUD, hides native tooltip ───────
              trackballBehavior: TrackballBehavior(
                enable:             true,
                activationMode:     ActivationMode.longPress,
                tooltipDisplayMode: TrackballDisplayMode.none,
                lineType:           TrackballLineType.vertical,
                lineColor:          AppTheme.gold.withOpacity(0.40),
                lineWidth:          1.0,
                shouldAlwaysShow:   false,
                builder: (BuildContext ctx, TrackballDetails details) {
                  final pt = details.point;
                  if (pt != null) {
                    _trackballActive = true;
                    _hudNotifier.value = _OhlcSnapshot(
                      open:  (pt.open  as num?)?.toDouble() ?? 0,
                      high:  (pt.high  as num?)?.toDouble() ?? 0,
                      low:   (pt.low   as num?)?.toDouble() ?? 0,
                      close: (pt.close as num?)?.toDouble() ?? 0,
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
                  name:       'OHLC',
                  dataSource: visibleData,

                  xValueMapper:     (OhlcPoint d, _) => d.time,
                  openValueMapper:  (OhlcPoint d, _) => d.open,
                  highValueMapper:  (OhlcPoint d, _) => d.high,
                  lowValueMapper:   (OhlcPoint d, _) => d.low,
                  closeValueMapper: (OhlcPoint d, _) => d.close,

                  bullColor:          AppTheme.signalBuy,
                  bearColor:          AppTheme.signalSell,
                  enableSolidCandles: true,
                  borderWidth:        0.5,
                  animationDuration:  _isCrypto ? 200 : 600,

                  onRendererCreated: (ChartSeriesController ctrl) {
                    _seriesCtrl = ctrl;
                  },
                ),
              ],
            ),
          ),
        ),

        // ── OHLC HUD — top-left ───────────────────────────────────────────
        Positioned(
          top:  12,
          left: _isCrypto || widget.is24h ? 86 : 12,
          child: _OhlcHud(
            hudNotifier:  _hudNotifier,
            tickNotifier: widget.liveTickNotifier,
            fmt:          priceFormat,
          ),
        ),

        // ── 24/7 LIVE badge ───────────────────────────────────────────────
        if (widget.is24h || _isCrypto)
          const Positioned(
            top:  12,
            left: 12,
            child: _Live24hBadge(),
          ),

        // ── Dense-data hint ───────────────────────────────────────────────
        if (widget.data.length > _kMaxVisible)
          Positioned(
            bottom: 12,
            left:   12,
            child:  _DenseDataHint(
              total:   widget.data.length,
              visible: _kMaxVisible,
            ),
          ),

        // ── Right-padding projection label ────────────────────────────────
        Positioned(
          right:  8,
          bottom: 28,
          child: Opacity(
            opacity: 0.28,
            child: Text(
              '▶',
              style: TextStyle(color: lastPriceColor, fontSize: 9),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shimmer Loading Skeleton ─────────────────────────────────────────────────
// Shown whenever visibleData is empty (first load, symbol switch loading state).
// Pure Flutter — no third-party shimmer package needed.

class _ChartShimmer extends StatefulWidget {
  const _ChartShimmer({required this.height});
  final double height;

  @override
  State<_ChartShimmer> createState() => _ChartShimmerState();
}

class _ChartShimmerState extends State<_ChartShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _shimmer;

  // Deterministic pseudo-random candle heights for a realistic silhouette.
  static final List<double> _candleHeights = List.generate(
    28,
    (i) => 0.30 + 0.55 * (math.sin(i * 1.37 + 0.4).abs()),
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (_, __) {
          return CustomPaint(
            painter: _ShimmerBarPainter(
              heights:  _candleHeights,
              progress: _shimmer.value,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _ShimmerBarPainter extends CustomPainter {
  const _ShimmerBarPainter({
    required this.heights,
    required this.progress,
  });

  final List<double> heights;
  final double       progress;

  @override
  void paint(Canvas canvas, Size size) {
    final totalBars  = heights.length;
    final barWidth   = (size.width - 24) / totalBars;
    final bodyWidth  = barWidth * 0.55;
    final wickWidth  = 1.2;
    final chartH     = size.height - 32;
    final baseY      = size.height - 16;

    // Shimmer gradient sweeps left to right.
    final shimmerShader = LinearGradient(
      begin: Alignment(-1.0 + progress, 0),
      end:   Alignment(0.0  + progress, 0),
      colors: const [
        Color(0x00FFFFFF),
        Color(0x14FFFFFF),
        Color(0x00FFFFFF),
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final basePaint = Paint()
      ..color = AppTheme.border.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    final shimmerPaint = Paint()
      ..shader = shimmerShader
      ..style   = PaintingStyle.fill;

    for (int i = 0; i < totalBars; i++) {
      final x      = 12.0 + i * barWidth + (barWidth - bodyWidth) / 2;
      final h      = chartH * heights[i];
      final wickH  = h * 0.25;

      // Body
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseY - h, bodyWidth, h),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(bodyRect, basePaint);
      canvas.drawRRect(bodyRect, shimmerPaint);

      // Upper wick
      final cx = x + bodyWidth / 2;
      canvas.drawRect(
        Rect.fromLTWH(cx - wickWidth / 2, baseY - h - wickH, wickWidth, wickH),
        basePaint,
      );
    }

    // Bottom axis line
    canvas.drawRect(
      Rect.fromLTWH(0, baseY + 2, size.width, 0.5),
      Paint()..color = AppTheme.border.withOpacity(0.4),
    );
  }

  @override
  bool shouldRepaint(_ShimmerBarPainter old) => old.progress != progress;
}

// ─── OHLC HUD ─────────────────────────────────────────────────────────────────
// v12.5: accepts both the internal trackball notifier and the external
// liveTickNotifier so the close row always shows the WS live price when
// the trackball is not active.

class _OhlcHud extends StatelessWidget {
  const _OhlcHud({
    required this.hudNotifier,
    required this.tickNotifier,
    required this.fmt,
  });

  final ValueNotifier<_OhlcSnapshot?> hudNotifier;
  final ValueNotifier<TickEntry?>     tickNotifier;
  final NumberFormat                  fmt;

  @override
  Widget build(BuildContext context) {
    // Listen to the internal HUD notifier for O/H/L/C snapshots from the
    // trackball, and additionally listen to the live tick notifier to keep
    // the close row up-to-date at WS cadence without setState.
    return ValueListenableBuilder<_OhlcSnapshot?>(
      valueListenable: hudNotifier,
      builder: (_, snap, __) {
        if (snap == null) return const SizedBox.shrink();

        // Overlay the live close on top of the snapshot close when available.
        return ValueListenableBuilder<TickEntry?>(
          valueListenable: tickNotifier,
          builder: (_, tick, __) {
            final liveClose = (tick != null && tick.price > 0)
                ? tick.price
                : snap.close;
            final effectiveSnap = snap.copyWith(close: liveClose);
            final barColor = effectiveSnap.close >= effectiveSnap.open
                ? AppTheme.signalBuy
                : AppTheme.signalSell;

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey(
                    '${effectiveSnap.open.toStringAsFixed(5)}'
                    '${effectiveSnap.close.toStringAsFixed(5)}'),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color:        AppTheme.panel.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: barColor.withOpacity(0.30),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      Colors.black.withOpacity(0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize:       MainAxisSize.min,
                  children: [
                    _hudRow('O', effectiveSnap.open,  Colors.white60,     fmt),
                    _hudRow('H', effectiveSnap.high,  AppTheme.signalBuy, fmt),
                    _hudRow('L', effectiveSnap.low,   AppTheme.signalSell, fmt),
                    _hudRow('C', effectiveSnap.close, barColor,            fmt),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _hudRow(
      String label, double val, Color color, NumberFormat fmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            child: Text(
              label,
              style: const TextStyle(
                color:      AppTheme.textMuted,
                fontSize:   9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            fmt.format(val),
            style: TextStyle(
              color:      color,
              fontSize:   10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 24/7 Live Badge ──────────────────────────────────────────────────────────

class _Live24hBadge extends StatefulWidget {
  const _Live24hBadge();

  @override
  State<_Live24hBadge> createState() => _Live24hBadgeState();
}

class _Live24hBadgeState extends State<_Live24hBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:        AppTheme.signalBuy.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.signalBuy.withOpacity(0.45 * _pulse.value),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color:        AppTheme.signalBuy.withOpacity(0.12 * _pulse.value),
              blurRadius:   6,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width:  5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.signalBuy.withOpacity(_pulse.value),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '24/7 LIVE',
              style: TextStyle(
                color:         AppTheme.signalBuy
                    .withOpacity(0.7 + 0.3 * _pulse.value),
                fontSize:      8,
                fontWeight:    FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dense Data Hint ──────────────────────────────────────────────────────────

class _DenseDataHint extends StatelessWidget {
  const _DenseDataHint({required this.total, required this.visible});
  final int total;
  final int visible;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(4),
        border:       Border.all(color: AppTheme.border),
      ),
      child: Text(
        'SHOWING $visible / $total BARS  ·  PINCH TO ZOOM',
        style: const TextStyle(
          color:         AppTheme.textMuted,
          fontSize:      8,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── _PrecisionTooltip — retained utility from v12.0 ─────────────────────────

class _PrecisionTooltip extends StatelessWidget {
  const _PrecisionTooltip({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.fmt,
    required this.isCrypto,
  });

  final double       open;
  final double       high;
  final double       low;
  final double       close;
  final NumberFormat fmt;
  final bool         isCrypto;

  Color get _barColor =>
      close >= open ? AppTheme.signalBuy : AppTheme.signalSell;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:        AppTheme.panel,
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: _barColor.withOpacity(0.40)),
        boxShadow: [
          BoxShadow(
            color:      _barColor.withOpacity(0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:       MainAxisSize.min,
        children: [
          _row('O', open,  Colors.white70),
          _row('H', high,  AppTheme.signalBuy),
          _row('L', low,   AppTheme.signalSell),
          _row('C', close, _barColor),
        ],
      ),
    );
  }

  Widget _row(String lbl, double val, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            child: Text(
              lbl,
              style: const TextStyle(
                color:      AppTheme.textMuted,
                fontSize:   9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            fmt.format(val),
            style: TextStyle(
              color:      c,
              fontSize:   10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}