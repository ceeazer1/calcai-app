import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Relative expected usage from response length, never a fixed price estimate.
/// Custom instructions have unknown length/cost and use an unfilled indicator.
class ResponseStyleUsageDots extends StatelessWidget {
  const ResponseStyleUsageDots({super.key, required this.style});
  final String? style;

  static int? levelFor(String? style) => switch (style) {
    'answer' => 1,
    'small' => 2,
    'detailed' => 3,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final level = levelFor(style);
    final label = level == null
        ? 'Variable AI usage with custom instructions'
        : 'Relative AI usage $level of 3; actual usage varies';
    return Semantics(
      label: label,
      child: Tooltip(
        message: level == null
            ? 'Usage varies with your instructions.'
            : 'Relative expected usage. Model, question and reply length affect actual usage.',
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: level != null && i < level
                        ? AppColors.electricBlue
                        : Colors.transparent,
                    border: Border.all(
                      color: level != null && i < level
                          ? AppColors.electricBlue
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
