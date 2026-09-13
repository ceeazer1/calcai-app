import 'package:calcai_app/services/auth_service.dart';

/// Test double for [AuthService] that boots signed-in with a paired device.
///
/// Constructed only by tests — nothing in lib/ instantiates it. It fakes the
/// session and pairing so widgets can be pumped without a network; it does not
/// fabricate any user content.
class FakeAuthService extends AuthService {
  @override
  Future<void> signOut() async {
    _isAuthenticated = false;
    _username = _email = _token = _primaryMac = null;
    _deviceMacs = [];
    notifyListeners();
  }

  bool _isAuthenticated = false;
  String? _username, _email, _token, _primaryMac;
  List<String> _deviceMacs = [];
  String? _error;
  @override
  bool get isAuthenticated => _isAuthenticated;
  @override
  String? get username => _username;
  @override
  String? get email => _email;
  @override
  String? get token => _token;
  @override
  String? get primaryMac => _primaryMac;
  @override
  List<String> get deviceMacs => List.unmodifiable(_deviceMacs);
  @override
  bool get hasDevices => deviceMacs.isNotEmpty;
  @override
  String? get error => _error;

  @override
  Future<void> init() async {
    _isAuthenticated = true;
    _username = 'Test User';
    _email = 'test@example.com';
    _token = 'test-token';
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
    String email,
    String password,
  ) async {
    await init();
    return EmailAuthOutcome.success;
  }

  @override
  Future<EmailAuthOutcome> signUpWithEmail(
    String email,
    String password,
  ) async {
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
