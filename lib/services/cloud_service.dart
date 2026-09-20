import 'dart:async';
import 'usage_tracker.dart';
import 'auth_service.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'resilient_http_client.dart';
import 'session_http_client.dart';
import '../utils/log.dart';

/// Returns true only for the Worker's explicit ownership-revocation response.
///
/// A 403 can also mean a failed device proof, a disabled feature, or another
/// security check. Treating every 403 as an unpair wipes a perfectly valid
/// local pairing and sends the user back through setup.
@visibleForTesting
bool isDeviceOwnershipRevocation(http.Response response) {
  if (response.statusCode != 403) return false;
  try {
    final body = jsonDecode(response.body);
    return body is Map && body['error'] == 'device_not_owned';
  } catch (_) {
    return false;
  }
}

class AiConsentException implements Exception {
  const AiConsentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PairingReleaseException implements Exception {
  const PairingReleaseException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  /// Session-guarded platform HTTP transport.
  final SessionHttpClient _client;

  CloudService({http.Client? client, AuthService? auth})
    : _client = SessionHttpClient(client ?? createResilientClient()) {
    usageTracker = UsageTracker(fetch: _fetchAccountUsage);
    usageTracker.addListener(notifyListeners);
    if (auth != null) {
      _auth = auth;
      _syncAuthUsage();
      auth.addListener(_syncAuthUsage);
    }
  }

  AuthService? _auth;
  String? _usageSession;
  late final UsageTracker usageTracker;
  void _syncAuthUsage() => bindUsageSession(_auth?.token);

  void bindUsageSession(String? token) {
    if (_usageSession == token) return;
    reset();
    _usageSession = token;
    usageTracker.bind(token);
    if (token != null) {
      unawaited(usageTracker.refresh());
      unawaited(listApiKeys(token));
    }
  }

  static const aiConsentVersion = '2026-09-13';

  Future<Map<String, dynamic>> readAiConsent(String token) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/ai/user/ai-consent'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    _checkConsentResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> saveAiConsent(String token, bool allowed) async {
    final response = await _client
        .put(
          Uri.parse('$_baseUrl/ai/user/ai-consent'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'version': aiConsentVersion, 'allowed': allowed}),
        )
        .timeout(const Duration(seconds: 20));
    _checkConsentResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['ok'] != true ||
        data['allowed'] != allowed ||
        data['version'] != aiConsentVersion) {
      throw const FormatException('Consent was not confirmed.');
    }
  }

  void _checkConsentResponse(http.Response response) {
    if (response.statusCode == 404 || response.statusCode == 405) {
      throw const AiConsentException(
        'AI sharing is not available on the server yet. Your choice has not been saved.',
      );
    }
    if (response.statusCode == 401) {
      throw const AiConsentException(
        'Your session expired. Please sign out and sign in again.',
      );
    }
    _assertSuccess(response);
  }

  int _keyGeneration = 0;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

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

  /// Authoritative account usage; independent of calculator pairing.
  Map<String, dynamic>? get usage => usageTracker.data?.json;

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
  String? get deviceName =>
      _deviceInfo?['model']?.toString() ?? _deviceInfo?['name']?.toString();

  /// Current AI model name (e.g. "gpt-5.4-mini").
  String? get currentModel => _modelInfo?['model']?.toString();

  /// Current response style ("answer", "small", or "detailed").
  String get responseStyle => _modelInfo?['style']?.toString() ?? 'small';

  /// How hard the model may think before answering ("fast", "balanced" or
  /// "thorough"). The worker translates it per provider.
  bool get fastMode => _modelInfo?['fastMode'] == true;

  String get thinkingEffort => _modelInfo?['effort']?.toString() ?? 'fast';

  /// The user's own standing instructions, appended to every prompt.
  String _customContext = '';
  String get customContext => _customContext;

  /// Plan type (e.g. "Free", "Pro").
  String? get planType =>
      usage?['plan']?.toString() ?? usage?['planType']?.toString();

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
      _devices = raw
          .map((e) {
            if (e is Map) return (e['mac'] ?? '').toString();
            return e.toString();
          })
          .where((m) => m.isNotEmpty)
          .toList();

      notifyListeners();
      return _devices;
    } catch (e) {
      _setError('Failed to load devices: ${_friendlyError(e)}');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  /// Re-checks the authoritative account-to-device mapping without changing
  /// any cached UI state. `null` means the check itself failed, so callers must
  /// preserve the local pairing instead of treating a network problem as an
  /// unpair.
  Future<bool?> confirmDeviceOwnership(String token, String mac) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/ai/user/devices'),
            headers: _authHeaders(token),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final List<dynamic> raw = data is List ? data : (data['devices'] ?? []);
      final target = mac.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toLowerCase();
      return raw.any((entry) {
        final value = entry is Map ? (entry['mac'] ?? '') : entry;
        final candidate = value
            .toString()
            .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
            .toLowerCase();
        return candidate == target;
      });
    } catch (_) {
      return null;
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

      // The successful claim is authoritative; avoid a second network request
      // before opening Wi-Fi setup. Dashboard refresh loads the full list later.
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

  /// Asks the backend to sign a proof that this account owns a calculator.
  ///
  /// POST /ai/pair/hello  body: {mac, nonce}
  ///
  /// Returns the signature, or null when the backend says this account is not
  /// the owner (403) or the device is unknown (404). The firmware cannot tell
  /// accounts apart on its own, so the backend is what decides.
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/ai/pair/hello'),
        headers: _jsonAuthHeaders(token),
        body: jsonEncode({'mac': mac, 'nonce': nonce}),
      );
      if (response.statusCode != 200) {
        logDebug(
          'ownership proof refused: ${response.statusCode} ${response.body}',
        );
        return null;
      }
      final j = jsonDecode(response.body);
      if (j is! Map || j['ok'] != true) return null;
      final sig = (j['response'] ?? '').toString();
      return RegExp(r'^[0-9a-f]{64}$').hasMatch(sig) ? sig : null;
    } catch (e) {
      logDebug('ownership proof failed: $e');
      return null;
    }
  }

  /// Asks the backend to sign a release for a calculator an admin has unpaired.
  ///
  /// POST /ai/pair/release  body: {mac, nonce}
  ///
  /// Null means the server explicitly confirmed an existing owner.
  /// Other failures retain their cause instead of pretending another owner exists.
  Future<String?> requestPairingRelease(
    String token,
    String mac,
    String nonce,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/ai/pair/release'),
            headers: _jsonAuthHeaders(token),
            body: jsonEncode({'mac': mac, 'nonce': nonce}),
          )
          .timeout(const Duration(seconds: 20));
      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      if (response.statusCode == 409 && body?['error'] == 'still_owned') {
        return null;
      }
      if (response.statusCode == 401) {
        throw const PairingReleaseException(
          'Sign out and sign in again, then scan your calculator.',
        );
      }
      if (response.statusCode == 503) {
        throw const PairingReleaseException(
          'Pairing recovery is unavailable on the server. Contact CalcAI support.',
        );
      }
      final signature = body?['response'];
      if (response.statusCode != 200 ||
          body?['ok'] != true ||
          signature is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(signature)) {
        throw const PairingReleaseException(
          'The server could not reset this pairing. Try again or contact CalcAI support.',
        );
      }
      return signature;
    } on PairingReleaseException {
      rethrow;
    } catch (_) {
      throw const PairingReleaseException(
        'Could not reach CalcAI to reset the pairing. Check your internet connection and retry.',
      );
    }
  }

  /// Loads the device's custom instructions.
  ///
  /// GET /ai/context/get?mac=…
  Future<String> getContext(String token, String mac) async {
    try {
      final response = await _client.get(
        Uri.parse(
          '$_baseUrl/ai/context/get?mac=${Uri.encodeQueryComponent(mac)}',
        ),
        headers: _authHeaders(token),
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
    bool? fastMode,
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
          if (fastMode != null) 'fastMode': fastMode,
        }),
      );

      _assertSuccess(response);

      // Use the server's accepted values, including model-switch resets.
      final accepted = jsonDecode(response.body) as Map<String, dynamic>;
      if (fastMode != null && accepted['fastMode'] is! bool) {
        throw StateError('Fast mode needs the updated CalcAI server.');
      }
      _modelInfo = {
        ...?_modelInfo,
        'model': accepted['model'] ?? model,
        'style': accepted['style'] ?? style,
        'effort': accepted['effort'] ?? effort ?? thinkingEffort,
        'fastMode': accepted['fastMode'] == true,
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
    if (_usageSession != token) bindUsageSession(token);
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
      final List<dynamic> raw = data is List
          ? data
          : (data['items'] ?? data['logs'] ?? []);
      final updated = raw.cast<Map<String, dynamic>>();
      final hasNewSolve =
          updated.isNotEmpty &&
          (_history.isEmpty ||
              jsonEncode(updated.first) != jsonEncode(_history.first));
      _history = updated;
      if (hasNewSolve) unawaited(refreshUsageAfterSolve(token));

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

  Future<Map<String, dynamic>> _fetchAccountUsage(String token) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/ai/usage/status'),
          headers: _authHeaders(token),
        )
        .timeout(const Duration(seconds: 20));
    _client.ensureCurrent(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Preserve the app's explicit ownership-revocation handling.
      try {
        _assertSuccess(response, updateUsage: false);
      } on CloudException {
        /* handled below */
      }
      Map body = {};
      try {
        body = jsonDecode(response.body) as Map;
      } catch (_) {}
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw UsageRequestException(
        response.statusCode,
        body['error']?.toString() ?? '',
        retryAfter: seconds == null
            ? null
            : Duration(seconds: seconds < 15 ? 15 : seconds),
        resetsAt: DateTime.tryParse(body['resetsAt']?.toString() ?? ''),
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['ok'] != true) throw const FormatException('Usage not confirmed');
    return body;
  }

  /// The optional MAC is retained for existing callers, never sent to the API.
  Future<Map<String, dynamic>> getUsage(String token, [String? mac]) async {
    if (_usageSession != token) {
      bindUsageSession(token);
    }
    await usageTracker.refresh();
    return usage ?? {};
  }

  /// Called when newly fetched calculator history reveals a completed solve.
  Future<void> refreshUsageAfterSolve(String token) async {
    if (_usageSession == token) await usageTracker.refreshAfterSolve();
  }

  // ── Dashboard Aggregator ──────────────────────────────────────────

  /// Loads the dashboard for [mac] by fetching model, usage, and device
  /// info in parallel. Sets [currentMac] so dependent widgets know which
  /// device is selected.
  ///
  /// Errors from individual calls are surfaced through [error]; partial
  /// successes still populate the corresponding state fields.
  Future<void> loadDashboard(String token, String mac) async {
    if (_usageSession != token) bindUsageSession(token);
    _currentMac = mac;
    _clearError();
    _setLoading(true);

    try {
      // Fire all requests concurrently. History is included so the home
      // "Recent Activity" card has data without needing the History tab.
      final results = await Future.wait<dynamic>([
        getModel(token, mac),
        getUsage(token, mac),
        getDeviceInfo(token, mac),
        getHistory(token, mac, limit: 10),
        getContext(token, mac),
      ], eagerError: false);

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
  /// True once the backend has told us this account no longer owns its
  /// calculator — an admin unpaired it, or it was claimed elsewhere.
  ///
  /// Every device-scoped call 403s from that point on, and without noticing it
  /// the app keeps showing a dashboard whose controls quietly do nothing.
  bool _deviceRevoked = false;
  bool get deviceRevoked => _deviceRevoked;

  void clearDeviceRevoked() {
    _deviceRevoked = false;
  }

  void _assertSuccess(http.Response response, {bool updateUsage = true}) {
    _client.ensureCurrent(response);
    // Only the Worker's explicit ownership error revokes a device. Other 403s
    // are independent security checks and must not erase a valid pairing.
    if (isDeviceOwnershipRevocation(response) && !_deviceRevoked) {
      _deviceRevoked = true;
      notifyListeners();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message;
      try {
        final body = jsonDecode(response.body);
        message = body['error'] ?? body['message'] ?? response.reasonPhrase;
      } catch (_) {
        message = response.reasonPhrase ?? 'Unknown error';
      }
      if (updateUsage &&
          (message == 'usage_limit_reached' ||
              message == 'usage_syncing' ||
              message == 'usage_unavailable')) {
        final body = jsonDecode(response.body) as Map;
        final retry =
            int.tryParse(response.headers['retry-after'] ?? '15') ?? 15;
        usageTracker.handleError(
          UsageRequestException(
            response.statusCode,
            message,
            resetsAt: DateTime.tryParse(body['resetsAt']?.toString() ?? ''),
            retryAfter: Duration(seconds: retry < 15 ? 15 : retry),
          ),
        );
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
    final generation = _keyGeneration;
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
      if (generation != _keyGeneration) return false;
      if (resp.statusCode == 200) return true;
    } catch (e) {
      logDebug('toggleApiKey error: $e');
    }
    // Revert on failure.
    if (generation == _keyGeneration && _apiKeys[p] is Map) {
      (_apiKeys[p] as Map)['enabled'] = !enabled;
      notifyListeners();
    }
    return false;
  }

  /// List all saved API keys. Returns provider → { active, last4 }.
  Future<Map<String, dynamic>> listApiKeys(String token) async {
    final generation = _keyGeneration;
    try {
      final resp = await _client.get(
        Uri.parse('$_baseUrl/ai/apikey/list'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (generation != _keyGeneration) return {};
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
    final generation = _keyGeneration;
    try {
      final resp = await _client.post(
        Uri.parse('$_baseUrl/ai/apikey/save'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'provider': provider.toLowerCase(), 'key': key}),
      );
      if (generation != _keyGeneration) return false;
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
    final generation = _keyGeneration;
    try {
      final resp = await _client.post(
        Uri.parse('$_baseUrl/ai/apikey/delete'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'provider': provider.toLowerCase()}),
      );
      if (generation != _keyGeneration) return false;
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
    _client.invalidate();
    _keyGeneration++;
    _apiKeys = {};
    _currentMac = null;
    _devices = [];
    _deviceInfo = null;
    _modelInfo = null;
    _customContext = '';
    _notes = null;
    _history = [];
    usageTracker.clear();
    _usageSession = null;
    _error = null;
    _historyError = null;
    _notesError = null;
    _isLoading = false;
    _deviceRevoked = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth?.removeListener(_syncAuthUsage);
    usageTracker.removeListener(notifyListeners);
    usageTracker.dispose();
    _keyGeneration++;
    _client.close();
    super.dispose();
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
