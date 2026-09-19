import 'package:calcai_app/services/cloud_service.dart';

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
  FakeCloudService();

  @override
  Future<void> loadDashboard(String token, String mac) async {
    _currentMac = mac;
    notifyListeners();
  }

  @override
  Future<String> getNotes(String token, String mac) async {
    _notes = _notesPayload;
    notifyListeners();
    return _notesPayload;
  }

  @override
  Future<void> setNotes(String token, String mac, String text) async {
    _notesPayload = text;
    _notes = text;
    notifyListeners();
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
  Future<String> getContext(String token, String mac) async => customContext;

  @override
  Future<bool> setContext(String token, String mac, String context) async {
    _customContext = context;
    notifyListeners();
    return true;
  }

  @override
  Future<void> setModel(
    String token,
    String mac,
    String model,
    String style, {
    String? effort,
    bool? fastMode,
  }) async {
    _modelInfo = {
      'model': model,
      'style': style,
      'effort': effort ?? thinkingEffort,
      'fastMode': fastMode ?? false,
    };
    notifyListeners();
  }
}
