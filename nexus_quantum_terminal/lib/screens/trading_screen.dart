// ============================================================================
//  NEXUS v14.0 — lib/screens/trading_screen.dart
//  Full Refactor: Notion + Big Brokers Design System
//  ✅ ALL 23 SECTIONS PRESERVED — NO DATA LOST
//  ✅ AppColors + AppConstants + AppCard + SectionTitle + SignalBadge
//  ✅ google_fonts (Inter + JetBrainsMono)
// ============================================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/market_models.dart';
import '../providers/market_state.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../widgets/app_widgets.dart';
import '../widgets/nexus_candle_chart.dart';
import '../widgets/glowing_signal_card.dart';
import '../widgets/ai_plan_card.dart';
import '../ads/ad_placeholders.dart';

// ════════════════════════════════════════════════════════════════════════════
//  TYPOGRAPHY HELPERS
// ════════════════════════════════════════════════════════════════════════════
TextStyle _mono(Color color, double size, [FontWeight weight = FontWeight.w700]) =>
    GoogleFonts.jetBrainsMono(
      color: color, fontSize: size, fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle _sans(Color color, double size, [FontWeight weight = FontWeight.w500]) =>
    GoogleFonts.inter(color: color, fontSize: size, fontWeight: weight);

// ════════════════════════════════════════════════════════════════════════════
//  FORMATTERS
// ════════════════════════════════════════════════════════════════════════════
bool _isCryptoType(String? t) => t == 'crypto' || t == 'cryptocurrency';

String _fmtPrice(double? p, String? type, {bool compact = false}) {
  if (p == null) return '---';
  if (type == 'forex') return p.toStringAsFixed(compact ? 4 : 5);
  if (_isCryptoType(type)) {
    if (compact) {
      if (p >= 10000) return '\$${(p / 1000).toStringAsFixed(1)}k';
      return '\$${p.toStringAsFixed(0)}';
    }
    if (p >= 100) return p.toStringAsFixed(2);
    if (p >= 1) return p.toStringAsFixed(4);
    return p.toStringAsFixed(6);
  }
  return p < 10 ? p.toStringAsFixed(4) : p.toStringAsFixed(2);
}

String _fmtLevel(double v, String assetType) {
  if (v == 0) return '---';
  if (assetType == 'forex') return v.toStringAsFixed(5);
  if (_isCryptoType(assetType)) {
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }
  return v < 10 ? v.toStringAsFixed(4) : v.toStringAsFixed(2);
}

String _fmtVolume(double v) {
  if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
  if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
  if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

// ════════════════════════════════════════════════════════════════════════════
//  COLOR MAPPERS
// ════════════════════════════════════════════════════════════════════════════
Color _regimeColor(String r) {
  final u = r.toUpperCase();
  if (u.contains('BULL') || u.contains('TREND')) return AppColors.bullish;
  if (u.contains('BEAR') || u.contains('CRISIS')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _hurstColor(double h) =>
    h > 0.6 ? AppColors.bullish : h < 0.4 ? AppColors.bearish : AppColors.textSecondary;
Color _zscoreColor(double z) {
  if (z.abs() > 2) return AppColors.bearish;
  if (z.abs() > 1) return AppColors.primary;
  return AppColors.textPrimary;
}
Color _volRegimeColor(String v) {
  final u = v.toUpperCase();
  if (u.contains('HIGH') || u.contains('EXTREME')) return AppColors.bearish;
  if (u.contains('LOW')) return AppColors.bullish;
  return AppColors.textSecondary;
}
Color _stabilityColor(int s) =>
    s >= 70 ? AppColors.bullish : s >= 40 ? AppColors.primary : AppColors.bearish;
Color _probColor(double p) =>
    p >= 65 ? AppColors.bullish : p <= 35 ? AppColors.bearish : AppColors.textSecondary;
Color _vdColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('BULL')) return AppColors.bullish;
  if (u.contains('BEAR')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _cavbColor(String s) {
  if (s == 'SQUEEZE') return AppColors.primary;
  if (s == 'EXPANSION') return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _cavbPosColor(String s) {
  if (s.contains('ABOVE')) return AppColors.bearish;
  if (s.contains('BELOW')) return AppColors.bullish;
  return AppColors.textSecondary;
}
Color _rsiColor(double v) =>
    v > 70 ? AppColors.bearish : v < 30 ? AppColors.bullish : AppColors.textPrimary;
Color _stochColor(double v) =>
    v > 80 ? AppColors.bearish : v < 20 ? AppColors.bullish : AppColors.textPrimary;
Color _adxColor(double v) =>
    v > 40 ? AppColors.bullish : v > 25 ? AppColors.primary : AppColors.textSecondary;
Color _cciColor(double v) =>
    v > 100 ? AppColors.bearish : v < -100 ? AppColors.bullish : AppColors.textPrimary;
Color _williamsColor(double v) =>
    v > -20 ? AppColors.bearish : v < -80 ? AppColors.bullish : AppColors.textPrimary;
Color _divColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('BULL')) return AppColors.bullish;
  if (u.contains('BEAR')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _emaColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('BULL')) return AppColors.bullish;
  if (u.contains('BEAR')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _signalColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('BULL') || u.contains('BUY') || u.contains('ABOVE')) return AppColors.bullish;
  if (u.contains('BEAR') || u.contains('SELL') || u.contains('BELOW')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _biasColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('BULL') || u.contains('BUY')) return AppColors.bullish;
  if (u.contains('BEAR') || u.contains('SELL')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _fibColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('SUPPORT')) return AppColors.bullish;
  if (u.contains('RESISTANCE')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _liqColor(String s) {
  final u = s.toUpperCase();
  if (u == 'HIGH' || u == 'EXTREME') return AppColors.bullish;
  if (u == 'MEDIUM') return AppColors.primary;
  return AppColors.bearish;
}
Color _macroColor(String s) {
  final u = s.toUpperCase();
  if (u.contains('BULL')) return AppColors.bullish;
  if (u.contains('BEAR')) return AppColors.bearish;
  return AppColors.textSecondary;
}
Color _actionColor(String action) {
  final u = action.toUpperCase();
  if (u.contains('SUSPENDED') || u.contains('AVOID')) return AppColors.bearish;
  if (u.contains('MONITOR')) return AppColors.primary;
  return AppColors.textSecondary;
}

// ════════════════════════════════════════════════════════════════════════════
//  1. ROOT SCREEN
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
      if (mounted) context.read<MarketState>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: GoogleFonts.inter(color: AppColors.textPrimary),
          child: Column(
            children: [
              _buildTopBar(),
              const _AuthBanner(),
              const _WatchlistBar(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => context.read<MarketState>().refreshCandles(),
                  color: AppColors.primary,
                  backgroundColor: AppColors.cardBackground,
                  child: const SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(bottom: AppConstants.spacingXLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MarketOverview(),
                        _WorldClockSection(),
                        _ChartSection(),
                        _LiveFeedBanner(),
                        _SignalSection(),
                        _TradePlanSection(),
                        _QuantumMetricsSection(),
                        _MonteCarloSection(),
                        _CryptoMetricsCard(),
                        _ForexMetricsCard(),
                        _MomentumSection(),
                        _SmartMoneySection(),
                        _MultiTimeframeSection(),
                        _SessionRiskSection(),
                        _CalendarSection(),
                        _ExplanationsSection(),
                        _VolatilitySection(),
                        _PivotPointsSection(),
                        _AiPlanSection(),
                        _NewsSection(),
                      ],
                    ),
                  ),
                ),
              ),
              const AdBannerPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.screenPadding, vertical: AppConstants.spacingMedium),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          const Text('NEXUS',
              style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: AppConstants.fontSizeXLarge,
                  letterSpacing: 3)),
          const SizedBox(width: AppConstants.spacingSmall),
          Text('QUANTUM v14.0',
              style: _mono(AppColors.textSecondary, AppConstants.fontSizeXSmall, FontWeight.w400)),
          const Spacer(),
          Consumer<MarketState>(
            builder: (context, state, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.isLive) ...[const _LivePulse(), const SizedBox(width: 8)],
                _StatusPill(online: state.online),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  2. AUTH BANNER
// ════════════════════════════════════════════════════════════════════════════
class _AuthBanner extends StatelessWidget {
  const _AuthBanner();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final user = state.currentUser;
        if (user == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.screenPadding, vertical: AppConstants.spacingSmall),
            decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: AppColors.primary, size: 14),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Free mode — 2 analyses per day',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            letterSpacing: 0.5))),
                GestureDetector(
                  onTap: () => _showLoginDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(AppConstants.cardRadiusSmall),
                        border: Border.all(color: AppColors.primary.withOpacity(0.4))),
                    child: const Text('LOGIN',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                  ),
                ),
              ],
            ),
          );
        }
        final isPro = user.isPro;
        final color = isPro ? AppColors.primary : AppColors.textSecondary;
        final tierLabel = isPro ? 'PRO' : 'FREE';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.screenPadding, vertical: AppConstants.spacingXSmall),
          decoration: BoxDecoration(
              color: color.withOpacity(0.04),
              border: const Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              Icon(isPro ? Icons.workspace_premium : Icons.person_outline, color: color, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                    children: [
                      TextSpan(
                          text: user.email, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const TextSpan(text: '  ·  '),
                      TextSpan(
                          text: tierLabel,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                      if (!isPro)
                        TextSpan(
                          text: '  (${user.tradesRemaining} scans left)',
                          style: _mono(AppColors.textSecondary, 10, FontWeight.w500),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isPro)
                GestureDetector(
                  onTap: () => _showUpgradeDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppConstants.cardRadiusSmall)),
                    child: const Text('UPGRADE',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => state.logout(),
                  child: const Icon(Icons.logout, color: AppColors.textSecondary, size: 14),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showLoginDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Coming Soon', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Login/Signup will be available in the next release.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: AppColors.primary)))
        ],
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Upgrade to Pro', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
            'Get unlimited analyses, real-time news, and advanced features.\n\$15/month · \$150/year',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse('https://nexus.app/upgrade');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Upgrade', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  3. WATCHLIST BAR
// ════════════════════════════════════════════════════════════════════════════
class _WatchlistBar extends StatelessWidget {
  const _WatchlistBar();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        if (state.watchlist.isEmpty) {
          return Container(
            height: 52,
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: const Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))),
          );
        }
        return Container(
          height: AppConstants.watchlistHeight,
          decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.screenPadding, vertical: AppConstants.spacingSmall),
            itemCount: state.watchlist.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final item = state.watchlist[index];
              final isSelected = item.symbol == state.selectedSymbol;
              return _WatchlistChip(
                item: item,
                isSelected: isSelected,
                onTap: () {
                  if (!isSelected) context.read<MarketState>().selectSymbol(item.symbol);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _WatchlistChip extends StatelessWidget {
  const _WatchlistChip(
      {required this.item, required this.isSelected, required this.onTap});
  final WatchlistItem item;
  final bool isSelected;
  final VoidCallback onTap;

  Color get _typeColor {
    if (item.isCrypto) return const Color(0xFFF7931A);
    if (item.isForex || item.symbol == 'XAUUSD') return AppColors.primary;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _typeColor;
    final chg = item.changePct;
    final chgUp = chg != null && chg >= 0;
    final chgStr = chg == null ? '' : '${chgUp ? "+" : ""}${chg.toStringAsFixed(2)}%';
    final chgColor = chgUp ? AppColors.bullish : AppColors.bearish;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? accent.withOpacity(0.60) : AppColors.border,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((item.emoji ?? '').isNotEmpty) ...[
              Text(item.emoji!, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
            ],
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.symbol,
                    style: TextStyle(
                        color: isSelected ? accent : AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 1),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_fmtPrice(item.price, item.type, compact: true),
                      style: _mono(
                          isSelected ? accent.withOpacity(0.85) : AppColors.textSecondary,
                          9,
                          FontWeight.w500)),
                  if (chgStr.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(chgStr, style: _mono(chgColor, 8)),
                  ],
                ]),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online});
  final bool online;
  @override
  Widget build(BuildContext context) {
    final c = online ? AppColors.bullish : AppColors.bearish;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(online ? 'QUANTUM LIVE' : 'OFFLINE',
            style: TextStyle(
                color: c, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
      ]),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse();
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
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
            color: AppColors.bullish.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.bullish.withOpacity(0.3 + 0.3 * _ctrl.value))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bullish.withOpacity(0.5 + 0.5 * _ctrl.value))),
          const SizedBox(width: 5),
          Text('LIVE',
              style: TextStyle(
                  color: AppColors.bullish.withOpacity(0.6 + 0.4 * _ctrl.value),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  4. MARKET OVERVIEW
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
        final chg = selected.changePct ?? 0.0;
        final isUp = chg >= 0;
        final typeColor = selected.isCrypto
            ? const Color(0xFFF7931A)
            : selected.isForex
                ? AppColors.primary
                : AppColors.textSecondary;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
              AppConstants.screenPadding, AppConstants.spacingLarge, AppConstants.screenPadding,
              AppConstants.spacingSmall),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                          child: Text(
                              '${selected.emoji ?? ''} ${selected.name ?? selected.symbol}'.trim(),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: AppConstants.fontSizeTitle,
                                  fontWeight: FontWeight.bold))),
                      if (selected.is24h) ...[
                        const SizedBox(width: 8),
                        _AssetTypeBadge(label: '24/7', color: AppColors.bullish),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(selected.symbol,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      if ((selected.type ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _AssetTypeBadge(
                            label: (selected.type ?? '').toUpperCase(), color: typeColor),
                      ],
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                        position:
                            Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
                                .animate(anim),
                        child: child),
                  ),
                  child: Text(_fmtPrice(selected.price, selected.type),
                      key: ValueKey(selected.price),
                      style: _mono(AppColors.primary, AppConstants.fontSizeDisplay,
                          FontWeight.w900)),
                ),
                const SizedBox(height: 2),
                Text('${isUp ? "+" : ""}${chg.toStringAsFixed(2)}%',
                    style: _mono(isUp ? AppColors.bullish : AppColors.bearish,
                        AppConstants.fontSizeLarge)),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _AssetTypeBadge extends StatelessWidget {
  const _AssetTypeBadge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withOpacity(0.35))),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8)),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  5. WORLD MARKET CLOCK
