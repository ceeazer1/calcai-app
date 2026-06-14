import 'package:flutter/material.dart';

/// Centralized color palette for the CalcAI app.
///
/// All colors use a sleek silver, gray, and black palette
/// for a premium monochrome aesthetic.
abstract final class AppColors {
  // ── Primary Background ──────────────────────────────────────────────
  static const Color background = Color(0xFF09090B);
  static const Color surface = Color(0xFF111113);
  static const Color surfaceLight = Color(0xFF1C1C1F);
  static const Color surfaceHighlight = Color(0xFF27272A);

  // ── Accent Colors ──────────────────────────────────────────────────
  static const Color electricBlue = Color(0xFFD4D4DC);   // Platinum silver
  static const Color purple = Color(0xFF8A8A96);          // Muted silver
  static const Color cyan = Color(0xFFE8E8F0);            // Bright silver
  static const Color magenta = Color(0xFFA1A1AB);         // Warm silver

  // ── Semantic Colors ────────────────────────────────────────────────
  static const Color success = Color(0xFF00E676);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFAB40);
  static const Color info = Color(0xFFA1A1AB);

  // ── Text Colors ────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFF8E8E96);
  static const Color textTertiary = Color(0xFF52525B);
  static const Color textOnAccent = Color(0xFF09090B);

  // ── Glass / Overlay ────────────────────────────────────────────────
  static const Color glassBackground = Color(0x1AFFFFFF); // 10% white
  static const Color glassBorder = Color(0x33FFFFFF);      // 20% white
  static const Color glassBorderLight = Color(0x1AFFFFFF); // 10% white
  static const Color glassHighlight = Color(0x0DFFFFFF);   // 5% white
  static const Color scrim = Color(0xCC09090B);            // 80% background

  // ── Gradients ──────────────────────────────────────────────────────

  /// The primary accent gradient used for buttons and highlights.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFE4E4EC), Color(0xFF71717A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// A softer accent gradient for backgrounds and large surfaces.
  static const LinearGradient accentGradientSoft = LinearGradient(
    colors: [Color(0x33D4D4DC), Color(0x338A8A96)],
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
    colors: [Color(0x33D4D4DC), Color(0x00000000)],
    radius: 0.8,
  );

  /// Background gradient overlay for screens.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [
      Color(0xFF09090B),
      Color(0xFF111113),
      Color(0xFF09090B),
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
