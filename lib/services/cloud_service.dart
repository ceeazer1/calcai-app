import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  // ── Convenience Getters ─────────────────────────────────────────────

  /// The display name for the device (e.g. "TI-84 Plus").
  String? get deviceName => _deviceInfo?['model']?.toString() ??
      _deviceInfo?['name']?.toString();

  /// Current AI model name (e.g. "gpt-5.4-mini").
  String? get currentModel => _modelInfo?['model']?.toString();

  /// Current response style ("answer", "small", or "detailed").
  String get responseStyle => _modelInfo?['style']?.toString() ?? 'small';

  /// Plan type (e.g. "Free", "Pro").
  String? get planType => _usage?['plan']?.toString() ??
      _usage?['planType']?.toString();

  /// Number of standard/cheap model calls used today.
  int get cheapUsage => (_usage?['cheapCount'] as num?)?.toInt() ?? 0;

  /// Number of premium model calls used today.
  int get premiumUsage => (_usage?['expensiveCount'] as num?)?.toInt() ?? 0;

  /// Daily limit for cheap calls (-1 = unlimited/pro).
  int get cheapLimit => (_usage?['cheapLimit'] as num?)?.toInt() ?? 30;

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

      final response = await http.get(
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

  /// Claims / pairs a new device to the authenticated user's account.
  ///
  /// POST /ai/pair/claim  body: {mac}
  Future<void> claimDevice(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await http.post(
        Uri.parse('$_baseUrl/ai/pair/claim'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({'mac': mac}),
      );

      _assertSuccess(response);

      // Refresh device list after successful claim.
      await getDevices(token);
    } catch (e) {
      _setError('Failed to claim device: ${_friendlyError(e)}');
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

      final response = await http.get(
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

      final response = await http.get(
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

  /// Updates the AI model and response style for a device.
  ///
  /// POST /ai/model/set  body: {mac, model, style}
  Future<void> setModel(
    String token,
    String mac,
    String model,
    String style,
  ) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await http.post(
        Uri.parse('$_baseUrl/ai/model/set'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({
          'mac': mac,
          'model': model,
          'style': style,
        }),
      );

      _assertSuccess(response);

      // Optimistic update so the UI reflects changes immediately.
      _modelInfo = {'model': model, 'style': style};
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
  /// GET /ai/notes/get?mac=
  Future<String> getNotes(String token, String mac) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await http.get(
        Uri.parse('$_baseUrl/ai/notes/get?mac=$mac'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      final data = jsonDecode(response.body);
      _notes = (data is Map ? data['text'] : data).toString();
      notifyListeners();
      return _notes!;
    } catch (e) {
      _setError('Failed to load notes: ${_friendlyError(e)}');
      return '';
    } finally {
      _setLoading(false);
    }
  }

  /// Saves user notes for a device.
  ///
  /// POST /ai/notes/set  body: {mac, text}
  Future<void> setNotes(String token, String mac, String text) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await http.post(
        Uri.parse('$_baseUrl/ai/notes/set'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({'mac': mac, 'text': text}),
      );

      _assertSuccess(response);

      _notes = text;
      notifyListeners();
    } catch (e) {
      _setError('Failed to save notes: ${_friendlyError(e)}');
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

      final response = await http.get(
        Uri.parse('$_baseUrl/ai/logs/recent?mac=$mac&limit=$limit'),
        headers: _authHeaders(token),
      );

      _assertSuccess(response);

      final data = jsonDecode(response.body);
      // Worker returns { ok, items: [...] }
      final List<dynamic> raw = data is List ? data : (data['items'] ?? data['logs'] ?? []);
      _history = raw.cast<Map<String, dynamic>>();

      notifyListeners();
      return _history;
    } catch (e) {
      _setError('Failed to load history: ${_friendlyError(e)}');
      return [];
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

      final response = await http.get(
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
      // Fire all three requests concurrently.
      final results = await Future.wait<dynamic>(
        [
          getModel(token, mac),
          getUsage(token, mac),
          getDeviceInfo(token, mac),
        ],
        eagerError: false,
      );

      debugPrint(
        'CalcAI Cloud: Dashboard loaded — '
        'model=${(results[0] as Map).length} keys, '
        'usage=${(results[1] as Map).length} keys, '
        'info=${(results[2] as Map).length} keys',
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

  /// List all saved API keys. Returns provider → { active, last4 }.
  Future<Map<String, dynamic>> listApiKeys(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/ai/apikey/list'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          // Remove non-provider keys like 'ok'
          _apiKeys = Map.from(data)..remove('ok');
          notifyListeners();
        }
      }
      return _apiKeys;
    } catch (e) {
      debugPrint('listApiKeys error: $e');
      return _apiKeys;
    }
  }

  /// Save an API key for a provider. Backend validates the key first.
  Future<bool> saveApiKey(String token, String provider, String key) async {
    try {
      final resp = await http.post(
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
          };
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('saveApiKey error: $e');
      return false;
    }
  }

  /// Delete a saved API key for a provider.
  Future<bool> deleteApiKey(String token, String provider) async {
    try {
      final resp = await http.post(
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
      debugPrint('deleteApiKey error: $e');
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    debugPrint('CalcAI Cloud: $message');
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
    _notes = null;
    _history = [];
    _usage = null;
    _error = null;
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
