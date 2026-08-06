import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';

/// Full-screen editor for the user's own standing instructions.
///
/// Whatever is typed here is appended to every prompt the calculator sends —
/// on top of the response style, not instead of it. The worker caps the stored
/// value at 2000 characters, so the field does too.
class CustomInstructionsScreen extends StatefulWidget {
  const CustomInstructionsScreen({super.key});

  static const int maxLength = 2000;

  @override
  State<CustomInstructionsScreen> createState() =>
      _CustomInstructionsScreenState();
}

class _CustomInstructionsScreenState extends State<CustomInstructionsScreen> {
  late final TextEditingController _ctrl;
  late String _original;
  bool _saving = false;

  /// Starting points, so the field is never a blank page. Tapping one appends
  /// it rather than replacing what is already there.
  static const List<String> _examples = [
    'Always show the formula before the numbers.',
    'Explain like I am in Algebra 1.',
    'Use decimals, not fractions.',
    'Answer in Spanish.',
  ];

  @override
  void initState() {
    super.initState();
    _original = context.read<CloudService>().customContext;
    _ctrl = TextEditingController(text: _original);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _dirty => _ctrl.text.trim() != _original.trim();

  Future<void> _handleBack() async {
    if (!_dirty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Discard changes?',
            style: GoogleFonts.outfit(color: AppColors.textPrimary)),
        content: Text('Your edits have not been saved.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep editing',
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Discard',
                style: GoogleFonts.inter(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    final mac = auth.primaryMac;
    final token = auth.token;
    if (mac == null || token == null) return;

    setState(() => _saving = true);
    final ok = await cloud.setContext(token, mac, _ctrl.text.trim());
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _original = _ctrl.text.trim();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cloud.error ?? 'Could not save',
              style: GoogleFonts.inter()),
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  void _append(String example) {
    final current = _ctrl.text.trimRight();
    final next = current.isEmpty ? example : '$current\n$example';
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: Text(
            'Custom instructions',
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.textSecondary),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: _dirty ? _save : null,
                child: Text(
                  'Save',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _dirty
                        ? AppColors.electricBlue
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).viewInsets.bottom + 28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Added to every question your calculator asks, on top of the '
                  'response style.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ctrl,
                  maxLines: 10,
                  minLines: 8,
                  maxLength: CustomInstructionsScreen.maxLength,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. Always show the formula before the numbers.',
                    hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                    counterStyle:
                        GoogleFonts.inter(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Examples',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _examples
                      .map((e) => ActionChip(
                            label: Text(
                              e,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            backgroundColor: AppColors.surface,
                            side: const BorderSide(
                                color: AppColors.glassBorder, width: 0.5),
                            onPressed: () => _append(e),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
