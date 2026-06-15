import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Manages authentication state for the CalcAI app.
///
/// Handles sign-in / sign-out, token persistence via [FlutterSecureStorage],
/// and device-list management via [SharedPreferences].
///
/// Consumers should listen to this [ChangeNotifier] (e.g. via `Provider`) to
/// react to auth-state transitions, loading indicators, and error messages.
class AuthService extends ChangeNotifier {
  // ── Dependencies ─────────────────────────────────────────────────────
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;

  // ── Constants ─────────────────────────────────────────────────────────
  static const String _baseUrl = 'https://ai.calcai.cc/ai';

  // Storage keys
  static const String _keyToken = 'auth_token';
  static const String _keyUsername = 'username';
  static const String _keyEmail = 'email';
  static const String _keyDeviceMacs = 'device_macs';
  static const String _keyPrimaryMac = 'primary_mac';

  /// Generate a cryptographically secure nonce for Apple Sign-In.
  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // ── State ─────────────────────────────────────────────────────────────

  /// Whether the user is currently authenticated.
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  /// True while an auth operation (sign-in, init, etc.) is in progress.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Bearer token returned by the server after successful sign-in.
  String? _token;
  String? get token => _token;

  /// Display name of the signed-in user.
  String? _username;
  String? get username => _username;

  /// Email address of the signed-in user.
  String? _email;
  String? get email => _email;

  /// Human-readable error message from the most recent operation, or `null`.
  String? _error;
  String? get error => _error;

  /// MAC addresses of all ESP32 devices paired to this account.
  List<String> _deviceMacs = [];
  List<String> get deviceMacs => List.unmodifiable(_deviceMacs);

  /// The MAC address of the currently active device.
  String? _primaryMac;
  String? get primaryMac => _primaryMac;

  /// Convenience getter — `true` when the user has at least one paired device.
  bool get hasDevices => _deviceMacs.isNotEmpty;

  // ── Constructor ───────────────────────────────────────────────────────

