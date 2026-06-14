import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

/// Root widget for the CalcAI application.
///
/// Applies the dark theme and sets up the initial route
/// to the [SplashScreen].
class CalcAIApp extends StatelessWidget {
  const CalcAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalcAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
