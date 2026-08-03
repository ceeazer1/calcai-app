import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Six separate boxes for a one-time code.
///
/// A single hidden [TextField] holds the real value and takes the keyboard —
/// the boxes are just painted from it. Six independent fields would mean six
/// focus nodes and hand-written backspace/paste handling, and would break
/// autofill, which needs one field to fill.
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.autofocus = true,
    this.enabled = true,
    this.onCompleted,
  });

  final TextEditingController controller;
  final int length;
  final bool autofocus;
  final bool enabled;

  /// Fires once the last box is filled.
  final ValueChanged<String>? onCompleted;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (widget.controller.text.length == widget.length) {
      widget.onCompleted?.call(widget.controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;

    return GestureDetector(
      onTap: widget.enabled ? () => _focus.requestFocus() : null,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (i) {
              final filled = i < text.length;
              // Highlight where the next digit will land.
              final active = _focus.hasFocus && i == text.length.clamp(0, widget.length - 1);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == widget.length - 1 ? 0 : 8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? const Color(0xFFBFBFC6)
                              : const Color(0xFF303036),
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        filled ? text[i] : '',
                        style: GoogleFonts.robotoMono(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          // The real input, invisible but on top so taps and the caret land
          // here. Opacity rather than Offstage: an offstage field cannot hold
          // focus or receive autofill.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: widget.length,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                showCursor: false,
                style: const TextStyle(color: Colors.transparent),
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
