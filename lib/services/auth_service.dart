import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'resilient_http_client.dart';
import '../utils/log.dart';

/// What an email sign-in or sign-up ended in.
///
/// Sign-up no longer returns a session — the address has to be confirmed
/// first — so a plain bool can't say what the caller should do next.
enum EmailAuthOutcome {
  /// Signed in; a token is stored.
  success,

  /// The account exists but its email is unconfirmed. Send the user to the
  /// code screen.
  verificationRequired,

  /// Nothing happened; [AuthService.error] explains why.
  failed,
}

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

  // Google OAuth client IDs (from Google Cloud Console).
  // The iOS client authenticates the app; serverClientId (Web) sets the
  // idToken audience so the backend can verify it.
  static const String _googleIosClientId =
      '520192434738-ot569t9hdad0i2hfoiuqr7scrdql14p7.apps.googleusercontent.com';
  static const String _googleWebClientId =
      '520192434738-sgkjkb455cb147rt10nabsa3auul2eki.apps.googleusercontent.com';

  // Storage keys
  static const String _keyToken = 'auth_token';
  static const String _keyUsername = 'username';
  static const String _keyEmail = 'email';
  static const String _keyDeviceMacs = 'device_macs';
  static const String _keyPrimaryMac = 'primary_mac';
  // Written to SharedPreferences on every successful sign-in.
  // Absent only on a true fresh install (SharedPreferences is wiped on
  // reinstall, Keychain is not), letting us detect and discard stale tokens.
  static const String _keySessionValid = 'session_valid';

  /// Generate a cryptographically secure nonce for Apple Sign-In.
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
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

  /// `true` when the user chose "Set up later", letting them into the app
  /// without a paired device. Reset on sign-out. Not persisted.
  bool _setupSkipped = false;
  bool get setupSkipped => _setupSkipped;

  /// Lets a device-less user bypass first-time setup and explore the app.
  void skipSetup() {
    _setupSkipped = true;
    notifyListeners();
  }

  // ── Constructor ───────────────────────────────────────────────────────

  /// Keychain policy for the session token.
  ///
  /// `first_unlock_this_device` rather than the package default (`unlocked`):
  /// the default is not "ThisDeviceOnly", so the token travels in encrypted
  /// device backups and can be restored onto a *different* phone — and the
  /// `session_valid` flag restores with it, so [init]'s stale-token check
  /// wouldn't catch it either. `first_unlock` (not `unlocked`) so a token
  /// refresh still works if the app is ever woken in the background.
  static const _tokenStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Creates an [AuthService].
  ///
  /// Accepts optional [secureStorage] and [httpClient] for testability;
  /// production callers can rely on the defaults.
  AuthService({
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  })  : _secureStorage = secureStorage ?? _tokenStorage,
        _httpClient = httpClient ?? createResilientClient();

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
      // Retrieve non-sensitive data from shared preferences first.
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString(_keyUsername);
      _email = prefs.getString(_keyEmail);

      // Retrieve sensitive token from secure storage.
      _token = await _secureStorage.read(key: _keyToken);

      // iOS Keychain survives app reinstalls but SharedPreferences does not.
      // If the session flag is absent, the token is left over from a previous
      // install — discard it so the user sees the sign-in screen.
      final sessionValid = prefs.getBool(_keySessionValid) ?? false;
      if (_token != null && !sessionValid) {
        await _secureStorage.delete(key: _keyToken);
        _token = null;
      }

      // Device MAC list stored as a JSON-encoded List<String>.
      final macsJson = prefs.getString(_keyDeviceMacs);
      if (macsJson != null) {
        _deviceMacs = List<String>.from(jsonDecode(macsJson) as List);
      }
      _primaryMac = prefs.getString(_keyPrimaryMac);

      _isAuthenticated = _token != null;
    } catch (e) {
      logDebug('AuthService.init error: $e');
      _error = 'Failed to load saved session.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Sign-In Methods ───────────────────────────────────────────────────

  /// Signs in using Apple credentials.
  ///
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> signInWithApple() async {
    _error = null;
    _setLoading(true);

    try {
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
        return 'No identity token received from Apple.';
      }

      // Exchange token with backend
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/apple'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'CalcAI/1.0',
            },
            body: jsonEncode({'identityToken': identityToken}),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['ok'] != true) {
        return data['error']?.toString() ??
            'Sign-in failed (${response.statusCode})';
      }

      _token = data['token'] as String?;
      _email = data['email'] as String?;
      // Apple only sends givenName on the FIRST sign-in
      _username = credential.givenName ??
          credential.familyName ??
          _email?.split('@').first ??
          'User';
      _isAuthenticated = true;
      _error = null;

      await _saveToStorage();
      await fetchDevices();

      return null; // success
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null; // user cancelled — not an error
      }
      return 'Apple sign-in failed: ${e.message}';
    } on TimeoutException {
      return 'Connection timed out. Please try again.';
    } catch (e) {
      logDebug('signInWithApple error: $e');
      return 'Sign-in failed. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  /// Signs in using Google credentials.
  ///
  /// Uses the `google_sign_in` package to get an ID token, then exchanges
  /// it with the CalcAI backend for a server session token.
  Future<bool> signInWithGoogle() async {
    _error = null;
    _setLoading(true);

    try {
      final googleSignIn = GoogleSignIn(
        clientId: _googleIosClientId,
        serverClientId: _googleWebClientId,
        scopes: ['email'],
      );
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
      logDebug('signInWithGoogle error: $e');
      _error = 'Google sign-in failed. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Signs in with an email and password.
  ///
  /// POST /ai/auth/login. Returns true on success; [error] carries a message
  /// on failure.
  Future<EmailAuthOutcome> signInWithEmail(String email, String password) =>
      _emailAuth('/auth/login', email, password);

  /// Creates an account with an email and password.
  ///
  /// POST /ai/auth/register. The backend stores the password as PBKDF2-SHA256
  /// and returns a session token, so a successful sign-up also signs the user
  /// in — there is no second round trip.
  Future<EmailAuthOutcome> signUpWithEmail(String email, String password) =>
      _emailAuth('/auth/register', email, password);

  /// Shared body for the two email flows. They differ only by path and by
  /// which errors the backend can return.
  Future<EmailAuthOutcome> _emailAuth(
      String path, String email, String password) async {
    _error = null;
    _setLoading(true);
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> data = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Fall through to the status-code message below.
      }

      final code = data['error']?.toString();

      // Logging in to an account whose address was never confirmed.
      if (response.statusCode == 403 && code == 'email_unverified') {
        _error = null;
        return EmailAuthOutcome.verificationRequired;
      }

      if (response.statusCode != 200 || data['ok'] != true) {
        _error = _emailAuthMessage(code, response.statusCode);
        return EmailAuthOutcome.failed;
      }

      // Sign-up succeeds without a token: a code has just been emailed.
      if (data['verificationRequired'] == true) {
        _error = null;
        return EmailAuthOutcome.verificationRequired;
      }

      _token = data['token'] as String?;
      if (_token == null || _token!.isEmpty) {
        _error = 'Sign-in failed. Please try again.';
        return EmailAuthOutcome.failed;
      }
      _email = (data['email'] as String?) ?? email.trim();
      _username = (data['username'] as String?) ?? _email!.split('@').first;
      _isAuthenticated = true;
      _error = null;

      await _saveToStorage();
      await fetchDevices();
      return EmailAuthOutcome.success;
    } on TimeoutException {
      _error = 'Connection timed out. Please try again.';
      return EmailAuthOutcome.failed;
    } catch (e) {
      logDebug('_emailAuth error: $e');
      _error = 'Network error — check your internet connection.';
      return EmailAuthOutcome.failed;
    } finally {
      _setLoading(false);
    }
  }

  /// Confirms the emailed code and finishes signing in.
  ///
  /// POST /ai/auth/verify. Returns true when the account is confirmed and a
  /// session is stored.
  Future<bool> verifyEmailCode(String email, String code) async {
    _error = null;
    _setLoading(true);
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'code': code}),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> data = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      if (response.statusCode != 200 || data['ok'] != true) {
        _error = _verifyMessage(data['error']?.toString(), response.statusCode);
        return false;
      }

      _token = data['token'] as String?;
      if (_token == null || _token!.isEmpty) {
        _error = 'Could not finish signing in. Please try again.';
        return false;
      }
      _email = email.trim();
      _username = _email!.split('@').first;
      _isAuthenticated = true;
      _error = null;

      await _saveToStorage();
      await fetchDevices();
      return true;
    } on TimeoutException {
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      logDebug('verifyEmailCode error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Asks the backend to email a fresh code.
  ///
  /// Always reports success: the endpoint deliberately answers the same way
  /// for a registered and an unregistered address, so there is nothing here to
  /// tell the user apart from "check your inbox".
  Future<void> resendVerificationCode(String email) async {
    try {
      await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/resend-code'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      logDebug('resendVerificationCode error: $e');
    }
  }

  /// Asks the backend to email a password-reset code.
  ///
  /// POST /ai/auth/forgot. Always reports success: the endpoint answers the
  /// same way for a registered and an unregistered address, so there is
  /// nothing to tell the user apart from "check your inbox".
  Future<void> requestPasswordReset(String email) async {
    try {
      await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/forgot'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      logDebug('requestPasswordReset error: $e');
    }
  }

  /// Checks a reset code without spending it.
  ///
  /// POST /ai/auth/reset/verify. Lets the app confirm the code before asking
  /// for a new password, so a wrong code is caught on the step where it was
  /// typed. Wrong guesses still count against the same attempt budget as the
  /// real reset, so this is not a free oracle.
  Future<bool> verifyResetCode(String email, String code) async {
    _error = null;
    _setLoading(true);
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/reset/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'code': code}),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> data = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      if (response.statusCode != 200 || data['ok'] != true) {
        _error = _verifyMessage(data['error']?.toString(), response.statusCode);
        return false;
      }
      return true;
    } on TimeoutException {
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      logDebug('verifyResetCode error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Spends a reset code and sets a new password.
  ///
  /// POST /ai/auth/reset. On success the backend returns a session, so the
  /// user is signed in straight away rather than being bounced back to login.
  Future<bool> resetPassword(String email, String code, String password) async {
    _error = null;
    _setLoading(true);
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/reset'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'code': code,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> data = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      if (response.statusCode != 200 || data['ok'] != true) {
        final code = data['error']?.toString();
        _error = code == 'invalid_password'
            ? 'Password must be at least 8 characters.'
            : _verifyMessage(code, response.statusCode);
        return false;
      }

      _token = data['token'] as String?;
      if (_token == null || _token!.isEmpty) {
        _error = 'Could not finish signing in. Please try again.';
        return false;
      }
      _email = email.trim();
      _username = _email!.split('@').first;
      _isAuthenticated = true;
      _error = null;

      await _saveToStorage();
      await fetchDevices();
      return true;
    } on TimeoutException {
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      logDebug('resetPassword error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  static String _verifyMessage(String? code, int status) {
    switch (code) {
      case 'bad_code':
        return 'That code is not right. Check it and try again.';
      case 'code_expired':
        return 'That code has expired. Tap Resend for a new one.';
      case 'too_many_attempts':
        return 'Too many tries. Tap Resend for a new code.';
      case 'no_account':
        return 'No account found for that email.';
      case 'bad_input':
        return 'Enter the 6-digit code from your email.';
      default:
        return 'Could not confirm the code ($status). Please try again.';
    }
  }

  /// Turns the backend's error codes into something a person can act on.
  static String _emailAuthMessage(String? code, int status) {
    switch (code) {
      case 'invalid_email':
        return 'Enter a valid email address.';
      case 'invalid_password':
        return 'Password must be at least 8 characters.';
      case 'exists':
        return 'An account with that email already exists. Try logging in.';
      case 'no_account':
      case 'unauth':
        // Deliberately identical for both: saying which one is wrong tells an
        // attacker whether an email is registered.
        return 'Email or password is incorrect.';
      case 'registration_disabled':
        return 'Sign-ups are currently closed.';
      case 'email_unavailable':
      case 'email_failed':
        return "Couldn't send the confirmation email. Please try again.";
      case 'rate_limited':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Something went wrong ($status). Please try again.';
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

        // Worker returns either plain strings or {mac, pairedAt} objects.
        _deviceMacs = rawMacs
            .map((e) {
              if (e is Map) return (e['mac'] ?? '').toString();
              return e.toString();
            })
            .where((m) => m.isNotEmpty)
            .toList();

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
        logDebug(
          'AuthService.fetchDevices failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      logDebug('AuthService.fetchDevices error: $e');
    }
  }

  /// Adds a device [mac] address to the paired list and sets it as primary.
  ///
  /// This is a **local-only** operation — call [fetchDevices] afterwards if
  /// the device also needs to be registered server-side.
  /// Forgets the paired calculator, sending the app back to setup.
  ///
  /// Used when the backend says this account no longer owns it, so the stored
  /// MAC does not keep the user on a dashboard that cannot work.
  /// Set when the device was taken away rather than removed by the user, so the
  /// pairing screen can say what happened instead of silently reappearing.
  bool _unpairedNotice = false;
  bool get unpairedNotice => _unpairedNotice;

  void clearUnpairedNotice() {
    if (!_unpairedNotice) return;
    _unpairedNotice = false;
    notifyListeners();
  }

  Future<void> forgetDevice() async {
    _deviceMacs = [];
    _primaryMac = null;
    _unpairedNotice = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPrimaryMac);
      await prefs.remove(_keyDeviceMacs);
    } catch (_) {
      // Losing the persisted copy is not worth failing over; the in-memory
      // state is what routing reads.
    }
    notifyListeners();
  }

  Future<void> addDevice(String mac, {bool announce = true}) async {
    // Lowercase, no separators — the backend's canonical form. This used to
    // uppercase, which meant the value written here never matched the list
    // /ai/user/devices returns, so primaryMac silently reset on the next
    // fetch. Storing it the same way everywhere removes that round trip.
    final normalised =
        mac.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toLowerCase();

    if (!_deviceMacs.contains(normalised)) {
      _deviceMacs.add(normalised);
    }

    _primaryMac = normalised;

    await _saveToStorage();
    if (announce) notifyListeners();
  }

  // ── Account Deletion ──────────────────────────────────────────────────

  /// Permanently deletes the account and all server-side data, then clears
  /// the local session. Returns `null` on success or an error message.
  ///
  /// Required by App Store Review Guideline 5.1.1(v).
  Future<String?> deleteAccount() async {
    if (_token == null) return 'You are not signed in.';
    _error = null;
    _setLoading(true);

    try {
      final response = await _httpClient.delete(
        Uri.parse('$_baseUrl/account/delete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        String message = 'Failed to delete account (${response.statusCode}).';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          message = body['error']?.toString() ?? message;
        } catch (_) {}
        return message;
      }

      // Wipe all local state so the user returns to the sign-in screen.
      await signOut();
      return null;
    } on TimeoutException {
      return 'Request timed out. Please try again.';
    } catch (e) {
      logDebug('deleteAccount error: $e');
      return 'Could not delete account. Please try again.';
    } finally {
      _setLoading(false);
    }
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
    _setupSkipped = false;

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

    // Mark that a real session exists so the stale-token check in init()
    // doesn't mistake a valid Keychain token for a post-reinstall leftover.
    await prefs.setBool(_keySessionValid, true);

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
      prefs.remove(_keySessionValid),
      // Signing out shouldn't leave the last peripheral behind either.
      prefs.remove('last_ble_device_id'),
    ]);

    // The saved Wi-Fi SSIDs are per-device and were surviving sign-out, so the
    // next account on this phone inherited the previous user's network names.
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith('saved_networks_')) await prefs.remove(k);
    }
  }

  /// Sets [_isLoading] and notifies listeners in one call.
  ///
  /// Deliberately does **not** touch [_error]. It used to clear it, and since
  /// every operation calls this from its `finally`, the error a `catch` had
  /// just set was wiped before the caller could read it — which is why failed
  /// sign-ins only ever showed a generic message. Operations clear the error
  /// themselves when they start.
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Cleans up the HTTP client when this service is disposed.
  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}

