const answerReportSupportEmail = 'info@calcai.cc';
const answerReportNoteLimit = 500;
const answerReportPartLimit = 1000;

String _reportText(String value, int limit, Iterable<String> sensitiveValues) {
  var text = value;
  for (final sensitive in sensitiveValues) {
    if (sensitive.isNotEmpty) {
      text = text.replaceAll(sensitive, '[removed]');
    }
  }
  text = text
      .replaceAll(
        RegExp(
          r'''(?:https?://|file://|data:|www\.)[^\s<>"']+''',
          caseSensitive: false,
        ),
        '[link omitted]',
      )
      .replaceAll(
        RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
        '[email omitted]',
      )
      .replaceAll(
        RegExp(
          r'\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b|\b[0-9a-f]{12}\b',
          caseSensitive: false,
        ),
        '[device omitted]',
      )
      .replaceAll(
        RegExp(r'\bBearer\s+\S+', caseSensitive: false),
        '[credential omitted]',
      )
      .trim();
  if (text.runes.length <= limit) {
    return text;
  }
  const suffix = '\n[shortened]';
  return '${String.fromCharCodes(text.runes.take(limit - suffix.length))}$suffix';
}

/// Only user-selected text enters the email, never a history entry or session.
String answerReportBody({
  String note = '',
  bool includeContent = false,
  String question = '',
  String answer = '',
  Iterable<String> sensitiveValues = const [],
}) {
  final safeNote = _reportText(note, answerReportNoteLimit, sensitiveValues);
  final body = StringBuffer('CalcAI answer report\n\nNote:\n')
    ..write(safeNote.isEmpty ? '(No additional note)' : safeNote);
  if (includeContent) {
    final safeQuestion = _reportText(
      question,
      answerReportPartLimit,
      sensitiveValues,
    );
    final safeAnswer = _reportText(
      answer,
      answerReportPartLimit,
      sensitiveValues,
    );
    body
      ..write('\n\nQuestion:\n')
      ..write(
        safeQuestion.isEmpty ? '(No text question included)' : safeQuestion,
      )
      ..write('\n\nAnswer:\n')
      ..write(safeAnswer.isEmpty ? '(No answer text included)' : safeAnswer);
  } else {
    body.write('\n\nQuestion and answer not included.');
  }
  return body.toString();
}

Uri answerReportEmailUri(String body) => Uri(
  scheme: 'mailto',
  path: answerReportSupportEmail,
  // Use percent escapes instead of form-style '+' for non-HTTP mail clients.
  query:
      'subject=${Uri.encodeComponent('CalcAI answer report')}'
      '&body=${Uri.encodeComponent(body)}',
);
