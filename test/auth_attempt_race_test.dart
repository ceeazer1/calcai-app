import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/services/auth_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _session(String account) => http.Response(
  jsonEncode({
    'ok': true,
    'token': 'fixture-$account',
    'email': '$account@example.com',
  }),
  200,
);

typedef _Operation = Future<Object?> Function(AuthService auth);

void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> secure;
  final operations = <String, _Operation>{
    'login': (auth) =>
        auth.signInWithEmail('a@example.com', 'fixture-password'),
    'register': (auth) =>
        auth.signUpWithEmail('a@example.com', 'fixture-password'),
    'verify': (auth) => auth.verifyEmailCode('a@example.com', '123456'),
    'reset': (auth) =>
        auth.resetPassword('a@example.com', '123456', 'fixture-password'),
    'reset/verify': (auth) => auth.verifyResetCode('a@example.com', '123456'),
  };

  setUp(() {
    secure = {};
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return secure[key];
            case 'write':
              secure[key] = args['value'] as String;
              return null;
            case 'delete':
              secure.remove(key);
              return null;
            default:
              throw UnsupportedError(call.method);
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  AuthService makeAuth(
    Future<http.Response> Function(http.Request request) authResponse,
  ) {
    final auth = AuthService(
      httpClient: MockClient((request) async {
        if (request.url.path == '/ai/user/devices') {
          return http.Response('{"ok":true,"devices":[]}', 200);
        }
        return authResponse(request);
      }),
    );
    addTearDown(auth.dispose);
    return auth;
  }

  bool rejected(Object? result) =>
      result == false || result == EmailAuthOutcome.failed;

  for (final entry in operations.entries) {
    test('late ${entry.key} cannot replace a newer account', () async {
      final oldResponse = Completer<http.Response>();
      final auth = makeAuth((request) async {
        final body = jsonDecode(request.body) as Map;
        return body['email'] == 'b@example.com'
            ? _session('b')
            : oldResponse.future;
      });
      final old = entry.value(auth);
      expect(
        await auth.signInWithEmail('b@example.com', 'fixture-password'),
        EmailAuthOutcome.success,
      );
      oldResponse.complete(_session('a'));
      expect(rejected(await old), isTrue);
      expect(auth.token, 'fixture-b');
      expect(auth.email, 'b@example.com');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isLoading, isFalse);
      expect(auth.error, isNull);
      expect(secure['auth_token'], 'fixture-b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('email'), 'b@example.com');
      expect(prefs.getBool('session_valid'), isTrue);
    });

    test('late ${entry.key} cannot restore a signed-out account', () async {
      final response = Completer<http.Response>();
      final auth = makeAuth((_) => response.future);
      final pending = entry.value(auth);
      await auth.signOut();
      response.complete(_session('a'));
      expect(rejected(await pending), isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.error, isNull);
      expect(auth.isLoading, isFalse);
      expect(secure, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getBool('session_valid'),
        isNull,
      );
    });
  }

  test('older failure does not finish a newer pending login', () async {
    final old = Completer<http.Response>();
    final current = Completer<http.Response>();
    final auth = makeAuth((request) {
      return request.url.path.endsWith('/verify') ? old.future : current.future;
    });
    final verifying = auth.verifyEmailCode('a@example.com', '123456');
    final signingIn = auth.signInWithEmail('b@example.com', 'fixture-password');
    old.complete(http.Response('{"ok":false,"error":"bad_code"}', 400));
    expect(await verifying, isFalse);
    expect(auth.isLoading, isTrue);
    expect(auth.error, isNull);
    current.complete(_session('b'));
    expect(await signingIn, EmailAuthOutcome.success);
    expect(auth.token, 'fixture-b');
    expect(auth.isLoading, isFalse);
  });

  test('leaving a pending route cancels only that route attempt', () async {
    final firstResponse = Completer<http.Response>();
    final secondResponse = Completer<http.Response>();
    final auth = makeAuth((request) {
      return request.url.path.endsWith('/verify')
          ? firstResponse.future
          : secondResponse.future;
    });
    final first = auth.verifyEmailCode('a@example.com', '123456');
    final firstHandle = auth.activeAuthAttempt;
    final second = auth.signInWithEmail('b@example.com', 'fixture-password');
    final secondHandle = auth.activeAuthAttempt;
    auth.cancelAuthAttempt(firstHandle);
    expect(auth.isCurrentAuthAttempt(secondHandle), isTrue);
    expect(auth.isLoading, isTrue);
    secondResponse.complete(_session('b'));
    expect(await second, EmailAuthOutcome.success);
    auth.cancelAuthAttempt(secondHandle);
    expect(auth.isAuthenticated, isTrue);
    firstResponse.complete(_session('a'));
    expect(await first, isFalse);
    expect(auth.token, 'fixture-b');
  });

  test('a canceled route cannot accept its late successful response', () async {
    final response = Completer<http.Response>();
    final auth = makeAuth((_) => response.future);
    final pending = auth.verifyEmailCode('a@example.com', '123456');
    auth.cancelAuthAttempt(auth.activeAuthAttempt);
    expect(auth.isLoading, isFalse);
    response.complete(_session('a'));
    expect(await pending, isFalse);
    expect(auth.isAuthenticated, isFalse);
    expect(secure, isEmpty);
  });

  for (final path in ['login', 'verify', 'reset']) {
    test(
      '$path rejects missing, empty, whitespace and non-string tokens',
      () async {
        Object? token;
        final auth = makeAuth(
          (_) async =>
              http.Response(jsonEncode({'ok': true, 'token': token}), 200),
        );
        for (final invalid in [null, '', '   ', 123]) {
          token = invalid;
          expect(rejected(await operations[path]!(auth)), isTrue);
          expect(auth.isAuthenticated, isFalse);
          expect(auth.token, isNull);
          expect(auth.isLoading, isFalse);
          expect(secure, isEmpty);
        }
      },
    );
  }
}
