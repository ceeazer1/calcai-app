import 'package:flutter/material.dart';

/// The CalcAI logo.
///
/// Renders the same artwork as the app icon (`assets/icon/app_icon.png`), so
/// the mark inside the app and the icon on the home screen can never drift
/// apart. This used to be a hand-drawn CustomPainter approximating the logo —
/// close, but not the real thing.
///
/// The source art is a black tile with the face knocked out in white, so it
/// reads correctly on light and dark surfaces alike.
class CalcAiMark extends StatelessWidget {
  const CalcAiMark({
    super.key,
    this.size = 64,
    this.cornerRadius,
  });

  final double size;

  /// Corner rounding. Defaults to iOS's squircle-ish ~22% of the size.
  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius ?? size * 0.22),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The icon is a solid tile; letting it fade in avoids a flash of empty
        // space on the sign-in screen while the image decodes.
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded || frame != null) return child;
          return SizedBox(width: size, height: size);
        },
      ),
    );
  }
}