  /// Creates an [AuthService].
  ///
  /// Accepts optional [secureStorage] and [httpClient] for testability;
  /// production callers can rely on the defaults.
  AuthService({
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _httpClient = httpClient ?? http.Client();

  // ── Initialisation ────────────────────────────────────────────────────

  /// Loads persisted auth state from secure / shared storage.
  ///
  /// Should be called once during app startup (e.g. from `main()` or the
  /// root widget's `initState`). If a token is found the user is considered
  /// authenticated immediately (the token's validity is **not** verified
  /// against the server here).
  Future<void> init() async {
    _isLoading = true;
    _error = null;
    // Don't call notifyListeners() here — we're likely inside a build frame.
    // The finally block will notify once loading completes.

    try {
      // Retrieve sensitive token from secure storage.
      _token = await _secureStorage.read(key: _keyToken);

      // Retrieve non-sensitive data from shared preferences.
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString(_keyUsername);
      _email = prefs.getString(_keyEmail);

      // Device MAC list stored as a JSON-encoded List<String>.
      final macsJson = prefs.getString(_keyDeviceMacs);
      if (macsJson != null) {
        _deviceMacs = List<String>.from(jsonDecode(macsJson) as List);
      }
      _primaryMac = prefs.getString(_keyPrimaryMac);

      _isAuthenticated = _token != null;
    } catch (e) {
      debugPrint('AuthService.init error: $e');
      _error = 'Failed to load saved session.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Sign-In Methods ───────────────────────────────────────────────────

  /// Signs in using Apple credentials.
  ///
  /// Uses the `sign_in_with_apple` package to get an identity token, then
  /// exchanges it with the CalcAI backend for a server session token.
  Future<bool> signInWithApple() async {
    _setLoading(true);

    try {
      // Generate a nonce for security
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        _error = 'No identity token received from Apple.';
        return false;
      }

      // Exchange with backend
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/apple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'identityToken': identityToken}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['ok'] != true) {
        _error = data['error'] ?? 'Apple sign-in failed';
        return false;
      }

      _token = data['token'];
      _email = data['email'];
      _username = credential.givenName ?? _email?.split('@').first ?? 'User';
      _isAuthenticated = true;
      _error = null;

      await _saveToStorage();
      await fetchDevices();
      return true;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        _error = null; // User cancelled — not an error
      } else {
        _error = 'Apple sign-in failed: ${e.message}';
      }
      return false;
    } catch (e) {
      _error = 'Apple sign-in failed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Signs in using Google credentials.
  ///
  /// Uses the `google_sign_in` package to get an ID token, then exchanges
  /// it with the CalcAI backend for a server session token.
  Future<bool> signInWithGoogle() async {
    _setLoading(true);

    try {
      final googleSignIn = GoogleSignIn(scopes: ['email']);
      final account = await googleSignIn.signIn();

      if (account == null) {
        _error = null; // User cancelled
        return false;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        _error = 'No ID token received from Google.';
        return false;
      }

      // Exchange with backend
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['ok'] != true) {
        _error = data['error'] ?? 'Google sign-in failed';
        return false;
      }

      _token = data['token'];
      _email = data['email'];
      _username = account.displayName ?? _email?.split('@').first ?? 'User';
      _isAuthenticated = true;
      _error = null;

      await _saveToStorage();
      await fetchDevices();
      return true;
    } catch (e) {
      _error = 'Google sign-in failed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Signs in with an email/username and password against the CalcAI API.
  ///
  /// On success the returned JWT is persisted and [fetchDevices] is called
  /// automatically to hydrate the device list.
  Future<bool> signInWithCredentials(String username, String password) async {
    _setLoading(true);

    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        _token = body['token'] as String?;
        _username = body['username'] as String? ?? username;
        _email = body['email'] as String? ?? username;
        _isAuthenticated = true;
        _error = null;

        await _saveToStorage();

        // Eagerly populate the device list after login.
        await fetchDevices();

        return true;
      } else {
        // Attempt to extract a server-provided error message.
        String message;
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          message = body['message'] as String? ??
              body['error'] as String? ??
              'Login failed (${response.statusCode})';
        } catch (_) {
          message = 'Login failed (${response.statusCode})';
        }
        _error = message;
        return false;
      }
    } on http.ClientException catch (e) {
      _error = 'Network error: ${e.message}';
      return false;
    } catch (e) {
      _error = 'Unexpected error during sign-in: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── Device Management ─────────────────────────────────────────────────

  /// Fetches the list of devices paired to the current user from the API.
  ///
  /// Requires a valid [token]. Silently returns if not authenticated.
  Future<void> fetchDevices() async {
    if (_token == null) return;

    try {
      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/user/devices'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);

        // The API may return a bare list or an object wrapping it.
        List<dynamic> rawMacs;
        if (body is List) {
          rawMacs = body;
        } else if (body is Map<String, dynamic>) {
          rawMacs = (body['devices'] ?? body['macs'] ?? []) as List<dynamic>;
        } else {
          rawMacs = [];
        }

        _deviceMacs = rawMacs.map((e) => e.toString()).toList();

        // Keep primaryMac in sync: reset if the previous value is no longer
        // in the list, or default to the first entry.
        if (_deviceMacs.isNotEmpty) {
          if (_primaryMac == null || !_deviceMacs.contains(_primaryMac)) {
            _primaryMac = _deviceMacs.first;
          }
        } else {
          _primaryMac = null;
        }

        await _saveToStorage();
        notifyListeners();
      } else {
        debugPrint(
          'AuthService.fetchDevices failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('AuthService.fetchDevices error: $e');
    }
  }

  /// Adds a device [mac] address to the paired list and sets it as primary.
  ///
  /// This is a **local-only** operation — call [fetchDevices] afterwards if
  /// the device also needs to be registered server-side.
  Future<void> addDevice(String mac) async {
    final normalised = mac.toUpperCase();

    if (!_deviceMacs.contains(normalised)) {
      _deviceMacs.add(normalised);
    }

    _primaryMac = normalised;

    await _saveToStorage();
    notifyListeners();
  }

  // ── Sign-Out ──────────────────────────────────────────────────────────

  /// Signs the user out and wipes all persisted auth state.
  Future<void> signOut() async {
    _isAuthenticated = false;
    _token = null;
    _username = null;
    _email = null;
    _error = null;
    _deviceMacs = [];
    _primaryMac = null;

    await _clearStorage();
    notifyListeners();
  }

  // ── Private Helpers ───────────────────────────────────────────────────

  /// Persists the current auth state to secure & shared storage.
  Future<void> _saveToStorage() async {
    // Sensitive — goes into flutter_secure_storage.
    if (_token != null) {
      await _secureStorage.write(key: _keyToken, value: _token);
    }

    // Non-sensitive — goes into shared_preferences.
    final prefs = await SharedPreferences.getInstance();

    if (_username != null) {
      await prefs.setString(_keyUsername, _username!);
    }
    if (_email != null) {
      await prefs.setString(_keyEmail, _email!);
    }

    await prefs.setString(_keyDeviceMacs, jsonEncode(_deviceMacs));

    if (_primaryMac != null) {
      await prefs.setString(_keyPrimaryMac, _primaryMac!);
    } else {
      await prefs.remove(_keyPrimaryMac);
    }
  }

  /// Removes all auth-related entries from both storage backends.
  Future<void> _clearStorage() async {
    await _secureStorage.delete(key: _keyToken);

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyUsername),
      prefs.remove(_keyEmail),
      prefs.remove(_keyDeviceMacs),
      prefs.remove(_keyPrimaryMac),
    ]);
  }

  /// Sets [_isLoading] and notifies listeners in one call.
  void _setLoading(bool value) {
    _isLoading = value;
    _error = null;
    notifyListeners();
  }

  /// Cleans up the HTTP client when this service is disposed.
  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
