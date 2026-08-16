import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'resilient_http_client.dart';
import '../utils/log.dart';

/// Cloud service for the CalcAI REST API at [_baseUrl].
///
/// Uses [ChangeNotifier] so the UI can reactively rebuild via [Provider].
/// Every network call requires a Bearer [token] obtained from AuthService.
///
/// State properties are populated by the individual fetch methods and by the
/// convenience [loadDashboard] aggregator. The UI simply reads the getters
/// and calls [notifyListeners] is handled internally.
class CloudService extends ChangeNotifier {
  // ── Constants ───────────────────────────────────────────────────────

  /// Base URL for all CalcAI cloud endpoints.
  static const String _baseUrl = 'https://ai.calcai.cc';

  /// Shared client that resolves the API host over DoH, so requests work even
  /// on networks whose router DNS blocks the domain.
  final http.Client _client = createResilientClient();

  // ── State ───────────────────────────────────────────────────────────

  /// MAC address of the currently selected device.
  String? _currentMac;
  String? get currentMac => _currentMac;

  /// List of MAC addresses owned by the user.
  List<String> _devices = [];
  List<String> get devices => List.unmodifiable(_devices);

  /// Detailed info for the currently selected device.
  Map<String, dynamic>? _deviceInfo;
  Map<String, dynamic>? get deviceInfo => _deviceInfo;

  /// AI model configuration for the current device ({model, style}).
  Map<String, dynamic>? _modelInfo;
  Map<String, dynamic>? get modelInfo => _modelInfo;

  /// User notes for the current device.
  String? _notes;
  String? get notes => _notes;

  /// Recent conversation history entries.
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  /// Token / usage status for the current device.
  Map<String, dynamic>? _usage;
  Map<String, dynamic>? get usage => _usage;

  /// Whether a network request is in progress.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Human-readable error message (null when there is no error).
  String? _error;
  String? get error => _error;

  /// Per-feature errors. [error] is shared by every call, so without these a
  /// failing notes fetch made the History tab report "Couldn't load history".
  /// Screens should prefer the specific one.
  String? _historyError;
  String? get historyError => _historyError;

  String? _notesError;
  String? get notesError => _notesError;

  // ── Convenience Getters ─────────────────────────────────────────────

  /// The display name for the device (e.g. "TI-84 Plus").
  String? get deviceName => _deviceInfo?['model']?.toString() ??
      _deviceInfo?['name']?.toString();

  /// Current AI model name (e.g. "gpt-5.4-mini").
  String? get currentModel => _modelInfo?['model']?.toString();

  /// Current response style ("answer", "small", or "detailed").
  String get responseStyle => _modelInfo?['style']?.toString() ?? 'small';

  /// How hard the model may think before answering ("fast", "balanced" or
  /// "thorough"). The worker translates it per provider.
  String get thinkingEffort => _modelInfo?['effort']?.toString() ?? 'fast';

  /// The user's own standing instructions, appended to every prompt.
  String _customContext = '';
  String get customContext => _customContext;

  /// Plan type (e.g. "Free", "Pro").
  String? get planType => _usage?['plan']?.toString() ??
      _usage?['planType']?.toString();

  /// Number of standard/cheap model calls used today.
  int get cheapUsage => (_usage?['cheapCount'] as num?)?.toInt() ?? 0;

  /// Number of premium model calls used today.
  int get premiumUsage => (_usage?['expensiveCount'] as num?)?.toInt() ?? 0;

  /// Daily limit for cheap calls (-1 = unlimited/pro).
  int get cheapLimit => (_usage?['cheapLimit'] as num?)?.toInt() ?? 50;

  /// Daily limit for premium calls (-1 = unlimited/pro).
  int get premiumLimit => (_usage?['expensiveLimit'] as num?)?.toInt() ?? 10;

  // ── Device Management ─────────────────────────────────────────────

  /// Fetches the list of MAC addresses associated with the authenticated user.
  ///
  /// GET /ai/user/devices
  Future<List<String>> getDevices(String token) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/user/devices'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      final data = jsonDecode(response.body);
      final List<dynamic> raw = data is List ? data : (data['devices'] ?? []);
      // Worker returns [{mac, pairedAt}] objects or plain strings.
      _devices = raw.map((e) {
        if (e is Map) return (e['mac'] ?? '').toString();
        return e.toString();
      }).where((m) => m.isNotEmpty).toList();