// ════════════════════════════════════════════════════════════════════════════
class _WorldClockSection extends StatefulWidget {
  const _WorldClockSection();
  @override
  State<_WorldClockSection> createState() => _WorldClockSectionState();
}

class _WorldClockSectionState extends State<_WorldClockSection> {
  Timer? _timer;
  static const List<({String flag, String name, double open, double close})> _sessions = [
    (flag: '🇦🇺', name: 'SYDNEY', open: 22.0, close: 7.0),
    (flag: '🇯🇵', name: 'TOKYO', open: 0.0, close: 9.0),
    (flag: '🇬🇧', name: 'LONDON', open: 8.0, close: 16.5),
    (flag: '🇺🇸', name: 'NEW YORK', open: 13.5, close: 20.0),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final nowLocal = DateTime.now();
    final nowUtc = nowLocal.toUtc();
    final utcHour = nowUtc.hour + nowUtc.minute / 60.0;
    bool isOpen(double open, double close) {
      if (open < close) return utcHour >= open && utcHour < close;
      return utcHour >= open || utcHour < close;
    }

    String inLocal(double utcH) {
      final base = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
      return _hhmm(base.add(Duration(minutes: (utcH * 60).round())).toLocal());
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: 'World Market Clock', icon: Icons.public),
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingMedium),
            child: Text('LOCAL ${_hhmm(nowLocal)} · UTC ${_hhmm(nowUtc)}',
                style: _mono(AppColors.textSecondary, AppConstants.fontSizeSmall,
                    FontWeight.w500)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sessions.map((s) {
              final open = isOpen(s.open, s.close);
              final color = open ? AppColors.bullish : AppColors.textSecondary;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.flag, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name,
                        style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1)),
                    Text('${inLocal(s.open)}–${inLocal(s.close)}',
                        style: _mono(AppColors.textSecondary, 9, FontWeight.w500)),
                  ]),
                  const SizedBox(width: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: open
                              ? AppColors.bullish.withOpacity(0.15)
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(open ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                              color: open ? AppColors.bullish : AppColors.textSecondary,
                              fontSize: 8,
                              fontWeight: FontWeight.w900))),
                ]),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  6. CHART SECTION
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
        final analysis = state.lastAnalysis;
        return AppCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.candlestick_chart_rounded,
                        color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    const Text('QUANTUM CHART',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.8)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (selected.is24h)
                      const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: _AssetTypeBadge(
                              label: '24/7', color: AppColors.bullish)),
                    const _TimeframeSelector(),
                  ]),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: state.loadingCandles && state.candles.isEmpty
                    ? const _ChartLoadingSkeleton(height: 300)
                    : state.candles.isEmpty
                        ? _ChartUnavailable(onRetry: () => state.refreshCandles())
                        : Stack(
                            children: [
                              NexusCandleChart(
                                key: ValueKey('${state.selectedSymbol}_${state.timeframe}'),
                                data: state.candles,
                                liveTickNotifier: state.liveTickNotifier,
                                height: 300,
                                assetType: selected.type ?? '',
                                is24h: selected.is24h,
                              ),
                              if (analysis != null)
                                Positioned.fill(
                                    child:
                                        AnalysisOverlay(intelligence: analysis.intelligence)),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimeframeSelector extends StatelessWidget {
  const _TimeframeSelector();
  static const List<List<String>> _tfs = [
    ['1M', 'M1'], ['5M', 'M5'], ['15M', 'M15'], ['1H', 'H1'], ['4H', 'H4'], ['1D', 'D1']
  ];
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: _tfs.map((tf) {
          final selected = state.timeframe == tf[1];
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => state.setTimeframe(tf[1]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(0.15)
                      : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: selected ? AppColors.primary.withOpacity(0.6) : AppColors.border),
                ),
                child: Text(tf[0],
                    style: _mono(selected ? AppColors.primary : AppColors.textSecondary, 9,
                        FontWeight.w800)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChartLoadingSkeleton extends StatefulWidget {
  const _ChartLoadingSkeleton({required this.height});
  final double height;
  @override
  State<_ChartLoadingSkeleton> createState() => _ChartLoadingSkeletonState();
}

class _ChartLoadingSkeletonState extends State<_ChartLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;
  static const List<double> _heights = [
    38.0, 52.0, 44.0, 70.0, 58.0, 34.0, 62.0, 46.0, 80.0, 56.0, 42.0, 66.0, 50.0, 74.0, 40.0,
    60.0, 54.0, 48.0,
  ];
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat(reverse: true);
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_heights.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                      width: 10,
                      height: _heights[i],
                      decoration: BoxDecoration(
                          color: (i % 3 == 0 ? AppColors.bearish : AppColors.bullish)
                              .withOpacity((_shimmer.value + 0.02 * (i % 4)).clamp(0.0, 1.0)),
                          borderRadius: BorderRadius.circular(2))),
                );
              })),
          const SizedBox(height: 20),
          Text('LOADING CHART DATA…',
              style: TextStyle(
                  color: AppColors.textSecondary
                      .withOpacity((0.3 + _shimmer.value * 4).clamp(0.0, 1.0)),
                  fontSize: 10,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _ChartUnavailable extends StatelessWidget {
  const _ChartUnavailable({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.candlestick_chart_rounded, color: AppColors.textSecondary, size: 32),
          const SizedBox(height: 12),
          const Text('CHART DATA UNAVAILABLE',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 3)),
          const SizedBox(height: 8),
          TextButton(
              onPressed: onRetry,
              child: const Text('RETRY',
                  style: TextStyle(color: AppColors.primary, fontSize: 10, letterSpacing: 2))),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  7. LIVE FEED BANNER
// ════════════════════════════════════════════════════════════════════════════
class _LiveFeedBanner extends StatelessWidget {
  const _LiveFeedBanner();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        if (!state.isLive) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 0,
              AppConstants.screenPadding, AppConstants.spacingSmall),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: AppColors.bullish.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.bullish.withOpacity(0.18))),
            child: Row(children: [
              const _LivePulse(),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text(
                      'LIVE AUTO-SCAN — Candles refresh every 8s · Quantum scan every 30s',
                      style: TextStyle(
                          color: AppColors.bullish, fontSize: 9, letterSpacing: 0.5))),
              Text('GEN ${state.scanGeneration}',
                  style: _mono(AppColors.textSecondary, 9, FontWeight.w500)),
            ]),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  8. SIGNAL SECTION
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
              child: Column(children: [
                CircularProgressIndicator(color: AppColors.primary, strokeWidth: 1.5),
                SizedBox(height: 16),
                Text('QUANTUM ENGINE RUNNING…',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 10, letterSpacing: 2)),
              ]),
            ),
          );
        }
        final analysis = state.lastAnalysis;
        if (analysis == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding, AppConstants.spacingSmall,
                AppConstants.screenPadding, AppConstants.spacingSmall),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => state.runQuantumScan(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.cardRadiusSmall)),
                ),
                child: const Text('RUN QUANTUM ANALYSIS',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ),
            ),
          );
        }
        final mi = analysis.intelligence;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding,
                AppConstants.spacingSmall, AppConstants.screenPadding, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: GlowingSignalCard(
                key: ValueKey('${mi.safetySignal}_${mi.signalStrength}_${state.scanGeneration}'),
                signal: mi.safetySignal,
                strength: mi.signalStrength.toDouble(),
                direction: mi.direction,
                probability: mi.probabilityBull,
                intelligence: mi,
                tradePlan: mi.tradePlan,
                newsItems: state.currentNews,
              ),
            ),
          ),
          if (state.isLive)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 4,
                  AppConstants.screenPadding, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                const Icon(Icons.update, color: AppColors.bullish, size: 10),
                const SizedBox(width: 4),
                const Text('AUTO-UPDATED · GEN ',
                    style: TextStyle(
                        color: AppColors.bullish,
                        fontSize: 8,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold)),
                Text('${state.scanGeneration}',
                    style: _mono(AppColors.bullish, 8, FontWeight.w900)),
              ]),
            ),
        ]);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  9. TRADE PLAN SECTION
