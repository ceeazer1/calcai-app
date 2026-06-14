import 'package:flutter/material.dart';

/// Centralized color palette for the CalcAI app.
///
/// All colors are derived from a deep navy dark theme with
/// electric blue-to-purple accent gradients.
abstract final class AppColors {
  // ── Primary Background ──────────────────────────────────────────────
  static const Color background = Color(0xFF0A0E1A);
  static const Color surface = Color(0xFF111627);
  static const Color surfaceLight = Color(0xFF1A2035);
  static const Color surfaceHighlight = Color(0xFF232A42);

  // ── Accent Colors ──────────────────────────────────────────────────
  static const Color electricBlue = Color(0xFF00D4FF);
  static const Color purple = Color(0xFF7B61FF);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color magenta = Color(0xFFBB86FC);

  // ── Semantic Colors ────────────────────────────────────────────────
  static const Color success = Color(0xFF00E676);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFAB40);
  static const Color info = Color(0xFF448AFF);

  // ── Text Colors ────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF8E95A9);
  static const Color textTertiary = Color(0xFF5A6178);
  static const Color textOnAccent = Color(0xFF0A0E1A);

  // ── Glass / Overlay ────────────────────────────────────────────────
  static const Color glassBackground = Color(0x1AFFFFFF); // 10% white
  static const Color glassBorder = Color(0x33FFFFFF);      // 20% white
  static const Color glassBorderLight = Color(0x1AFFFFFF); // 10% white
  static const Color glassHighlight = Color(0x0DFFFFFF);   // 5% white
  static const Color scrim = Color(0xCC0A0E1A);            // 80% background

  // ── Gradients ──────────────────────────────────────────────────────

  /// The primary accent gradient used for buttons and highlights.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [electricBlue, purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// A softer accent gradient for backgrounds and large surfaces.
  static const LinearGradient accentGradientSoft = LinearGradient(
    colors: [Color(0x3300D4FF), Color(0x337B61FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle border gradient used on glass cards.
  static const LinearGradient glassBorderGradient = LinearGradient(
    colors: [
      Color(0x66FFFFFF),
      Color(0x0DFFFFFF),
      Color(0x33FFFFFF),
    ],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Radial glow used behind accent elements.
  static const RadialGradient accentGlow = RadialGradient(
    colors: [Color(0x3300D4FF), Color(0x00000000)],
    radius: 0.8,
  );

  /// Background gradient overlay for screens.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [
      Color(0xFF0A0E1A),
      Color(0xFF0F1528),
      Color(0xFF0A0E1A),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Signal-strength color helper.
  static Color signalColor(int rssi) {
    if (rssi >= -50) return success;
    if (rssi >= -70) return electricBlue;
    if (rssi >= -85) return warning;
    return error;
  }
}
