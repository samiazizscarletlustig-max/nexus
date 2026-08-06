// ============================================================================
//  NEXUS v11.3 — home_shell.dart
//  Responsive shell: DesktopDashboard (≥1100 px) / MobileTerminal (< 1100 px).
//
//  v11.3 additions over v11.2:
//  ─────────────────────────────────────────────────────────────────────────
//  WATCHLIST TILE — FULL OBJECT PROPAGATION
//  • Watchlist tiles now call selectSymbol(w.symbol) unchanged in signature,
//    but the tile's onTap callback is wired through _handleTileTap() which
//    first calls selectSymbol() then — if the asset is crypto / is24h —
//    calls runQuantumScan() immediately so the signal card refreshes for the
//    new asset without waiting for the first timer tick.
//  • Crypto tiles get a pulsing "● LIVE" micro-indicator on their right edge
//    when that symbol is the currently selected one, driven by MarketState.isLive.
//  • The desktop scan column shows a "LIVE AUTO-SCAN" indicator row when
//    isLive == true so the user knows the periodic feed is active.
//
//  LIVE STATUS IN STATUS BAR
//  • _TopStatusBar shows a pulsing green dot + "LIVE FEED" label when
//    MarketState.isLive is true (crypto selected with timer running).
//
//  CHART SECTION
//  • NexusCandleChart receives assetType, is24h, and the correct decimal
//    places on every rebuild.  When candles is empty AND loadingCandles is
//    true a shimmer-style skeleton is shown instead of the permanent
//    "AWAITING CHART DATA" message, giving immediate visual feedback after
//    a symbol switch.
//  ─────────────────────────────────────────────────────────────────────────
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ads/ad_placeholders.dart';
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
                _TopStatusBar(),
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
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ColoredBox(
                                color: AppTheme.panel,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: s.loadingCandles && s.candles.isEmpty
                                      ? _ChartSkeleton(
                                          height: constraints.maxHeight
                                              .isFinite
                                              ? constraints.maxHeight
                                              : 420,
                                        )
                                      : NexusCandleChart(
                                          data: s.candles,
                                          height: constraints.maxHeight
                                                  .isFinite
                                              ? constraints.maxHeight
                                              : 420,
                                          assetType:
                                              item?.type ?? '',
                                          is24h:
                                              item?.is24h ?? false,
                                          decimalPlaces:
                                              _dpForType(item?.type),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 320,
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
//  TOP STATUS BAR  — v11.3: live-feed indicator
// ════════════════════════════════════════════════════════════════════════════

class _TopStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s    = context.watch<MarketState>();
    final item = s.selectedItem;

    return Row(
      children: [
        // ── API online pill ─────────────────────────────────────────────────
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
                color: s.online
                    ? AppTheme.signalBuy
                    : AppTheme.signalSell,
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

        // ── Symbol label ────────────────────────────────────────────────────
        Text(
          'SYMBOL  ${s.selectedSymbol}',
          style: const TextStyle(
            color: AppTheme.gold,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 13,
          ),
        ),

        // ── Type chips ──────────────────────────────────────────────────────
        if (item?.is24h == true) ...[
          const SizedBox(width: 8),
          _TypeChip(label: '24/7', color: AppTheme.signalBuy),
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

        // ── v11.3: pulsing LIVE FEED indicator ──────────────────────────────
        if (s.isLive) ...[
          const SizedBox(width: 10),
          const _PulsingLiveChip(),
        ],

        const Spacer(),
        TextButton.icon(
          onPressed:
              s.loadingCandles ? null : () => s.refreshCandles(),
          icon: const Icon(Icons.refresh,
              color: AppTheme.goldDim, size: 18),
          label: const Text(
            'REFRESH CHART',
            style: TextStyle(color: AppTheme.goldDim, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PULSING LIVE CHIP  — v11.3
// ════════════════════════════════════════════════════════════════════════════

class _PulsingLiveChip extends StatefulWidget {
  const _PulsingLiveChip();

  @override
  State<_PulsingLiveChip> createState() => _PulsingLiveChipState();
}

class _PulsingLiveChipState extends State<_PulsingLiveChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.45, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
              width:  5,
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
//  TYPE CHIP  (reused throughout)
// ════════════════════════════════════════════════════════════════════════════

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(3),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:       color,
          fontSize:    8,
          fontWeight:  FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CHART SKELETON  — shown while candles is empty AND loadingCandles == true
// ════════════════════════════════════════════════════════════════════════════

class _ChartSkeleton extends StatefulWidget {
  const _ChartSkeleton({required this.height});
  final double height;

  @override
  State<_ChartSkeleton> createState() => _ChartSkeletonState();
}

class _ChartSkeletonState extends State<_ChartSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: 0.03, end: 0.12)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
            // Fake candle bars
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
                      color: AppTheme.textMuted
                          .withOpacity(_shimmer.value + 0.04 * (i % 3)),
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
//  WATCHLIST PANE  — v11.3: full-object tap + live indicator on tile
// ════════════════════════════════════════════════════════════════════════════

class _WatchlistPane extends StatelessWidget {
  const _WatchlistPane({required this.compact});
  final bool compact;

  // ── v11.3: called on tile tap ─────────────────────────────────────────────
  void _handleTileTap(BuildContext context, WatchlistItem w) {
    final state = context.read<MarketState>();
    // selectSymbol() performs a deep flush + starts the live timer if crypto.
    state.selectSymbol(w.symbol);
    // For crypto assets kick off an immediate quantum scan so the signal card
    // populates right away instead of waiting for the first timer tick.
    if (w.isCrypto || w.is24h) {
      Future.microtask(() => state.runQuantumScan());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MarketState>();

    return AnimatedSwitcher(
      duration:      const Duration(milliseconds: 320),
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
                color:       AppTheme.gold,
                fontWeight:  FontWeight.w900,
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
                color:        sel ? AppTheme.panel : AppTheme.oledBlack,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap:        () => _handleTileTap(context, w),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve:    Curves.easeOutCubic,
                    padding:  const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel
                            ? (w.isCrypto
                                ? const Color(0xFFF7931A)
                                : AppTheme.gold)
                                .withOpacity(0.55)
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
                                color: sel
                                    ? (w.isCrypto
                                        ? const Color(0xFFF7931A)
                                        : AppTheme.gold)
                                    : AppTheme.textPrimary,
                                fontWeight:  FontWeight.w800,
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
                              _TypeChip(
                                label: '24/7',
                                color: AppTheme.signalBuy,
                              ),
                            ],
                            const Spacer(),
                            // v11.3: pulsing live dot on selected crypto tile
                            if (sel && s.isLive) ...[
                              const _TileLiveDot(),
                              const SizedBox(width: 6),
                            ],
                            if (w.changePct != null)
                              Text(
                                '${w.changePct! >= 0 ? "+" : ""}${w.changePct!.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: w.changePct! >= 0
                                      ? AppTheme.signalBuy
                                      : AppTheme.signalSell,
                                  fontSize:   11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        if (w.name != null)
                          Text(
                            w.name!,
                            style: const TextStyle(
                              color:    AppTheme.textMuted,
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

// ─── Tiny live dot shown on the selected crypto tile ─────────────────────────

class _TileLiveDot extends StatefulWidget {
  const _TileLiveDot();

  @override
  State<_TileLiveDot> createState() => _TileLiveDotState();
}

class _TileLiveDotState extends State<_TileLiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
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
        width:  7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.signalBuy.withOpacity(
            0.4 + 0.6 * _ctrl.value,
          ),
          boxShadow: [
            BoxShadow(
              color:       AppTheme.signalBuy.withOpacity(0.3 * _ctrl.value),
              blurRadius:  4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SCAN & SIGNAL COLUMN  — v11.3: shows LIVE AUTO-SCAN row when isLive
// ════════════════════════════════════════════════════════════════════════════

class _ScanAndSignalColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s    = context.watch<MarketState>();
    final mi   = s.lastAnalysis?.intelligence;
    final sig  = mi?.safetySignal  ?? '—';
    final str  = mi?.signalStrength.toDouble() ?? 0;
    final dir  = mi?.direction      ?? '';
    final prob = mi?.probabilityBull ?? 50;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Manual scan button ────────────────────────────────────────────
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold.withOpacity(0.12),
            foregroundColor: AppTheme.gold,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.gold),
                )
              : const Icon(Icons.radar),
          label:
              Text(s.scanning ? 'SCANNING…' : 'QUANTUM SCAN'),
        ),

        // ── v11.3: live auto-scan status row ─────────────────────────────
        if (s.isLive) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:        AppTheme.signalBuy.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(
                color: AppTheme.signalBuy.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                const _TileLiveDot(),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'LIVE AUTO-SCAN ACTIVE',
                    style: TextStyle(
                      color:       AppTheme.signalBuy,
                      fontSize:    9,
                      fontWeight:  FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Text(
                  'GEN ${s.scanGeneration}',
                  style: const TextStyle(
                    color:    AppTheme.textMuted,
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
              signal:      sig,
              strength:    str,
              direction:   dir,
              probability: prob,
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MOBILE TERMINAL  — v11.3: full-object tap + live dot + chart skeleton
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
    final s    = context.watch<MarketState>();
    final item = s.selectedItem;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned:          true,
          backgroundColor: AppTheme.oledBlack,
          title: Row(
            children: [
              const Text('NEXUS · QUANTUM'),
              if (s.isLive) ...[
                const SizedBox(width: 10),
                const _PulsingLiveChip(),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip:   'Refresh chart',
              onPressed: s.loadingCandles
                  ? null
                  : () => s.refreshCandles(),
              icon: const Icon(Icons.refresh,
                  color: AppTheme.goldDim),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _TopStatusBar(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final w   = s.watchlist[i];
                final sel = w.symbol == s.selectedSymbol;
                final chipColor = w.isCrypto
                    ? const Color(0xFFF7931A)
                    : w.isForex
                        ? AppTheme.gold
                        : AppTheme.textMuted;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color:        AppTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap:        () => _handleTileTap(ctx, w),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve:    Curves.easeOutCubic,
                        padding:  const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? (w.isCrypto
                                    ? const Color(0xFFF7931A)
                                    : AppTheme.signalBuy)
                                    .withOpacity(0.55)
                                : AppTheme.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sel
                                  ? Icons.show_chart
                                  : Icons.candlestick_chart,
                              color: sel
                                  ? AppTheme.signalBuy
                                  : AppTheme.textMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        w.symbol,
                                        style: const TextStyle(
                                          fontWeight:  FontWeight.w800,
                                          letterSpacing: 1.1,
                                          color:       AppTheme.textPrimary,
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
                                        _TypeChip(
                                          label: '24/7',
                                          color: AppTheme.signalBuy,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (w.name != null)
                                    Text(w.name!,
                                        style: const TextStyle(
                                            color:    AppTheme.textMuted,
                                            fontSize: 12)),
                                ],
                              ),
                            ),
                            // v11.3: live dot on selected crypto tile
                            if (sel && s.isLive) ...[
                              const _TileLiveDot(),
                              const SizedBox(width: 8),
                            ],
                            if (w.changePct != null)
                              Text(
                                '${w.changePct! >= 0 ? "+" : ""}${w.changePct!.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: w.changePct! >= 0
                                      ? AppTheme.signalBuy
                                      : AppTheme.signalSell,
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
        // ── Chart or skeleton ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: AppTheme.panel,
                child: s.loadingCandles && s.candles.isEmpty
                    ? const _ChartSkeleton(height: 380)
                    : NexusCandleChart(
                        data:          s.candles,
                        height:        380,
                        assetType:     item?.type  ?? '',
                        is24h:         item?.is24h ?? false,
                        decimalPlaces:
                            item?.type == 'forex' ? 5 : 2,
                      ),
              ),
            ),
          ),
        ),
        // ── Signal card ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Builder(builder: (context) {
              final mi = s.lastAnalysis?.intelligence;
              return GlowingSignalCard(
                signal:      mi?.safetySignal ?? 'AWAITING SCAN',
                strength:    mi?.signalStrength.toDouble() ?? 0,
                direction:   mi?.direction ?? '',
                probability: mi?.probabilityBull ?? 50,
              );
            }),
          ),
        ),
        // ── Scan button ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: Column(
              children: [
                if (s.isLive) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:        AppTheme.signalBuy.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border:       Border.all(
                        color: AppTheme.signalBuy.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const _TileLiveDot(),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'LIVE AUTO-SCAN ACTIVE',
                            style: TextStyle(
                              color:      AppTheme.signalBuy,
                              fontSize:   9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Text(
                          'GEN ${s.scanGeneration}',
                          style: const TextStyle(
                            color:    AppTheme.textMuted,
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
                    backgroundColor:
                        AppTheme.signalBuy.withOpacity(0.12),
                    foregroundColor: AppTheme.signalBuy,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(
                        color: AppTheme.signalBuy),
                  ),
                  onPressed: s.scanning
                      ? null
                      : () async {
                          await context
                              .read<MarketState>()
                              .runQuantumScan();
                          if (context.mounted) {
                            await showInterstitialPlaceholder(
                                context);
                          }
                        },
                  icon: const Icon(Icons.radar),
                  label: Text(
                      s.scanning ? 'SCANNING…' : 'QUANTUM SCAN'),
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
//  HOME SHELL  (unchanged routing logic)
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
              duration:      const Duration(milliseconds: 420),
              switchInCurve:  Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.02, 0),
                    end:   Offset.zero,
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