// ════════════════════════════════════════════════════════════════════════════
class _TradePlanSection extends StatelessWidget {
  const _TradePlanSection();
  Widget _vDivider() =>
      Container(width: 1, height: 40, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 4));
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final scan = state.lastAnalysis;
        if (scan == null) return const SizedBox.shrink();
        final mi = scan.intelligence;
        final tp = mi.tradePlan;
        if (!tp.valid) return const SizedBox.shrink();
        final dirU = tp.direction.toUpperCase();
        final isLong = dirU.contains('BULL') || dirU.contains('BUY');
        final expColor = tp.expectancyPerDollar > 0
            ? AppColors.bullish
            : tp.expectancyPerDollar < 0
                ? AppColors.bearish
                : AppColors.textSecondary;
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Institutional Trade Plan', icon: Icons.account_balance),
            Row(children: [
              _PriceLevel(label: 'ENTRY', value: tp.entry, color: Colors.white, assetType: mi.assetType),
              _vDivider(),
              _PriceLevel(label: 'STOP', value: tp.sl, color: AppColors.bearish, assetType: mi.assetType),
              _vDivider(),
              _PriceLevel(label: 'TP 1', value: tp.tp1, color: AppColors.bullish, assetType: mi.assetType),
              _vDivider(),
              _PriceLevel(label: 'TP 2', value: tp.tp2, color: AppColors.bullish.withOpacity(0.7), assetType: mi.assetType),
              _vDivider(),
              _PriceLevel(label: 'TP 3', value: tp.tp3, color: AppColors.primary, assetType: mi.assetType),
            ]),
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _StatChip(label: 'RR', value: '1:${tp.rr1.toStringAsFixed(1)}'),
              _StatChip(label: 'CONF', value: '${tp.confidence.toStringAsFixed(0)}%'),
              _StatChip(label: 'QUALITY', value: tp.quality),
              _StatChip(label: 'NEWS RISK', value: tp.newsRisk,
                  valueColor: tp.newsRisk == 'HIGH' ? AppColors.bearish : AppColors.bullish),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.15))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ADVANCED EXPECTANCY METRICS',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _MetricChip(label: 'EXPECTANCY',
                      value: '${tp.expectancyPerDollar >= 0 ? "+" : ""}${tp.expectancyPerDollar.toStringAsFixed(2)}',
                      suffix: '/ \$1', color: expColor)),
                  const SizedBox(width: 6),
                  Expanded(child: _MetricChip(label: 'WIN RATE',
                      value: '${(tp.estimatedWinRate * 100).toStringAsFixed(0)}%',
                      color: tp.estimatedWinRate >= 0.5 ? AppColors.bullish : AppColors.bearish)),
                  const SizedBox(width: 6),
                  Expanded(child: _MetricChip(label: 'VOL-RISK',
                      value: tp.volatilityAdjustedRiskPct.toStringAsFixed(2),
                      suffix: '%', color: AppColors.primary)),
                ]),
              ]),
            ),
            if (tp.layerScores.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.layers, color: AppColors.primary, size: 12),
                const SizedBox(width: 6),
                Text('CONFLUENCE: ${tp.bullLayers}B / ${tp.bearLayers}S LAYERS',
                    style: _mono(AppColors.textSecondary, 9, FontWeight.w800)),
              ]),
            ],
            if (tp.proxyOrderFlow.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.water_drop, color: AppColors.primary, size: 12),
                const SizedBox(width: 6),
                Flexible(child: Text(
                    'ORDER FLOW: ${tp.deltaSignal.replaceAll('_', ' ')}',
                    overflow: TextOverflow.ellipsis,
                    style: _mono(
                        tp.buyingPressure > 60
                            ? AppColors.bullish
                            : tp.buyingPressure < 40
                                ? AppColors.bearish
                                : AppColors.textSecondary,
                        9, FontWeight.w800))),
                const Spacer(),
                Text('${tp.buyingPressure.toStringAsFixed(0)}% BUYING',
                    style: _mono(AppColors.textSecondary, 9, FontWeight.w500)),
              ]),
            ],
            if (tp.reasoning.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ExplanationBox(label: 'TRADE REASONING', text: tp.reasoning,
                  accentColor: isLong ? AppColors.bullish : AppColors.bearish),
            ],
            if (tp.invalidation.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ExplanationBox(label: 'INVALIDATION', text: tp.invalidation,
                  accentColor: AppColors.bearish.withOpacity(0.6)),
            ],
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  10. QUANTUM METRICS SECTION
// ════════════════════════════════════════════════════════════════════════════
class _QuantumMetricsSection extends StatelessWidget {
  const _QuantumMetricsSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        return AppCard(
          child: Column(children: [
            const SectionTitle(title: 'Quantum Engine', icon: Icons.memory_rounded),
            _Row2Col(
                left: _DetailRow('Regime', mi.regimeAdvanced, _regimeColor(mi.regimeAdvanced)),
                right: _DetailRow('Market State', mi.regime, AppColors.primary)),
            _Row2Col(
                left: _DetailRow('Hurst Exp.', mi.hurst.toStringAsFixed(3), _hurstColor(mi.hurst)),
                right: _DetailRow('Fractal Dim.', mi.fractalDim.toStringAsFixed(3),
                    AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow('Z-Score',
                    '${mi.zscore >= 0 ? "+" : ""}${mi.zscore.toStringAsFixed(2)}σ',
                    _zscoreColor(mi.zscore)),
                right: _DetailRow('Z-Signal', mi.zscoreSignal, _zscoreColor(mi.zscore))),
            _Row2Col(
                left: _DetailRow('Shannon Entropy', mi.shannonEntropy.toStringAsFixed(3),
                    AppColors.textPrimary),
                right: _DetailRow('Kaufman ER', mi.kaufmanEr.toStringAsFixed(3),
                    AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow('Realized Vol.',
                    '${(mi.realizedVol * 100).toStringAsFixed(2)}%', AppColors.textPrimary),
                right: _DetailRow('Vol Regime', mi.volRegime, _volRegimeColor(mi.volRegime))),
            _Row2Col(
                left: _DetailRow('Kurtosis', mi.kurtosis.toStringAsFixed(2),
                    AppColors.textPrimary),
                right: _DetailRow('Skewness', mi.skewness.toStringAsFixed(2),
                    AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow('Tail Risk', mi.tailRisk,
                    mi.tailRisk == 'NORMAL' ? AppColors.bullish : AppColors.bearish),
                right: _DetailRow('Stability Index', '${mi.stabilityIndex}/100',
                    _stabilityColor(mi.stabilityIndex))),
            _Row2Col(
                left: _DetailRow('Autocorr (lag-1)', mi.autocorrLag1.toStringAsFixed(3),
                    AppColors.textPrimary),
                right: _DetailRow('Probability Bull',
                    '${mi.probabilityBull.toStringAsFixed(1)}%', _probColor(mi.probabilityBull))),
            const Divider(color: AppColors.border, height: 24),
            _Row2Col(
                left: _DetailRow('Kelly Fraction',
                    '${(mi.kellyFraction * 100).toStringAsFixed(1)}%', AppColors.primary),
                right: _DetailRow('ATR (14)', mi.atr14.toStringAsFixed(4), AppColors.textPrimary)),
            if (mi.kellyRecommendation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _ExplanationBox(label: 'KELLY RECOMMENDATION',
                    text: mi.kellyRecommendation, accentColor: AppColors.primary),
              ),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  11. MONTE CARLO SECTION
// ════════════════════════════════════════════════════════════════════════════
class _MonteCarloSection extends StatelessWidget {
  const _MonteCarloSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mc = state.lastAnalysis?.intelligence.monteCarlo;
        if (mc == null) return const SizedBox.shrink();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(
                title: 'Monte Carlo Simulation',
                icon: Icons.casino,
                trailing: Text('${mc.simulationsRun} RUNS',
                    style: _mono(AppColors.textSecondary, 9, FontWeight.w500))),
            Row(children: [
              Expanded(child: _McStatBox(label: 'VaR 95%',
                  value: '\$${mc.var95.toStringAsFixed(0)}',
                  color: AppColors.bearish, icon: Icons.warning_amber)),
              const SizedBox(width: 6),
              Expanded(child: _McStatBox(label: 'VaR 99%',
                  value: '\$${mc.var99.toStringAsFixed(0)}',
                  color: AppColors.bearish.withOpacity(0.8), icon: Icons.dangerous)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _McStatBox(label: 'MAX DRAWDOWN',
                  value: '${mc.expectedMaxDrawdown.toStringAsFixed(1)}%',
                  color: mc.expectedMaxDrawdown > 30 ? AppColors.bearish : AppColors.primary,
                  icon: Icons.trending_down)),
              const SizedBox(width: 6),
              Expanded(child: _McStatBox(label: 'RUIN PROB.',
                  value: '${mc.probabilityOfRuin.toStringAsFixed(1)}%',
                  color: mc.probabilityOfRuin > 20 ? AppColors.bearish : AppColors.bullish,
                  icon: Icons.shield_outlined)),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.insights, color: AppColors.primary, size: 12),
                const SizedBox(width: 6),
                Expanded(child: Text(
                    'Expected final balance: \$${mc.expectedFinalBalance.toStringAsFixed(0)}',
                    style: _mono(AppColors.textSecondary, 10, FontWeight.w500))),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _McStatBox extends StatelessWidget {
  const _McStatBox(
      {required this.label, required this.value, required this.color, required this.icon});
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Expanded(child: Text(label,
              style: _mono(color.withOpacity(0.8), 8, FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Text(value, style: _mono(color, 16, FontWeight.w900)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  12. CRYPTO METRICS CARD
// ════════════════════════════════════════════════════════════════════════════
class _CryptoMetricsCard extends StatelessWidget {
  const _CryptoMetricsCard();
  Widget _pill(String text, Color c) => Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
            color: c.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(0.35))),
        child: Text(text,
            style: TextStyle(
                color: c, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ));
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        final cm = mi?.cryptoMetrics;
        if (mi == null || cm == null) return const SizedBox.shrink();
        final weekendColor = cm.isWeekend ? AppColors.primary : AppColors.bullish;
        final vdc = _vdColor(cm.volumeDeltaSignal);
        final cavbC = _cavbColor(cm.cavbSignal);
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(
                title: 'Crypto Intelligence',
                icon: Icons.currency_bitcoin,
                trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.bullish.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.bullish.withOpacity(0.25))),
                    child: const Text('24/7 MARKET',
                        style: TextStyle(
                            color: AppColors.bullish,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2)))),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: weekendColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: weekendColor.withOpacity(0.2))),
              child: Row(children: [
                Icon(cm.isWeekend ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                    color: weekendColor, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(cm.sessionNote,
                    style: TextStyle(color: weekendColor, fontSize: 11))),
              ]),
            ),
            const SizedBox(height: 10),
            _Row2Col(
                left: _DetailRow('24h Change',
                    '${cm.change24hPct >= 0 ? "+" : ""}${cm.change24hPct.toStringAsFixed(2)}%',
                    cm.change24hPct >= 0 ? AppColors.bullish : AppColors.bearish),
                right: _DetailRow('Weekend',
                    cm.isWeekend ? 'YES — thin liquidity' : 'NO', weekendColor)),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('VOLUME DELTA ENGINE'),
            _pill(cm.volumeDeltaSignal.replaceAll('_', ' '), vdc),
            const SizedBox(height: 10),
            _VolumeDeltaBar(buyVolume: cm.buyVolume, sellVolume: cm.sellVolume),
            const SizedBox(height: 10),
            _Row2Col(
                left: _DetailRow('Buy Volume', _fmtVolume(cm.buyVolume), AppColors.bullish),
                right: _DetailRow('Sell Volume', _fmtVolume(cm.sellVolume), AppColors.bearish)),
            _Row2Col(
                left: _DetailRow('Net Delta', _fmtVolume(cm.volumeDelta),
                    cm.volumeDelta >= 0 ? AppColors.bullish : AppColors.bearish),
                right: _DetailRow('Delta %',
                    '${cm.volumeDeltaPct >= 0 ? "+" : ""}${cm.volumeDeltaPct.toStringAsFixed(1)}%',
                    cm.volumeDeltaPct >= 0 ? AppColors.bullish : AppColors.bearish)),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('CRYPTO VOLATILITY BAND (CAVB ±2.5σ)'),
            _pill('CAVB ${cm.cavbSignal}', cavbC),
            const SizedBox(height: 10),
            _Row2Col(
                left: _DetailRow('CAVB Position',
                    cm.cavbPosition.replaceAll('_', ' '), _cavbPosColor(cm.cavbPosition)),
                right: _DetailRow('Norm. BW / ATR',
                    cm.normalizedBandwidth.toStringAsFixed(2), cavbC)),
            _Row2Col(
                left: _DetailRow('CAVB Upper', _fmtLevel(cm.cavbUpper, mi.assetType),
                    AppColors.bearish),
                right: _DetailRow('CAVB Lower', _fmtLevel(cm.cavbLower, mi.assetType),
                    AppColors.bullish)),
          ]),
        );
      },
    );
  }
}

