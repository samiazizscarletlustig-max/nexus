// ============================================================================
//  NEXUS v11.2 — ad_placeholders.dart
//  AdMob slot placeholders.
//  No changes from v11.1 — reproduced in full for completeness.
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bottom strip — replace inner `Placeholder` with `BannerAd` from
/// `google_mobile_ads` on Android.
class AdBannerPlaceholder extends StatelessWidget {
  const AdBannerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panel,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: const Text(
          'ADMOB BANNER SLOT · ca. 320×50 / adaptive',
          style: TextStyle(
            color:       AppTheme.textMuted,
            fontSize:    10,
            letterSpacing: 1.2,
            fontWeight:  FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Call after a Quantum Scan completes — swap body for real
/// `InterstitialAd.load`.
Future<void> showInterstitialPlaceholder(BuildContext context) async {
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context:         context,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.ads_click, color: AppTheme.gold, size: 36),
          const SizedBox(height: 12),
          const Text(
            'INTERSTITIAL PLACEHOLDER',
            style: TextStyle(
              color:       AppTheme.gold,
              fontWeight:  FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hook google_mobile_ads here after analysis completes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color:    Colors.white.withOpacity(0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('DISMISS'),
          ),
        ],
      ),
    ),
  );
}