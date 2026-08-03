import 'package:flutter/material.dart';

/// The full CalcAI lockup — the face mark plus the "calcai" wordmark.
///
/// The artwork is a dark silhouette on transparency, so it is tinted rather
/// than shipped in two colours: `srcIn` replaces every opaque pixel with
/// [color] and leaves the alpha alone, which keeps the anti-aliased edges
/// clean at any size and means one file works on light and dark surfaces.
class CalcAiWordmark extends StatelessWidget {
  const CalcAiWordmark({
    super.key,
    this.width = 190,
    this.color = Colors.white,
  });

  final double width;
  final Color color;

  /// Intrinsic aspect ratio of the asset, so callers only pass a width.
  static const double _aspect = 1000 / 220;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/calcai_wordmark.png',
      width: width,
      height: width / _aspect,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
