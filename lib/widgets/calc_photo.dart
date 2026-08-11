import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/photo_view_screen.dart';
import '../theme/app_colors.dart';

/// A calculator photo in history, tappable to open full screen.
///
/// Used by the history list, the history detail sheet and the home card so all
/// three behave the same. A failed load is retryable rather than a dead icon:
/// the photo lives behind the same session the rest of the app uses, so a
/// transient network blip should not permanently look like a missing file.
class CalcPhoto extends StatefulWidget {
  const CalcPhoto({
    super.key,
    required this.imageUrl,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String imageUrl;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<CalcPhoto> createState() => _CalcPhotoState();
}

class _CalcPhotoState extends State<CalcPhoto> {
  /// Bumped on retry so Flutter drops the failed entry from its image cache
  /// instead of replaying the same error.
  int _attempt = 0;

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(imageUrl: widget.imageUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(16);
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: radius,
        child: Image.network(
          widget.imageUrl,
          key: ValueKey('${widget.imageUrl}#$_attempt'),
          width: double.infinity,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              height: widget.height,
              color: AppColors.surfaceLight,
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.electricBlue,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => GestureDetector(
            onTap: () => setState(() => _attempt++),
            child: Container(
              height: widget.height,
              color: AppColors.surfaceLight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.refresh_rounded,
                      color: AppColors.textTertiary, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to load photo',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