      notifyListeners();
      return _devices;
    } catch (e) {
      _setError('Failed to load devices: ${_friendlyError(e)}');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  /// Asks the backend whether a BLE peripheral is a genuine CalcAI device.
  ///
  /// POST /ai/device/verify  body: {mac, nonce, response}
  ///
  /// Only the backend holds PAIR_MASTER_SECRET, so only it can judge the
  /// device's answer. Returns false on any error, including no network —
  /// callers treat a failure as "do not trust this device", so an attacker
  /// cannot get past the check by making the request fail.
  Future<bool> verifyDevice(
    String token,
    String mac,
    String nonce,
    String response,
  ) async {
    try {
      final resp = await _client
          .post(
            Uri.parse('$_baseUrl/ai/device/verify'),
            headers: _jsonAuthHeaders(token),
            body: jsonEncode({
              'mac': mac,
              'nonce': nonce,
              'response': response,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        logDebug('verifyDevice rejected: ${resp.statusCode}');
        return false;
      }
      final data = jsonDecode(resp.body);
      return data is Map && data['ok'] == true;
    } catch (e) {
      logDebug('verifyDevice error: $e');
      return false;
    }
  }

  /// Claims / pairs a new device to the authenticated user's account.
  ///
  /// POST /ai/pair/claim  body: {mac, nonce, response}
  ///
  /// [nonce] / [challengeResponse] are the device's answer to the identity
  /// challenge read over BLE, proving the claimer was physically connected to
  /// a real device rather than guessing a MAC.
  /// Returns true only when the device now belongs to this account.
  ///
  /// This **must** be checked. A device already claimed by someone else comes
  /// back 409, and treating that as success leaves the app believing it owns
  /// hardware the backend will refuse to serve — every history/notes/usage
  /// call then 403s with no explanation.
  Future<bool> claimDevice(
    String token,
    String mac, {
    String? nonce,
    String? challengeResponse,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.post(
        Uri.parse('$_baseUrl/ai/pair/claim'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({
          'mac': mac,
          if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
          if (challengeResponse != null && challengeResponse.isNotEmpty)
            'response': challengeResponse,
        }),
      );

      // 409 is the ownership lock doing its job, and the body is plain text,
      // so spell the message out rather than surfacing "Conflict".
      if (response.statusCode == 409) {
        _setError(
          'This CalcAI is already linked to another account. Sign in with '
          'that account, or remove the device from it first.',
        );
        return false;
      }

      _assertSuccess(response);

      // Refresh device list after successful claim.
      await getDevices(token);
      return true;
    } catch (e) {
      _setError('Failed to claim device: ${_friendlyError(e)}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Retrieves detailed information for a specific device.
  ///
  /// GET /ai/device/info?mac=
  Future<Map<String, dynamic>> getDeviceInfo(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/device/info?mac=$mac'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      _deviceInfo = jsonDecode(response.body) as Map<String, dynamic>;
      notifyListeners();
      return _deviceInfo!;
    } catch (e) {
      _setError('Failed to load device info: ${_friendlyError(e)}');
      return {};
    } finally {
      _setLoading(false);
    }
  }

  // ── AI Model ──────────────────────────────────────────────────────

  /// Gets the current AI model configuration for a device.
  ///
  /// GET /ai/model/get?mac=  → {model, style}
  Future<Map<String, dynamic>> getModel(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/model/get?mac=$mac'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      _modelInfo = jsonDecode(response.body) as Map<String, dynamic>;
      notifyListeners();
      return _modelInfo!;
    } catch (e) {
      _setError('Failed to load model: ${_friendlyError(e)}');
      return {};
    } finally {
      _setLoading(false);
    }
  }

  /// Loads the device's custom instructions.
  ///
  /// GET /ai/context/get?mac=…
  Future<String> getContext(String mac) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/context/get?mac=${Uri.encodeQueryComponent(mac)}'),
      );
      _assertSuccess(response);
      final j = jsonDecode(response.body) as Map<String, dynamic>;
      _customContext = (j['context'] ?? '').toString();
      notifyListeners();
      return _customContext;
    } catch (e) {
      // Non-fatal: an empty value just means no custom instructions.
      return _customContext;
    }
  }

  /// Saves the device's custom instructions.
  ///
  /// POST /ai/context/set  body: {mac, context}
  Future<bool> setContext(String token, String mac, String context) async {
    try {
      _setLoading(true);
      _clearError();
      final response = await _client.post(
        Uri.parse('$_baseUrl/ai/context/set'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({'mac': mac, 'context': context}),
      );
      _assertSuccess(response);
      _customContext = context;
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Failed to save instructions: ${_friendlyError(e)}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Updates the AI model, response style and thinking effort for a device.
  ///
  /// POST /ai/model/set  body: {mac, model, style, effort}
  Future<void> setModel(
    String token,
    String mac,
    String model,
    String style, {
    String? effort,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.post(
        Uri.parse('$_baseUrl/ai/model/set'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({
          'mac': mac,
          'model': model,
          'style': style,
          // Omitted rather than guessed: the worker keeps the stored value when
          // the field is absent, so a partial update can't reset it.
          if (effort != null) 'effort': effort,
        }),
      );

      _assertSuccess(response);

      // Optimistic update so the UI reflects changes immediately.
      _modelInfo = {
        'model': model,
        'style': style,
        'effort': effort ?? thinkingEffort,
      };
      notifyListeners();
    } catch (e) {
      _setError('Failed to update model: ${_friendlyError(e)}');
    } finally {
      _setLoading(false);
    }
  }

  // ── Notes ─────────────────────────────────────────────────────────

  /// Retrieves user notes for a device.
  ///
  /// GET /ai/notes/raw?mac= — the app-facing JSON endpoint, which returns the
  /// stored `calcai-notes-v1` envelope verbatim.
  ///
  /// Deliberately *not* /ai/notes/get: that one belongs to the firmware. It
  /// answers `text/plain`, replies 204 with an empty body when there are no
  /// notes, and flattens the envelope into " | "-joined bodies for the
  /// calculator LCD — none of which the app can parse.
  Future<String> getNotes(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/notes/raw?mac=$mac'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);
      _notesError = null;

      // An empty body is "no notes", not a failure.
      final body = response.body.trim();
      _notes = body.isEmpty ? '' : (_decodeJson(body)['text'] ?? '').toString();
      notifyListeners();
      return _notes!;
    } catch (e) {
      _notesError = 'Failed to load notes: ${_friendlyError(e)}';
      _setError(_notesError!);
      return '';
    } finally {
      _setLoading(false);
    }
  }

  /// Decodes a JSON object body, turning a non-JSON payload into a clear
  /// message instead of a bare `FormatException`.
  Map<String, dynamic> _decodeJson(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Expected a JSON object');
  }

  /// Saves user notes for a device.
  ///
  /// POST /ai/notes/set  body: {mac, text}
  Future<void> setNotes(String token, String mac, String text) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.post(
        Uri.parse('$_baseUrl/ai/notes/set'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({'mac': mac, 'text': text}),
      );

      _assertSuccess(response);
      _notesError = null;

      _notes = text;
      notifyListeners();
    } catch (e) {
      _notesError = 'Failed to save notes: ${_friendlyError(e)}';
      _setError(_notesError!);
    } finally {
      _setLoading(false);
    }
  }

  // ── History ───────────────────────────────────────────────────────

  /// Fetches recent conversation history for a device.
  ///
  /// GET /ai/logs/recent?mac=&limit=
  Future<List<Map<String, dynamic>>> getHistory(
    String token,
    String mac, {
    int limit = 50,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/logs/recent?mac=$mac&limit=$limit'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);
      _historyError = null;

      final data = jsonDecode(response.body);
      // Worker returns { ok, items: [...] }
      final List<dynamic> raw = data is List ? data : (data['items'] ?? data['logs'] ?? []);
      _history = raw.cast<Map<String, dynamic>>();

      notifyListeners();
      return _history;
    } catch (e) {
      _historyError = 'Failed to load history: ${_friendlyError(e)}';
      _setError(_historyError!);
      return [];
    } finally {
      _setLoading(false);
    }
  }

  /// Permanently deletes all activity history for a device.
  ///
  /// DELETE /ai/logs/clear?mac=
  Future<bool> clearHistory(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.delete(
        Uri.parse('$_baseUrl/ai/logs/clear?mac=$mac'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      _history = [];
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Failed to clear history: ${_friendlyError(e)}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── Usage ─────────────────────────────────────────────────────────

  /// Gets token / usage status for a device.
  ///
  /// GET /ai/usage/status?mac=
  Future<Map<String, dynamic>> getUsage(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _client.get(
        Uri.parse('$_baseUrl/ai/usage/status?mac=$mac'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      _usage = jsonDecode(response.body) as Map<String, dynamic>;
      notifyListeners();
      return _usage!;
    } catch (e) {
      _setError('Failed to load usage: ${_friendlyError(e)}');
      return {};
    } finally {
      _setLoading(false);
    }
  }

  // ── Dashboard Aggregator ──────────────────────────────────────────

  /// Loads the dashboard for [mac] by fetching model, usage, and device
  /// info in parallel. Sets [currentMac] so dependent widgets know which
  /// device is selected.
  ///
  /// Errors from individual calls are surfaced through [error]; partial
  /// successes still populate the corresponding state fields.
  Future<void> loadDashboard(String token, String mac) async {
    _currentMac = mac;
    _clearError();
    _setLoading(true);

    try {
      // Fire all requests concurrently. History is included so the home
      // "Recent Activity" card has data without needing the History tab.
      final results = await Future.wait<dynamic>(
        [
          getModel(token, mac),
          getUsage(token, mac),
          getDeviceInfo(token, mac),
          getHistory(token, mac, limit: 10),
          getContext(mac),
        ],
        eagerError: false,
      );

      logDebug(
        'CalcAI Cloud: Dashboard loaded — '
        'model=${(results[0] as Map).length} keys, '
        'usage=${(results[1] as Map).length} keys, '
        'info=${(results[2] as Map).length} keys, '
        'history=${(results[3] as List).length} items',
      );
    } catch (e) {
      _setError('Dashboard load error: ${_friendlyError(e)}');
    } finally {
      _setLoading(false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Standard authorization header map.
  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
      };

  /// Authorization + JSON content-type header map (for POST requests).
  Map<String, String> _jsonAuthHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Throws a [CloudException] when the HTTP status code indicates failure.
  void _assertSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message;
      try {
        final body = jsonDecode(response.body);
        message = body['error'] ?? body['message'] ?? response.reasonPhrase;
      } catch (_) {
        message = response.reasonPhrase ?? 'Unknown error';
      }
      throw CloudException(response.statusCode, message.toString());
    }
  }

  // ── API Key Management ───────────────────────────────────────────────

  /// Saved API key info per provider: { 'openai': { active: true, last4: 'xxxx' }, ... }
  Map<String, dynamic> _apiKeys = {};
  Map<String, dynamic> get apiKeys => Map.unmodifiable(_apiKeys);

  /// Whether a specific provider has a saved key.
  bool hasApiKey(String provider) {
    final info = _apiKeys[provider.toLowerCase()];
    return info != null && info['active'] == true;
  }

  /// Get the last 4 chars of a saved key for display.
  String? apiKeyLast4(String provider) {
    final info = _apiKeys[provider.toLowerCase()];
    return info?['last4']?.toString();
  }

  /// Whether the saved key for [provider] is currently enabled (in use).
  /// Defaults to true when a key exists but no flag is present.
  bool apiKeyEnabled(String provider) {
    final info = _apiKeys[provider.toLowerCase()];
    if (info == null) return false;
    return info['enabled'] != false;
  }

  /// Turns usage of a saved key on/off without deleting it.
  Future<bool> toggleApiKey(String token, String provider, bool enabled) async {
    final p = provider.toLowerCase();
    // Optimistic update.
    if (_apiKeys[p] is Map) {
      (_apiKeys[p] as Map)['enabled'] = enabled;
      notifyListeners();
    }
    try {
      final resp = await _client.post(
        Uri.parse('$_baseUrl/ai/apikey/toggle'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'provider': p, 'enabled': enabled}),
      );
      if (resp.statusCode == 200) return true;
    } catch (e) {
      logDebug('toggleApiKey error: $e');
    }
    // Revert on failure.
    if (_apiKeys[p] is Map) {
      (_apiKeys[p] as Map)['enabled'] = !enabled;
      notifyListeners();
    }
    return false;
  }

  /// List all saved API keys. Returns provider → { active, last4 }.
  Future<Map<String, dynamic>> listApiKeys(String token) async {
    try {
      final resp = await _client.get(
        Uri.parse('$_baseUrl/ai/apikey/list'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        // Worker returns { ok, keys: { openai: {...}, ... } }.
        final keysMap = (data is Map) ? data['keys'] : null;
        if (keysMap is Map) {
          _apiKeys = Map<String, dynamic>.from(keysMap);
          notifyListeners();
        }
      }
      return _apiKeys;
    } catch (e) {
      logDebug('listApiKeys error: $e');
      return _apiKeys;
    }
  }

  /// Save an API key for a provider. Backend validates the key first.
  Future<bool> saveApiKey(String token, String provider, String key) async {
    try {
      final resp = await _client.post(
        Uri.parse('$_baseUrl/ai/apikey/save'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'provider': provider.toLowerCase(), 'key': key}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['ok'] == true) {
          _apiKeys[provider.toLowerCase()] = {
            'active': true,
            'last4': data['last4'],
            'enabled': true,
          };
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      logDebug('saveApiKey error: $e');
      return false;
    }
  }

  /// Delete a saved API key for a provider.
  Future<bool> deleteApiKey(String token, String provider) async {
    try {
      final resp = await _client.post(
        Uri.parse('$_baseUrl/ai/apikey/delete'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'provider': provider.toLowerCase()}),
      );
      if (resp.statusCode == 200) {
        _apiKeys.remove(provider.toLowerCase());
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      logDebug('deleteApiKey error: $e');
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    logDebug('CalcAI Cloud: $message');
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  /// Converts exceptions to concise, user-friendly messages.
  String _friendlyError(dynamic e) {
    if (e is CloudException) return e.message;
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('HandshakeException')) {
      return 'Network error — check your internet connection.';
    }
    if (msg.contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }
    if (msg.contains('FormatException')) {
      return 'Unexpected server response.';
    }
    return msg.replaceAll('Exception: ', '');
  }

  /// Resets all cached state. Useful when switching users or signing out.
  void reset() {
    _currentMac = null;
    _devices = [];
    _deviceInfo = null;
    _modelInfo = null;
    _customContext = '';
    _notes = null;
    _history = [];
    _usage = null;
    _error = null;
    _historyError = null;
    _notesError = null;
    _isLoading = false;
    notifyListeners();
  }
}

/// Exception type for non-2xx HTTP responses from the CalcAI API.
class CloudException implements Exception {
  /// The HTTP status code returned by the server.
  final int statusCode;

  /// A human-readable error description.
  final String message;

  const CloudException(this.statusCode, this.message);

  @override
  String toString() => 'CloudException($statusCode): $message';
}

/// Test double for [CloudService].
///
/// It starts empty — no fabricated notes or history — but lets notes be
/// created, edited and deleted so the feature can be exercised in a test.
class PreviewCloudService extends CloudService {
  /// Notes envelope, exactly as the real backend would store it.
  String _notesPayload = '';
  PreviewCloudService();

  @override
  Future<void> loadDashboard(String token, String mac) async {
    _currentMac = mac;
    notifyListeners();
  }

  @override
  Future<String> getNotes(String token, String mac) async {
    _notes = _notesPayload;
    _clearError();
    notifyListeners();
    return _notesPayload;
  }

  @override
  Future<void> setNotes(String token, String mac, String text) async {
    _notesPayload = text;
    _notes = text;
    _clearError();
    notifyListeners();
  }

  // ── Everything else stays local so preview never hits the network ──

  @override
  Future<List<Map<String, dynamic>>> getHistory(String token, String mac,
      {int limit = 50}) async => _history;

  @override
  Future<bool> clearHistory(String token, String mac) async {
    _history = [];
    notifyListeners();
    return true;
  }

  @override
  Future<List<String>> getDevices(String token) async => _devices;

  @override
  Future<bool> claimDevice(String token, String mac,
      {String? nonce, String? challengeResponse}) async => true;

  @override
  Future<Map<String, dynamic>> listApiKeys(String token) async => _apiKeys;

  @override
  Future<String> getContext(String mac) async => customContext;

  @override
  Future<bool> setContext(String token, String mac, String context) async {
    _customContext = context;
    notifyListeners();
    return true;
  }

  @override
  Future<void> setModel(String token, String mac, String model, String style,
      {String? effort}) async {
    _modelInfo = {
      'model': model,
      'style': style,
      'effort': effort ?? thinkingEffort,
    };
    notifyListeners();
  }
}
