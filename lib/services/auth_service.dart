import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'local_bench_profile.dart';
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

class _AuthAttempt {
  bool pending = true;
  bool sessionCommitted = false;
}

typedef _SessionSnapshot = ({
  String token,
  String? username,
  String? email,
  List<String> deviceMacs,
  String? primaryMac,
});

/// Manages authentication state for the CalcAI app.
///
/// Handles sign-in / sign-out, token persistence via [FlutterSecureStorage],
/// and device-list management via [AppPreferences].
///
/// Consumers should listen to this [ChangeNotifier] (e.g. via `Provider`) to
/// react to auth-state transitions, loading indicators, and error messages.
class AuthService extends ChangeNotifier {
  // ── Dependencies ─────────────────────────────────────────────────────
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  int _sessionGeneration = 0;
  bool _disposed = false;
  Future<void> _storageTail = Future<void>.value();
  _AuthAttempt? _activeAuthAttempt;

  /// Opaque handle for canceling only the request started by a particular route.
  Object? get activeAuthAttempt => _activeAuthAttempt;

  bool isCurrentAuthAttempt(Object? attempt) =>
      !_disposed && identical(attempt, _activeAuthAttempt);

  /// Leaving an auth route must not cancel a newer request or an accepted login.
  void cancelAuthAttempt(Object? attempt, {bool notify = true}) {
    final active = _activeAuthAttempt;
    if (active == null ||
        !identical(active, attempt) ||
        !active.pending ||
        active.sessionCommitted) {
      return;
    }
    _activeAuthAttempt = null;
    _isLoading = false;
    _error = null;
    if (notify) notifyListeners();
  }

  _AuthAttempt _startAuthAttempt({bool notify = true}) {
    final attempt = _AuthAttempt();
    if (_disposed) return attempt;
    _activeAuthAttempt = attempt;
    _error = null;
    _isLoading = true;
    if (notify) notifyListeners();
    return attempt;
  }

  bool _ownsAttempt(_AuthAttempt attempt) =>
      !_disposed && identical(_activeAuthAttempt, attempt);

  void _finishAuthAttempt(_AuthAttempt attempt) {
    if (!_ownsAttempt(attempt)) return;
    attempt.pending = false;
    _isLoading = false;
    notifyListeners();
  }