class _VolumeDeltaBar extends StatelessWidget {
  const _VolumeDeltaBar({required this.buyVolume, required this.sellVolume});
  final double buyVolume;
  final double sellVolume;
  @override
  Widget build(BuildContext context) {
    final total = buyVolume + sellVolume;
    final buyPct = total > 0 ? (buyVolume / total * 100).clamp(0.0, 100.0) : 50.0;
    final sellPct = 100.0 - buyPct;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('SELL  ${sellPct.toStringAsFixed(1)}%', style: _mono(AppColors.bearish, 10)),
        const Text('VOLUME DELTA',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 9, letterSpacing: 1.5)),
        Text('${buyPct.toStringAsFixed(1)}%  BUY', style: _mono(AppColors.bullish, 10)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 6,
          color: Colors.white.withOpacity(0.04),
          child: Row(children: [
            Expanded(
                flex: sellPct.toInt().clamp(1, 99),
                child: Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [AppColors.bearish, AppColors.bearish.withOpacity(0.3)])))),
            Expanded(
                flex: buyPct.toInt().clamp(1, 99),
                child: Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [AppColors.bullish.withOpacity(0.3), AppColors.bullish])))),
          ]),
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  13. FOREX METRICS CARD
// ════════════════════════════════════════════════════════════════════════════
class _ForexMetricsCard extends StatelessWidget {
  const _ForexMetricsCard();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        final fm = mi?.forexMetrics;
        if (mi == null || fm == null) return const SizedBox.shrink();
        final overlapColor = fm.isOverlapSession ? AppColors.bullish : AppColors.textSecondary;
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(
                title: 'Forex Intelligence',
                icon: Icons.currency_exchange,
                trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.primary.withOpacity(0.25))),
                    child: Text(fm.isJpyPair ? 'JPY PAIR' : 'MAJOR FX',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2)))),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: overlapColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: overlapColor.withOpacity(0.25))),
              child: Row(children: [
                Icon(fm.isOverlapSession ? Icons.bolt_rounded : Icons.schedule_outlined,
                    color: overlapColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fm.sessionOverlap,
                          style: TextStyle(
                              color: overlapColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                      if (fm.isOverlapSession)
                        const Text('PEAK LIQUIDITY — highest-probability entry window',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                    ])),
                if (fm.isOverlapSession)
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.bullish.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3)),
                      child: const Text('OVERLAP',
                          style: TextStyle(
                              color: AppColors.bullish,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1))),
              ]),
            ),
            const SizedBox(height: 10),
            _Row2Col(
                left: _DetailRow('Pip Size', fm.pipSize.toString(), AppColors.primary),
                right: _DetailRow('Pair Type',
                    fm.isJpyPair ? 'JPY (2dp)' : 'Standard (4dp)', AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow('24h Change',
                    '${fm.change24hPct >= 0 ? "+" : ""}${fm.change24hPct.toStringAsFixed(4)}%',
                    fm.change24hPct >= 0 ? AppColors.bullish : AppColors.bearish),
                right: _DetailRow('Session Status',
                    fm.isOverlapSession ? 'HIGH LIQUIDITY' : 'NORMAL', overlapColor)),
            if (!fm.isOverlapSession) ...[
              const SizedBox(height: 8),
              _ExplanationBox(
                  label: 'SESSION NOTE',
                  text:
                      'Current session: ${fm.sessionOverlap}. Wait for London-NY or Tokyo-London overlap for peak liquidity.',
                  accentColor: AppColors.textSecondary),
            ],
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  14. MOMENTUM SECTION
// ════════════════════════════════════════════════════════════════════════════
class _MomentumSection extends StatelessWidget {
  const _MomentumSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Momentum Indicators', icon: Icons.speed_rounded),
            _Row2Col(
                left: _DetailRow('RSI (14)', mi.rsi.toStringAsFixed(1), _rsiColor(mi.rsi)),
                right: _DetailRow('RSI Signal', mi.rsiSignal, _rsiColor(mi.rsi))),
            _Row2Col(
                left: _DetailRow('EMA Alignment', mi.emaAlignment, _emaColor(mi.emaAlignment)),
                right: _DetailRow('Supertrend', mi.supertrendSignal,
                    _signalColor(mi.supertrendSignal))),
            _Row2Col(
                left: _DetailRow('MACD Cross', mi.macdCross, _signalColor(mi.macdCross)),
                right: _DetailRow('MACD Hist', mi.macdHist.toStringAsFixed(4),
                    mi.macdHist >= 0 ? AppColors.bullish : AppColors.bearish)),
            _Row2Col(
                left: _DetailRow('Stoch %K', mi.stochK.toStringAsFixed(1), _stochColor(mi.stochK)),
                right: _DetailRow('Stoch Signal', mi.stochSignal,
                    _signalColor(mi.stochSignal))),
            _Row2Col(
                left: _DetailRow('ADX', mi.adxValue.toStringAsFixed(1), _adxColor(mi.adxValue)),
                right: _DetailRow('ADX Signal', mi.adxSignal, _adxColor(mi.adxValue))),
            _Row2Col(
                left: _DetailRow('Williams %R', mi.williamsR.toStringAsFixed(1),
                    _williamsColor(mi.williamsR)),
                right: _DetailRow('%R Signal', mi.williamsSignal,
                    _williamsColor(mi.williamsR))),
            _Row2Col(
                left: _DetailRow('CCI', mi.cciValue.toStringAsFixed(1), _cciColor(mi.cciValue)),
                right: _DetailRow('OBV Trend', mi.obvTrend, _signalColor(mi.obvTrend))),
            _Row2Col(
                left: _DetailRow('Ichimoku', mi.ichimokuSignal,
                    _signalColor(mi.ichimokuSignal)),
                right: _DetailRow('VWAP Signal', mi.vwapSignal, _signalColor(mi.vwapSignal))),
            _Row2Col(
                left: _DetailRow('BB Position', mi.bbPosition, AppColors.textPrimary),
                right: _DetailRow('TTM Squeeze', mi.ttmSqueezeLabel,
                    mi.ttmSqueezeActive ? AppColors.primary : AppColors.textSecondary)),
            const Divider(color: AppColors.border, height: 24),
            const _SubHeader('DIVERGENCE ENGINE'),
            _Row2Col(
                left: _DetailRow('RSI Div.', mi.rsiDivergence, _divColor(mi.rsiDivergence)),
                right: _DetailRow('MACD Div.', mi.macdDivergence, _divColor(mi.macdDivergence))),
            _Row2Col(
                left: _DetailRow('OBV Div.', mi.obvDivergence, _divColor(mi.obvDivergence)),
                right: _DetailRow('Master Div.', mi.divergenceSignal,
                    _divColor(mi.divergenceSignal))),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  15. SMART MONEY SECTION
// ════════════════════════════════════════════════════════════════════════════
class _SmartMoneySection extends StatelessWidget {
  const _SmartMoneySection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        final waveTarget = mi.waveTarget;
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Smart Money Concepts', icon: Icons.hub_rounded),
            _Row2Col(
                left: _DetailRow('SMC Bias', mi.smcBias, _biasColor(mi.smcBias)),
                right: _DetailRow('Order Blocks', '${mi.orderBlocks.length} active',
                    mi.orderBlocks.isNotEmpty ? AppColors.primary : AppColors.textSecondary)),
            _Row2Col(
                left: _DetailRow('FVG Count', '${mi.fairValueGaps.length}',
                    mi.fairValueGaps.isNotEmpty ? AppColors.primary : AppColors.textSecondary),
                right: _DetailRow('Liq. Sweeps', '${mi.liquiditySweeps.length}',
                    mi.liquiditySweeps.isNotEmpty ? AppColors.primary : AppColors.textSecondary)),
            _Row2Col(
                left: _DetailRow('Nearest Support',
                    _fmtLevel(mi.nearestSupport, mi.assetType), AppColors.bullish),
                right: _DetailRow('Nearest Resist.',
                    _fmtLevel(mi.nearestResist, mi.assetType), AppColors.bearish)),
            _Row2Col(
                left: _DetailRow('SR Zone', mi.srZone, AppColors.textPrimary),
                right: _DetailRow('Nearest Pivot',
                    mi.nearestPivotLevel.isNotEmpty ? mi.nearestPivotLevel : 'N/A',
                    AppColors.textPrimary)),
            const Divider(color: AppColors.border, height: 24),
            const _SubHeader('FIBONACCI & ELLIOTT WAVE'),
            _Row2Col(
                left: _DetailRow('Fib Zone', mi.fibZone, _fibColor(mi.fibZone)),
                right: _DetailRow('Fib Strength', mi.fibStrength.toStringAsFixed(1),
                    AppColors.primary)),
            _Row2Col(
                left: _DetailRow('Wave Position', mi.wavePosition, AppColors.textPrimary),
                right: _DetailRow('Wave Trend', mi.waveTrend, _biasColor(mi.waveTrend))),
            if (waveTarget != null)
              _Row2Col(
                  left: _DetailRow('Wave Target', _fmtLevel(waveTarget, mi.assetType),
                      AppColors.primary),
                  right: _DetailRow('Wave Conf.',
                      '${mi.waveConfidence.toStringAsFixed(0)}%', AppColors.textPrimary)),
            const Divider(color: AppColors.border, height: 24),
            const _SubHeader('CANDLESTICK PATTERN'),
            _Row2Col(
                left: _DetailRow('Pattern', mi.candlePattern,
                    mi.candlePattern != 'NONE' ? AppColors.primary : AppColors.textSecondary),
                right: _DetailRow('Pattern Dir.', mi.candleDirection,
                    _biasColor(mi.candleDirection))),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  16. MULTI-TIMEFRAME SECTION
// ════════════════════════════════════════════════════════════════════════════
class _MultiTimeframeSection extends StatelessWidget {
  const _MultiTimeframeSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        final confU = mi.mtfConfluence.toUpperCase();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Multi-Timeframe Confluence', icon: Icons.layers_rounded),
            _Row2Col(
                left: _DetailRow(
                    'MTF Confluence',
                    mi.mtfConfluence,
                    confU.contains('STRONG BULL')
                        ? AppColors.bullish
                        : confU.contains('STRONG BEAR')
                            ? AppColors.bearish
                            : AppColors.primary),
                right: _DetailRow('Bull / Bear TFs',
                    '${mi.mtfBullCount} / ${mi.mtfBearCount}',
                    mi.mtfBullCount > mi.mtfBearCount
                        ? AppColors.bullish
                        : AppColors.bearish)),
            if (mi.mtfSignals.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...mi.mtfSignals.entries.map((entry) {
                final value = entry.value;
                final sig = value is Map ? (value['signal']?.toString() ?? '---') : '---';
                final u = sig.toUpperCase();
                return _DetailRow(
                    'TF ${entry.key}',
                    sig,
                    u.contains('BULL')
                        ? AppColors.bullish
                        : u.contains('BEAR')
                            ? AppColors.bearish
                            : AppColors.textSecondary);
              }),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 4),
                child: Text('Enable MTF in scan settings for full confluence data.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
              ),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  17. SESSION & RISK SECTION
// ════════════════════════════════════════════════════════════════════════════
class _SessionRiskSection extends StatelessWidget {
  const _SessionRiskSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Session & Risk', icon: Icons.schedule_rounded),
            _Row2Col(
                left: _DetailRow('Session', mi.tradingSession, AppColors.primary),
                right: _DetailRow('Liquidity', mi.sessionLiquidity,
                    _liqColor(mi.sessionLiquidity))),
            _Row2Col(
                left: _DetailRow('Macro Sentiment', mi.macroSentimentLabel,
                    _macroColor(mi.macroSentimentLabel)),
                right: _DetailRow('Macro Score', '${mi.macroSentimentScore}/100',
                    AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow('Bull Hits', '${mi.macroBullHits}', AppColors.bullish),
                right: _DetailRow('Bear Hits', '${mi.macroBearHits}', AppColors.bearish)),
            if (mi.newsLockActive) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.bearish.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.bearish.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.bearish, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('NEWS LOCK · ${mi.newsLockEvent} — ${mi.newsLockReason}',
                          style: const TextStyle(color: AppColors.bearish, fontSize: 11))),
                ]),
              ),
            ],
            if (mi.sessionWarning.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ExplanationBox(label: 'SESSION WARNING', text: mi.sessionWarning,
                  accentColor: AppColors.primary),
            ],
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  18. ECONOMIC CALENDAR SECTION
// ════════════════════════════════════════════════════════════════════════════
class _CalendarSection extends StatelessWidget {
  const _CalendarSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final events = state.upcomingEvents;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 16,
                AppConstants.screenPadding, 8),
            child: Row(children: [
              const Icon(Icons.event_busy, color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              const Text('ECONOMIC CALENDAR',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.8)),
              const Spacer(),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2))),
                  child: Text('${events.length} EVENTS',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1))),
            ]),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border)),
                child: const Row(children: [
                  Icon(Icons.event_available, color: AppColors.textSecondary, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text('No high-impact events in the next 7 days',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
                ]),
              ),
            )
          else
            ...events.take(5).map((e) => _CalendarEventCard(event: e)),
        ]);
      },
    );
  }
}

