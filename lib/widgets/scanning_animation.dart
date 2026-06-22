import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An animated radar / pulse effect for the BLE scanning screen.
///
/// Draws concentric expanding rings with fading opacity over a
/// central icon, giving a real radar-sweep impression.
class ScanningAnimation extends StatefulWidget {
  /// Creates a [ScanningAnimation].
  const ScanningAnimation({
    super.key,
    this.size = 280,
    this.isScanning = true,
    this.ringCount = 4,
    this.color = AppColors.electricBlue,
    this.child,
  });

  /// Outer dimension of the animation.
  final double size;

  /// Whether the animation is active.
  final bool isScanning;

  /// Number of expanding pulse rings.
  final int ringCount;

  /// Pulse ring color.
  final Color color;

  /// Optional center widget (e.g. an icon).
  final Widget? child;

  @override
  State<ScanningAnimation> createState() => _ScanningAnimationState();
}

class _ScanningAnimationState extends State<ScanningAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (widget.isScanning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ScanningAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isScanning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              ringCount: widget.ringCount,
              color: widget.color,
              isActive: widget.isScanning,
            ),
            child: Center(child: widget.child),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.progress,
    required this.ringCount,
    required this.color,
    required this.isActive,
  });

  final double progress;
  final int ringCount;
  final Color color;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // ── Static grid rings ──────────────────────────────────────────
    final gridPaint = Paint()
      ..color = color.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * (i / 4), gridPaint);
    }

    // ── Cross-hairs ────────────────────────────────────────────────
    final crossPaint = Paint()
      ..color = color.withOpacity(0.04)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      crossPaint,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      crossPaint,
    );

    if (!isActive) return;

    // ── Expanding pulse rings ──────────────────────────────────────
    // Each ring eases outward, fading IN from the center and OUT at the
    // edge (sine envelope) so rings never pop on birth or death — the
    // loop stays seamless.
    for (int i = 0; i < ringCount; i++) {
      final phaseOffset = i / ringCount;
      final ringProgress = (progress + phaseOffset) % 1.0;
      final eased = Curves.easeOutCubic.transform(ringProgress);
      final radius = maxRadius * eased;
      final opacity = math.sin(math.pi * ringProgress) * 0.35;

      final ringPaint = Paint()
        ..color = color.withOpacity(opacity.clamp(0.0, 0.35))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - ringProgress) + 0.6;

      canvas.drawCircle(center, radius, ringPaint);
    }

    // ── Sweep arc ──────────────────────────────────────────────────
    final sweepAngle = progress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.8,
        endAngle: sweepAngle,
        colors: [
          color.withOpacity(0.0),
          color.withOpacity(0.15),
        ],
        transform: GradientRotation(sweepAngle - 0.8),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);

    // ── Scanning line ──────────────────────────────────────────────
    final linePaint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final lineEnd = Offset(
      center.dx + maxRadius * math.cos(sweepAngle),
      center.dy + maxRadius * math.sin(sweepAngle),
    );

    canvas.drawLine(center, lineEnd, linePaint);

    // ── Center glow (gentle breathing) ─────────────────────────────
    final pulse = 0.5 + 0.5 * math.sin(progress * 2 * math.pi);
    final glowRadius = maxRadius * (0.16 + 0.05 * pulse);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(0.18 + 0.10 * pulse),
          color.withOpacity(0.0),
        ],
        radius: 0.5,
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));

    canvas.drawCircle(center, glowRadius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isActive != isActive;
  }
}
