import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/market_state.dart';
import 'screens/trading_screen.dart';
import 'theme/app_theme.dart';

void main() {
  // ضمان تهيئة Widgets قبل تشغيل التطبيق
  WidgetsFlutterBinding.ensureInitialized();
  
  // تثبيت اتجاه الشاشة ووضع شريط الحالة ليتناسب مع التصميم الداكن الفاخر
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  
  runApp(const NexusApp());
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MarketState(),
      child: MaterialApp(
        title: 'NEXUS Quantum Terminal',
        debugShowCheckedModeBanner: false,
        
        // ✅ التصحيح الجذري: استخدام نظام التصميم الجديد بالكامل (Notion + Big Brokers Style)
        // هذا يطبق الخلفية #0A0E17، البطاقات #1A1F2E، والخطوط الاحترافية تلقائياً
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, // فرض الوضع الداكن لضمان مظهر التداول الاحترافي
        
        home: const TradingScreen(),
      ),
    );
  }
}