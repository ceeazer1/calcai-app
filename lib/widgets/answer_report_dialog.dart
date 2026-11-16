import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../utils/answer_report.dart';

Future<void> showAnswerReportDialog(
  BuildContext context, {
  required String question,
  required String answer,
  Future<bool> Function(Uri)? launchEmail,
}) async {
  final auth = context.read<AuthService>();
  final token = auth.token;
  final mac = auth.primaryMac;
  if (token == null || mac == null) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _AnswerReportDialog(
      question: question,
      answer: answer,
      auth: auth,
      token: token,
      mac: mac,
      launchEmail:
          launchEmail ??
          ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
    ),
  );
}

class _AnswerReportDialog extends StatefulWidget {
  const _AnswerReportDialog({
    required this.question,
    required this.answer,
    required this.auth,
    required this.token,
    required this.mac,
    required this.launchEmail,
  });

  final String question, answer, token, mac;
  final AuthService auth;
  final Future<bool> Function(Uri) launchEmail;

  @override
  State<_AnswerReportDialog> createState() => _AnswerReportDialogState();
}

class _AnswerReportDialogState extends State<_AnswerReportDialog> {
  final _note = TextEditingController();
  bool _includeContent = false;
  bool _preparing = false;
  bool _invalidated = false;
  String? _notice;

  bool get _current =>
      !_invalidated &&
      widget.auth.token == widget.token &&
      widget.auth.primaryMac == widget.mac;

  String get _body => answerReportBody(
    note: _note.text,
    includeContent: _includeContent,
    question: widget.question,
    answer: widget.answer,
    sensitiveValues: [widget.token, widget.mac, widget.auth.email ?? ''],
  );

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onScopeChanged);
  }

  void _onScopeChanged() {
    if (!_current && mounted) {
      _note.clear();
      setState(() {
        _invalidated = true;
        _includeContent = false;
        _notice = null;
      });
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onScopeChanged);
    _note.dispose();
    super.dispose();
  }

  Future<void> _prepareEmail() async {
    if (_preparing || !_current) {
      return;
    }
    final uri = answerReportEmailUri(_body);
    setState(() {
      _preparing = true;
      _notice = null;
    });
    var opened = false;
    try {
      opened = await widget.launchEmail(uri);
    } catch (_) {
      // Do not log the URI: the draft can contain voluntarily included text.
    }
    if (!mounted || !_current) {
      return;
    }
    setState(() {
      _preparing = false;
      _notice = opened
          ? 'Email app opened. Review and send it there.'
          : 'Could not open an email app. Copy the support email to contact us.';
    });
  }

  Future<void> _copyEmail() async {
    try {
      await Clipboard.setData(
        const ClipboardData(text: answerReportSupportEmail),
      );
      if (mounted && _current) {
        setState(() => _notice = 'Support email copied.');
      }
    } catch (_) {
      if (mounted && _current) {
        setState(
          () => _notice = 'Could not copy. Use the support email shown above.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return AlertDialog(
        title: const Text('Report unavailable'),
        content: const Text(
          'Your account or calculator changed. Reopen the answer to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Report this answer'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Prepare an email to support. Nothing is sent by CalcAI.',
              ),
              const SizedBox(height: 8),
              const SelectableText(answerReportSupportEmail),
              TextButton.icon(
                onPressed: _copyEmail,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy email'),
              ),
              TextField(
                controller: _note,
                enabled: !_preparing,
                maxLength: answerReportNoteLimit,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Brief note (optional)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeContent,
                onChanged: _preparing
                    ? null
                    : (value) =>
                          setState(() => _includeContent = value ?? false),
                title: const Text('Include this question and answer'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const Text(
                'Only this answer’s text can be included. Photos, links and account details are omitted. Long text is shortened.',
              ),
              const SizedBox(height: 12),
              const Text('Email text'),
              const SizedBox(height: 6),
              SelectableText(
                _body,
                key: const ValueKey('answer-report-preview'),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_notice!)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _preparing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _preparing ? null : _prepareEmail,
          child: Text(_preparing ? 'Opening email…' : 'Prepare email'),
        ),
      ],
    );
  }
}
