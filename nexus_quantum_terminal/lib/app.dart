import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/trading_screen.dart';

class NexusQuantumApp extends StatelessWidget {
  const NexusQuantumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXUS Quantum Terminal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const TradingScreen(),
    );
  }
}
