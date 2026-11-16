import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/models/initial_release_ai.dart';

/// Test double for [CloudService].
///
/// It starts empty — no fabricated notes or history — but lets notes be
/// created, edited and deleted so the feature can be exercised in a test.
class FakeCloudService extends CloudService {
  @override
  Future<Map<String, dynamic>> readAiConsent(String token) async => {
    'ok': true,
    'version': CloudService.aiConsentVersion,
    'reviewed': true,
    'allowed': false,
  };

  @override
  Future<void> saveAiConsent(String token, bool allowed) async {}
  String? _currentMac, _notes;
  String _customContext = '';
  Map<String, dynamic>? _modelInfo;
  int _modelSaveRevision = 0;
  @override
  int get modelSaveRevision => _modelSaveRevision;
  List<Map<String, dynamic>> _history = [];
  final List<String> _devices = [];
  final Map<String, dynamic> _apiKeys = {};
  @override
  String? get currentMac => _currentMac;
  @override
  String? get notes => _notes;
  @override
  String get customContext => _customContext;
  @override
  Map<String, dynamic>? get modelInfo => _modelInfo;
  @override
  String? get currentModel => _modelInfo?['model']?.toString();
  @override
  String get responseStyle => _modelInfo?['style']?.toString() ?? 'small';
  @override
  String get thinkingEffort => _modelInfo?['effort']?.toString() ?? 'fast';

  /// Notes envelope, exactly as the real backend would store it.
  String _notesPayload = '';
  int _notesRevision = 0;
  FakeCloudService({http.Client? client})
    : super(
        client:
            client ??
            MockClient(
              (_) async => http.Response('{"error":"usage_unavailable"}', 503),
            ),
      );

  @override
  Future<void> loadDashboard(String token, String mac) async {
    _currentMac = mac;
    notifyListeners();
  }

  @override
  Future<String> getNotes(String token, String mac) async =>
      (await readNotesSnapshot(token, mac)).text;

  @override
  Future<EditSnapshot> readNotesSnapshot(String token, String mac) async {
    _notes = _notesPayload;
    notifyListeners();
    return (
      text: _notesPayload,
      revision: _notesRevision,
      etag: '"fixture-notes-$_notesRevision"',
    );
  }

  @override
  Future<bool> setNotes(
    String token,
    String mac,
    String text, {
    EditSnapshot? base,
  }) async =>
      base != null &&
      await writeNotesSnapshot(token, mac, text, base: base) != null;

  @override
  Future<EditSnapshot?> writeNotesSnapshot(
    String token,
    String mac,
    String text, {
    required EditSnapshot base,
  }) async {
    if (base.revision != _notesRevision ||
        base.etag != '"fixture-notes-$_notesRevision"') {
      return null;
    }
    _notesRevision++;
    _notesPayload = text;
    _notes = text;
    notifyListeners();
    return (
      text: text,
      revision: _notesRevision,
      etag: '"fixture-notes-$_notesRevision"',
    );
  }

  // ── Everything else stays local so the test never hits the network ──

  @override
  Future<List<Map<String, dynamic>>> getHistory(
    String token,
    String mac, {
    int limit = 50,
  }) async => _history;

  @override
  Future<bool> clearHistory(String token, String mac) async {
    _history = [];
    notifyListeners();
    return true;
  }

  @override
  Future<List<String>> getDevices(String token) async => _devices;

  @override
  Future<bool> claimDevice(
    String token,
    String mac, {
    String? nonce,
    String? challengeResponse,
  }) async => true;

  @override
  Future<Map<String, dynamic>> listApiKeys(String token) async => _apiKeys;

  @override
  Future<String> getContext(String token, String mac) async =>
      (await readContextSnapshot(token, mac)).text;

  int _contextRevision = 0;

  @override
  Future<EditSnapshot> readContextSnapshot(String token, String mac) async => (
    text: _customContext,
    revision: _contextRevision,
    etag: '"fixture-context-$_contextRevision"',
  );

  @override
  Future<bool> setContext(
    String token,
    String mac,
    String context, {
    EditSnapshot? base,
  }) async =>
      base != null &&
      await writeContextSnapshot(token, mac, context, base: base) != null;

  @override
  Future<EditSnapshot?> writeContextSnapshot(
    String token,
    String mac,
    String context, {
    required EditSnapshot base,
  }) async {
    if (base.revision != _contextRevision ||
        base.etag != '"fixture-context-$_contextRevision"') {
      return null;
    }
    _contextRevision++;
    _customContext = context;
    notifyListeners();
    return (
      text: context,
      revision: _contextRevision,
      etag: '"fixture-context-$_contextRevision"',
    );
  }

  @override
  Future<void> updateModelPreferences(
    String token,
    String mac, {
    String? style,
    String? effort,
  }) async {
    _modelInfo = {
      ...?_modelInfo,
      'model': _modelInfo?['model'] ?? InitialReleaseAi.defaultModel,
      'style': style ?? responseStyle,
      'effort': effort ?? thinkingEffort,
    };
    _modelSaveRevision++;
    notifyListeners();
  }

  @override
  Future<void> setModel(
    String token,
    String mac,
    String model,
    String style, {
    String? effort,
    bool? fastMode,
    String? fastModeFunding,
  }) async {
    _modelInfo = {
      'model': model,
      'style': style,
      'effort': effort ?? thinkingEffort,
      'fastMode': fastMode ?? false,
    };
    _modelSaveRevision++;
    notifyListeners();
  }
}
