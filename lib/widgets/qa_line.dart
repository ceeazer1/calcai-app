import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// One line of a logged exchange, tagged Q or A.
///
/// The question and the answer used to be two unlabelled paragraphs that
/// differed only in text colour, which read as one block at a glance. A fixed
/// letter column keeps the text left edges aligned between the two rows.
class QaLine extends StatelessWidget {
  const QaLine({
    super.key,
    required this.letter,
    required this.text,
    required this.textStyle,
    this.maxLines,
  });

  /// 'Q' or 'A'.
  final String letter;
  final String text;
  final TextStyle textStyle;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            letter,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              height: textStyle.height ?? 1.35,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: textStyle,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
