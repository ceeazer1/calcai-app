import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calc_note.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/ti84_screen.dart';

typedef _NotesEditBase = ({EditSnapshot snapshot, String token, String mac});

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
  bool _verified = false;
  bool _reading = false;
  bool _editing = false;
  String? _verifiedToken;
  String? _verifiedMac;
  List<CalcNote>? _pendingNotes;
  bool _saveConflict = false;
  _NotesEditBase? _base;
  String? _pendingText;

  bool get _canEdit =>
      _verified && !_loading && !_saving && !_editing && _error == null;

  bool _sameScope(String token, String mac) =>
      mounted &&
      context.read<AuthService>().token == token &&
      context.read<AuthService>().primaryMac == mac;

  /// Whether the calculator preview is expanded in the editor. Remembered
  /// across opens so the choice sticks.
  bool _previewExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int get _maxNotes {
    final cloud = context.read<CloudService>();
    return cloud.planType?.toLowerCase() == 'pro'
        ? kMaxNotesPro
        : kMaxNotesFree;
  }

  Future<void> _load() async {
    if (!mounted || _reading || _saving || _editing || _pendingNotes != null) {
      return;
    }
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    final token = auth.token;
    final mac = auth.primaryMac;
    if (token == null || mac == null) {
      setState(() {
        _loading = false;
        _error = 'No device paired yet';
      });
      return;
    }
    _reading = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    final snapshot = await cloud.readNotesSnapshot(token, mac);
    _reading = false;
    if (!_sameScope(token, mac)) return;
    setState(() {
      if (snapshot != null) {
        _notes = CalcNote.parseStored(snapshot.text);
        _base = (snapshot: snapshot, token: token, mac: mac);
        _verified = true;
        _verifiedToken = token;
        _verifiedMac = mac;
      }
      _loading = false;
      _error = snapshot == null
          ? cloud.notesError ?? 'Could not load notes. Please try again.'
          : null;
    });
  }

  /// Pushes the current list to the backend. The calculator picks it up on its
  /// next sync.
  Future<bool> _save(
    List<CalcNote> updated, {
    required _NotesEditBase base,
  }) async {
    if (_saving ||
        _reading ||
        !_verified ||
        _pendingNotes != null ||
        !_sameScope(base.token, base.mac)) {
      return false;
    }
    final cloud = context.read<CloudService>();
    final text = CalcNote.toEnvelope(updated);
    setState(() => _saving = true);
    final accepted = await cloud.writeNotesSnapshot(
      base.token,
      base.mac,
      text,
      base: base.snapshot,
    );
    if (!_sameScope(base.token, base.mac)) return false;
    setState(() {
      _saving = false;
      if (accepted != null) {
        _notes = updated;
        _base = (snapshot: accepted, token: base.token, mac: base.mac);
        _pendingNotes = null;
        _pendingText = null;
        _saveConflict = false;
        _error = null;
      } else {
        _pendingNotes = updated;
        _pendingText = text;
        _saveConflict = true;
        _error = cloud.notesConflict
            ? 'Notes changed during this save. Review your unsaved changes and reload to compare.'
            : 'The save could not be confirmed. Review your unsaved changes and reload to compare.';
      }
    });
    return accepted != null;
  }

  Future<void> _reconcilePending() async {
    final base = _base;
    final pending = _pendingNotes;
    if (base == null ||
        pending == null ||
        _reading ||
        _saving ||
        !_sameScope(base.token, base.mac)) {
      return;
    }
    final cloud = context.read<CloudService>();
    setState(() => _reading = true);
    final latest = await cloud.readNotesSnapshot(base.token, base.mac);
    if (!_sameScope(base.token, base.mac)) return;
    var confirmed = false;
    setState(() {
      _reading = false;
      if (latest == null) {
        _error =
            cloud.notesError ?? 'Could not reload notes. Please try again.';
        return;
      }
      _base = (snapshot: latest, token: base.token, mac: base.mac);
      _notes = CalcNote.parseStored(latest.text);
      if (latest.text == _pendingText) {
        // Confirm the desired content by a read; the original POST outcome
        // remains unknown without an idempotency receipt. Never repeat POST.
        _notes = pending;
        _pendingNotes = null;
        _pendingText = null;
        _saveConflict = false;
        _error = null;
        confirmed = true;
      } else {
        _error =
            'Saved notes differ from your unsaved changes. Review them before discarding your draft.';
      }
    });
    if (confirmed) _toast('Saved to your account');
  }

  /// True when the body holds nothing but empty list markers (e.g. the seeded
  /// "1. "), so we don't save or preview an empty numbered note.
  static bool _isBlankBody(String body) => body
      .split('\n')
      .every((l) => l.replaceAll(RegExp(r'^\s*\d+[.)]\s*'), '').trim().isEmpty);

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
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
  static void _attachAutoNumbering(TextEditingController ctrl) {
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

      final priorLine = text.substring(0, sel.baseOffset - 1).split('\n').last;
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
        newText =
            text.substring(0, sel.baseOffset) +
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
    if (!_canEdit) return;
    final token = _verifiedToken!;
    final mac = _verifiedMac!;
    final base = _base!;
    final isNew = existing == null;
    if (isNew && _notes.length >= _maxNotes) {
      _toast('Note limit reached ($_maxNotes)');
      return;
    }

    // Full screen rather than a bottom sheet: the body field, the numbered
    // list and the calculator preview all want the room, and a back arrow is
    // a clearer way out than a drag handle.
    _editing = true;
    final draft = await Navigator.of(context).push<_NoteDraft>(
      MaterialPageRoute(
        builder: (_) => _NoteEditorPage(
          existing: existing,
          previewExpanded: _previewExpanded,
          onPreviewChanged: (v) => _previewExpanded = v,
        ),
      ),
    );
    _editing = false;

    if (draft == null || !_sameScope(token, mac)) return;
    if (_isBlankBody(draft.body)) {
      _toast('Note is empty');
      return;
    }

    final updated = isNew
        ? [..._notes, CalcNote.create(body: draft.body, title: draft.title)]
        : _notes
              .map(
                (n) => n.id == existing.id
                    ? n.copyWith(body: draft.body, title: draft.title)
                    : n,
              )
              .toList();
    final ok = await _save(updated, base: base);
    if (mounted) _toast(ok ? 'Saved to your account' : 'Could not save');
  }

  /// Confirms before deleting.
  ///
  /// A note only exists here and in the cloud copy, so a mis-tap on a small
  /// icon would lose the text for good.
  Future<void> _confirmDelete(CalcNote note) async {
    if (!_canEdit) return;
    final token = _verifiedToken!;
    final mac = _verifiedMac!;
    final base = _base!;
    _editing = true;
    final label = note.displayTitle.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Delete note?',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          label.isEmpty
              ? 'This note will be removed from your CalcAI. This cannot be '
                    'undone.'
              : '"$label" will be removed from your CalcAI. This cannot be '
                    'undone.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    _editing = false;
    if (ok == true && _sameScope(token, mac) && _canEdit) {
      await _deleteNote(note, base: base);
    }
  }

  Future<void> _deleteNote(
    CalcNote note, {
    required _NotesEditBase base,
  }) async {
    if (!_canEdit) return;
    final ok = await _save(
      _notes.where((n) => n.id != note.id).toList(),
      base: base,
    );
    if (!mounted) return;
    if (!ok) {
      _toast('Could not delete');
    } else {
      _toast('Note deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rendered inside MainShell's IndexedStack, so no Scaffold/back button —
    // matches the Home and History tabs.
    final canAdd = _canEdit && _notes.length < _maxNotes;
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
                    tooltip: _notes.length >= _maxNotes
                        ? 'Note limit reached'
                        : 'Add note',
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
                  'Open Notes on your calculator while connected to Wi-Fi.',
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

  Widget _buildRecovery() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(liveRegion: true, child: Text(_error!)),
        if (_pendingNotes != null)
          const Text(
            'Your unsaved changes are kept only on this screen and are lost if you leave it.',
          ),
        Wrap(
          children: [
            if (!_saveConflict)
              TextButton(
                onPressed: _saving || _loading || _reading
                    ? null
                    : () async {
                        await _load();
                      },
                child: const Text('Retry'),
              ),
            if (_saveConflict)
              TextButton(
                onPressed: _saving || _reading ? null : _reconcilePending,
                child: const Text('Reload and compare'),
              ),
            if (_saveConflict)
              TextButton(
                onPressed: _reviewPendingNotes,
                child: const Text('Review unsaved changes'),
              ),
            if (_pendingNotes != null)
              TextButton(
                onPressed: _saving || _reading
                    ? null
                    : () {
                        setState(() {
                          _pendingNotes = null;
                          _pendingText = null;
                          _saveConflict = false;
                        });
                        _load();
                      },
                child: Text(
                  _saveConflict
                      ? 'Discard changes and reload'
                      : 'Discard changes',
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _reviewPendingNotes() async {
    final pending = _pendingNotes;
    final base = _base;
    if (pending == null || base == null || !_sameScope(base.token, base.mac)) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final auth = dialogContext.watch<AuthService>();
        if (!mounted ||
            auth.token != base.token ||
            auth.primaryMac != base.mac) {
          return AlertDialog(
            title: const Text('Notes unavailable'),
            content: const Text(
              'Your account or calculator changed. Reopen Notes to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        }
        return AlertDialog(
          title: const Text('Unsaved notes'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                pending
                    .map(
                      (note) =>
                          '${note.title.isEmpty ? note.displayTitle : note.title}\n${note.body}',
                    )
                    .join('\n\n'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
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

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.electricBlue,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_error != null) SliverToBoxAdapter(child: _buildRecovery()),
          if (_notes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 100),
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
                        _error != null
                            ? 'Notes are unavailable'
                            : 'No notes yet',
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
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList.builder(
                itemCount: _notes.length,
                itemBuilder: (context, i) => _buildNote(_notes[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNote(CalcNote note) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      onTap: _canEdit ? () => _editNote(existing: note) : null,
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
            onPressed: _canEdit ? () => _confirmDelete(note) : null,
            tooltip:
                '${MaterialLocalizations.of(context).deleteButtonTooltip}: ${note.displayTitle}',
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ),
        ],
      ),
    ),
  );
}

/// What the editor hands back to the list.
class _NoteDraft {
  const _NoteDraft({required this.title, required this.body});
  final String title;
  final String body;
}

/// Full-screen note editor.
///
/// Replaced a bottom sheet: the body field, the auto-numbered list and the
/// calculator preview all want the height, and a back arrow reads more
/// clearly than a drag handle. Returns a [_NoteDraft] on save, null if
/// dismissed.
class _NoteEditorPage extends StatefulWidget {
  const _NoteEditorPage({
    required this.existing,
    required this.previewExpanded,
    required this.onPreviewChanged,
  });

  final CalcNote? existing;
  final bool previewExpanded;

  /// Reports the preview toggle up, so the choice survives closing the editor.
  final ValueChanged<bool> onPreviewChanged;

  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late bool _showPreview;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    // New notes start the numbered list off at "1. ".
    _bodyCtrl = TextEditingController(text: widget.existing?.body ?? '1. ');
    _bodyCtrl.selection = TextSelection.collapsed(
      offset: _bodyCtrl.text.length,
    );
    _NotesScreenState._attachAutoNumbering(_bodyCtrl);
    _showPreview = widget.previewExpanded;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _dirty {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trimRight();
    if (_isNew) {
      return title.isNotEmpty || !_NotesScreenState._isBlankBody(body);
    }
    return title != widget.existing!.title ||
        body != widget.existing!.body.trimRight();
  }

  void _save() {
    Navigator.pop(
      context,
      _NoteDraft(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trimRight(),
      ),
    );
  }

  /// Guards the back arrow so edits aren't silently thrown away.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Discard changes?',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This note has not been saved yet.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
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
              style: GoogleFonts.inter(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _handleBack() async {
    if (await _confirmDiscard() && mounted) Navigator.pop(context);
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
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: Text(
            _isNew ? 'New note' : 'Edit note',
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.electricBlue,
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
                TextField(
                  controller: _titleCtrl,
                  style: GoogleFonts.inter(color: AppColors.textPrimary),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Title (optional)',
                    hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyCtrl,
                  autofocus: _isNew,
                  maxLines: null,
                  minLines: 12,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.inter(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. QUADRATIC: X=(-B±√(B²-4AC))/2A',
                    hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Collapsible 1:1 TI-84 Plus screen preview ──────
                InkWell(
                  onTap: () {
                    setState(() => _showPreview = !_showPreview);
                    widget.onPreviewChanged(_showPreview);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calculate_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Calc preview',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        AnimatedRotation(
                          turns: _showPreview ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _showPreview
                      ? Column(
                          children: [
                            const SizedBox(height: 8),
                            Center(
                              child: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _bodyCtrl,
                                builder: (_, value, __) => Ti84Pager(
                                  scale: 2,
                                  text:
                                      _NotesScreenState._isBlankBody(value.text)
                                      ? 'YOUR NOTE APPEARS HERE'
                                      : value.text,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '96x64 screen — 16 chars per line, 8 lines each.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
