// ============================================================================
//  NEXUS v13.1 FINAL — app.dart
//  Root widget that configures theme, routing, and the main home screen.
//
//  Architecture:
//  ─────────────────────────────────────────────────────────────────────────
//  • HomeShell (lib/screens/home_shell.dart)
//    → Fast dashboard (watchlist + chart + signal card)
//    → Responsive: DesktopDashboard / MobileTerminal
//
//  • TradingScreen (lib/screens/trading_screen.dart)
//    → Deep analysis (18 sections: volatility, SMC, pivots, news, etc.)
//    → Accessible via "FULL ANALYSIS" button on HomeShell
//  ============================================================================

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'screens/home_shell.dart';
import 'screens/trading_screen.dart';

class NexusQuantumApp extends StatelessWidget {
  const NexusQuantumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXUS Quantum Terminal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // v13.1: HomeShell is the main dashboard
      home: const HomeShell(),
      // Named routes for navigation
      routes: {
        '/analysis': (ctx) => const TradingScreen(),
      },
    );
  }
}