class _CalendarEventCard extends StatelessWidget {
  const _CalendarEventCard({required this.event});
  final EconomicEvent event;
  @override
  Widget build(BuildContext context) {
    final isHigh = event.isHighImpact;
    final impactColor = isHigh ? AppColors.bearish : AppColors.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 0,
          AppConstants.screenPadding, 8),
      decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
      child: Stack(children: [
        Positioned(
          left: 0, top: 0, bottom: 0, width: 3,
          child: Container(
            decoration: BoxDecoration(
                color: impactColor,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12).copyWith(left: 15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: impactColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: impactColor.withOpacity(0.4))),
                  child: Text(isHigh ? '🔴 HIGH IMPACT' : '🟡 MEDIUM',
                      style: TextStyle(
                          color: impactColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1))),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(event.country,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5))),
              Text(event.datetime, style: _mono(AppColors.primary, 10, FontWeight.w500)),
            ]),
            const SizedBox(height: 8),
            Text(event.event,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3)),
            if (event.estimate.isNotEmpty || event.prev.isNotEmpty || event.actual.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                if (event.estimate.isNotEmpty)
                  Expanded(child: _EventDataPoint(label: 'ESTIMATE', value: event.estimate, color: AppColors.primary)),
                if (event.prev.isNotEmpty)
                  Expanded(child: _EventDataPoint(label: 'PREVIOUS', value: event.prev, color: AppColors.textSecondary)),
                if (event.actual.isNotEmpty)
                  Expanded(child: _EventDataPoint(label: 'ACTUAL', value: event.actual, color: AppColors.bullish)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _EventDataPoint extends StatelessWidget {
  const _EventDataPoint({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: color.withOpacity(0.6),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0)),
      const SizedBox(height: 2),
      Text(value, style: _mono(color, 12, FontWeight.w900)),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  19. EXPLANATIONS SECTION
// ════════════════════════════════════════════════════════════════════════════
class _ExpBlock {
  const _ExpBlock(this.label, this.text, this.icon, this.color);
  final String label;
  final String text;
  final IconData icon;
  final Color color;
}

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
            _ExpBlock('ENTRY LOGIC', mi.entryExplanation, Icons.flag_rounded, AppColors.primary),
          if (mi.smcExplanation.isNotEmpty)
            _ExpBlock('SMART MONEY', mi.smcExplanation, Icons.hub_rounded, AppColors.bullish),
          if (mi.fibExplanation.isNotEmpty)
            _ExpBlock('FIBONACCI', mi.fibExplanation, Icons.show_chart, AppColors.primary),
          if (mi.candleExplanation.isNotEmpty)
            _ExpBlock('CANDLESTICK', mi.candleExplanation, Icons.bar_chart_rounded,
                AppColors.textPrimary),
          if (mi.rsiExplanation.isNotEmpty)
            _ExpBlock('RSI', mi.rsiExplanation, Icons.speed_rounded, _rsiColor(mi.rsi)),
          if (mi.atrExplanation.isNotEmpty)
            _ExpBlock('ATR / STOPS', mi.atrExplanation, Icons.adjust_rounded,
                AppColors.textSecondary),
          if (mi.sessionExplanation.isNotEmpty)
            _ExpBlock('SESSION', mi.sessionExplanation, Icons.schedule_rounded,
                AppColors.primary),
        ];
        if (blocks.isEmpty) return const SizedBox.shrink();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Quantum Reasoning', icon: Icons.auto_awesome),
            const SizedBox(height: 8),
            ...blocks.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExplanationBox(label: b.label, text: b.text,
                      accentColor: b.color, leadIcon: b.icon),
                )),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  20. VOLATILITY SECTION
