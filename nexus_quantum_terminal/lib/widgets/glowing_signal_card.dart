// ============================================================================
//  NEXUS v13.1 — glowing_signal_card.dart
//  Animated signal card with neon glow pulse, confidence ring, and
//  dual-gradient bear/bull probability bar.
//
//  v13.1 additions over v11.2:
//  ─────────────────────────────────────────────────────────────────────────
//  ✅ NEW: Extended constructor accepts advanced v13.1 metrics
//  ✅ NEW: Order Flow indicator (buying pressure bar)
//  ✅ NEW: Expectancy pill (+$ per $1 risked)
//  ✅ NEW: 7-layer mini bars (confluence breakdown)
//  ✅ NEW: News sentiment badge (Finnhub integration)
//  ✅ NEW: Monte Carlo stats row (VaR / MaxDD / Ruin probability)
//  ✅ NEW: Backward compatible — old constructor signature still works
//
//  ALL v11.2 FEATURES RETAINED 100% UNCHANGED:
//  • Neon glow pulse animation
//  • Confidence arc (0→100 ring)
//  • Dual-gradient probability bar (bear/bull)
//  • Accent color derived from signal text
//  • Re-trigger animation on signal change
//  ============================================================================

import 'package:flutter/material.dart';
import '../models/market_models.dart';
import '../theme/app_theme.dart';

class GlowingSignalCard extends StatefulWidget {
  const GlowingSignalCard({
    super.key,
    required this.signal,
    required this.strength,
    required this.direction,
    required this.probability,
    // ── v13.1 advanced metrics (all optional) ──
    this.intelligence,
    this.tradePlan,
    this.newsItems,
    this.showAdvanced = true,
  });

  /// e.g. "STRONG BUY", "SELL", "WAIT"
  final String signal;

  /// 0–100 confidence score
  final double strength;

  /// e.g. "BULLISH", "BEARISH", "NEUTRAL"
  final String direction;

  /// 0–100 bull probability
  final double probability;

  // ── v13.1 advanced metrics ──────────────────────────────────────────────
  final MarketIntelligence? intelligence;
  final TradePlan? tradePlan;
  final List<NewsItem>? newsItems;

  /// Toggle to hide advanced section (for compact layouts).
  final bool showAdvanced;

  @override
  State<GlowingSignalCard> createState() => _GlowingSignalCardState();
}