/// Test double for [AuthService] that boots signed-in with a paired device.
///
/// Constructed only by tests — nothing in lib/ instantiates it. It fakes the
/// session and pairing so widgets can be pumped without a network; it does not
/// fabricate any user content.
class PreviewAuthService extends AuthService {
  @override
  Future<void> init() async {
    _isAuthenticated = true;
    _username = 'Preview';
    _email = 'preview@calcai.cc';
    _token = 'preview-token';
    _deviceMacs = ['ca1ca1000001'];
    _primaryMac = 'ca1ca1000001';
    _error = null;
    notifyListeners();
  }

  @override
  Future<void> fetchDevices() async {}

  @override
  Future<String?> signInWithApple() async {
    await init();
    return null;
  }

  @override
  Future<bool> signInWithGoogle() async {
    await init();
    return true;
  }

  @override
  Future<EmailAuthOutcome> signInWithEmail(
      String email, String password) async {
    await init();
    return EmailAuthOutcome.success;
  }

  @override
  Future<EmailAuthOutcome> signUpWithEmail(
      String email, String password) async {
    await init();
    return EmailAuthOutcome.success;
  }

  @override
  Future<bool> verifyEmailCode(String email, String code) async {
    await init();
    return true;
  }

  @override
  Future<void> resendVerificationCode(String email) async {}

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<bool> verifyResetCode(String email, String code) async => true;

  @override
  Future<bool> resetPassword(String email, String code, String password) async {
    await init();
    return true;
  }
}
