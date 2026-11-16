import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final String? _token;
  late final String? _mac;
  String _original = '';
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  bool _checking = false;
  bool _needsReconcile = false;
  EditSnapshot? _base;
  EditSnapshot? _serverSnapshot;
  String? _loadError;
  String? _saveError;
  int _loadGeneration = 0;

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
    final auth = context.read<AuthService>();
    _token = auth.token;
    _mac = auth.primaryMac;
    _ctrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ctrl.dispose();
    super.dispose();
  }

  bool get _dirty => _ctrl.text.trim() != _original.trim();
  bool get _overLimit => _ctrl.text.length > CustomInstructionsScreen.maxLength;
  bool get _sameScope {
    if (!mounted) return false;
    final auth = context.read<AuthService>();
    return _token != null &&
        _mac != null &&
        auth.token == _token &&
        auth.primaryMac == _mac;
  }

  Future<void> _load() async {
    if (!mounted || _saving) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loaded = false;
      _loadError = null;
    });
    EditSnapshot? saved;
    try {
      if (_sameScope) {
        saved = await context.read<CloudService>().readContextSnapshot(
          _token!,
          _mac!,
        );
      }
    } catch (_) {
      // A failed read must never make an unknown value editable as empty.
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = false;
      if (_sameScope && saved != null) {
        _original = saved.text;
        _ctrl.text = saved.text;
        _base = saved;
        _loaded = true;
      } else {
        _loadError =
            context.read<CloudService>().contextError ??
            'Could not load your instructions. Try again before editing.';
      }
    });
  }

  Future<void> _handleBack() async {
    if (_saving || _checking) return;
    if (!_sameScope || !_dirty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Discard changes?',
          style: GoogleFonts.outfit(color: AppColors.textPrimary),
        ),
        content: Text(
          'Your edits have not been saved.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep editing',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Discard',
              style: GoogleFonts.inter(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final base = _base;
    if (_saving ||
        _checking ||
        _needsReconcile ||
        base == null ||
        !_loaded ||
        !_sameScope ||
        !_dirty ||
        _overLimit) {
      return;
    }
    final cloud = context.read<CloudService>();
    final saved = _ctrl.text.trim();

    setState(() => _saving = true);
    EditSnapshot? accepted;
    try {
      accepted = await cloud.writeContextSnapshot(
        _token!,
        _mac!,
        saved,
        base: base,
      );
    } catch (_) {
      // Keep the draft available after an unexpected transport failure.
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!_sameScope) return;
    if (accepted != null) {
      _original = saved;
      _base = accepted;
      Navigator.pop(context);
    } else {
      setState(() {
        _needsReconcile = true;
        _serverSnapshot = null;
        _saveError = cloud.contextConflict
            ? 'Saved instructions changed. Check the saved version before trying again.'
            : 'The save could not be confirmed. Check saved instructions before trying again.';
      });
    }
  }

  Future<void> _reconcile() async {
    if (_saving || _checking || !_sameScope || !_needsReconcile) return;
    final cloud = context.read<CloudService>();
    final draft = _ctrl.text.trim();
    setState(() => _checking = true);
    EditSnapshot? saved;
    try {
      saved = await cloud.readContextSnapshot(_token!, _mac!);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _checking = false);
    if (!_sameScope) return;
    final latest = saved;
    if (latest == null) {
      setState(() {
        _saveError =
            'Could not check saved instructions. Your draft is still here.';
      });
      return;
    }
    if (latest.text == draft) {
      // A lost reply can follow a committed write. Confirm the stored text
      // without replaying that mutation or inventing its acknowledgement.
      _original = latest.text;
      _base = latest;
      Navigator.pop(context);
      return;
    }
    setState(() {
      if (latest.text == _original) {
        _base = latest;
        _needsReconcile = false;
        _serverSnapshot = null;
        _saveError =
            'Your draft is not saved. Review it, then tap Save to try again.';
      } else {
        _serverSnapshot = latest;
        _saveError =
            'Saved instructions changed. Review both versions before choosing what to keep.';
      }
    });
  }

  Future<void> _reviewConflict() async {
    final saved = _serverSnapshot;
    if (saved == null || !_sameScope || _checking || _saving) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        ctx.watch<AuthService>();
        if (!_sameScope) {
          return AlertDialog(
            title: const Text('Instructions unavailable'),
            content: const Text(
              'Your account or calculator changed. Reopen instructions to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        }
        return AlertDialog(
          title: const Text('Review instructions'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Saved instructions'),
                SelectableText(saved.text.isEmpty ? '(Empty)' : saved.text),
                const SizedBox(height: 16),
                const Text('Your draft'),
                SelectableText(_ctrl.text),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'saved'),
              child: const Text('Use saved instructions'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'draft'),
              child: const Text('Keep my draft'),
            ),
          ],
        );
      },
    );
    if (!mounted || !_sameScope || choice == null) return;
    setState(() {
      _base = saved;
      _original = saved.text;
      if (choice == 'saved') _ctrl.text = saved.text;
      _needsReconcile = false;
      _serverSnapshot = null;
      _saveError = choice == 'draft'
          ? 'Your draft is not saved. Tap Save to replace the version you reviewed.'
          : null;
    });
  }

  Future<void> _copyDraft() async {
    if (!_sameScope) return;
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    if (!mounted || !_sameScope) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Draft copied.')));
  }

  void _append(String example) {
    if (!_loaded || _saving || _checking || _needsReconcile || !_sameScope) {
      return;
    }
    final current = _ctrl.text.trimRight();
    final next = current.isEmpty ? example : '$current\n$example';
    if (next.length > CustomInstructionsScreen.maxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Not enough space for this example. Limit: 2,000 characters.',
          ),
        ),
      );
      return;
    }
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthService>();
    final sameScope = _sameScope;
    final busy = _saving || _checking;
    final canSave =
        _loaded &&
        _base != null &&
        sameScope &&
        _dirty &&
        !_overLimit &&
        !busy &&
        !_needsReconcile;
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
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
            tooltip: 'Back',
            onPressed: busy ? null : _handleBack,
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
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.textSecondary),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: canSave ? _save : null,
                child: Text(
                  'Save',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: canSave
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
          child: _loading && sameScope
              ? const Center(child: CircularProgressIndicator())
              : !_loaded || !sameScope
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sameScope
                              ? _loadError ?? 'Could not load instructions.'
                              : 'Your account or calculator changed. Reopen instructions to continue.',
                          textAlign: TextAlign.center,
                        ),
                        if (sameScope)
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
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
                      if (_saveError != null) ...[
                        Text(_saveError!),
                        if (_needsReconcile)
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: busy ? null : _reconcile,
                                child: const Text('Check saved instructions'),
                              ),
                              if (_serverSnapshot != null)
                                TextButton(
                                  onPressed: busy ? null : _reviewConflict,
                                  child: const Text('Review changes'),
                                ),
                              TextButton(
                                onPressed: _copyDraft,
                                child: const Text('Copy draft'),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _ctrl,
                        enabled: !busy && !_needsReconcile,
                        maxLines: 10,
                        minLines: 8,
                        maxLength: CustomInstructionsScreen.maxLength,
                        // The API caps JavaScript string length (UTF-16 units).
                        // Enforce that same bound without splitting a visible character.
                        maxLengthEnforcement: MaxLengthEnforcement.none,
                        inputFormatters: const [_InstructionLengthFormatter()],
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          counterText:
                              '${_ctrl.text.length}/${CustomInstructionsScreen.maxLength}',
                          hintText:
                              'e.g. Always show the formula before the numbers.',
                          hintStyle: GoogleFonts.inter(
                            color: AppColors.textTertiary,
                          ),
                          counterStyle: GoogleFonts.inter(
                            color: AppColors.textTertiary,
                          ),
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
                            .map(
                              (e) => ActionChip(
                                label: Text(
                                  e,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                backgroundColor: AppColors.surface,
                                side: const BorderSide(
                                  color: AppColors.glassBorder,
                                  width: 0.5,
                                ),
                                onPressed: busy || _needsReconcile
                                    ? null
                                    : () => _append(e),
                              ),
                            )
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

class _InstructionLengthFormatter extends TextInputFormatter {
  const _InstructionLengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Let the keyboard finish composing before changing its text. Save stays
    // disabled if a composition temporarily exceeds the server's limit.
    if (newValue.text.length <= CustomInstructionsScreen.maxLength ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }
    final text = StringBuffer();
    for (final character in newValue.text.characters) {
      if (text.length + character.length > CustomInstructionsScreen.maxLength) {
        break;
      }
      text.write(character);
    }
    return newValue.copyWith(
      text: text.toString(),
      selection: TextSelection(
        baseOffset: newValue.selection.baseOffset.clamp(0, text.length),
        extentOffset: newValue.selection.extentOffset.clamp(0, text.length),
      ),
      composing: TextRange.empty,
    );
  }
}
