import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TI-84 Plus LCD geometry.
///
/// The screen is 96x64 pixels. The large home-screen font is 6x8 px per cell,
/// so text lays out on a 16-column x 8-row grid — which is why the calculator
/// prompts tell the AI to keep lines to 16 characters.
const int kTi84Cols = 16;

/// Physical rows on the LCD.
const int kTi84Rows = 8;

/// Rows available for note text. The BASIC program reserves the bottom row for
/// its `< | >  Pg:` navigation footer, and the firmware paginates at 7
/// (`sendPage()` in esp32.ino: `linesPerPage = 7`).
const int kTi84TextRows = 7;

const double _kCellW = 6;
const double _kCellH = 8;

/// Wraps [text] the way the firmware does.
///
/// Mirrors `paginateForTI()` in esp32.ino exactly: characters are accumulated
/// and the line is flushed the moment it reaches [cols] — a **hard wrap that
/// breaks mid-word**, not a word wrap. Newlines flush early. Matching this is
/// what makes the preview truthful rather than merely pretty.
List<String> wrapForTi84(String text, {int cols = kTi84Cols}) {
  final out = <String>[];
  var curr = StringBuffer();

  void flush() {
    out.add(curr.toString());
    curr = StringBuffer();
  }

  final s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final rune in s.runes) {
    final c = String.fromCharCode(rune);
    if (c == '\n') {
      flush();
    } else {
      curr.write(c);
      if (curr.length >= cols) flush();
    }
  }
  if (curr.isNotEmpty) flush();
  return out;
}

/// A 1:1 mock of the TI-84 Plus screen, scaled up by [scale].
///
/// Renders [text] the way the calculator does: monospaced, hard-wrapped to 16
/// columns, 7 text rows plus the BASIC nav footer, on the grey-green LCD.
class Ti84Screen extends StatelessWidget {
  const Ti84Screen({
    super.key,
    required this.text,
    this.scale = 3,
    this.showOverflowHint = true,
    this.lines,
    this.footerPage,
  });

  /// 1-based page number drawn in the nav footer, matching what the BASIC
  /// program shows.
  final int? footerPage;

  final String text;

  /// Pre-wrapped lines to render instead of wrapping [text]. Used by
  /// [Ti84Pager] to draw one page at a time.
  final List<String>? lines;

  /// Pixel multiplier. 3 renders the 96x64 panel at 288x192.
  final double scale;

  /// Whether to note that content ran past the 7 visible text rows.
  final bool showOverflowHint;

  // Classic monochrome TI LCD.
  static const Color _lcd = Color(0xFF9DAA8B);
  static const Color _ink = Color(0xFF10160E);

  @override
  Widget build(BuildContext context) {
    // The firmware does not change case (sanitizeForTI84 leaves it alone), so
    // neither do we.
    final allLines = lines ?? wrapForTi84(text);
    final visible = allLines.take(kTi84TextRows).toList();
    final overflowed = allLines.length > kTi84TextRows;

    // RobotoMono advances 0.6em per glyph, so this fontSize makes one glyph
    // exactly one 6px cell at the given scale.
    final fontSize = _kCellW / 0.6 * scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bezel around the panel, so it reads as a screen.
        Container(
          padding: EdgeInsets.all(3 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(2 * scale),
          ),
          child: Container(
            width: kTi84Cols * _kCellW * scale,
            height: kTi84Rows * _kCellH * scale,
            color: _lcd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(kTi84Rows, (i) {
                // Bottom row is the BASIC program's nav footer:
                // Output(8,1,"< | >  Pg:") / Output(8,11,V+1)
                final line = i == kTi84TextRows
                    ? '< | >  Pg:${footerPage ?? 1}'
                    : (i < visible.length ? visible[i] : '');
                return SizedBox(
                  height: _kCellH * scale,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      line,
                      maxLines: 1,
                      softWrap: false,
                      style: GoogleFonts.robotoMono(
                        fontSize: fontSize,
                        height: (_kCellH * scale) / fontSize,
                        color: _ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        if (showOverflowHint && overflowed) ...[
          const SizedBox(height: 6),
          Text(
            'Too long — ${allLines.length - kTi84TextRows} line(s) run off screen',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFFFFAB40),
            ),
          ),
        ],
      ],
    );
  }
}

/// Splits [text] into calculator-sized pages of [kTi84TextRows] lines each,
/// matching `sendPage()`'s `linesPerPage = 7` in the firmware.
List<List<String>> paginateForTi84(String text) {
  final lines = wrapForTi84(text);
  if (lines.isEmpty) return [<String>[]];
  final pages = <List<String>>[];
  for (var i = 0; i < lines.length; i += kTi84TextRows) {
    pages.add(lines.sublist(
      i,
      i + kTi84TextRows > lines.length ? lines.length : i + kTi84TextRows,
    ));
  }
  return pages;
}

/// A TI-84 screen preview that pages through longer notes, so you can see how
/// many calculator screens the note actually takes.
class Ti84Pager extends StatefulWidget {
  const Ti84Pager({super.key, required this.text, this.scale = 2});

  final String text;
  final double scale;

  @override
  State<Ti84Pager> createState() => _Ti84PagerState();
}

class _Ti84PagerState extends State<Ti84Pager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final pages = paginateForTi84(widget.text);
    // Keep the index valid as the user edits the text.
    final page = _page.clamp(0, pages.length - 1);
    final usedOnPage = pages[page].length;

    return Column(
      children: [
        Ti84Screen(
          text: '',
          lines: pages[page],
          scale: widget.scale,
          showOverflowHint: false,
          footerPage: page + 1,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed:
                  page > 0 ? () => setState(() => _page = page - 1) : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: const Color(0xFFF4F4F5),
              disabledColor: const Color(0xFF52525B),
            ),
            Text(
              'Screen ${page + 1} of ${pages.length}  ·  $usedOnPage/$kTi84TextRows lines',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF8E8E96),
              ),
            ),
            IconButton(
              onPressed: page < pages.length - 1
                  ? () => setState(() => _page = page + 1)
                  : null,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: const Color(0xFFF4F4F5),
              disabledColor: const Color(0xFF52525B),
            ),
          ],
        ),
      ],
    );
  }
}
