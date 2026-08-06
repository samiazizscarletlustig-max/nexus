// ============================================================================
//  NEXUS v13.0 — trading_screen.dart
//  Ultra-premium institutional trading terminal.
//
//  v13.0 additions over v11.3:
//  ─────────────────────────────────────────────────────────────────────────
//  • liveTickNotifier: state.liveTickNotifier wired to NexusCandleChart
//  • _NewsSection         — enriched cards: imageUrl, sentimentLabel,
//                           impactPercentage, sourceLogoUrl
//  • _VolatilitySection   — BB, Keltner, ATR, Supertrend, VWAP full detail
//  • _PivotPointsSection  — all 12 pivot levels (PP/R1-3/S1-3/FR1-3/FS1-3)
//  • Version bumped to QUANTUM v13.0 in top bar
//  All Gold/XAUUSD rendering logic unchanged.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/market_models.dart';
import '../providers/market_state.dart';
import '../theme/app_theme.dart';
import '../widgets/nexus_candle_chart.dart';
import '../widgets/glowing_signal_card.dart';
import '../ads/ad_placeholders.dart';

// ════════════════════════════════════════════════════════════════════════════
//  ROOT SCREEN
// ════════════════════════════════════════════════════════════════════════════

class TradingScreen extends StatefulWidget {
  const TradingScreen({super.key});

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketState>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.oledBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const _WatchlistBar(),   // ← asset selector strip (v11.3)
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    context.read<MarketState>().refreshCandles(),
                color:           AppTheme.gold,
                backgroundColor: AppTheme.panel,
                child: const SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MarketOverview(),
                      _ChartSection(),
                      _LiveFeedBanner(),
                      _SignalSection(),
                      _TradePlanSection(),
                      _QuantumMetricsSection(),
                      _CryptoMetricsCard(),
                      _ForexMetricsCard(),
                      _MomentumSection(),
                      _VolatilitySection(),       // v13.0 NEW
                      _SmartMoneySection(),
                      _PivotPointsSection(),      // v13.0 NEW
                      _MultiTimeframeSection(),
                      _SessionRiskSection(),
                      _ExplanationsSection(),
                      _NewsSection(),             // v13.0 NEW
                      SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            const AdBannerPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Text(
            'NEXUS',
            style: TextStyle(
              color:       AppTheme.gold,
              fontWeight:  FontWeight.w900,
              fontSize:    20,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'QUANTUM v13.0',
            style: TextStyle(
              color:       AppTheme.textMuted,
              fontWeight:  FontWeight.w400,
              fontSize:    10,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          Consumer<MarketState>(
            builder: (context, state, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // v11.3: live feed indicator in top bar
                  if (state.isLive) ...[
                    const _LivePulse(),
                    const SizedBox(width: 8),
                  ],
                  _StatusPill(online: state.online),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Live pulse dot (top bar) ─────────────────────────────────────────────

class _LivePulse extends StatefulWidget {
  const _LivePulse();

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color:        AppTheme.signalBuy.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
          border:       Border.all(
            color: AppTheme.signalBuy.withOpacity(0.3 + 0.3 * _ctrl.value),
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
                color: AppTheme.signalBuy.withOpacity(
                    0.5 + 0.5 * _ctrl.value),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                color: AppTheme.signalBuy.withOpacity(
                    0.6 + 0.4 * _ctrl.value),
                fontSize:    8,
                fontWeight:  FontWeight.bold,
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
//  WATCHLIST BAR — horizontal asset selector strip
//  Rendered between the top bar and the scrollable content.
//  Each chip shows: emoji · symbol · price (or ---) · change %.
//  The active chip is highlighted with a gold border + subtle background.
//  Calls state.selectSymbol() which performs a Deep Flush before loading the
//  new asset, so zero stale data bleeds through.
// ════════════════════════════════════════════════════════════════════════════

class _WatchlistBar extends StatelessWidget {
  const _WatchlistBar();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        // Show a thin shimmer-style placeholder while watchlist is loading.
        if (state.watchlist.isEmpty) {
          return Container(
            height: 52,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.gold,
                ),
              ),
            ),
          );
        }

        return Container(
          height: 52,
          decoration: const BoxDecoration(
            color: AppTheme.panel,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: ListView.separated(
            scrollDirection:   Axis.horizontal,
            padding:           const EdgeInsets.symmetric(horizontal: 12),
            itemCount:         state.watchlist.length,
            separatorBuilder:  (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final item       = state.watchlist[index];
              final isSelected = item.symbol == state.selectedSymbol;
              return _WatchlistChip(
                item:       item,
                isSelected: isSelected,
                onTap: () {
                  if (!isSelected) {
                    context.read<MarketState>().selectSymbol(item.symbol);
                  }
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ─── Single watchlist chip ────────────────────────────────────────────────

class _WatchlistChip extends StatelessWidget {
  const _WatchlistChip({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final WatchlistItem item;
  final bool          isSelected;
  final VoidCallback  onTap;

  // Resolve the accent colour for each asset type (mirrors AppTheme palette).
  Color get _typeColor {
    if (item.isCrypto)          return const Color(0xFFF7931A);   // BTC orange
    if (item.isForex)           return AppTheme.gold;
    if (item.symbol == 'XAUUSD') return AppTheme.gold;
    return AppTheme.textMuted;
  }

  String _fmtPrice(double? p, String? type) {
    if (p == null) return '---';
    if (type == 'forex')  return p.toStringAsFixed(4);
    if (type == 'crypto' || type == 'cryptocurrency') {
      if (p >= 10000) return '\$${(p / 1000).toStringAsFixed(1)}k';
      return '\$${p.toStringAsFixed(0)}';
    }
    return p.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final accent  = _typeColor;
    final chg     = item.changePct;
    final chgUp   = chg != null && chg >= 0;
    final chgStr  = chg == null
        ? ''
        : '${chgUp ? "+" : ""}${chg.toStringAsFixed(2)}%';
    final chgColor = chgUp ? AppTheme.signalBuy : AppTheme.signalSell;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding:   const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withOpacity(0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? accent.withOpacity(0.60)
                : AppTheme.border,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji icon
            if ((item.emoji ?? '').isNotEmpty) ...[
              Text(
                item.emoji!,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 5),
            ],

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Symbol label
                Text(
                  item.symbol,
                  style: TextStyle(
                    color:         isSelected ? accent : AppTheme.textPrimary,
                    fontSize:      11,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 1),
                // Price + change on one compact row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmtPrice(item.price, item.type),
                      style: TextStyle(
                        color:      isSelected ? accent.withOpacity(0.85) : AppTheme.textMuted,
                        fontSize:   9,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (chgStr.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        chgStr,
                        style: TextStyle(
                          color:     chgColor,
                          fontSize:  8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            // Active indicator dot
            if (isSelected) ...[
              const SizedBox(width: 6),
              Container(
                width:  4,
                height: 4,
                decoration: BoxDecoration(
                  color:  accent,
                  shape:  BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Status pill ─────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = online ? AppTheme.signalBuy : AppTheme.signalSell;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border:       Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'QUANTUM LIVE' : 'OFFLINE',
            style: TextStyle(
              color: c, fontSize: 10, fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MARKET OVERVIEW  (price + change)
// ════════════════════════════════════════════════════════════════════════════

class _MarketOverview extends StatelessWidget {
  const _MarketOverview();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final selected = state.watchlist.firstWhere(
          (e) => e.symbol == state.selectedSymbol,
          orElse: () => state.watchlist.isNotEmpty
              ? state.watchlist.first
              : const WatchlistItem(symbol: '---'),
        );
        final chg  = selected.changePct ?? 0;
        final isUp = chg >= 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${selected.emoji ?? ''} ${selected.name ?? selected.symbol}',
                        style: const TextStyle(
                          color:      AppTheme.textPrimary,
                          fontSize:   22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (selected.is24h) ...[
                        const SizedBox(width: 8),
                        _AssetTypeBadge(
                          label: '24/7',
                          color: AppTheme.signalBuy,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        selected.symbol,
                        style: const TextStyle(
                          color:    AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if ((selected.type ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _AssetTypeBadge(
                          label: (selected.type ?? '').toUpperCase(),
                          color: selected.isCrypto
                              ? const Color(0xFFF7931A)
                              : selected.isForex
                                  ? AppTheme.gold
                                  : AppTheme.textMuted,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              // v11.3: AnimatedSwitcher on price so live ticks animate
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSwitcher(
                    duration:      const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOut,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.3),
                          end:   Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _fmtPrice(selected.price, selected.type),
                      key: ValueKey(selected.price),
                      style: const TextStyle(
                        color:      AppTheme.gold,
                        fontSize:   26,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isUp ? "+" : ""}${chg.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: isUp
                          ? AppTheme.signalBuy
                          : AppTheme.signalSell,
                      fontSize:   13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmtPrice(double? p, String? type) {
    if (p == null) return '---';
    if (type == 'forex') return p.toStringAsFixed(5);
    if (type == 'crypto' || type == 'cryptocurrency') {
      if (p >= 10000) return p.toStringAsFixed(2);
      if (p >= 100)   return p.toStringAsFixed(2);
      if (p >= 1)     return p.toStringAsFixed(4);
      return p.toStringAsFixed(6);
    }
    if (p < 10) return p.toStringAsFixed(4);
    return p.toStringAsFixed(2);
  }
}

// ─── Asset type badge ─────────────────────────────────────────────────────

class _AssetTypeBadge extends StatelessWidget {
  const _AssetTypeBadge({required this.label, required this.color});
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
          fontSize:    9,
          fontWeight:  FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CHART SECTION  — v11.3: skeleton + smart decimal + live badge
// ════════════════════════════════════════════════════════════════════════════

class _ChartSection extends StatelessWidget {
  const _ChartSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final selected = state.watchlist.firstWhere(
          (e) => e.symbol == state.selectedSymbol,
          orElse: () => const WatchlistItem(symbol: '---'),
        );

        // v11.3: interval label adapts to asset type
        final intervalLabel = (selected.isCrypto || selected.isForex)
            ? '5M'
            : '15M';

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              _SectionHeader(
                icon:  Icons.candlestick_chart_rounded,
                label: 'QUANTUM CHART',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected.is24h)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _AssetTypeBadge(
                          label: '24/7',
                          color: AppTheme.signalBuy,
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:        Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        intervalLabel,
                        style: const TextStyle(
                          color:    AppTheme.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // v11.3: skeleton while loading; chart when ready
              AnimatedSwitcher(
                duration:       const Duration(milliseconds: 360),
                switchInCurve:  Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: state.loadingCandles && state.candles.isEmpty
                    ? const _ChartLoadingSkeleton(height: 300)
                    : state.candles.isEmpty
                        ? _ChartUnavailable(
                            onRetry: () => state.refreshCandles(),
                          )
                        : NexusCandleChart(
                            key: ValueKey(state.selectedSymbol),
                            data:             state.candles,
                            liveTickNotifier: state.liveTickNotifier,
                            height:           300,
                            assetType:        selected.type ?? '',
                            is24h:            selected.is24h,
                            decimalPlaces:    _dpForAsset(
                              selected.type,
                              selected.price,
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// v11.3: resolve decimal places from asset type AND price magnitude
  int _dpForAsset(String? type, double? price) {
    if (type == 'forex') return 5;
    if (type == 'crypto' || type == 'cryptocurrency') {
      // BTC-scale prices → 2dp; mid-cap → 4dp; micro → 6dp
      if (price != null) {
        if (price >= 1000) return 2;
        if (price >= 1)    return 4;
        return 6;
      }
      return 2;
    }
    return 2;
  }
}

// ─── Chart loading skeleton ───────────────────────────────────────────────

class _ChartLoadingSkeleton extends StatefulWidget {
  const _ChartLoadingSkeleton({required this.height});
  final double height;

  @override
  State<_ChartLoadingSkeleton> createState() => _ChartLoadingSkeletonState();
}

class _ChartLoadingSkeletonState extends State<_ChartLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: 0.03, end: 0.14)
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(18, (i) {
                final heights = [38.0, 52.0, 44.0, 70.0, 58.0, 34.0,
                                 62.0, 46.0, 80.0, 56.0, 42.0, 66.0,
                                 50.0, 74.0, 40.0, 60.0, 54.0, 48.0];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width:  10,
                    height: heights[i % heights.length],
                    decoration: BoxDecoration(
                      color: (i % 3 == 0
                              ? AppTheme.signalSell
                              : AppTheme.signalBuy)
                          .withOpacity(_shimmer.value + 0.02 * (i % 4)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Text(
              'LOADING CHART DATA…',
              style: TextStyle(
                color:       AppTheme.textMuted
                    .withOpacity(0.3 + _shimmer.value * 4),
                fontSize:    10,
                letterSpacing: 3,
                fontWeight:  FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chart unavailable (after load failure) ───────────────────────────────

class _ChartUnavailable extends StatelessWidget {
  const _ChartUnavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.candlestick_chart_rounded,
                color: AppTheme.textMuted, size: 32),
            const SizedBox(height: 12),
            const Text(
              'CHART DATA UNAVAILABLE',
              style: TextStyle(
                color:       AppTheme.textMuted,
                fontSize:    11,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color:       AppTheme.gold,
                  fontSize:    10,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LIVE FEED BANNER  — v11.3: shown only when state.isLive == true
// ════════════════════════════════════════════════════════════════════════════

class _LiveFeedBanner extends StatelessWidget {
  const _LiveFeedBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        if (!state.isLive) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:        AppTheme.signalBuy.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(
                color: AppTheme.signalBuy.withOpacity(0.18),
              ),
            ),
            child: Row(
              children: [
                const _LivePulse(),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'LIVE AUTO-SCAN — Candles refresh every 8s  ·  '
                    'Quantum scan every 30s',
                    style: TextStyle(
                      color:    AppTheme.signalBuy,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  'GEN ${state.scanGeneration}',
                  style: const TextStyle(
                    color:      AppTheme.textMuted,
                    fontSize:   9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SIGNAL CARD  — v11.3: AUTO-UPDATED watermark when isLive
// ════════════════════════════════════════════════════════════════════════════

class _SignalSection extends StatelessWidget {
  const _SignalSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        if (state.scanning) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(
                    color: AppTheme.gold, strokeWidth: 1.5),
                  SizedBox(height: 16),
                  Text(
                    'QUANTUM ENGINE RUNNING…',
                    style: TextStyle(
                      color:       AppTheme.textMuted,
                      fontSize:    10,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (state.lastAnalysis == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => state.runQuantumScan(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'RUN QUANTUM ANALYSIS',
                  style: TextStyle(
                    fontWeight:  FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          );
        }

        final mi = state.lastAnalysis!.intelligence;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              // v11.3: fade between signals on live update
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: GlowingSignalCard(
                  key:         ValueKey(
                    '${mi.safetySignal}_${mi.signalStrength}_${state.scanGeneration}',
                  ),
                  signal:      mi.safetySignal,
                  strength:    mi.signalStrength.toDouble(),
                  direction:   mi.direction,
                  probability: mi.probabilityBull,
                ),
              ),
            ),
            // v11.3: auto-updated watermark
            if (state.isLive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.update,
                        color: AppTheme.signalBuy, size: 10),
                    const SizedBox(width: 4),
                    Text(
                      'AUTO-UPDATED  ·  GEN ${state.scanGeneration}',
                      style: const TextStyle(
                        color:       AppTheme.signalBuy,
                        fontSize:    8,
                        letterSpacing: 1.2,
                        fontWeight:  FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TRADE PLAN
// ════════════════════════════════════════════════════════════════════════════

class _TradePlanSection extends StatelessWidget {
  const _TradePlanSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final scan = state.lastAnalysis;
        if (scan == null) return const SizedBox.shrink();
        final mi = scan.intelligence;
        final tp = mi.tradePlan;
        if (!tp.valid) return const SizedBox.shrink();

        final isLong = tp.direction.toUpperCase().contains('BULL') ||
            tp.direction.toUpperCase().contains('BUY');

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon:  Icons.account_balance,
                label: 'INSTITUTIONAL TRADE PLAN',
              ),
              const SizedBox(height: 4),

              Row(
                children: [
                  _PriceLevel(
                    label: 'ENTRY',
                    value: tp.entry,
                    color: Colors.white,
                    assetType: mi.assetType,
                  ),
                  _vDivider(),
                  _PriceLevel(
                    label: 'STOP',
                    value: tp.sl,
                    color: AppTheme.signalSell,
                    assetType: mi.assetType,
                  ),
                  _vDivider(),
                  _PriceLevel(
                    label: 'TP 1',
                    value: tp.tp1,
                    color: AppTheme.signalBuy,
                    assetType: mi.assetType,
                  ),
                  _vDivider(),
                  _PriceLevel(
                    label: 'TP 2',
                    value: tp.tp2,
                    color: AppTheme.signalBuy.withOpacity(0.7),
                    assetType: mi.assetType,
                  ),
                  _vDivider(),
                  _PriceLevel(
                    label: 'TP 3',
                    value: tp.tp3,
                    color: AppTheme.gold,
                    assetType: mi.assetType,
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatChip(
                    label: 'RR',
                    value: '1:${tp.rr1.toStringAsFixed(1)}',
                  ),
                  _StatChip(
                    label: 'CONF',
                    value: '${tp.confidence.toStringAsFixed(0)}%',
                  ),
                  _StatChip(label: 'QUALITY', value: tp.quality),
                  _StatChip(
                    label:      'NEWS RISK',
                    value:      tp.newsRisk,
                    valueColor: tp.newsRisk == 'HIGH'
                        ? AppTheme.signalSell
                        : AppTheme.signalBuy,
                  ),
                ],
              ),

              if (tp.reasoning.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ExplanationBox(
                  label:       'TRADE REASONING',
                  text:        tp.reasoning,
                  accentColor: isLong
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
              ],
              if (tp.invalidation.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ExplanationBox(
                  label:       'INVALIDATION',
                  text:        tp.invalidation,
                  accentColor: AppTheme.signalSell.withOpacity(0.6),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _vDivider() => Container(
        width:  1,
        height: 40,
        color:  AppTheme.border,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  QUANTUM METRICS
// ════════════════════════════════════════════════════════════════════════════

class _QuantumMetricsSection extends StatelessWidget {
  const _QuantumMetricsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const _SectionHeader(
                icon:  Icons.memory_rounded,
                label: 'QUANTUM ENGINE',
              ),
              const SizedBox(height: 4),
              _Row2Col(
                left: _DetailRow(
                  'Regime',
                  mi.regimeAdvanced,
                  _regimeColor(mi.regimeAdvanced),
                ),
                right: _DetailRow(
                  'Market State', mi.regime, AppTheme.gold),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Hurst Exp.',
                  mi.hurst.toStringAsFixed(3),
                  _hurstColor(mi.hurst),
                ),
                right: _DetailRow(
                  'Fractal Dim.',
                  mi.fractalDim.toStringAsFixed(3),
                  AppTheme.textPrimary,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Z-Score',
                  '${mi.zscore >= 0 ? "+" : ""}${mi.zscore.toStringAsFixed(2)}σ',
                  _zscoreColor(mi.zscore),
                ),
                right: _DetailRow(
                  'Z-Signal', mi.zscoreSignal, _zscoreColor(mi.zscore)),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Shannon Entropy',
                  mi.shannonEntropy.toStringAsFixed(3),
                  AppTheme.textPrimary,
                ),
                right: _DetailRow(
                  'Kaufman ER',
                  mi.kaufmanEr.toStringAsFixed(3),
                  AppTheme.textPrimary,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Realized Vol.',
                  '${(mi.realizedVol * 100).toStringAsFixed(2)}%',
                  AppTheme.textPrimary,
                ),
                right: _DetailRow(
                  'Vol Regime', mi.volRegime, _volRegimeColor(mi.volRegime)),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Kurtosis',
                  mi.kurtosis.toStringAsFixed(2),
                  AppTheme.textPrimary,
                ),
                right: _DetailRow(
                  'Skewness',
                  mi.skewness.toStringAsFixed(2),
                  AppTheme.textPrimary,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Tail Risk',
                  mi.tailRisk,
                  mi.tailRisk == 'NORMAL'
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
                right: _DetailRow(
                  'Stability Index',
                  '${mi.stabilityIndex}/100',
                  _stabilityColor(mi.stabilityIndex),
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Autocorr (lag-1)',
                  mi.autocorrLag1.toStringAsFixed(3),
                  AppTheme.textPrimary,
                ),
                right: _DetailRow(
                  'Probability Bull',
                  '${mi.probabilityBull.toStringAsFixed(1)}%',
                  _probColor(mi.probabilityBull),
                ),
              ),
              const Divider(color: AppTheme.border, height: 24),
              _Row2Col(
                left: _DetailRow(
                  'Kelly Fraction',
                  '${(mi.kellyFraction * 100).toStringAsFixed(1)}%',
                  AppTheme.gold,
                ),
                right: _DetailRow(
                  'ATR (14)',
                  mi.atr14.toStringAsFixed(4),
                  AppTheme.textPrimary,
                ),
              ),
              if (mi.kellyRecommendation.isNotEmpty)
                _ExplanationBox(
                  label:       'KELLY RECOMMENDATION',
                  text:        mi.kellyRecommendation,
                  accentColor: AppTheme.gold,
                ),
            ],
          ),
        );
      },
    );
  }

  Color _regimeColor(String r) {
    if (r.contains('BULL'))   return AppTheme.signalBuy;
    if (r.contains('BEAR'))   return AppTheme.signalSell;
    if (r.contains('CRISIS')) return AppTheme.signalSell;
    if (r.contains('TREND'))  return AppTheme.signalBuy;
    return AppTheme.textMuted;
  }

  Color _hurstColor(double h) {
    if (h > 0.6) return AppTheme.signalBuy;
    if (h < 0.4) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }

  Color _zscoreColor(double z) {
    if (z.abs() > 2) return AppTheme.signalSell;
    if (z.abs() > 1) return AppTheme.gold;
    return AppTheme.textPrimary;
  }

  Color _volRegimeColor(String v) {
    if (v.contains('HIGH') || v.contains('EXTREME')) return AppTheme.signalSell;
    if (v.contains('LOW'))  return AppTheme.signalBuy;
    return AppTheme.textMuted;
  }

  Color _stabilityColor(int s) {
    if (s >= 70) return AppTheme.signalBuy;
    if (s >= 40) return AppTheme.gold;
    return AppTheme.signalSell;
  }

  Color _probColor(double p) {
    if (p >= 65) return AppTheme.signalBuy;
    if (p <= 35) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CRYPTO METRICS CARD  — null-guarded: renders ONLY for crypto assets
// ════════════════════════════════════════════════════════════════════════════

class _CryptoMetricsCard extends StatelessWidget {
  const _CryptoMetricsCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        final cm = mi.cryptoMetrics;
        if (cm == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon:  Icons.currency_bitcoin,
                label: 'CRYPTO INTELLIGENCE',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:        AppTheme.signalBuy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border:       Border.all(
                      color: AppTheme.signalBuy.withOpacity(0.25),
                    ),
                  ),
                  child: const Text(
                    '24/7 MARKET',
                    style: TextStyle(
                      color:       AppTheme.signalBuy,
                      fontSize:    9,
                      fontWeight:  FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Session context banner
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        (cm.isWeekend
                          ? AppTheme.gold
                          : AppTheme.signalBuy)
                      .withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (cm.isWeekend
                            ? AppTheme.gold
                            : AppTheme.signalBuy)
                        .withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      cm.isWeekend
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      color: cm.isWeekend
                          ? AppTheme.gold
                          : AppTheme.signalBuy,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cm.sessionNote,
                        style: TextStyle(
                          color: cm.isWeekend
                              ? AppTheme.gold
                              : AppTheme.signalBuy,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              _Row2Col(
                left: _DetailRow(
                  '24h Change',
                  '${cm.change24hPct >= 0 ? "+" : ""}${cm.change24hPct.toStringAsFixed(2)}%',
                  cm.change24hPct >= 0
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
                right: _DetailRow(
                  'Weekend',
                  cm.isWeekend ? 'YES — thin liquidity' : 'NO',
                  cm.isWeekend ? AppTheme.gold : AppTheme.signalBuy,
                ),
              ),

              const Divider(color: AppTheme.border, height: 20),

              // Volume Delta
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'VOLUME DELTA ENGINE',
                  style: TextStyle(
                    color:       AppTheme.textMuted,
                    fontSize:    9,
                    fontWeight:  FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color:        _vdColor(cm.volumeDeltaSignal)
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _vdColor(cm.volumeDeltaSignal)
                          .withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    cm.volumeDeltaSignal.replaceAll('_', ' '),
                    style: TextStyle(
                      color:       _vdColor(cm.volumeDeltaSignal),
                      fontSize:    10,
                      fontWeight:  FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              _VolumeDeltaBar(
                buyVolume:  cm.buyVolume,
                sellVolume: cm.sellVolume,
              ),

              const SizedBox(height: 10),

              _Row2Col(
                left: _DetailRow(
                  'Buy Volume',
                  _fmtVolume(cm.buyVolume),
                  AppTheme.signalBuy,
                ),
                right: _DetailRow(
                  'Sell Volume',
                  _fmtVolume(cm.sellVolume),
                  AppTheme.signalSell,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Net Delta',
                  _fmtVolume(cm.volumeDelta),
                  cm.volumeDelta >= 0
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
                right: _DetailRow(
                  'Delta %',
                  '${cm.volumeDeltaPct >= 0 ? "+" : ""}${cm.volumeDeltaPct.toStringAsFixed(1)}%',
                  cm.volumeDeltaPct >= 0
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
              ),

              const Divider(color: AppTheme.border, height: 20),

              // CAVB
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'CRYPTO VOLATILITY BAND (CAVB ±2.5σ)',
                  style: TextStyle(
                    color:       AppTheme.textMuted,
                    fontSize:    9,
                    fontWeight:  FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color:        _cavbColor(cm.cavbSignal).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _cavbColor(cm.cavbSignal).withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    'CAVB ${cm.cavbSignal}',
                    style: TextStyle(
                      color:       _cavbColor(cm.cavbSignal),
                      fontSize:    10,
                      fontWeight:  FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              _Row2Col(
                left: _DetailRow(
                  'CAVB Position',
                  cm.cavbPosition.replaceAll('_', ' '),
                  _cavbPosColor(cm.cavbPosition),
                ),
                right: _DetailRow(
                  'Norm. BW / ATR',
                  cm.normalizedBandwidth.toStringAsFixed(2),
                  _cavbColor(cm.cavbSignal),
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'CAVB Upper',
                  _fmtCryptoPrice(cm.cavbUpper),
                  AppTheme.signalSell,
                ),
                right: _DetailRow(
                  'CAVB Lower',
                  _fmtCryptoPrice(cm.cavbLower),
                  AppTheme.signalBuy,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _vdColor(String s) {
    if (s.contains('BULL')) return AppTheme.signalBuy;
    if (s.contains('BEAR')) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }

  Color _cavbColor(String s) {
    if (s == 'SQUEEZE')   return AppTheme.gold;
    if (s == 'EXPANSION') return AppTheme.signalSell;
    return AppTheme.textMuted;
  }

  Color _cavbPosColor(String s) {
    if (s.contains('ABOVE'))      return AppTheme.signalSell;
    if (s.contains('BELOW'))      return AppTheme.signalBuy;
    if (s.contains('NEAR_UPPER')) return AppTheme.signalSell.withOpacity(0.7);
    if (s.contains('NEAR_LOWER')) return AppTheme.signalBuy.withOpacity(0.7);
    return AppTheme.textMuted;
  }

  String _fmtVolume(double v) {
    if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtCryptoPrice(double v) {
    if (v == 0)    return '---';
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1)    return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }
}

// ─── Volume Delta Bar ─────────────────────────────────────────────────────

class _VolumeDeltaBar extends StatelessWidget {
  const _VolumeDeltaBar(
      {required this.buyVolume, required this.sellVolume});
  final double buyVolume;
  final double sellVolume;

  @override
  Widget build(BuildContext context) {
    final total   = buyVolume + sellVolume;
    final buyPct  = total > 0
        ? (buyVolume / total * 100).clamp(0.0, 100.0)
        : 50.0;
    final sellPct = 100.0 - buyPct;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SELL  ${sellPct.toStringAsFixed(1)}%',
              style: const TextStyle(
                color:      AppTheme.signalSell,
                fontSize:   10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'VOLUME DELTA',
              style: TextStyle(
                color:       AppTheme.textMuted,
                fontSize:    9,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${buyPct.toStringAsFixed(1)}%  BUY',
              style: const TextStyle(
                color:      AppTheme.signalBuy,
                fontSize:   10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: sellPct.toInt().clamp(1, 99),
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
                  flex: buyPct.toInt().clamp(1, 99),
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

// ════════════════════════════════════════════════════════════════════════════
//  FOREX METRICS CARD  — null-guarded: renders ONLY for forex assets
// ════════════════════════════════════════════════════════════════════════════

class _ForexMetricsCard extends StatelessWidget {
  const _ForexMetricsCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        final fm = mi.forexMetrics;
        if (fm == null) return const SizedBox.shrink();

        final overlapColor =
            fm.isOverlapSession ? AppTheme.signalBuy : AppTheme.textMuted;

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon:  Icons.currency_exchange,
                label: 'FOREX INTELLIGENCE',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:        AppTheme.gold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border:       Border.all(
                        color: AppTheme.gold.withOpacity(0.25)),
                  ),
                  child: Text(
                    fm.isJpyPair ? 'JPY PAIR' : 'MAJOR FX',
                    style: const TextStyle(
                      color:       AppTheme.gold,
                      fontSize:    9,
                      fontWeight:  FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        overlapColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: overlapColor.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Icon(
                      fm.isOverlapSession
                          ? Icons.bolt_rounded
                          : Icons.schedule_outlined,
                      color: overlapColor,
                      size:  16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fm.sessionOverlap,
                            style: TextStyle(
                              color:      overlapColor,
                              fontSize:   12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          if (fm.isOverlapSession)
                            const Text(
                              'PEAK LIQUIDITY — highest-probability entry window',
                              style: TextStyle(
                                color:    AppTheme.textMuted,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (fm.isOverlapSession)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        AppTheme.signalBuy.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'OVERLAP',
                          style: TextStyle(
                            color:       AppTheme.signalBuy,
                            fontSize:    8,
                            fontWeight:  FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              _Row2Col(
                left:  _DetailRow('Pip Size',  fm.pipSize.toString(), AppTheme.gold),
                right: _DetailRow(
                  'Pair Type',
                  fm.isJpyPair ? 'JPY (2dp)' : 'Standard (4dp)',
                  AppTheme.textPrimary,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  '24h Change',
                  '${fm.change24hPct >= 0 ? "+" : ""}${fm.change24hPct.toStringAsFixed(4)}%',
                  fm.change24hPct >= 0
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
                right: _DetailRow(
                  'Session Status',
                  fm.isOverlapSession ? 'HIGH LIQUIDITY' : 'NORMAL',
                  fm.isOverlapSession
                      ? AppTheme.signalBuy
                      : AppTheme.textMuted,
                ),
              ),

              if (!fm.isOverlapSession) ...[
                const SizedBox(height: 8),
                _ExplanationBox(
                  label:       'SESSION NOTE',
                  text:        'Current session: ${fm.sessionOverlap}. '
                      'Wait for London-NY or Tokyo-London overlap '
                      'for peak liquidity.',
                  accentColor: AppTheme.textMuted,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MOMENTUM INDICATORS
// ════════════════════════════════════════════════════════════════════════════

class _MomentumSection extends StatelessWidget {
  const _MomentumSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const _SectionHeader(
                icon:  Icons.speed_rounded,
                label: 'MOMENTUM INDICATORS',
              ),
              const SizedBox(height: 4),
              _Row2Col(
                left:  _DetailRow('RSI (14)',     mi.rsi.toStringAsFixed(1),    _rsiColor(mi.rsi)),
                right: _DetailRow('RSI Signal',   mi.rsiSignal,                 _rsiColor(mi.rsi)),
              ),
              _Row2Col(
                left:  _DetailRow('EMA Alignment', mi.emaAlignment,             _emaColor(mi.emaAlignment)),
                right: _DetailRow('Supertrend',    mi.supertrendSignal,         _signalColor(mi.supertrendSignal)),
              ),
              _Row2Col(
                left:  _DetailRow('MACD Cross',    mi.macdCross,                _signalColor(mi.macdCross)),
                right: _DetailRow('MACD Hist',
                    mi.macdHist.toStringAsFixed(4),
                    mi.macdHist >= 0 ? AppTheme.signalBuy : AppTheme.signalSell),
              ),
              _Row2Col(
                left:  _DetailRow('Stoch %K',     mi.stochK.toStringAsFixed(1), _stochColor(mi.stochK)),
                right: _DetailRow('Stoch Signal', mi.stochSignal,               _signalColor(mi.stochSignal)),
              ),
              _Row2Col(
                left:  _DetailRow('ADX',          mi.adxValue.toStringAsFixed(1), _adxColor(mi.adxValue)),
                right: _DetailRow('ADX Signal',   mi.adxSignal,                   _adxColor(mi.adxValue)),
              ),
              _Row2Col(
                left:  _DetailRow('Williams %R',  mi.williamsR.toStringAsFixed(1), _williamsColor(mi.williamsR)),
                right: _DetailRow('%R Signal',    mi.williamsSignal,               _williamsColor(mi.williamsR)),
              ),
              _Row2Col(
                left:  _DetailRow('CCI',          mi.cciValue.toStringAsFixed(1), _cciColor(mi.cciValue)),
                right: _DetailRow('OBV Trend',    mi.obvTrend,                    _signalColor(mi.obvTrend)),
              ),
              _Row2Col(
                left:  _DetailRow('Ichimoku',     mi.ichimokuSignal,              _signalColor(mi.ichimokuSignal)),
                right: _DetailRow('VWAP Signal',  mi.vwapSignal,                  _signalColor(mi.vwapSignal)),
              ),
              _Row2Col(
                left:  _DetailRow('BB Position',  mi.bbPosition,                  AppTheme.textPrimary),
                right: _DetailRow('TTM Squeeze',  mi.ttmSqueezeLabel,
                    mi.ttmSqueezeActive ? AppTheme.gold : AppTheme.textMuted),
              ),
              const Divider(color: AppTheme.border, height: 24),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'DIVERGENCE ENGINE',
                  style: TextStyle(
                    color:       AppTheme.textMuted,
                    fontSize:    9,
                    fontWeight:  FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              _Row2Col(
                left:  _DetailRow('RSI Div.',    mi.rsiDivergence,   _divColor(mi.rsiDivergence)),
                right: _DetailRow('MACD Div.',   mi.macdDivergence,  _divColor(mi.macdDivergence)),
              ),
              _Row2Col(
                left:  _DetailRow('OBV Div.',    mi.obvDivergence,   _divColor(mi.obvDivergence)),
                right: _DetailRow('Master Div.', mi.divergenceSignal, _divColor(mi.divergenceSignal)),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _rsiColor(double v)      { if (v > 70) return AppTheme.signalSell; if (v < 30) return AppTheme.signalBuy; return Colors.white; }
  Color _stochColor(double v)    { if (v > 80) return AppTheme.signalSell; if (v < 20) return AppTheme.signalBuy; return Colors.white; }
  Color _adxColor(double v)      { if (v > 40) return AppTheme.signalBuy; if (v > 25) return AppTheme.gold; return AppTheme.textMuted; }
  Color _cciColor(double v)      { if (v > 100) return AppTheme.signalSell; if (v < -100) return AppTheme.signalBuy; return Colors.white; }
  Color _williamsColor(double v) { if (v > -20) return AppTheme.signalSell; if (v < -80) return AppTheme.signalBuy; return Colors.white; }
  Color _divColor(String s)      { if (s.contains('BULL')) return AppTheme.signalBuy; if (s.contains('BEAR')) return AppTheme.signalSell; return AppTheme.textMuted; }
  Color _emaColor(String s)      { if (s.contains('BULL')) return AppTheme.signalBuy; if (s.contains('BEAR')) return AppTheme.signalSell; return AppTheme.textMuted; }
  Color _signalColor(String s)   {
    final u = s.toUpperCase();
    if (u.contains('BULL') || u.contains('BUY')  || u.contains('ABOVE')) return AppTheme.signalBuy;
    if (u.contains('BEAR') || u.contains('SELL') || u.contains('BELOW')) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SMART MONEY / PRICE STRUCTURE
// ════════════════════════════════════════════════════════════════════════════

class _SmartMoneySection extends StatelessWidget {
  const _SmartMoneySection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon:  Icons.hub_rounded,
                label: 'SMART MONEY CONCEPTS',
              ),
              const SizedBox(height: 4),
              _Row2Col(
                left: _DetailRow('SMC Bias', mi.smcBias, _biasColor(mi.smcBias)),
                right: _DetailRow(
                  'Order Blocks',
                  '${mi.orderBlocks.length} active',
                  mi.orderBlocks.isNotEmpty
                      ? AppTheme.gold
                      : AppTheme.textMuted,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'FVG Count', '${mi.fairValueGaps.length}',
                  mi.fairValueGaps.isNotEmpty
                      ? AppTheme.gold
                      : AppTheme.textMuted,
                ),
                right: _DetailRow(
                  'Liq. Sweeps', '${mi.liquiditySweeps.length}',
                  mi.liquiditySweeps.isNotEmpty
                      ? AppTheme.gold
                      : AppTheme.textMuted,
                ),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Nearest Support',
                  _fmtPrice(mi.nearestSupport, mi.assetType),
                  AppTheme.signalBuy,
                ),
                right: _DetailRow(
                  'Nearest Resist.',
                  _fmtPrice(mi.nearestResist, mi.assetType),
                  AppTheme.signalSell,
                ),
              ),
              _Row2Col(
                left:  _DetailRow('SR Zone',       mi.srZone,  AppTheme.textPrimary),
                right: _DetailRow(
                  'Nearest Pivot',
                  mi.nearestPivotLevel.isNotEmpty ? mi.nearestPivotLevel : 'N/A',
                  AppTheme.textPrimary,
                ),
              ),
              const Divider(color: AppTheme.border, height: 24),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'FIBONACCI & ELLIOTT WAVE',
                  style: TextStyle(
                    color:       AppTheme.textMuted,
                    fontSize:    9,
                    fontWeight:  FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              _Row2Col(
                left:  _DetailRow('Fib Zone',     mi.fibZone,                    _fibColor(mi.fibZone)),
                right: _DetailRow('Fib Strength', mi.fibStrength.toStringAsFixed(1), AppTheme.gold),
              ),
              _Row2Col(
                left:  _DetailRow('Wave Position', mi.wavePosition,              AppTheme.textPrimary),
                right: _DetailRow('Wave Trend',    mi.waveTrend,                 _biasColor(mi.waveTrend)),
              ),
              if (mi.waveTarget != null)
                _Row2Col(
                  left: _DetailRow(
                    'Wave Target',
                    _fmtPrice(mi.waveTarget!, mi.assetType),
                    AppTheme.gold,
                  ),
                  right: _DetailRow(
                    'Wave Conf.',
                    '${mi.waveConfidence.toStringAsFixed(0)}%',
                    AppTheme.textPrimary,
                  ),
                ),
              const Divider(color: AppTheme.border, height: 24),
              _Row2Col(
                left: _DetailRow(
                  'Pattern', mi.candlePattern,
                  mi.candlePattern != 'NONE'
                      ? AppTheme.gold
                      : AppTheme.textMuted,
                ),
                right: _DetailRow(
                  'Pattern Dir.', mi.candleDirection, _biasColor(mi.candleDirection)),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _biasColor(String s) {
    final u = s.toUpperCase();
    if (u.contains('BULL') || u.contains('BUY'))  return AppTheme.signalBuy;
    if (u.contains('BEAR') || u.contains('SELL')) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }

  Color _fibColor(String s) {
    if (s.contains('SUPPORT'))    return AppTheme.signalBuy;
    if (s.contains('RESISTANCE')) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }

  String _fmtPrice(double v, String assetType) {
    if (v == 0) return 'N/A';
    if (assetType == 'forex') return v.toStringAsFixed(5);
    if (assetType == 'crypto' || assetType == 'cryptocurrency') {
      if (v >= 1000) return v.toStringAsFixed(2);
      if (v >= 1)    return v.toStringAsFixed(4);
      return v.toStringAsFixed(6);
    }
    return v.toStringAsFixed(2);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MULTI-TIMEFRAME
// ════════════════════════════════════════════════════════════════════════════

class _MultiTimeframeSection extends StatelessWidget {
  const _MultiTimeframeSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon:  Icons.layers_rounded,
                label: 'MULTI-TIMEFRAME CONFLUENCE',
              ),
              const SizedBox(height: 4),
              _Row2Col(
                left: _DetailRow(
                  'MTF Confluence',
                  mi.mtfConfluence,
                  mi.mtfConfluence.contains('STRONG BULL')
                      ? AppTheme.signalBuy
                      : mi.mtfConfluence.contains('STRONG BEAR')
                          ? AppTheme.signalSell
                          : AppTheme.gold,
                ),
                right: _DetailRow(
                  'Bull / Bear TFs',
                  '${mi.mtfBullCount} / ${mi.mtfBearCount}',
                  mi.mtfBullCount > mi.mtfBearCount
                      ? AppTheme.signalBuy
                      : AppTheme.signalSell,
                ),
              ),
              if (mi.mtfSignals.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...mi.mtfSignals.entries.map((entry) {
                  final tf  = entry.key;
                  final sig = entry.value is Map
                      ? (entry.value as Map)['signal']?.toString() ?? '---'
                      : '---';
                  return _DetailRow(
                    'TF $tf', sig,
                    sig.toUpperCase().contains('BULL')
                        ? AppTheme.signalBuy
                        : sig.toUpperCase().contains('BEAR')
                            ? AppTheme.signalSell
                            : AppTheme.textMuted,
                  );
                }),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Enable MTF in scan settings for full confluence data.',
                    style: TextStyle(
                      color:     AppTheme.textMuted,
                      fontSize:  11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SESSION & RISK
// ════════════════════════════════════════════════════════════════════════════

class _SessionRiskSection extends StatelessWidget {
  const _SessionRiskSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const _SectionHeader(
                icon:  Icons.schedule_rounded,
                label: 'SESSION & RISK',
              ),
              const SizedBox(height: 4),
              _Row2Col(
                left:  _DetailRow('Session',   mi.tradingSession,   AppTheme.gold),
                right: _DetailRow('Liquidity', mi.sessionLiquidity, _liqColor(mi.sessionLiquidity)),
              ),
              _Row2Col(
                left: _DetailRow(
                  'Macro Sentiment', mi.macroSentimentLabel, _macroColor(mi.macroSentimentLabel)),
                right: _DetailRow(
                  'Macro Score', '${mi.macroSentimentScore}/100', AppTheme.textPrimary),
              ),
              _Row2Col(
                left:  _DetailRow('Bull Hits', '${mi.macroBullHits}', AppTheme.signalBuy),
                right: _DetailRow('Bear Hits', '${mi.macroBearHits}', AppTheme.signalSell),
              ),
              if (mi.newsLockActive) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:        AppTheme.signalSell.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.signalSell.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppTheme.signalSell, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${mi.newsLockEvent}  —  ${mi.newsLockReason}',
                          style: const TextStyle(
                            color: AppTheme.signalSell, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (mi.sessionWarning.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ExplanationBox(
                  label:       'SESSION WARNING',
                  text:        mi.sessionWarning,
                  accentColor: AppTheme.gold,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _liqColor(String s) {
    if (s == 'HIGH')   return AppTheme.signalBuy;
    if (s == 'MEDIUM') return AppTheme.gold;
    return AppTheme.signalSell;
  }

  Color _macroColor(String s) {
    final u = s.toUpperCase();
    if (u.contains('BULL')) return AppTheme.signalBuy;
    if (u.contains('BEAR')) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  EXPLANATIONS
// ════════════════════════════════════════════════════════════════════════════

class _ExplanationsSection extends StatelessWidget {
  const _ExplanationsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        final blocks = <_ExpBlock>[
          if (mi.entryExplanation.isNotEmpty)
            _ExpBlock('ENTRY LOGIC',   mi.entryExplanation,   Icons.flag_rounded,      AppTheme.gold),
          if (mi.smcExplanation.isNotEmpty)
            _ExpBlock('SMART MONEY',   mi.smcExplanation,     Icons.hub_rounded,       AppTheme.signalBuy),
          if (mi.fibExplanation.isNotEmpty)
            _ExpBlock('FIBONACCI',     mi.fibExplanation,     Icons.show_chart,        AppTheme.gold),
          if (mi.candleExplanation.isNotEmpty)
            _ExpBlock('CANDLESTICK',   mi.candleExplanation,  Icons.bar_chart_rounded, AppTheme.textPrimary),
          if (mi.rsiExplanation.isNotEmpty)
            _ExpBlock('RSI',           mi.rsiExplanation,     Icons.speed_rounded,     _rsiExp(mi.rsi)),
          if (mi.atrExplanation.isNotEmpty)
            _ExpBlock('ATR / STOPS',   mi.atrExplanation,     Icons.adjust_rounded,    AppTheme.textMuted),
          if (mi.sessionExplanation.isNotEmpty)
            _ExpBlock('SESSION',       mi.sessionExplanation, Icons.schedule_rounded,  AppTheme.gold),
        ];

        if (blocks.isEmpty) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon:  Icons.auto_awesome,
                label: 'QUANTUM REASONING',
              ),
              const SizedBox(height: 8),
              ...blocks.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExplanationBox(
                    label:       b.label,
                    text:        b.text,
                    accentColor: b.color,
                    leadIcon:    b.icon,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _rsiExp(double rsi) {
    if (rsi > 70) return AppTheme.signalSell;
    if (rsi < 30) return AppTheme.signalBuy;
    return AppTheme.textMuted;
  }
}

class _ExpBlock {
  final String   label;
  final String   text;
  final IconData icon;
  final Color    color;
  const _ExpBlock(this.label, this.text, this.icon, this.color);
}

// ════════════════════════════════════════════════════════════════════════════
//  VOLATILITY — BB / Keltner / ATR / Supertrend / VWAP  (v13.0 NEW)
// ════════════════════════════════════════════════════════════════════════════

class _VolatilitySection extends StatelessWidget {
  const _VolatilitySection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon:  Icons.bar_chart_rounded,
                label: 'VOLATILITY FRAMEWORK',
              ),
              // ── Bollinger Bands ─────────────────────────────────────────
              const _SubHeader('BOLLINGER BANDS (20,2)'),
              _Row2Col(
                left:  _DetailRow('Upper',    _p(mi.bbUpper,  mi.assetType), AppTheme.signalSell),
                right: _DetailRow('Mid (SMA)', _p(mi.bbMid,   mi.assetType), Colors.white70),
              ),
              _Row2Col(
                left:  _DetailRow('Lower',    _p(mi.bbLower,  mi.assetType), AppTheme.signalBuy),
                right: _DetailRow('Width %',  mi.bbWidth.toStringAsFixed(3), AppTheme.textPrimary),
              ),
              _Row2Col(
                left:  _DetailRow('Position', mi.bbPosition,
                    mi.bbPosition.contains('ABOVE') ? AppTheme.signalSell
                    : mi.bbPosition.contains('BELOW') ? AppTheme.signalBuy
                    : AppTheme.textMuted),
                right: _DetailRow('Squeeze',  mi.bbSqueeze ? 'ACTIVE' : 'OFF',
                    mi.bbSqueeze ? AppTheme.gold : AppTheme.textMuted),
              ),
              const Divider(color: AppTheme.border, height: 20),
              // ── Keltner Channels ────────────────────────────────────────
              const _SubHeader('KELTNER CHANNELS (20, 1.5×ATR)'),
              _Row2Col(
                left:  _DetailRow('KC Upper', _p(mi.kcUpper, mi.assetType), AppTheme.signalSell),
                right: _DetailRow('KC Mid',   _p(mi.kcMid,   mi.assetType), Colors.white70),
              ),
              _DetailRow('KC Lower', _p(mi.kcLower, mi.assetType), AppTheme.signalBuy),
              const Divider(color: AppTheme.border, height: 20),
              // ── TTM Squeeze ─────────────────────────────────────────────
              const _SubHeader('TTM SQUEEZE'),
              _Row2Col(
                left: _DetailRow(
                  'Status',
                  mi.ttmSqueezeActive ? '🔴 SQUEEZE ON' : '🟢 SQUEEZE OFF',
                  mi.ttmSqueezeActive ? AppTheme.gold : AppTheme.textMuted,
                ),
                right: _DetailRow(
                  'Momentum',
                  mi.ttmMomentum.toStringAsFixed(4),
                  mi.ttmMomentum >= 0 ? AppTheme.signalBuy : AppTheme.signalSell,
                ),
              ),
              const Divider(color: AppTheme.border, height: 20),
              // ── Supertrend ──────────────────────────────────────────────
              const _SubHeader('SUPERTREND (10, 3×ATR)'),
              _Row2Col(
                left:  _DetailRow('Signal', mi.supertrendSignal,
                    _signalClr(mi.supertrendSignal)),
                right: _DetailRow('Line', _p(mi.supertrendValue, mi.assetType),
                    _signalClr(mi.supertrendSignal)),
              ),
              const Divider(color: AppTheme.border, height: 20),
              // ── VWAP ────────────────────────────────────────────────────
              const _SubHeader('VWAP + ±2σ BANDS'),
              _Row2Col(
                left:  _DetailRow('VWAP',       _p(mi.vwap,      mi.assetType), Colors.white),
                right: _DetailRow('VWAP Signal', mi.vwapSignal,  _signalClr(mi.vwapSignal)),
              ),
              _Row2Col(
                left:  _DetailRow('VWAP Upper', _p(mi.vwapUpper, mi.assetType), AppTheme.signalSell),
                right: _DetailRow('VWAP Lower', _p(mi.vwapLower, mi.assetType), AppTheme.signalBuy),
              ),
              const Divider(color: AppTheme.border, height: 20),
              // ── ATR & Stops ─────────────────────────────────────────────
              const _SubHeader('ATR & DYNAMIC STOPS'),
              _Row2Col(
                left:  _DetailRow('ATR (14)',  mi.atr14.toStringAsFixed(4),     AppTheme.gold),
                right: _DetailRow('SL Pips',  mi.slPips.toStringAsFixed(1),     AppTheme.textPrimary),
              ),
              _Row2Col(
                left:  _DetailRow('SL Buy',   mi.slBuy  != null ? _p(mi.slBuy!,  mi.assetType) : '---', AppTheme.signalSell),
                right: _DetailRow('SL Sell',  mi.slSell != null ? _p(mi.slSell!, mi.assetType) : '---', AppTheme.signalSell),
              ),
              _Row2Col(
                left:  _DetailRow('TP Buy',   mi.tpBuy  != null ? _p(mi.tpBuy!,  mi.assetType) : '---', AppTheme.signalBuy),
                right: _DetailRow('TP Sell',  mi.tpSell != null ? _p(mi.tpSell!, mi.assetType) : '---', AppTheme.signalBuy),
              ),
            ],
          ),
        );
      },
    );
  }

  String _p(double v, String at) {
    if (v == 0) return '---';
    if (at == 'forex') return v.toStringAsFixed(5);
    if (at == 'crypto' || at == 'cryptocurrency') {
      if (v >= 1000) return v.toStringAsFixed(2);
      if (v >= 1)    return v.toStringAsFixed(4);
      return v.toStringAsFixed(6);
    }
    return v.toStringAsFixed(2);
  }

  Color _signalClr(String s) {
    final u = s.toUpperCase();
    if (u.contains('BULL') || u.contains('ABOVE') || u.contains('BUY')) return AppTheme.signalBuy;
    if (u.contains('BEAR') || u.contains('BELOW') || u.contains('SELL')) return AppTheme.signalSell;
    return AppTheme.textMuted;
  }
}

// ── Sub-header used inside multi-section cards ────────────────────────────

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        text,
        style: const TextStyle(
          color:       AppTheme.textMuted,
          fontSize:    9,
          fontWeight:  FontWeight.bold,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PIVOT POINTS  (v13.0 NEW)
// ════════════════════════════════════════════════════════════════════════════

class _PivotPointsSection extends StatelessWidget {
  const _PivotPointsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        final pp = mi.pivotPoints;
        if (pp.isEmpty) return const SizedBox.shrink();

        // Pre-extract all known pivot levels with fallback null.
        double? _v(String key) {
          final raw = pp[key];
          if (raw == null) return null;
          return (raw as num?)?.toDouble();
        }

        final nearestColor = mi.nearestPivotLevel.startsWith('S')
            ? AppTheme.signalBuy
            : mi.nearestPivotLevel.startsWith('R')
                ? AppTheme.signalSell
                : AppTheme.gold;

        String fmt(double? v) {
          if (v == null) return '---';
          if (mi.assetType == 'forex') return v.toStringAsFixed(5);
          if (mi.assetType == 'crypto' || mi.assetType == 'cryptocurrency') {
            if (v >= 1000) return v.toStringAsFixed(2);
            if (v >= 1)    return v.toStringAsFixed(4);
            return v.toStringAsFixed(6);
          }
          return v.toStringAsFixed(2);
        }

        return _NexusCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon:  Icons.table_chart_rounded,
                label: 'PIVOT POINTS (CLASSIC + FIB)',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:        nearestColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:       Border.all(color: nearestColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    'NEAREST: ${mi.nearestPivotLevel}  '
                    '${mi.nearestPivotDist.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: nearestColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const _SubHeader('CLASSIC PIVOTS'),
              _Row2Col(
                left:  _DetailRow('PP',  fmt(_v('PP')),  AppTheme.gold),
                right: _DetailRow('',    '',             Colors.transparent),
              ),
              _Row2Col(
                left:  _DetailRow('R1',  fmt(_v('R1')),  AppTheme.signalSell),
                right: _DetailRow('S1',  fmt(_v('S1')),  AppTheme.signalBuy),
              ),
              _Row2Col(
                left:  _DetailRow('R2',  fmt(_v('R2')),  AppTheme.signalSell.withOpacity(0.7)),
                right: _DetailRow('S2',  fmt(_v('S2')),  AppTheme.signalBuy.withOpacity(0.7)),
              ),
              _Row2Col(
                left:  _DetailRow('R3',  fmt(_v('R3')),  AppTheme.signalSell.withOpacity(0.5)),
                right: _DetailRow('S3',  fmt(_v('S3')),  AppTheme.signalBuy.withOpacity(0.5)),
              ),
              const Divider(color: AppTheme.border, height: 20),
              const _SubHeader('FIBONACCI PIVOTS'),
              _Row2Col(
                left:  _DetailRow('FR1 (38.2%)', fmt(_v('FR1')), AppTheme.signalSell.withOpacity(0.8)),
                right: _DetailRow('FS1 (38.2%)', fmt(_v('FS1')), AppTheme.signalBuy.withOpacity(0.8)),
              ),
              _Row2Col(
                left:  _DetailRow('FR2 (61.8%)', fmt(_v('FR2')), AppTheme.signalSell.withOpacity(0.6)),
                right: _DetailRow('FS2 (61.8%)', fmt(_v('FS2')), AppTheme.signalBuy.withOpacity(0.6)),
              ),
              _Row2Col(
                left:  _DetailRow('FR3 (100%)',  fmt(_v('FR3')), AppTheme.signalSell.withOpacity(0.4)),
                right: _DetailRow('FS3 (100%)',  fmt(_v('FS3')), AppTheme.signalBuy.withOpacity(0.4)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  NEWS FEED  (v13.0 NEW — enriched with imageUrl, sentimentLabel, impact%)
// ════════════════════════════════════════════════════════════════════════════

class _NewsSection extends StatelessWidget {
  const _NewsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final news = state.lastAnalysis?.news;
        if (news == null || news.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.newspaper_rounded,
                      color: AppTheme.gold, size: 14),
                  const SizedBox(width: 6),
                  const Text(
                    'MARKET INTELLIGENCE FEED',
                    style: TextStyle(
                      color:       AppTheme.gold,
                      fontSize:    10,
                      fontWeight:  FontWeight.bold,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color:        AppTheme.gold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                      border:       Border.all(
                          color: AppTheme.gold.withOpacity(0.2)),
                    ),
                    child: Text(
                      '${news.length} ITEMS',
                      style: const TextStyle(
                        color:       AppTheme.gold,
                        fontSize:    9,
                        fontWeight:  FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...news.take(10).map((item) => _NewsCard(item: item)),
          ],
        );
      },
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final catColor = item.categoryColor;
    final isBull   = item.sentimentLabel.contains('BULL');
    final isBear   = item.sentimentLabel.contains('BEAR');
    final sentColor = isBull
        ? AppTheme.signalBuy
        : isBear ? AppTheme.signalSell : AppTheme.textMuted;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: catColor, width: 3),
          top:    BorderSide(color: AppTheme.border),
          right:  BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: category pill + impact bar + sentiment ────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:        catColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(3),
                  border:       Border.all(color: catColor.withOpacity(0.3)),
                ),
                child: Text(
                  item.category,
                  style: TextStyle(
                    color:       catColor,
                    fontSize:    8,
                    fontWeight:  FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Impact bar
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value:     (item.impactPercentage / 100).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor:  catColor.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        catColor.withOpacity(0.7)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${item.impactPercentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  color:     catColor,
                  fontSize:  9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              // Sentiment label
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color:        sentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  item.sentimentLabel.replaceAll('_', ' '),
                  style: TextStyle(
                    color:     sentColor,
                    fontSize:  8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Headline ──────────────────────────────────────────────────
          Text(
            item.title,
            style: const TextStyle(
              color:    AppTheme.textPrimary,
              fontSize: 12,
              height:   1.4,
            ),
          ),
          const SizedBox(height: 6),
          // ── NEXUS Intelligence comment ────────────────────────────────
          if (item.nexusComment.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        AppTheme.gold.withOpacity(0.04),
                borderRadius: BorderRadius.circular(6),
                border:       Border.all(
                    color: AppTheme.gold.withOpacity(0.12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.bolt_rounded,
                      color: AppTheme.gold, size: 11),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      item.nexusComment,
                      style: const TextStyle(
                        color:     AppTheme.gold,
                        fontSize:  11,
                        fontStyle: FontStyle.italic,
                        height:    1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // ── Footer: source + action + time ───────────────────────────
          Row(
            children: [
              Text(
                item.source,
                style: const TextStyle(
                  color:     AppTheme.textMuted,
                  fontSize:  10,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color:        _actionColor(item.quantAction).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _actionColor(item.quantAction).withOpacity(0.25),
                  ),
                ),
                child: Text(
                  item.quantAction,
                  style: TextStyle(
                    color:     _actionColor(item.quantAction),
                    fontSize:  9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                item.published,
                style: const TextStyle(
                  color:     AppTheme.textMuted,
                  fontSize:  9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _actionColor(String action) {
    final u = action.toUpperCase();
    if (u.contains('SUSPENDED') || u.contains('AVOID')) return AppTheme.signalSell;
    if (u.contains('MONITOR'))   return AppTheme.gold;
    return AppTheme.textMuted;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE COMPONENTS
// ════════════════════════════════════════════════════════════════════════════

class _NexusCard extends StatelessWidget {
  const _NexusCard({required this.child, this.margin});
  final Widget                child;
  final EdgeInsetsGeometry?   margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color:        AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.trailing,
  });
  final IconData icon;
  final String   label;
  final Widget?  trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.gold, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color:       AppTheme.gold,
              fontSize:    10,
              fontWeight:  FontWeight.bold,
              letterSpacing: 1.8,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, this.valueColor);
  final String label;
  final String value;
  final Color  valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color:      valueColor,
                fontSize:   12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row2Col extends StatelessWidget {
  const _Row2Col({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

/// v11.3: _PriceLevel now receives assetType for correct decimal formatting
class _PriceLevel extends StatelessWidget {
  const _PriceLevel({
    required this.label,
    required this.value,
    required this.color,
    this.assetType = '',
  });
  final String label;
  final double value;
  final Color  color;
  final String assetType;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                color:       AppTheme.textMuted,
                fontSize:    9,
                letterSpacing: 1,
              )),
          const SizedBox(height: 4),
          Text(
            _fmt(value),
            style: TextStyle(
              color:      color,
              fontSize:   13,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == 0) return '---';
    if (assetType == 'forex') return v.toStringAsFixed(5);
    if (assetType == 'crypto' || assetType == 'cryptocurrency') {
      if (v >= 1000) return v.toStringAsFixed(2);
      if (v >= 1)    return v.toStringAsFixed(4);
      return v.toStringAsFixed(6);
    }
    return v < 10 ? v.toStringAsFixed(5) : v.toStringAsFixed(2);
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.valueColor = AppTheme.textPrimary,
  });
  final String label;
  final String value;
  final Color  valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
              color:       AppTheme.textMuted,
              fontSize:    9,
              letterSpacing: 1,
            )),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              color:      valueColor,
              fontSize:   12,
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }
}

class _ExplanationBox extends StatelessWidget {
  const _ExplanationBox({
    required this.label,
    required this.text,
    required this.accentColor,
    this.leadIcon,
  });
  final String    label;
  final String    text;
  final Color     accentColor;
  final IconData? leadIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color:        accentColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: accentColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leadIcon != null) ...[
                Icon(leadIcon, color: accentColor, size: 11),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color:       accentColor,
                  fontSize:    9,
                  fontWeight:  FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color:     AppTheme.textPrimary,
              fontSize:  12,
              height:    1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}