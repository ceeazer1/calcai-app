import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A frosted-glass card with a subtle gradient border.
///
/// Uses [BackdropFilter] + [ClipRRect] to achieve a premium glassmorphism
/// look on the CalcAI dark background.
class GlassCard extends StatelessWidget {
  /// Creates a [GlassCard].
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 20.0,
    this.blurAmount = 24.0,
    this.onTap,
    this.gradient,
    this.showBorderGradient = true,
  });

  /// Card contents.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  /// Outer margin.
  final EdgeInsetsGeometry margin;

  /// Corner radius.
  final double borderRadius;

  /// Gaussian blur sigma.
  final double blurAmount;

  /// Optional tap handler — adds a ripple effect.
  final VoidCallback? onTap;

  /// Optional custom background gradient.
  final Gradient? gradient;

  /// Whether to show the gradient border effect.
  final bool showBorderGradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurAmount,
            sigmaY: blurAmount,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: gradient ??
                  LinearGradient(
                    colors: [
                      AppColors.glassBackground,
                      AppColors.glassHighlight,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
              border: showBorderGradient
                  ? Border.all(color: AppColors.glassBorder, width: 0.5)
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                splashColor: AppColors.electricBlue.withOpacity(0.1),
                highlightColor: AppColors.electricBlue.withOpacity(0.05),
                child: Padding(
                  padding: padding,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