class _GlowingSignalCardState extends State<GlowingSignalCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
    _glowAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant GlowingSignalCard old) {
    super.didUpdateWidget(old);
    if (old.signal != widget.signal || old.strength != widget.strength) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accent {
    final s = widget.signal.toUpperCase();
    if (s.contains('STRONG BUY'))  return AppTheme.signalBuy;
    if (s.contains('BUY'))         return AppTheme.signalBuy;
    if (s.contains('STRONG SELL')) return AppTheme.signalSell;
    if (s.contains('SELL'))        return AppTheme.signalSell;
    if (s.contains('WAIT') || s.contains('HOLD')) return AppTheme.goldDim;
    return AppTheme.gold;
  }

  double get _arcFraction => (widget.strength.clamp(0.0, 100.0)) / 100.0;

  // ── v13.1 derived metrics ────────────────────────────────────────────────

  TradePlan get _tp => widget.tradePlan ?? widget.intelligence?.tradePlan ?? const TradePlan();
  List<NewsItem> get _news => widget.newsItems ?? const [];

  bool get _hasAdvanced =>
      widget.showAdvanced &&
      (widget.intelligence != null || widget.tradePlan != null);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        final t = _glowAnim.value;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accent.withOpacity(0.25 + 0.40 * t),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:       _accent.withOpacity(0.18 * (1 - t * 0.7)),
                blurRadius:  12 + 28 * t,
                spreadRadius: 1 + 4 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        children: [
          // ── Confidence badge + arc ─────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ConfidenceArc(fraction: _arcFraction, color: _accent),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.signal.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                          color:       _accent,
                          fontSize:    28,
                          fontWeight:  FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.direction.toUpperCase(),
                      style: const TextStyle(
                        color:       AppTheme.textPrimary,
                        fontSize:    13,
                        fontWeight:  FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Confidence pill ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color:        _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: _accent.withOpacity(0.25)),
            ),
            child: Text(
              'CONFIDENCE  ${widget.strength.toInt()}%',
              style: TextStyle(
                color:       _accent,
                fontSize:    10,
                fontWeight:  FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 14),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),

          // ── Probability bar ────────────────────────────────────────────
          _ProbabilityBar(probability: widget.probability),

          // ── v13.1 Advanced Section ─────────────────────────────────────
          if (_hasAdvanced) ...[
            const SizedBox(height: 16),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 12),

            // ── Expectancy + Win Rate Row ──────────────────────────────
            _AdvancedMetricsRow(tradePlan: _tp),

            // ── Order Flow ─────────────────────────────────────────────
            if (_tp.proxyOrderFlow.isNotEmpty) ...[
              const SizedBox(height: 12),
              _OrderFlowIndicator(proxyOrderFlow: _tp.proxyOrderFlow),
            ],

            // ── 7-Layer Confluence Bars ────────────────────────────────
            if (_tp.layerScores.isNotEmpty) ...[
              const SizedBox(height: 14),
              _LayerScoresBars(scores: _tp.layerScores),
            ],

            // ── Monte Carlo Stats ──────────────────────────────────────
            if (widget.intelligence?.monteCarlo != null) ...[
              const SizedBox(height: 14),
              _MonteCarloStats(stats: widget.intelligence!.monteCarlo!),
            ],

            // ── News Sentiment Badge ───────────────────────────────────
            if (_news.isNotEmpty) ...[
              const SizedBox(height: 14),
              _NewsSentimentBadge(news: _news),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Confidence arc widget (unchanged) ─────────────────────────────────────

class _ConfidenceArc extends StatelessWidget {
  const _ConfidenceArc({required this.fraction, required this.color});
  final double fraction;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: CustomPaint(
        painter: _ArcPainter(fraction: fraction, color: color),
        child: Center(
          child: Text(
            '${(fraction * 100).toInt()}',
            style: TextStyle(
              color:      color,
              fontSize:   14,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.fraction, required this.color});
  final double fraction;
  final Color  color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const startAngle = -3.14159 / 2;

    canvas.drawCircle(
      center, radius,
      Paint()
        ..color      = color.withOpacity(0.1)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * 3.14159 * fraction,
      false,
      Paint()
        ..color      = color
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap  = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color;
}

// ─── Probability bar (unchanged) ──────────────────────────────────────────

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({required this.probability});
  final double probability;

  @override
  Widget build(BuildContext context) {
    final bullPct = probability.clamp(0.0, 100.0);
    final bearPct = 100.0 - bullPct;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'BEAR  ${bearPct.toStringAsFixed(1)}%',
              style: const TextStyle(
                color:      AppTheme.signalSell,
                fontSize:   10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const Text(
              'PROBABILITY',
              style: TextStyle(
                color:       AppTheme.textMuted,
                fontSize:    9,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${bullPct.toStringAsFixed(1)}%  BULL',
              style: const TextStyle(
                color:      AppTheme.signalBuy,
                fontSize:   10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: bearPct.toInt().clamp(1, 100),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.signalSell,
                          AppTheme.signalSell.withOpacity(0.3),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: bullPct.toInt().clamp(1, 100),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.signalBuy.withOpacity(0.3),
                          AppTheme.signalBuy,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  v13.1 — ADVANCED METRICS WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

// ─── Expectancy + Win Rate Row ─────────────────────────────────────────────

class _AdvancedMetricsRow extends StatelessWidget {
  const _AdvancedMetricsRow({required this.tradePlan});
  final TradePlan tradePlan;

  @override
  Widget build(BuildContext context) {
    final expectancy = tradePlan.expectancyPerDollar;
    final winRate = tradePlan.estimatedWinRate * 100;
    final volRisk = tradePlan.volatilityAdjustedRiskPct;
    final expectancyColor = expectancy > 0
        ? AppTheme.signalBuy
        : expectancy < 0
            ? AppTheme.signalSell
            : AppTheme.textMuted;

    return Row(
      children: [
        // Expectancy
        Expanded(
          child: _MetricPill(
            label: 'EXPECTANCY',
            value: '${expectancy >= 0 ? '+' : ''}${expectancy.toStringAsFixed(2)}',
            suffix: 'per \$1',
            color: expectancyColor,
          ),
        ),
        const SizedBox(width: 8),
        // Win Rate
        Expanded(
          child: _MetricPill(
            label: 'EST. WIN RATE',
            value: winRate.toStringAsFixed(0),
            suffix: '%',
            color: winRate >= 50
                ? AppTheme.signalBuy
                : AppTheme.signalSell,
          ),
        ),
        const SizedBox(width: 8),
        // Vol-Adjusted Risk
        Expanded(
          child: _MetricPill(
            label: 'VOL-RISK',
            value: volRisk.toStringAsFixed(2),
            suffix: '%',
            color: AppTheme.gold,
          ),
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
  });

  final String label;
  final String value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color:        AppTheme.textMuted,
              fontSize:     8,
              fontWeight:   FontWeight.w700,
              letterSpacing: 1.0,
              fontFamily:   'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color:        color,
                  fontSize:     14,
                  fontWeight:   FontWeight.w900,
                  fontFamily:   'monospace',
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  suffix,
                  style: TextStyle(
                    color:      color.withOpacity(0.7),
                    fontSize:   9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Order Flow Indicator ─────────────────────────────────────────────────

class _OrderFlowIndicator extends StatelessWidget {
  const _OrderFlowIndicator({required this.proxyOrderFlow});
  final Map<String, dynamic> proxyOrderFlow;

  @override
  Widget build(BuildContext context) {
    final deltaSignal = (proxyOrderFlow['deltaSignal'] ?? 'NEUTRAL').toString();
    final buyingPressure = (proxyOrderFlow['buyingPressure'] as num?)?.toDouble() ?? 50.0;

    final isBullish = deltaSignal.contains('BUYING') || buyingPressure > 60;
    final isBearish = deltaSignal.contains('SELLING') || buyingPressure < 40;
    final color = isBullish
        ? AppTheme.signalBuy
        : isBearish
            ? AppTheme.signalSell
            : AppTheme.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.water_drop, size: 12, color: AppTheme.goldDim),
            const SizedBox(width: 6),
            Text(
              'PROXY ORDER FLOW',
              style: TextStyle(
                color:        AppTheme.textMuted,
                fontSize:     9,
                fontWeight:   FontWeight.w700,
                letterSpacing: 1.0,
                fontFamily:   'monospace',
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:        color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border:       Border.all(color: color.withOpacity(0.4)),
              ),
              child: Text(
                deltaSignal.replaceAll('_', ' '),
                style: TextStyle(
                  color:      color,
                  fontSize:   9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Label row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SELLERS',
              style: TextStyle(
                color:      AppTheme.signalSell.withOpacity(0.7),
                fontSize:   8,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '${buyingPressure.toStringAsFixed(0)}% BUYING',
              style: TextStyle(
                color:      color,
                fontSize:   9,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'BUYERS',
              style: TextStyle(
                color:      AppTheme.signalBuy.withOpacity(0.7),
                fontSize:   8,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 6,
            color: AppTheme.signalSell.withOpacity(0.3),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (buyingPressure / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.signalBuy.withOpacity(0.6),
                      AppTheme.signalBuy,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 7-Layer Confluence Bars ──────────────────────────────────────────────

class _LayerScoresBars extends StatelessWidget {
  const _LayerScoresBars({required this.scores});
  final Map<String, double> scores;

  static const Map<String, String> _labels = {
    'trend':      'TREND',
    'structure':  'STRUCT',
    'momentum':   'MOMNT',
    'smc':        'SMC',
    'volume':     'VOL',
    'divergence': 'DIVRG',
    'pattern':    'PATTR',
  };

  @override
  Widget build(BuildContext context) {
    final entries = scores.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.layers, size: 12, color: AppTheme.goldDim),
            const SizedBox(width: 6),
            Text(
              '7-LAYER CONFLUENCE',
              style: TextStyle(
                color:        AppTheme.textMuted,
                fontSize:     9,
                fontWeight:   FontWeight.w700,
                letterSpacing: 1.0,
                fontFamily:   'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...entries.map((e) {
          final label = _labels[e.key] ?? e.key.toUpperCase();
          final score = e.value;
          final color = score > 0
              ? AppTheme.layerPositive
              : score < 0
                  ? AppTheme.layerNegative
                  : AppTheme.layerNeutral;
          // Normalize -100..+100 → 0..1 for bar width
          final normalized = ((score + 100) / 200).clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color:      AppTheme.textMuted,
                      fontSize:   9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Stack(
                    children: [
                      // Background track
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color:        Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Center marker
                      Positioned(
                        left: 0, right: 0, top: 0, bottom: 0,
                        child: Center(
                          child: Container(
                            width: 1,
                            height: 8,
                            color: AppTheme.border,
                          ),
                        ),
                      ),
                      // Score bar
                      FractionallySizedBox(
                        widthFactor: normalized,
                        child: Container(
                          decoration: BoxDecoration(
                            color:        color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 30,
                  child: Text(
                    score.toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color:      color,
                      fontSize:   10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Monte Carlo Stats ────────────────────────────────────────────────────

class _MonteCarloStats extends StatelessWidget {
  const _MonteCarloStats({required this.stats});
  final MonteCarloStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.casino, size: 12, color: AppTheme.goldDim),
              const SizedBox(width: 6),
              Text(
                'MONTE CARLO SIMULATION',
                style: TextStyle(
                  color:        AppTheme.textMuted,
                  fontSize:     9,
                  fontWeight:   FontWeight.w700,
                  letterSpacing: 1.0,
                  fontFamily:   'monospace',
                ),
              ),
              const Spacer(),
              Text(
                '${stats.simulationsRun} runs',
                style: TextStyle(
                  color:      AppTheme.textDim,
                  fontSize:   8,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _McStat(
                  label: 'VaR 95%',
                  value: '\$${stats.var95.toStringAsFixed(0)}',
                  color: AppTheme.signalSell,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _McStat(
                  label: 'MAX DD',
                  value: '${stats.expectedMaxDrawdown.toStringAsFixed(1)}%',
                  color: AppTheme.signalSell.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _McStat(
                  label: 'RUIN PROB',
                  value: '${stats.probabilityOfRuin.toStringAsFixed(1)}%',
                  color: stats.probabilityOfRuin > 20
                      ? AppTheme.signalSell
                      : AppTheme.goldDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _McStat extends StatelessWidget {
  const _McStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color:        AppTheme.textMuted,
            fontSize:     8,
            fontWeight:   FontWeight.w600,
            letterSpacing: 0.8,
            fontFamily:   'monospace',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color:        color,
            fontSize:     13,
            fontWeight:   FontWeight.w900,
            fontFamily:   'monospace',
          ),
        ),
      ],
    );
  }
}

// ─── News Sentiment Badge ─────────────────────────────────────────────────

class _NewsSentimentBadge extends StatelessWidget {
  const _NewsSentimentBadge({required this.news});
  final List<NewsItem> news;

  @override
  Widget build(BuildContext context) {
    if (news.isEmpty) return const SizedBox.shrink();

    final avg = news.fold<double>(
      0.0,
      (sum, n) => sum + n.sentimentScore,
    ) / news.length;

    final bullishCount = news.where((n) => n.sentimentScore > 0.3).length;
    final bearishCount = news.where((n) => n.sentimentScore < -0.3).length;

    final color = avg > 0.1
        ? AppTheme.newsBullish
        : avg < -0.1
            ? AppTheme.newsBearish
            : AppTheme.newsNeutral;

    final label = avg > 0.1
        ? 'BULLISH SENTIMENT'
        : avg < -0.1
            ? 'BEARISH SENTIMENT'
            : 'NEUTRAL SENTIMENT';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.article, size: 14, color: AppTheme.goldDim),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color:        color,
                    fontSize:     9,
                    fontWeight:   FontWeight.w800,
                    letterSpacing: 1.0,
                    fontFamily:   'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${news.length} articles  •  ${avg > 0 ? '+' : ''}${avg.toStringAsFixed(2)}',
                  style: TextStyle(
                    color:      AppTheme.textMuted,
                    fontSize:   9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniCount(
                count: bullishCount,
                color: AppTheme.newsBullish,
                icon: Icons.trending_up,
              ),
              const SizedBox(width: 6),
              _MiniCount(
                count: bearishCount,
                color: AppTheme.newsBearish,
                icon: Icons.trending_down,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  const _MiniCount({
    required this.count,
    required this.color,
    required this.icon,
  });

  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              color:      color,
              fontSize:   10,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
