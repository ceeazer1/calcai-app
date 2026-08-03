import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The CalcAI face mark — a plus eye, a dash eye, and a smile.
///
/// Drawn rather than loaded from an asset so it stays sharp at any size and
/// can be recoloured for light or dark surfaces. The geometry matches the app
/// icon, expressed in fractions of the box so one set of numbers serves every
/// size.
class CalcAiMark extends StatelessWidget {
  const CalcAiMark({
    super.key,
    this.size = 64,
    this.background = const Color(0xFF000000),
    this.foreground = const Color(0xFFFFFFFF),
    this.cornerRadius,
  });

  final double size;

  /// Tile colour. Pass [Colors.transparent] to draw the face on its own.
  final Color background;
  final Color foreground;

  /// Corner rounding of the tile. Defaults to iOS-like ~22% of the size.
  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          background: background,
          foreground: foreground,
          radius: cornerRadius ?? size * 0.22,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.background,
    required this.foreground,
    required this.radius,
  });

  final Color background;
  final Color foreground;
  final double radius;

  // Fractions of the box, taken from the icon artwork.
  static const _plusC = Offset(0.373, 0.388);
  static const _plusArm = 0.1025; // half-length
  static const _plusTh = 0.0415; // half-thickness
  static const _dashC = Offset(0.640, 0.390);
  static const _dashW = 0.1045;
  static const _dashH = 0.0423;
  static const _smileC = Offset(0.508, 0.461);
  static const _smileOuter = 0.2197;
  static const _smileInner = 0.1338;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final fill = Paint()..color = foreground..isAntiAlias = true;

    if (background.alpha != 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        Paint()..color = background,
      );
    }

    Offset at(Offset f) => Offset(f.dx * s, f.dy * s);

    // Plus eye — two bars crossing.
    final pc = at(_plusC);
    canvas.drawRect(
      Rect.fromCenter(
          center: pc, width: _plusTh * 2 * s, height: _plusArm * 2 * s),
      fill,
    );
    canvas.drawRect(
      Rect.fromCenter(
          center: pc, width: _plusArm * 2 * s, height: _plusTh * 2 * s),
      fill,
    );

    // Dash eye.
    canvas.drawRect(
      Rect.fromCenter(
        center: at(_dashC),
        width: _dashW * 2 * s,
        height: _dashH * 2 * s,
      ),
      fill,
    );

    // Smile — a stroked arc. A butt cap gives the square-cut ends the
    // artwork has, and stroking is exact where two filled pie slices would
    // leave a seam.
    final mid = (_smileOuter + _smileInner) / 2 * s;
    canvas.drawArc(
      Rect.fromCircle(center: at(_smileC), radius: mid),
      17.6 * math.pi / 180, // start, clockwise from 3 o'clock
      144.8 * math.pi / 180, // sweep
      false,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = (_smileOuter - _smileInner) * s
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.background != background ||
      old.foreground != foreground ||
      old.radius != radius;
}
