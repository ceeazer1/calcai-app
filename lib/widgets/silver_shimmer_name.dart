import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A soft silver highlight travels across the name on the welcome screen.
class SilverShimmerName extends StatefulWidget {
  const SilverShimmerName({super.key, required this.name});
  final String name;

  @override
  State<SilverShimmerName> createState() => _SilverShimmerNameState();
}

class _SilverShimmerNameState extends State<SilverShimmerName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
      _shimmer.value = 0.5;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.outfit(
      fontSize: 42,
      height: 1.12,
      letterSpacing: -0.8,
      fontWeight: FontWeight.w600,
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          final position = -3 + _shimmer.value * 6;
          return Stack(alignment: Alignment.center, children: [
            ExcludeSemantics(
                child: Text(
              widget.name,
              textAlign: TextAlign.center,
              style: style.copyWith(color: Colors.transparent, shadows: const [
                Shadow(color: Color(0x607F879B), blurRadius: 22),
                Shadow(color: Color(0x40E5E9F5), blurRadius: 10),
              ]),
            )),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(position - 1, -0.2),
                end: Alignment(position + 1, 0.2),
                colors: const [
                  Color(0xFF969CA8),
                  Color(0xFFD5D9E2),
                  Colors.white,
                  Color(0xFFD5D9E2),
                  Color(0xFF969CA8)
                ],
                stops: const [0, 0.35, 0.5, 0.65, 1],
              ).createShader(bounds),
              child: Text(widget.name,
                  textAlign: TextAlign.center,
                  style: style.copyWith(color: Colors.white)),
            ),
          ]);
        },
      ),
    );
  }
}
