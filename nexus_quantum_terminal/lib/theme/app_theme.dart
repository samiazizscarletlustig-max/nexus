// ============================================================================
//  NEXUS v11.2 — app_theme.dart
//  Strict OLED black + Bloomberg gold + neon signal accents.
//  No changes from v11.1 — reproduced in full for completeness.
// ============================================================================

import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color oledBlack  = Color(0xFF000000);
  static const Color panel      = Color(0xFF0A0A0A);
  static const Color border     = Color(0xFF1A1A1A);
  static const Color gold       = Color(0xFFD4AF37);
  static const Color goldDim    = Color(0xFF8A7428);
  static const Color textPrimary = Color(0xFFE8E8E8);
  static const Color textMuted  = Color(0xFF6B6B6B);
  static const Color signalBuy  = Color(0xFF00FF88);
  static const Color signalSell = Color(0xFFFF3131);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: oledBlack,
        colorScheme: const ColorScheme.dark(
          surface:   panel,
          primary:   gold,
          secondary: signalBuy,
          error:     signalSell,
          onSurface: textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: oledBlack,
          foregroundColor: gold,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily:  'monospace',
            fontSize:    18,
            fontWeight:  FontWeight.w700,
            letterSpacing: 1.2,
            color:       gold,
          ),
        ),
        dividerColor: border,
        cardTheme: CardTheme(
          color:     panel,
          elevation: 0,
          shape:     RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: border, width: 1),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: goldDim,
          textColor: textPrimary,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: panel,
          contentTextStyle: const TextStyle(color: textPrimary),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: goldDim, width: 0.5),
          ),
        ),
        fontFamily: 'Roboto',
      );
}