  static Map<String, dynamic> _responseData(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
    } catch (_) {}
    return const {};
  }

  static String? _sessionToken(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static const _supersededMessage =
      'This request is no longer active. Please try again.';

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

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
  static const String _keyToken =
      '${LocalBenchProfile.storagePrefix}auth_token';
  static const String _keyUsername = 'username';
  static const String _keyEmail = 'email';
  static const String _keyDeviceMacs = 'device_macs';
  static const String _keyPrimaryMac = 'primary_mac';
  // Written to SharedPreferences on every successful sign-in.
  // Absent only on a true fresh install (SharedPreferences is wiped on
  // reinstall, Keychain is not), letting us detect and discard stale tokens.
  static const String _keySessionValid = 'session_valid';

  static String _normaliseDeviceMac(Object? value) => (value ?? '')
      .toString()
      .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
      .toLowerCase();

  static bool _isUsableDeviceMac(String value) =>
      RegExp(r'^[0-9a-f]{12}$').hasMatch(value) &&
      value != '000000000000' &&
      value != 'ffffffffffff';

  /// Generate a cryptographically secure nonce for Apple Sign-In.
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
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

  bool _deviceListVerified = false;
  bool get deviceListVerified => _deviceListVerified;
  bool _deviceListLoading = false;
  bool get deviceListLoading => _deviceListLoading;
  String? _deviceListError;
  String? get deviceListError => _deviceListError;
  int _deviceRequestGeneration = 0;

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
  AuthService({FlutterSecureStorage? secureStorage, http.Client? httpClient})
    : _secureStorage = secureStorage ?? _tokenStorage,
      _httpClient = httpClient ?? createResilientClient();

  // ── Initialisation ────────────────────────────────────────────────────

  /// Loads persisted auth state from secure / shared storage.
  ///
  /// Should be called once during app startup (e.g. from `main()` or the
  /// root widget's `initState`). If a token is found the user is considered
  /// authenticated immediately (the token's validity is **not** verified
  /// against the server here).
  Future<void> init() async {
    // Init can race a new login or sign-out; read a single queued snapshot and
    // only install it while this startup attempt still owns the operation.
    final attempt = _startAuthAttempt(notify: false);
    if (!_ownsAttempt(attempt)) return;
    try {
      await _queueStorage(() async {
        if (!_ownsAttempt(attempt)) return;
        final prefs = await AppPreferences.getInstance();
        if (!_ownsAttempt(attempt)) return;
        final username = prefs.getString(_keyUsername);
        final email = prefs.getString(_keyEmail);
        final sessionValid = prefs.getBool(_keySessionValid) ?? false;
        final macsJson = prefs.getString(_keyDeviceMacs);
        final savedPrimary = _normaliseDeviceMac(
          prefs.getString(_keyPrimaryMac),
        );
        final token = _sessionToken(await _secureStorage.read(key: _keyToken));
        if (!_ownsAttempt(attempt)) return;

        // Keychain survives reinstall. A missing install marker, or a malformed
        // token, must not restore credentials or pairing from an older install.
        if (!sessionValid || token == null) {
          await _clearStorage();
          if (!_ownsAttempt(attempt)) return;
          _clearSessionState();
          return;
        }
        var macs = <String>[];
        try {
          final decoded = macsJson == null ? null : jsonDecode(macsJson);
          if (decoded is List) {
            macs = decoded
                .map(_normaliseDeviceMac)
                .where(_isUsableDeviceMac)
                .toSet()
                .toList();
          }
        } catch (_) {
          // A corrupt local pairing list does not invalidate a valid session.
        }
        _sessionGeneration++;
        _token = token;
        _username = username;
        _email = email;
        _deviceMacs = macs;
        _primaryMac = macs.contains(savedPrimary)
            ? savedPrimary
            : (macs.isEmpty ? null : macs.first);
        _deviceListVerified = false;
        _deviceListLoading = false;
        _deviceListError = null;
        _deviceRequestGeneration++;
        _setupSkipped = false;
        _unpairedNotice = false;
        _isAuthenticated = true;
        attempt.sessionCommitted = true;
      });
    } catch (e) {
      if (!_ownsAttempt(attempt)) return;
      logDebug('AuthService.init error: $e');
      _error = 'Failed to load saved session.';
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  // ── Sign-In Methods ───────────────────────────────────────────────────

  /// Signs in using Apple credentials.
  ///
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> signInWithApple() async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return _supersededMessage;

    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      ).timeout(const Duration(minutes: 2));
      if (!_ownsAttempt(attempt)) return _supersededMessage;

      final identityToken = credential.identityToken;
      if (_sessionToken(identityToken) == null) {
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
            body: jsonEncode({
              'identityToken': identityToken,
              'authorizationCode': credential.authorizationCode,
              // The Worker verifies that Apple's signed token belongs to this
              // exact sign-in attempt, preventing replayed identity tokens.
              'rawNonce': rawNonce,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (!_ownsAttempt(attempt)) return _supersededMessage;

      final data = _responseData(response);
      if (response.statusCode != 200 || data['ok'] != true) {
        return data['error']?.toString() ??
            'Sign-in failed (${response.statusCode})';
      }

      final token = _sessionToken(data['token']);
      if (token == null) return 'Sign-in failed. Please try again.';
      final email = data['email'] is String ? data['email'] as String : null;
      // Apple only sends givenName on the FIRST sign-in
      final username =
          credential.givenName ??
          credential.familyName ??
          email?.split('@').first ??
          'User';
      return await _acceptSession(attempt, token, email, username)
          ? null
          : _supersededMessage;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!_ownsAttempt(attempt)) return _supersededMessage;
      if (e.code == AuthorizationErrorCode.canceled) {
        return null; // user cancelled — not an error
      }
      return 'Apple sign-in failed: ${e.message}';
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return _supersededMessage;
      return 'Connection timed out. Please try again.';
    } on http.ClientException catch (e) {
      if (!_ownsAttempt(attempt)) return _supersededMessage;
      return connectionFailureMessage(e);
    } catch (e) {
      if (!_ownsAttempt(attempt)) return _supersededMessage;
      logDebug('signInWithApple error: $e');
      return 'Sign-in failed. Please try again.';
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  /// Signs in using Google credentials.
  ///
  /// Uses the `google_sign_in` package to get an ID token, then exchanges
  /// it with the CalcAI backend for a server session token.
  Future<bool> signInWithGoogle() async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return false;

    try {
      final googleSignIn = GoogleSignIn(
        clientId: _googleIosClientId,
        serverClientId: _googleWebClientId,
        scopes: ['email'],
      );
      final account = await googleSignIn.signIn().timeout(
        const Duration(minutes: 2),
      );
      if (!_ownsAttempt(attempt)) return false;

      if (account == null) {
        _error = null; // User cancelled
        return false;
      }

      final auth = await account.authentication.timeout(
        const Duration(seconds: 30),
      );
      if (!_ownsAttempt(attempt)) return false;
      final idToken = auth.idToken;

      if (_sessionToken(idToken) == null) {
        _error = 'No ID token received from Google.';
        return false;
      }

      // Exchange with backend
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 30));
      if (!_ownsAttempt(attempt)) return false;

      final data = _responseData(response);
      if (response.statusCode != 200 || data['ok'] != true) {
        _error = data['error']?.toString() ?? 'Google sign-in failed';
        return false;
      }

      final token = _sessionToken(data['token']);
      if (token == null) {
        _error = 'Google sign-in failed. Please try again.';
        return false;
      }
      final email = data['email'] is String ? data['email'] as String : null;
      final username = account.displayName ?? email?.split('@').first ?? 'User';
      return await _acceptSession(attempt, token, email, username);
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return false;
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      if (!_ownsAttempt(attempt)) return false;
      logDebug('signInWithGoogle error: $e');
      _error = 'Google sign-in failed. Please try again.';
      return false;
    } finally {
      _finishAuthAttempt(attempt);
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
  /// POST /ai/auth/register. A new account must verify its email before
  /// receiving a session; the outcome routes to the verification screen.
  Future<EmailAuthOutcome> signUpWithEmail(String email, String password) =>
      _emailAuth('/auth/register', email, password);

  /// Shared body for the two email flows. They differ only by path and by
  /// which errors the backend can return.
  Future<EmailAuthOutcome> _emailAuth(
    String path,
    String email,
    String password,
  ) async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return EmailAuthOutcome.failed;
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      if (!_ownsAttempt(attempt)) return EmailAuthOutcome.failed;
      final data = _responseData(response);

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

      final token = _sessionToken(data['token']);
      if (token == null) {
        _error = 'Sign-in failed. Please try again.';
        return EmailAuthOutcome.failed;
      }
      final sessionEmail = data['email'] is String
          ? data['email'] as String
          : email.trim();
      final username = data['username'] is String
          ? data['username'] as String
          : sessionEmail.split('@').first;
      return await _acceptSession(attempt, token, sessionEmail, username)
          ? EmailAuthOutcome.success
          : EmailAuthOutcome.failed;
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return EmailAuthOutcome.failed;
      _error = 'Connection timed out. Please try again.';
      return EmailAuthOutcome.failed;
    } catch (e) {
      if (!_ownsAttempt(attempt)) return EmailAuthOutcome.failed;
      logDebug('_emailAuth error: $e');
      _error = 'Network error — check your internet connection.';
      return EmailAuthOutcome.failed;
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  /// Confirms the emailed code and finishes signing in.
  ///
  /// POST /ai/auth/verify. Returns true when the account is confirmed and a
  /// session is stored.
  Future<bool> verifyEmailCode(String email, String code) async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return false;
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'code': code}),
          )
          .timeout(const Duration(seconds: 30));
      if (!_ownsAttempt(attempt)) return false;
      final data = _responseData(response);

      if (response.statusCode != 200 || data['ok'] != true) {
        _error = _verifyMessage(data['error']?.toString(), response.statusCode);
        return false;
      }

      final token = _sessionToken(data['token']);
      if (token == null) {
        _error = 'Could not finish signing in. Please try again.';
        return false;
      }
      return await _acceptSession(
        attempt,
        token,
        email.trim(),
        email.trim().split('@').first,
      );
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return false;
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      if (!_ownsAttempt(attempt)) return false;
      logDebug('verifyEmailCode error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  /// Asks the backend to email a fresh code.
  ///
  /// The accepted response remains identical for known and unknown addresses.
  /// Transport/server failures are retryable and must not claim an email sent.
  Future<bool> resendVerificationCode(String email) =>
      _sendEmailCode('/auth/resend-code', email);

  /// Asks the backend to email a password-reset code.
  ///
  /// POST /ai/auth/forgot. Accepted requests do not reveal account existence.
  Future<bool> requestPasswordReset(String email) =>
      _sendEmailCode('/auth/forgot', email);

  Future<bool> _sendEmailCode(String path, String email) async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return false;
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 20));
      if (!_ownsAttempt(attempt)) return false;
      if (response.statusCode == 200 && _responseData(response)['ok'] == true) {
        return true;
      }
      _error = response.statusCode == 429
          ? 'Too many attempts. Please wait a moment and try again.'
          : 'Could not send the code. Please try again.';
      return false;
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return false;
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      if (!_ownsAttempt(attempt)) return false;
      logDebug('sendEmailCode error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  /// Checks a reset code without spending it.
  ///
  /// POST /ai/auth/reset/verify. Lets the app confirm the code before asking
  /// for a new password, so a wrong code is caught on the step where it was
  /// typed. Wrong guesses still count against the same attempt budget as the
  /// real reset, so this is not a free oracle.
  Future<bool> verifyResetCode(String email, String code) async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return false;
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/reset/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'code': code}),
          )
          .timeout(const Duration(seconds: 30));
      if (!_ownsAttempt(attempt)) return false;
      final data = _responseData(response);

      if (response.statusCode != 200 || data['ok'] != true) {
        _error = _verifyMessage(data['error']?.toString(), response.statusCode);
        return false;
      }
      return true;
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return false;
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      if (!_ownsAttempt(attempt)) return false;
      logDebug('verifyResetCode error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  /// Spends a reset code and sets a new password.
  ///
  /// POST /ai/auth/reset. On success the backend returns a session, so the
  /// user is signed in straight away rather than being bounced back to login.
  Future<bool> resetPassword(String email, String code, String password) async {
    final attempt = _startAuthAttempt();
    if (!_ownsAttempt(attempt)) return false;
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
      if (!_ownsAttempt(attempt)) return false;
      final data = _responseData(response);

      if (response.statusCode != 200 || data['ok'] != true) {
        final code = data['error']?.toString();
        _error = code == 'invalid_password'
            ? 'Password must be at least 8 characters.'
            : _verifyMessage(code, response.statusCode);
        return false;
      }

      final token = _sessionToken(data['token']);
      if (token == null) {
        _error = 'Could not finish signing in. Please try again.';
        return false;
      }
      return await _acceptSession(
        attempt,
        token,
        email.trim(),
        email.trim().split('@').first,
      );
    } on TimeoutException {
      if (!_ownsAttempt(attempt)) return false;
      _error = 'Connection timed out. Please try again.';
      return false;
    } catch (e) {
      if (!_ownsAttempt(attempt)) return false;
      logDebug('resetPassword error: $e');
      _error = 'Network error — check your internet connection.';
      return false;
    } finally {
      _finishAuthAttempt(attempt);
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
    final token = _token;
    final generation = _sessionGeneration;
    if (token == null || _disposed) return;
    final request = ++_deviceRequestGeneration;
    bool stillCurrent() =>
        !_disposed &&
        generation == _sessionGeneration &&
        token == _token &&
        request == _deviceRequestGeneration;
    _deviceListLoading = true;
    _deviceListError = null;
    notifyListeners();

    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_baseUrl/user/devices'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!stillCurrent()) return;

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);

        // Only the server's confirmed schema is authoritative for unpairing.
        if (body is! Map<String, dynamic> ||
            body['ok'] != true ||
            body['devices'] is! List) {
          throw const FormatException('Unconfirmed device list');
        }
        final rawMacs = body['devices'] as List;
        final macs = <String>[];
        for (final device in rawMacs) {
          if (device is! Map) throw const FormatException('Invalid device');
          final rawMac = device['mac'];
          if (rawMac is! String) throw const FormatException('Invalid device');
          final mac = _normaliseDeviceMac(rawMac);
          if (!_isUsableDeviceMac(mac)) {
            throw const FormatException('Invalid device');
          }
          if (!macs.contains(mac)) macs.add(mac);
        }
        _deviceMacs = macs;
        _deviceListVerified = true;

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
      } else {
        logDebug('AuthService.fetchDevices failed: ${response.statusCode}');
        _deviceListError =
            'Could not confirm linked calculators. Please try again.';
      }
    } catch (e) {
      if (!stillCurrent()) return;
      logDebug('AuthService.fetchDevices error: $e');
      _deviceListError =
          'Could not confirm linked calculators. Please try again.';
    } finally {
      if (stillCurrent()) {
        _deviceListLoading = false;
        notifyListeners();
      }
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
    if (_disposed) return;
    final generation = _sessionGeneration;
    _deviceMacs = [];
    _primaryMac = null;
    _deviceListVerified = true;
    _deviceListLoading = false;
    _deviceListError = null;
    _deviceRequestGeneration++;
    _unpairedNotice = true;
    try {
      await _saveToStorage();
    } catch (_) {
      // Losing the persisted copy is not worth failing over; the in-memory
      // state is what routing reads.
    }
    if (generation == _sessionGeneration) notifyListeners();
  }

  Future<void> addDevice(String mac, {bool announce = true}) async {
    if (_disposed) return;
    final generation = _sessionGeneration;
    // Lowercase, no separators — the backend's canonical form. This used to
    // uppercase, which meant the value written here never matched the list
    // /ai/user/devices returns, so primaryMac silently reset on the next
    // fetch. Storing it the same way everywhere removes that round trip.
    final normalised = _normaliseDeviceMac(mac);
    if (!_isUsableDeviceMac(normalised)) {
      logDebug('AuthService refused invalid device id');
      return;
    }

    if (!_deviceMacs.contains(normalised)) {
      _deviceMacs.add(normalised);
    }

    _primaryMac = normalised;
    _deviceListVerified = true;
    _deviceListLoading = false;
    _deviceListError = null;
    _deviceRequestGeneration++;
    // A successful claim is authoritative. Do not carry an unpair banner from
    // a previous account or an earlier revoked pairing into this device.
    _unpairedNotice = false;

    await _saveToStorage();
    if (announce && generation == _sessionGeneration) notifyListeners();
  }

  // ── Account Deletion ──────────────────────────────────────────────────

  /// Permanently deletes the account and all server-side data, then clears
  /// the local session. Returns `null` on success or an error message.
  ///
  /// Required by App Store Review Guideline 5.1.1(v).
  Future<String?> deleteAccount() async {
    final token = _token;
    final generation = _sessionGeneration;
    if (token == null || _disposed) return 'You are not signed in.';
    final attempt = _startAuthAttempt();
    bool stillCurrent() =>
        _ownsAttempt(attempt) &&
        generation == _sessionGeneration &&
        token == _token;

    try {
      var response = await _httpClient
          .delete(
            Uri.parse('$_baseUrl/account/delete'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (!stillCurrent()) return _supersededMessage;

      if (response.statusCode == 409 &&
          _responseData(response)['error'] ==
              'apple_reauthorization_required') {
        // Older accounts predate server-side refresh-token storage. Reauthorize
        // the same Apple identity; the backend binds it to the current account.
        final rawNonce = _generateNonce();
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [AppleIDAuthorizationScopes.email],
          nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
        ).timeout(const Duration(minutes: 2));
        if (!stillCurrent()) return _supersededMessage;
        if (_sessionToken(credential.identityToken) == null) {
          return 'Apple could not confirm your identity. Please try again.';
        }
        response = await _httpClient
            .post(
              Uri.parse('$_baseUrl/account/delete'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'identityToken': credential.identityToken,
                'authorizationCode': credential.authorizationCode,
                'rawNonce': rawNonce,
              }),
            )
            .timeout(const Duration(seconds: 45));
        if (!stillCurrent()) return _supersededMessage;
      }

      if (response.statusCode != 200 || _responseData(response)['ok'] != true) {
        String message = 'Failed to delete account (${response.statusCode}).';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          message = switch (body['error']) {
            'apple_not_configured' || 'apple_revocation_failed' =>
              'Apple could not complete account deletion. Please try again later.',
            'apple_identity_mismatch' =>
              'Use the Apple account originally linked to CalcAI.',
            _ => 'Account deletion did not finish. Please try again.',
          };
        } catch (_) {}
        return message;
      }

      // Wipe all local state so the user returns to the sign-in screen.
      await signOut();
      // A new login can begin while the old Keychain cleanup is finishing.
      // Its caller must not clear that new account's cloud/BLE state either.
      return _sessionGeneration == generation + 1 &&
              _token == null &&
              _activeAuthAttempt == null
          ? null
          : _supersededMessage;
    } on TimeoutException {
      if (!stillCurrent()) return _supersededMessage;
      return 'Request timed out. Please try again.';
    } catch (e) {
      if (!stillCurrent()) return _supersededMessage;
      logDebug('deleteAccount error: $e');
      return 'Could not delete account. Please try again.';
    } finally {
      _finishAuthAttempt(attempt);
    }
  }

  // ── Sign-Out ──────────────────────────────────────────────────────────

  /// Signs the user out and wipes all persisted auth state.
  Future<void> signOut() async {
    if (_disposed) return;
    _activeAuthAttempt = null;
    _isLoading = false;
    _clearSessionState();
    _error = null;

    // Invalidate cloud/BLE consumers immediately, even if Keychain is slow.
    notifyListeners();
    await _queueStorage(_clearStorage);
  }

  // ── Private Helpers ───────────────────────────────────────────────────

  void _clearSessionState() {
    _sessionGeneration++;
    _isAuthenticated = false;
    _token = null;
    _username = null;
    _email = null;
    _deviceMacs = [];
    _primaryMac = null;
    _deviceListVerified = false;
    _deviceListLoading = false;
    _deviceListError = null;
    _deviceRequestGeneration++;
    _setupSkipped = false;
    _unpairedNotice = false;
  }

  Future<bool> _acceptSession(
    _AuthAttempt attempt,
    String token,
    String? email,
    String username,
  ) async {
    if (!_ownsAttempt(attempt)) return false;
    _clearSessionState();
    final generation = _sessionGeneration;
    _token = token;
    _email = email;
    _username = username;
    _isAuthenticated = true;
    attempt.sessionCommitted = true;
    try {
      await _saveToStorage(clearPrevious: true);
    } catch (_) {
      if (_ownsAttempt(attempt) && generation == _sessionGeneration) {
        _clearSessionState();
        try {
          await _queueStorage(_clearStorage);
        } catch (_) {}
      }
      rethrow;
    }
    if (!_ownsAttempt(attempt) || generation != _sessionGeneration) {
      return false;
    }
    await fetchDevices();
    return _ownsAttempt(attempt) && generation == _sessionGeneration;
  }

  /// Persists the current auth state to secure & shared storage.
  Future<void> _queueStorage(Future<void> Function() operation) {
    final result = _storageTail.then((_) => operation());
    // Keep subsequent cleanup possible when an earlier storage operation fails.
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _saveToStorage({bool clearPrevious = false}) {
    final generation = _sessionGeneration;
    final token = _token;
    if (token == null) return Future<void>.value();
    final snapshot = (
      token: token,
      username: _username,
      email: _email,
      deviceMacs: List<String>.unmodifiable(_deviceMacs),
      primaryMac: _primaryMac,
    );
    return _queueStorage(() async {
      if (_disposed || generation != _sessionGeneration) return;
      if (clearPrevious) {
        await _clearStorage();
        if (_disposed || generation != _sessionGeneration) return;
      }
      await _writeToStorage(snapshot, generation);
    });
  }

  Future<void> _writeToStorage(
    _SessionSnapshot snapshot,
    int generation,
  ) async {
    final prefs = await AppPreferences.getInstance();
    if (_disposed || generation != _sessionGeneration) return;
    // The marker is written last so a failed or superseded write cannot make
    // an incomplete Keychain/preferences snapshot restorable on next launch.
    await prefs.remove(_keySessionValid);
    await _secureStorage.write(key: _keyToken, value: snapshot.token);
    if (_disposed || generation != _sessionGeneration) return;
    for (final entry in {
      _keyUsername: snapshot.username,
      _keyEmail: snapshot.email,
      _keyDeviceMacs: jsonEncode(snapshot.deviceMacs),
      _keyPrimaryMac: snapshot.primaryMac,
    }.entries) {
      if (entry.value == null) {
        await prefs.remove(entry.key);
      } else {
        await prefs.setString(entry.key, entry.value!);
      }
      if (_disposed || generation != _sessionGeneration) return;
    }
    await prefs.setBool(_keySessionValid, true);
    if (_disposed || generation != _sessionGeneration) {
      await prefs.remove(_keySessionValid);
    }
  }

  /// Removes all auth-related entries from both storage backends.
  Future<void> _clearStorage() async {
    final prefs = await AppPreferences.getInstance();
    // A Keychain failure must not make the next launch restore this session.
    await prefs.remove(_keySessionValid);
    await _secureStorage.delete(key: _keyToken);
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
      if (k.startsWith('saved_networks_') || k.startsWith('iphone_hotspots_')) {
        await prefs.remove(k);
      }
    }
  }

  /// Cleans up the HTTP client when this service is disposed.
  @override
  void dispose() {
    _disposed = true;
    _activeAuthAttempt = null;
    _sessionGeneration++;
    _httpClient.close();
    super.dispose();
  }
}