// ════════════════════════════════════════════════════════════════════════════
class _VolatilitySection extends StatelessWidget {
  const _VolatilitySection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final mi = state.lastAnalysis?.intelligence;
        if (mi == null) return const SizedBox.shrink();
        final at = mi.assetType;
        final slBuy = mi.slBuy;
        final slSell = mi.slSell;
        final tpBuy = mi.tpBuy;
        final tpSell = mi.tpSell;
        final bbPosU = mi.bbPosition.toUpperCase();
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Volatility Framework', icon: Icons.bar_chart_rounded),
            const _SubHeader('BOLLINGER BANDS (20,2)'),
            _Row2Col(
                left: _DetailRow('Upper', _fmtLevel(mi.bbUpper, at), AppColors.bearish),
                right: _DetailRow('Mid (SMA)', _fmtLevel(mi.bbMid, at), Colors.white70)),
            _Row2Col(
                left: _DetailRow('Lower', _fmtLevel(mi.bbLower, at), AppColors.bullish),
                right: _DetailRow('Width %', mi.bbWidth.toStringAsFixed(3),
                    AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow(
                    'Position',
                    mi.bbPosition,
                    bbPosU.contains('ABOVE')
                        ? AppColors.bearish
                        : bbPosU.contains('BELOW')
                            ? AppColors.bullish
                            : AppColors.textSecondary),
                right: _DetailRow('Squeeze', mi.bbSqueeze ? 'ACTIVE' : 'OFF',
                    mi.bbSqueeze ? AppColors.primary : AppColors.textSecondary)),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('KELTNER CHANNELS (20, 1.5×ATR)'),
            _Row2Col(
                left: _DetailRow('KC Upper', _fmtLevel(mi.kcUpper, at), AppColors.bearish),
                right: _DetailRow('KC Mid', _fmtLevel(mi.kcMid, at), Colors.white70)),
            _DetailRow('KC Lower', _fmtLevel(mi.kcLower, at), AppColors.bullish),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('TTM SQUEEZE'),
            _Row2Col(
                left: _DetailRow('Status',
                    mi.ttmSqueezeActive ? '🔴 SQUEEZE ON' : '🟢 SQUEEZE OFF',
                    mi.ttmSqueezeActive ? AppColors.primary : AppColors.textSecondary),
                right: _DetailRow('Momentum', mi.ttmMomentum.toStringAsFixed(4),
                    mi.ttmMomentum >= 0 ? AppColors.bullish : AppColors.bearish)),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('SUPERTREND (10, 3×ATR)'),
            _Row2Col(
                left: _DetailRow('Signal', mi.supertrendSignal,
                    _signalColor(mi.supertrendSignal)),
                right: _DetailRow('Line', _fmtLevel(mi.supertrendValue, at),
                    _signalColor(mi.supertrendSignal))),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('VWAP + ±2σ BANDS'),
            _Row2Col(
                left: _DetailRow('VWAP', _fmtLevel(mi.vwap, at), Colors.white),
                right: _DetailRow('VWAP Signal', mi.vwapSignal,
                    _signalColor(mi.vwapSignal))),
            _Row2Col(
                left: _DetailRow('VWAP Upper', _fmtLevel(mi.vwapUpper, at), AppColors.bearish),
                right: _DetailRow('VWAP Lower', _fmtLevel(mi.vwapLower, at), AppColors.bullish)),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('ATR & DYNAMIC STOPS'),
            _Row2Col(
                left: _DetailRow('ATR (14)', mi.atr14.toStringAsFixed(4), AppColors.primary),
                right: _DetailRow('SL Pips', mi.slPips.toStringAsFixed(1),
                    AppColors.textPrimary)),
            _Row2Col(
                left: _DetailRow('SL Buy', slBuy != null ? _fmtLevel(slBuy, at) : '---',
                    AppColors.bearish),
                right: _DetailRow('SL Sell', slSell != null ? _fmtLevel(slSell, at) : '---',
                    AppColors.bearish)),
            _Row2Col(
                left: _DetailRow('TP Buy', tpBuy != null ? _fmtLevel(tpBuy, at) : '---',
                    AppColors.bullish),
                right: _DetailRow('TP Sell', tpSell != null ? _fmtLevel(tpSell, at) : '---',
                    AppColors.bullish)),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  21. PIVOT POINTS SECTION
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
        double? val(String key) {
          final raw = pp[key];
          return raw is num ? raw.toDouble() : null;
        }

        String fmt(String key) {
          final v = val(key);
          return v == null ? '---' : _fmtLevel(v, mi.assetType);
        }

        final nearestColor = mi.nearestPivotLevel.startsWith('S')
            ? AppColors.bullish
            : mi.nearestPivotLevel.startsWith('R')
                ? AppColors.bearish
                : AppColors.primary;
        Widget pair(String lKey, String lLabel, String rKey, String rLabel, double alpha) {
          return _Row2Col(
            left: _DetailRow(lLabel, fmt(lKey), AppColors.bearish.withOpacity(alpha)),
            right: _DetailRow(rLabel, fmt(rKey), AppColors.bullish.withOpacity(alpha)),
          );
        }

        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(
                title: 'Pivot Points',
                icon: Icons.table_chart_rounded,
                trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: nearestColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: nearestColor.withOpacity(0.3))),
                    child: Text(
                        'NEAREST: ${mi.nearestPivotLevel}  ${mi.nearestPivotDist.toStringAsFixed(2)}%',
                        style: _mono(nearestColor, 9)))),
            const _SubHeader('CLASSIC PIVOTS'),
            _Row2Col(
                left: _DetailRow('PP', fmt('PP'), AppColors.primary),
                right: const SizedBox.shrink()),
            pair('R1', 'R1', 'S1', 'S1', 1.0),
            pair('R2', 'R2', 'S2', 'S2', 0.7),
            pair('R3', 'R3', 'S3', 'S3', 0.5),
            const Divider(color: AppColors.border, height: 20),
            const _SubHeader('FIBONACCI PIVOTS'),
            pair('FR1', 'FR1 (38.2%)', 'FS1', 'FS1 (38.2%)', 0.8),
            pair('FR2', 'FR2 (61.8%)', 'FS2', 'FS2 (61.8%)', 0.6),
            pair('FR3', 'FR3 (100%)', 'FS3', 'FS3 (100%)', 0.4),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  22. AI PLAN SECTION
