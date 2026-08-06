// ============================================================================
//  NEXUS v11.2 — glowing_signal_card.dart
//  Animated signal card with neon glow pulse, confidence ring, and
//  dual-gradient bear/bull probability bar.
//
//  v11.2: No logic changes. Reproduced in full for completeness.
//  The constructor signature is now positional-parameter compatible with
//  the v11.2 callers in home_shell.dart and trading_screen.dart which
//  pass signal / strength / direction / probability as named params.
// ============================================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlowingSignalCard extends StatefulWidget {
  const GlowingSignalCard({
    super.key,
    required this.signal,
    required this.strength,
    required this.direction,
    required this.probability,
  });

  /// e.g. "STRONG BUY", "SELL", "WAIT"
  final String signal;

  /// 0–100 confidence score
  final double strength;

  /// e.g. "BULLISH", "BEARISH", "NEUTRAL"
  final String direction;

  /// 0–100 bull probability
  final double probability;

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
    // Re-trigger animation whenever the signal changes
    if (old.signal != widget.signal || old.strength != widget.strength) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Accent colour derived from signal text ────────────────────────────────

  Color get _accent {
    final s = widget.signal.toUpperCase();
    if (s.contains('STRONG BUY'))  return AppTheme.signalBuy;
    if (s.contains('BUY'))         return AppTheme.signalBuy;
    if (s.contains('STRONG SELL')) return AppTheme.signalSell;
    if (s.contains('SELL'))        return AppTheme.signalSell;
    if (s.contains('WAIT') || s.contains('HOLD')) return AppTheme.goldDim;
    return AppTheme.gold;
  }

  // ── Strength arc angle (0 → 2π) ──────────────────────────────────────────

  double get _arcFraction => (widget.strength.clamp(0.0, 100.0)) / 100.0;

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.signal.toUpperCase(),
                    style: TextStyle(
                      color:       _accent,
                      fontSize:    28,
                      fontWeight:  FontWeight.w900,
                      letterSpacing: 4,
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
        ],
      ),
    );
  }
}

// ─── Confidence arc widget ────────────────────────────────────────────────

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
    const startAngle = -3.14159 / 2; // top

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color      = color.withOpacity(0.1)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Arc
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

// ─── Probability bar ──────────────────────────────────────────────────────

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
                // Bear segment
                Expanded(
                  flex: bearPct.toInt(),
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
                // Bull segment
                Expanded(
                  flex: bullPct.toInt(),
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