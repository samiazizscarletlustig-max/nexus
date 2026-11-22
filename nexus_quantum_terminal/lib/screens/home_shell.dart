// ============================================================================
//  NEXUS v13.4 — home_shell.dart
//  Responsive shell: DesktopDashboard (≥1100 px) / MobileTerminal (< 1100 px).
//  Fully wired with AnalysisOverlay, GlowingSignalCard, and Live Ticks.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ads/ad_placeholders.dart';
import '../models/market_models.dart';
import '../providers/market_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glowing_signal_card.dart';
import '../widgets/nexus_candle_chart.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DESKTOP DASHBOARD
// ════════════════════════════════════════════════════════════════════════════

class DesktopDashboard extends StatelessWidget {
  const DesktopDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: 300,
            child: _WatchlistPane(compact: false),
          ),
          const VerticalDivider(width: 1, color: AppTheme.border),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TopStatusBar(),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final item = s.selectedItem;
                            final chartHeight = constraints.maxHeight.isFinite
                                ? constraints.maxHeight
                                : 420.0;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ColoredBox(
                                color: AppTheme.panel,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: s.loadingCandles && s.candles.isEmpty
                                      ? _ChartSkeleton(height: chartHeight)
                                      : Stack(
                                          children: [
                                            NexusCandleChart(
                                              data: s.candles,
                                              liveTickNotifier: s.liveTickNotifier,
                                              height: chartHeight,
                                              assetType: item?.type ?? '',
                                              is24h: item?.is24h ?? false,
                                              decimalPlaces: _dpForType(item?.type),
                                            ),
                                            if (s.lastAnalysis != null)
                                              Positioned.fill(
                                                child: AnalysisOverlay(
                                                  intelligence: s.lastAnalysis!.intelligence,
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 340,
                        child: _ScanAndSignalColumn(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _dpForType(String? type) {
    if (type == 'forex') return 5;
    return 2;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TOP STATUS BAR
// ════════════════════════════════════════════════════════════════════════════

class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();
    final item = s.selectedItem;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
            color: AppTheme.panel,
          ),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: s.online ? AppTheme.signalBuy : AppTheme.signalSell,
              ),
              const SizedBox(width: 8),
              Text(
                s.online ? 'API ONLINE' : 'API OFFLINE',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _AuthBadge(user: s.currentUser),
        const SizedBox(width: 12),
        Text(
          'SYMBOL  ${s.selectedSymbol}',
          style: const TextStyle(
            color: AppTheme.gold,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 13,
          ),
        ),
        if (item?.is24h == true) ...[
          const SizedBox(width: 8),
          const _TypeChip(label: '24/7', color: AppTheme.signalBuy),
        ],
        if ((item?.type ?? '').isNotEmpty) ...[
          const SizedBox(width: 6),
          _TypeChip(
            label: item!.type!.toUpperCase(),
            color: item.isCrypto
                ? const Color(0xFFF7931A)
                : item.isForex
                    ? AppTheme.gold
                    : AppTheme.textMuted,
          ),
        ],
        if (s.isLive) ...[
          const SizedBox(width: 10),
          const _PulsingLiveChip(),
        ],
        const Spacer(),
        _CalendarButton(eventCount: s.upcomingEvents.length),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: s.loadingCandles ? null : () => s.refreshCandles(),
          icon: const Icon(Icons.refresh, color: AppTheme.goldDim, size: 18),
          label: const Text(
            'REFRESH',
            style: TextStyle(color: AppTheme.goldDim, fontSize: 11),
          ),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pushNamed(context, '/analysis'),
          icon: const Icon(Icons.analytics, size: 14),
          label: const Text(
            'FULL ANALYSIS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  AUTH BADGE
// ════════════════════════════════════════════════════════════════════════════

class _AuthBadge extends StatelessWidget {
  const _AuthBadge({required this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.textMuted.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.textMuted.withOpacity(0.25)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, color: AppTheme.textMuted, size: 12),
            SizedBox(width: 4),
            Text(
              'FREE',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    final isPro = user!.isPro;
    final color = isPro ? AppTheme.proAccent : AppTheme.freeAccent;
    final icon = isPro ? Icons.workspace_premium : Icons.person_outline;
    final label = isPro ? 'PRO' : 'FREE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          if (!isPro && user!.tradesRemaining < 10) ...[
            const SizedBox(width: 4),
            Text(
              '(${user!.tradesRemaining})',
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CALENDAR BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _CalendarButton extends StatelessWidget {
  const _CalendarButton({required this.eventCount});
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final hasEvents = eventCount > 0;
    return IconButton(
      tooltip: 'Economic Calendar ($eventCount events)',
      onPressed: () => _showCalendarDialog(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.event_busy,
            color: hasEvents ? AppTheme.gold : AppTheme.textMuted,
            size: 20,
          ),
          if (hasEvents)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.impactHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.oledBlack, width: 1.5),
                ),
                child: Text(
                  '$eventCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCalendarDialog(BuildContext context) {
    final events = context.read<MarketState>().upcomingEvents;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.goldDim, width: 1),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_busy, color: AppTheme.gold, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'ECONOMIC CALENDAR',
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (events.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No high-impact events in the next 7 days',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: events.length,
                      itemBuilder: (_, i) {
                        final e = events[i];
                        final isHigh = e.isHighImpact;
                        final impactColor = isHigh ? AppTheme.impactHigh : AppTheme.impactMedium;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.panelRaised,
                            borderRadius: BorderRadius.circular(10),
                            border: Border(
                              left: BorderSide(color: impactColor, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: impactColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isHigh ? 'HIGH' : 'MEDIUM',
                                      style: TextStyle(
                                        color: impactColor,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    e.country,
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    e.datetime,
                                    style: const TextStyle(
                                      color: AppTheme.gold,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                e.event,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (e.estimate.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Est: ${e.estimate}  Prev: ${e.prev}',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PULSING LIVE CHIP
// ════════════════════════════════════════════════════════════════════════════

class _PulsingLiveChip extends StatefulWidget {
  const _PulsingLiveChip();

  @override
  State<_PulsingLiveChip> createState() => _PulsingLiveChipState();
}

class _PulsingLiveChipState extends State<_PulsingLiveChip> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.signalBuy.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.signalBuy.withOpacity(0.35 * _fade.value),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.signalBuy.withOpacity(_fade.value),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'LIVE FEED',
              style: TextStyle(
                color: AppTheme.signalBuy.withOpacity(_fade.value),
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TYPE CHIP
// ════════════════════════════════════════════════════════════════════════════

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CHART SKELETON
// ════════════════════════════════════════════════════════════════════════════

class _ChartSkeleton extends StatefulWidget {
  const _ChartSkeleton({required this.height});
  final double height;

  @override
  State<_ChartSkeleton> createState() => _ChartSkeletonState();
}

class _ChartSkeletonState extends State<_ChartSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: 0.03, end: 0.12).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) => SizedBox(
        height: widget.height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(14, (i) {
                final h = 30.0 + (i % 4) * 22.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    width: 12,
                    height: h,
                    decoration: BoxDecoration(
                      color: AppTheme.textMuted.withOpacity(_shimmer.value + 0.04 * (i % 3)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Text(
              'LOADING CHART…',
              style: TextStyle(
                color: AppTheme.textMuted.withOpacity(_shimmer.value * 6),
                fontSize: 10,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  WATCHLIST PANE
// ════════════════════════════════════════════════════════════════════════════

class _WatchlistPane extends StatelessWidget {
  const _WatchlistPane({required this.compact});
  final bool compact;

  void _handleTileTap(BuildContext context, WatchlistItem w) {
    final state = context.read<MarketState>();
    state.selectSymbol(w.symbol);
    if (w.isCrypto || w.is24h) {
      Future.microtask(() => state.runQuantumScan());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: ListView(
        key: ValueKey(s.watchlist.length),
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'WATCHLIST',
              style: TextStyle(
                color: AppTheme.gold,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                fontSize: 11,
              ),
            ),
          ),
          ...s.watchlist.map((w) {
            final sel = w.symbol == s.selectedSymbol;
            final chipColor = w.isCrypto
                ? const Color(0xFFF7931A)
                : w.isForex
                    ? AppTheme.gold
                    : AppTheme.textMuted;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: sel ? AppTheme.panel : AppTheme.oledBlack,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => _handleTileTap(context, w),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel
                            ? (w.isCrypto ? const Color(0xFFF7931A) : AppTheme.gold).withOpacity(0.55)
                            : AppTheme.border,
                        width: sel ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              w.symbol,
                              style: TextStyle(
                                color: sel ? (w.isCrypto ? const Color(0xFFF7931A) : AppTheme.gold) : AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                fontSize: compact ? 13 : 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if ((w.type ?? '').isNotEmpty)
                              _TypeChip(
                                label: w.type!.toUpperCase(),
                                color: chipColor,
                              ),
                            if (w.is24h) ...[
                              const SizedBox(width: 4),
                              const _TypeChip(
                                label: '24/7',
                                color: AppTheme.signalBuy,
                              ),
                            ],
                            const Spacer(),
                            if (sel && s.isLive) ...[
                              const _TileLiveDot(),
                              const SizedBox(width: 6),
                            ],
                            if (w.changePct != null)
                              Text(
                                '${w.changePct! >= 0 ? "+" : ""}${w.changePct!.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: w.changePct! >= 0 ? AppTheme.signalBuy : AppTheme.signalSell,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        if (w.name != null && w.name!.isNotEmpty)
                          Text(
                            w.name!,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TileLiveDot extends StatefulWidget {
  const _TileLiveDot();

  @override
  State<_TileLiveDot> createState() => _TileLiveDotState();
}

class _TileLiveDotState extends State<_TileLiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.signalBuy.withOpacity(0.4 + 0.6 * _ctrl.value),
          boxShadow: [
            BoxShadow(
              color: AppTheme.signalBuy.withOpacity(0.3 * _ctrl.value),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SCAN & SIGNAL COLUMN
// ════════════════════════════════════════════════════════════════════════════

class _ScanAndSignalColumn extends StatelessWidget {
  const _ScanAndSignalColumn();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();
    final mi = s.lastAnalysis?.intelligence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold.withOpacity(0.12),
            foregroundColor: AppTheme.gold,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: const BorderSide(color: AppTheme.goldDim),
          ),
          onPressed: s.scanning
              ? null
              : () async {
                  await context.read<MarketState>().runQuantumScan();
                  if (context.mounted) {
                    await showInterstitialPlaceholder(context);
                  }
                },
          icon: s.scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
                )
              : const Icon(Icons.radar),
          label: Text(s.scanning ? 'SCANNING…' : 'QUANTUM SCAN'),
        ),
        if (s.isLive) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.signalBuy.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.signalBuy.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const _TileLiveDot(),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'LIVE AUTO-SCAN ACTIVE',
                    style: TextStyle(
                      color: AppTheme.signalBuy,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Text(
                  'GEN ${s.scanGeneration}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: GlowingSignalCard(
              signal: mi?.safetySignal ?? 'AWAITING SCAN',
              strength: mi?.signalStrength.toDouble() ?? 0,
              direction: mi?.direction ?? 'NEUTRAL',
              probability: mi?.probabilityBull ?? 50,
              intelligence: mi,
              tradePlan: mi?.tradePlan,
              newsItems: s.currentNews,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MOBILE TERMINAL
// ════════════════════════════════════════════════════════════════════════════

class MobileTerminal extends StatelessWidget {
  const MobileTerminal({super.key});

  void _handleTileTap(BuildContext context, WatchlistItem w) {
    final state = context.read<MarketState>();
    state.selectSymbol(w.symbol);
    if (w.isCrypto || w.is24h) {
      Future.microtask(() => state.runQuantumScan());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();
    final item = s.selectedItem;
    final mi = s.lastAnalysis?.intelligence;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppTheme.oledBlack,
          title: Row(
            children: [
              const Text(
                'NEXUS',
                style: TextStyle(
                  color: AppTheme.gold,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'v13.4',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              _AuthBadge(user: s.currentUser),
              if (s.isLive) ...[
                const SizedBox(width: 8),
                const _PulsingLiveChip(),
              ],
            ],
          ),
          actions: [
            _CalendarButton(eventCount: s.upcomingEvents.length),
            IconButton(
              tooltip: 'Refresh chart',
              onPressed: s.loadingCandles ? null : () => s.refreshCandles(),
              icon: const Icon(Icons.refresh, color: AppTheme.goldDim),
            ),
            IconButton(
              tooltip: 'Full quantum analysis',
              onPressed: () => Navigator.pushNamed(context, '/analysis'),
              icon: const Icon(Icons.analytics, color: AppTheme.gold),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: const _TopStatusBar(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final w = s.watchlist[i];
                final sel = w.symbol == s.selectedSymbol;
                final chipColor = w.isCrypto
                    ? const Color(0xFFF7931A)
                    : w.isForex
                        ? AppTheme.gold
                        : AppTheme.textMuted;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _handleTileTap(ctx, w),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? (w.isCrypto ? const Color(0xFFF7931A) : AppTheme.signalBuy).withOpacity(0.55)
                                : AppTheme.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sel ? Icons.show_chart : Icons.candlestick_chart,
                              color: sel ? AppTheme.signalBuy : AppTheme.textMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        w.symbol,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.1,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if ((w.type ?? '').isNotEmpty)
                                        _TypeChip(
                                          label: w.type!.toUpperCase(),
                                          color: chipColor,
                                        ),
                                      if (w.is24h) ...[
                                        const SizedBox(width: 4),
                                        const _TypeChip(
                                          label: '24/7',
                                          color: AppTheme.signalBuy,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (w.name != null && w.name!.isNotEmpty)
                                    Text(
                                      w.name!,
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            if (sel && s.isLive) ...[
                              const _TileLiveDot(),
                              const SizedBox(width: 8),
                            ],
                            if (w.changePct != null)
                              Text(
                                '${w.changePct! >= 0 ? "+" : ""}${w.changePct!.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: w.changePct! >= 0 ? AppTheme.signalBuy : AppTheme.signalSell,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: s.watchlist.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: AppTheme.panel,
                child: s.loadingCandles && s.candles.isEmpty
                    ? const _ChartSkeleton(height: 380)
                    : Stack(
                        children: [
                          NexusCandleChart(
                            data: s.candles,
                            liveTickNotifier: s.liveTickNotifier,
                            height: 380,
                            assetType: item?.type ?? '',
                            is24h: item?.is24h ?? false,
                            decimalPlaces: item?.type == 'forex' ? 5 : 2,
                          ),
                          if (s.lastAnalysis != null)
                            Positioned.fill(
                              child: AnalysisOverlay(
                                intelligence: s.lastAnalysis!.intelligence,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GlowingSignalCard(
              signal: mi?.safetySignal ?? 'AWAITING SCAN',
              strength: mi?.signalStrength.toDouble() ?? 0,
              direction: mi?.direction ?? 'NEUTRAL',
              probability: mi?.probabilityBull ?? 50,
              intelligence: mi,
              tradePlan: mi?.tradePlan,
              newsItems: s.currentNews,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: Column(
              children: [
                if (s.isLive) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.signalBuy.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.signalBuy.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const _TileLiveDot(),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'LIVE AUTO-SCAN ACTIVE',
                            style: TextStyle(
                              color: AppTheme.signalBuy,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Text(
                          'GEN ${s.scanGeneration}',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.signalBuy.withOpacity(0.12),
                    foregroundColor: AppTheme.signalBuy,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(color: AppTheme.signalBuy),
                  ),
                  onPressed: s.scanning
                      ? null
                      : () async {
                          await context.read<MarketState>().runQuantumScan();
                          if (context.mounted) {
                            await showInterstitialPlaceholder(context);
                          }
                        },
                  icon: const Icon(Icons.radar),
                  label: Text(s.scanning ? 'SCANNING…' : 'QUANTUM SCAN'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pushNamed(context, '/analysis'),
                    icon: const Icon(Icons.analytics, size: 18),
                    label: const Text(
                      'FULL ANALYSIS →',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
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

// ════════════════════════════════════════════════════════════════════════════
//  HOME SHELL
// ════════════════════════════════════════════════════════════════════════════

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const double _kDesktopBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final desktop = c.maxWidth >= _kDesktopBreakpoint;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.02, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: desktop
                  ? const KeyedSubtree(
                      key: ValueKey('desk'),
                      child: DesktopDashboard())
                  : const KeyedSubtree(
                      key: ValueKey('mob'),
                      child: MobileTerminal()),
            );
          },
        ),
      ),
      bottomNavigationBar: const AdBannerPlaceholder(),
    );
  }
}