// ════════════════════════════════════════════════════════════════════════════
class _AiPlanSection extends StatefulWidget {
  const _AiPlanSection();
  @override
  State<_AiPlanSection> createState() => _AiPlanSectionState();
}

class _AiPlanSectionState extends State<_AiPlanSection> {
  String? _requestedKey;
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final key = '${state.selectedSymbol}_${state.timeframe}';
        if (state.aiPlan == null && !state.loadingAiPlan && _requestedKey != key) {
          _requestedKey = key;
          Future.microtask(() {
            if (mounted) context.read<MarketState>().loadAiPlan();
          });
        }
        final plan = state.aiPlan;
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 12,
              AppConstants.screenPadding, 0),
          child: state.loadingAiPlan && plan == null
              ? const AiPlanSkeleton()
              : plan == null
                  ? const SizedBox.shrink()
                  : AiPlanCard(plan: plan, onRegenerate: () => state.loadAiPlan(force: true)),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  23. NEWS FEED SECTION
// ════════════════════════════════════════════════════════════════════════════
class _NewsSection extends StatelessWidget {
  const _NewsSection();
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketState>(
      builder: (context, state, _) {
        final news = state.currentNews.isNotEmpty
            ? state.currentNews
            : (state.lastAnalysis?.news ?? const <NewsItem>[]);
        if (news.isEmpty) return const SizedBox.shrink();
        final avg = news.fold<double>(0.0, (s, n) => s + n.sentimentScore) / news.length;
        final sentColor = avg > 0.1
            ? AppColors.bullish
            : avg < -0.1
                ? AppColors.bearish
                : AppColors.textSecondary;
        final sentLabel =
            avg > 0.1 ? 'BULLISH' : avg < -0.1 ? 'BEARISH' : 'NEUTRAL';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 16,
                AppConstants.screenPadding, 8),
            child: Row(children: [
              const Icon(Icons.newspaper_rounded, color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              const Text('MARKET INTELLIGENCE FEED',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.8)),
              const Spacer(),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: sentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: sentColor.withOpacity(0.3))),
                  child: Text('${news.length} • $sentLabel',
                      style: TextStyle(
                          color: sentColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1))),
            ]),
          ),
          ...news.take(10).map((item) => _NewsCard(item: item)),
        ]);
      },
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});
  final NewsItem item;
  Future<void> _open() async {
    if (item.url.isEmpty) return;
    final uri = Uri.tryParse(item.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catColor = item.categoryColor;
    final sentU = item.sentimentLabel.toUpperCase();
    final sentColor = sentU.contains('BULL')
        ? AppColors.bullish
        : sentU.contains('BEAR')
            ? AppColors.bearish
            : AppColors.textSecondary;
    final actColor = _actionColor(item.quantAction);
    return GestureDetector(
      onTap: _open,
      child: Container(
        margin: const EdgeInsets.fromLTRB(AppConstants.screenPadding, 0,
            AppConstants.screenPadding, 10),
        decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
        child: Stack(children: [
          Positioned(
            left: 0, top: 0, bottom: 0, width: 3,
            child: Container(
              decoration: BoxDecoration(
                  color: catColor,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12).copyWith(left: 15),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: catColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: catColor.withOpacity(0.3))),
                    child: Text(item.category,
                        style: TextStyle(
                            color: catColor,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1))),
                const SizedBox(width: 6),
                Expanded(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                            value: (item.impactPercentage / 100).clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: catColor.withOpacity(0.1),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(catColor.withOpacity(0.7))))),
                const SizedBox(width: 6),
                Text('${item.impactPercentage.toStringAsFixed(0)}%',
                    style: _mono(catColor, 9)),
                const SizedBox(width: 8),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: sentColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(3)),
                    child: Text(item.sentimentLabel.replaceAll('_', ' '),
                        style: TextStyle(
                            color: sentColor, fontSize: 8, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 8),
              Text(item.title,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12, height: 1.4)),
              const SizedBox(height: 6),
              if (item.nexusComment.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary.withOpacity(0.12))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 11),
                    const SizedBox(width: 5),
                    Expanded(
                        child: Text(item.nexusComment,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                height: 1.4))),
                  ]),
                ),
              const SizedBox(height: 6),
              Row(children: [
                Flexible(
                    child: Text(item.source,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10))),
                const SizedBox(width: 8),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: actColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: actColor.withOpacity(0.25))),
                    child: Text(item.quantAction,
                        style: TextStyle(
                            color: actColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5))),
                const Spacer(),
                Text(item.published,
                    style: _mono(AppColors.textSecondary, 9, FontWeight.w400)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE LOCAL WIDGETS
// ════════════════════════════════════════════════════════════════════════════
class _MetricChip extends StatelessWidget {
  const _MetricChip(
      {required this.label, required this.value, required this.color, this.suffix = ''});
  final String label;
  final String value;
  final String suffix;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(color, 13, FontWeight.w900))),
          if (suffix.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(bottom: 1, left: 2),
                child: Text(suffix,
                    style: _mono(color.withOpacity(0.7), 9, FontWeight.w500))),
        ]),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, this.valueColor);
  final String label;
  final String value;
  final Color valueColor;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        const SizedBox(width: 8),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right, style: _mono(valueColor, 12))),
      ]),
    );
  }
}

