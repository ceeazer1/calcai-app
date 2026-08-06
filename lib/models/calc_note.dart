import 'dart:convert';
import 'dart:math';

/// Maximum notes per plan.
const int kMaxNotesFree = 5;
const int kMaxNotesPro = 10;

/// A single note synced to the CalcAI device.
///
/// Notes are stored server-side as a `calcai-notes-v1` envelope. The worker
/// flattens them to `body | body | …` when the calculator fetches them, so the
/// [body] is what actually shows up on the calculator screen.
class CalcNote {
  CalcNote({
    required this.id,
    required this.body,
    this.title = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String body;
  final String title;
  final int createdAt;
  final int updatedAt;

  /// First line of the body, used as a fallback label in the list.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final first = body.trim().split(RegExp(r'\r?\n')).first;
    return first.length > 30 ? first.substring(0, 30) : first;
  }

  CalcNote copyWith({String? body, String? title}) => CalcNote(
        id: id,
        body: body ?? this.body,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  static String newId() {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    // 1 << 30, not 1 << 32: on the web an int shift wraps at 32 bits, so
    // `1 << 32` evaluates to 0 and nextInt(0) throws a RangeError. Only four
    // base-36 characters are kept anyway, so the smaller range costs nothing.
    final rand = Random().nextInt(1 << 30).toRadixString(36);
    return '$now${rand.padLeft(4, '0').substring(0, 4)}';
  }

  factory CalcNote.create({required String body, String title = ''}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return CalcNote(
      id: newId(),
      body: body,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory CalcNote.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return CalcNote(
      id: (j['id'] ?? newId()).toString(),
      body: (j['body'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      createdAt: (j['createdAt'] as num?)?.toInt() ?? now,
      updatedAt: (j['updatedAt'] as num?)?.toInt() ?? now,
    );
  }

  /// Parses the stored payload. Accepts the `calcai-notes-v1` envelope and
  /// falls back to treating raw text as a single note (same as the dashboard,
  /// so older single-text notes aren't lost).
  static List<CalcNote> parseStored(String raw) {
    if (raw.trim().isEmpty) return [];
    try {
      final obj = jsonDecode(raw);
      if (obj is Map &&
          obj['type'] == 'calcai-notes-v1' &&
          obj['notes'] is List) {
        return (obj['notes'] as List)
            .whereType<Map>()
            .map((n) => CalcNote.fromJson(Map<String, dynamic>.from(n)))
            .take(kMaxNotesPro)
            .toList();
      }
    } catch (_) {
      // Not JSON — treat as legacy plain text below.
    }
    return [CalcNote.create(body: raw)];
  }

  /// Serialises notes back into the envelope the worker and dashboard expect.
  static String toEnvelope(List<CalcNote> notes) => jsonEncode({
        'type': 'calcai-notes-v1',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'count': notes.length,
        'notes': notes.map((n) => n.toJson()).toList(),
      });
}
