import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calc_note.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/ti84_screen.dart';

/// Notes screen — short reference notes synced to the calculator.
///
/// The calculator fetches these over WiFi and shows the bodies joined by " | ",
/// so they're meant to be short (formulas, constants, reminders).
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<CalcNote> _notes = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int get _maxNotes {
    final cloud = context.read<CloudService>();
    return cloud.planType?.toLowerCase() == 'pro' ? kMaxNotesPro : kMaxNotesFree;
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token == null || auth.primaryMac == null) {
      setState(() {
        _loading = false;
        _error = 'No device paired yet';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final raw = await cloud.getNotes(auth.token!, auth.primaryMac!);
    if (!mounted) return;
    setState(() {
      _notes = CalcNote.parseStored(raw);
      _loading = false;
      _error = cloud.error;
    });
  }

  /// Pushes the current list to the backend. The calculator picks it up on its
  /// next sync.
  Future<bool> _save() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token == null || auth.primaryMac == null) return false;

    setState(() => _saving = true);
    await cloud.setNotes(
      auth.token!,
      auth.primaryMac!,
      CalcNote.toEnvelope(_notes),
    );
    if (!mounted) return false;
    final ok = cloud.error == null;
    setState(() {
      _saving = false;
      _error = cloud.error;
    });
    return ok;
  }

  /// True when the body holds nothing but empty list markers (e.g. the seeded
  /// "1. "), so we don't save or preview an empty numbered note.
  static bool _isBlankBody(String body) => body
      .split('\n')
      .every((l) => l.replaceAll(RegExp(r'^\s*\d+[.)]\s*'), '').trim().isEmpty);

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.surfaceLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Keeps the body field behaving like a numbered document: pressing Enter
  /// after "3. foo" starts "4. ", and pressing Enter on an empty numbered line
  /// ends the list instead of adding another number.
  void _attachAutoNumbering(TextEditingController ctrl) {
    var previous = ctrl.text;
    ctrl.addListener(() {
      final text = ctrl.text;
      final sel = ctrl.selection;
      // Only react to a single character being typed at the caret.
      if (text.length != previous.length + 1 ||
          !sel.isCollapsed ||
          sel.baseOffset <= 0 ||
          text[sel.baseOffset - 1] != '\n') {
        previous = text;
        return;
      }

      final priorLine =
          text.substring(0, sel.baseOffset - 1).split('\n').last;
      final numbered = RegExp(r'^(\d+)[.)]\s*(.*)$').firstMatch(priorLine);
      if (numbered == null) {
        previous = text;
        return;
      }

      String newText;
      int caret;
      if (numbered.group(2)!.trim().isEmpty) {
        // Enter on an empty numbered line → drop the number, end the list.
        final start = sel.baseOffset - 1 - priorLine.length;
        newText = text.substring(0, start) + text.substring(sel.baseOffset - 1);
        caret = start;
      } else {
        final next = '${int.parse(numbered.group(1)!) + 1}. ';
        newText = text.substring(0, sel.baseOffset) +
            next +
            text.substring(sel.baseOffset);
        caret = sel.baseOffset + next.length;
      }

      previous = newText;
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: caret),
      );
    });
  }

  Future<void> _editNote({CalcNote? existing}) async {
    final isNew = existing == null;
    if (isNew && _notes.length >= _maxNotes) {
      _toast('Note limit reached ($_maxNotes)');
      return;
    }

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    // New notes start the numbered list off at "1. ".
    final bodyCtrl = TextEditingController(text: existing?.body ?? '1. ');
    bodyCtrl.selection =
        TextSelection.collapsed(offset: bodyCtrl.text.length);
    _attachAutoNumbering(bodyCtrl);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          // Cap the height so the taller body field still fits with the
          // keyboard up, and let the content scroll if it doesn't.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.glassBorder, width: 0.5),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isNew ? 'New note' : 'Edit note',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleCtrl,
                    style: GoogleFonts.inter(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Title (optional)',
                      hintStyle:
                          GoogleFonts.inter(color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bodyCtrl,
                    autofocus: isNew,
                    maxLines: 14,
                    minLines: 9,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.inter(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. QUADRATIC: X=(-B±√(B²-4AC))/2A',
                      hintStyle:
                          GoogleFonts.inter(color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Live 1:1 TI-84 Plus screen preview ──────────
                  Row(
                    children: [
                      const Icon(Icons.calculate_outlined,
                          size: 15, color: AppColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        'On your calculator',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: bodyCtrl,
                      builder: (_, value, __) => Ti84Pager(
                        // Scale 2 (192x128) keeps the Save button reachable
                        // without scrolling on short screens.
                        scale: 2,
                        text: _isBlankBody(value.text)
                            ? 'YOUR NOTE APPEARS HERE'
                            : value.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '96x64 screen — 16 characters per line, 8 lines each.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondary),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          'Save',
                          style:
                              GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;
    final body = bodyCtrl.text.trimRight();
    if (_isBlankBody(body)) {
      _toast('Note is empty');
      return;
    }

    setState(() {
      if (isNew) {
        _notes = [
          ..._notes,
          CalcNote.create(body: body, title: titleCtrl.text.trim()),
        ];
      } else {
        _notes = _notes
            .map((n) => n.id == existing.id
                ? n.copyWith(body: body, title: titleCtrl.text.trim())
                : n)
            .toList();
      }
    });
    final ok = await _save();
    if (mounted) _toast(ok ? 'Synced to your CalcAI' : 'Could not save');
  }

  Future<void> _deleteNote(CalcNote note) async {
    final before = _notes;
    setState(() => _notes = _notes.where((n) => n.id != note.id).toList());
    final ok = await _save();
    if (!mounted) return;
    if (!ok) {
      setState(() => _notes = before); // roll back on failure
      _toast('Could not delete');
    } else {
      _toast('Note deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rendered inside MainShell's IndexedStack, so no Scaffold/back button —
    // matches the Home and History tabs.
    final canAdd = !_loading && _notes.length < _maxNotes;
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text(
                    'Notes',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    Text(
                      '${_notes.length}/$_maxNotes',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  IconButton(
                    onPressed: canAdd ? () => _editNote() : null,
                    tooltip: canAdd ? 'Add note' : 'Note limit reached',
                    icon: Icon(
                      Icons.add_rounded,
                      color: canAdd
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Synced to your calculator over WiFi.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppColors.textSecondary),
        ),
      );
    }

    if (_notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _error != null
                    ? Icons.cloud_off_rounded
                    : Icons.sticky_note_2_outlined,
                color: AppColors.textTertiary,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'No notes yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add formulas or reminders to see them on your calculator.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textTertiary.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.electricBlue,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: _notes.length,
        itemBuilder: (context, i) {
          final note = _notes[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              onTap: () => _editNote(existing: note),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.displayTitle,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          note.body,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _deleteNote(note),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textTertiary, size: 20),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