class _Row2Col extends StatelessWidget {
  const _Row2Col({required this.left, required this.right});
  final Widget left;
  final Widget right;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      Expanded(child: right),
    ]);
  }
}

class _PriceLevel extends StatelessWidget {
  const _PriceLevel(
      {required this.label, required this.value, required this.color, this.assetType = ''});
  final String label;
  final double value;
  final Color color;
  final String assetType;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 4),
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_fmtLevel(value, assetType),
                style: _mono(color, 13, FontWeight.w900))),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label, required this.value, this.valueColor = AppColors.textPrimary});
  final String label;
  final String value;
  final Color valueColor;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 9, letterSpacing: 1)),
      const SizedBox(height: 4),
      Text(value, style: _mono(valueColor, 12)),
    ]);
  }
}

class _ExplanationBox extends StatelessWidget {
  const _ExplanationBox(
      {required this.label, required this.text, required this.accentColor, this.leadIcon});
  final String label;
  final String text;
  final Color accentColor;
  final IconData? leadIcon;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
          color: accentColor.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentColor.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (leadIcon != null) ...[
            Icon(leadIcon, color: accentColor, size: 11),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  color: accentColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 6),
        Text(text,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                height: 1.5,
                fontStyle: FontStyle.italic)),
      ]),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.8)),
    );
  }
}