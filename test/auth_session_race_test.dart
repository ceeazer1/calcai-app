import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/screens/verify_email_screen.dart';
import 'package:calcai_app/screens/reset_password_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const appleChannel = MethodChannel(
    'com.aboutyou.dart_packages.sign_in_with_apple',
  );
  const googleChannel = MethodChannel('plugins.flutter.io/google_sign_in');
  late Map<String, String> secure;
  Future<void> Function()? beforeRead;
  Future<void> Function()? beforeWrite;
  Future<Object?> Function(MethodCall)? apple;

  setUp(() {
    secure = {'auth_token': 'account-a'};
    beforeRead = null;
    beforeWrite = null;
    apple = null;
    SharedPreferences.setMockInitialValues({
      'session_valid': true,
      'email': 'a@example.com',
      'device_macs': '["aabbccddeeff"]',
      'primary_mac': 'aabbccddeeff',
      'saved_networks_aabbccddeeff': '["Private network"]',
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          final value = secure[key];
          await beforeRead?.call();
          return value;
        case 'write':
          await beforeWrite?.call();
          secure[key] = args['value'] as String;
          return null;
        case 'delete':
          secure.remove(key);
          return null;
        default:
          throw UnsupportedError(call.method);
      }
    });
    messenger.setMockMethodCallHandler(appleChannel, (call) async {
      if (apple != null) return apple!(call);
      return {
        'type': 'appleid',
        'authorizationCode': 'fixture-code',
        'identityToken': 'fixture-apple-identity',
      };
    });
    messenger.setMockMethodCallHandler(googleChannel, (call) async {
      return switch (call.method) {
        'init' => null,
        'signIn' => {
          'id': 'fixture-google-id',
          'email': 'social@example.com',
          'displayName': 'Social',
        },
        'getTokens' => {'idToken': 'fixture-google-identity'},
        _ => null,
      };
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [secureChannel, appleChannel, googleChannel]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  http.Response session([String token = 'account-b']) => http.Response(
    jsonEncode({'ok': true, 'token': token, 'email': 'b@example.com'}),
    200,
  );

  Future<AuthService> restored(
    Future<http.Response> Function(http.Request) respond,
  ) async {
    final auth = AuthService(httpClient: MockClient(respond));
    addTearDown(auth.dispose);
    await auth.init();
    return auth;
  }

  test(
    'blocked init cannot replace a newer login or its stored snapshot',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      beforeRead = () async {
        entered.complete();
        await release.future;
      };
      final auth = AuthService(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) return session();
          return http.Response('{"ok":true,"devices":[]}', 200);
        }),
      );
      addTearDown(auth.dispose);
      final startup = auth.init();
      await entered.future;
      final login = auth.signInWithEmail('b@example.com', 'fixture-password');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await startup;
      expect(await login, EmailAuthOutcome.success);
      expect(auth.token, 'account-b');
      expect(auth.deviceMacs, isEmpty);
      expect(secure['auth_token'], 'account-b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('email'), 'b@example.com');
      expect(prefs.getString('device_macs'), '[]');
    },
  );

  test('blocked init cannot restore a session after sign-out', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeRead = () async {
      entered.complete();
      await release.future;
    };
    final auth = AuthService(httpClient: MockClient((_) async => session()));
    addTearDown(auth.dispose);
    final startup = auth.init();
    await entered.future;
    final logout = auth.signOut();
    release.complete();
    await Future.wait([startup, logout]);
    expect(auth.token, isNull);
    expect(auth.isLoading, isFalse);
    expect(secure, isEmpty);
  });

  test(
    'old blocked storage write cannot mix account data into a new session',
    () async {
      final auth = await restored((request) async {
        if (request.url.path.endsWith('/auth/login')) return session();
        return http.Response(
          '{"ok":true,"devices":[{"mac":"112233445566"}]}',
          200,
        );
      });
      final entered = Completer<void>();
      final release = Completer<void>();
      var writes = 0;
      beforeWrite = () async {
        if (writes++ == 0) {
          entered.complete();
          await release.future;
        }
      };
      final refresh = auth.fetchDevices();
      await entered.future;
      final logout = auth.signOut();
      final login = auth.signInWithEmail('b@example.com', 'fixture-password');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await Future.wait([refresh, logout]);
      expect(await login, EmailAuthOutcome.success);
      expect(auth.token, 'account-b');
      expect(secure['auth_token'], 'account-b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('email'), 'b@example.com');
      expect(prefs.getBool('session_valid'), isTrue);
      expect(prefs.getString('saved_networks_aabbccddeeff'), isNull);
    },
  );

  test(
    'new login cannot inherit prior pairing, skipped setup or unpair notice',
    () async {
      final auth = await restored((request) async {
        if (request.url.path.endsWith('/auth/login')) return session();
        return http.Response('{}', 503);
      });
      auth.skipSetup();
      await auth.forgetDevice();
      await auth.addDevice('aabbccddeeff');
      expect(
        await auth.signInWithEmail('b@example.com', 'fixture-password'),
        EmailAuthOutcome.success,
      );
      expect(auth.primaryMac, isNull);
      expect(auth.deviceMacs, isEmpty);
      expect(auth.setupSkipped, isFalse);
      expect(auth.unpairedNotice, isFalse);
      expect(auth.deviceListVerified, isFalse);
      expect(auth.deviceListLoading, isFalse);
      expect(auth.deviceListError, isNotNull);
    },
  );

  test('whitespace Keychain token is not an authenticated session', () async {
    secure['auth_token'] = '   ';
    final auth = await restored((_) async => session());
    expect(auth.isAuthenticated, isFalse);
    expect(auth.token, isNull);
    expect(auth.deviceMacs, isEmpty);
    expect(secure, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getBool('session_valid'),
      isNull,
    );
  });

  for (final body in [
    '[]',
    '{}',
    '{"ok":false,"devices":[]}',
    '{"ok":true}',
    '{"ok":true,"devices":"bad"}',
    '{"ok":true,"devices":[{"mac":"invalid"}]}',
    '{"ok":true,"devices":["112233445566"]}',
  ]) {
    test('malformed device success preserves known pairing: $body', () async {
      final auth = await restored((_) async => http.Response(body, 200));
      await auth.fetchDevices();
      expect(auth.deviceMacs, ['aabbccddeeff']);
      expect(auth.primaryMac, 'aabbccddeeff');
      expect(auth.deviceListVerified, isFalse);
      expect(auth.deviceListError, isNotNull);
    });
  }

  test('authoritative empty device success clears pairing', () async {
    final auth = await restored(
      (_) async => http.Response('{"ok":true,"devices":[]}', 200),
    );
    await auth.fetchDevices();
    expect(auth.deviceMacs, isEmpty);
    expect(auth.primaryMac, isNull);
    expect(auth.deviceListVerified, isTrue);
    expect(auth.deviceListError, isNull);
  });

  test('unknown device discovery retries to a verified account list', () async {
    var fail = true;
    final auth = await restored((request) async {
      if (request.url.path.endsWith('/auth/login')) return session();
      return fail
          ? http.Response('{}', 503)
          : http.Response(
              '{"ok":true,"devices":[{"mac":"112233445566"}]}',
              200,
            );
    });
    expect(
      await auth.signInWithEmail('b@example.com', 'fixture-password'),
      EmailAuthOutcome.success,
    );
    expect(auth.deviceListVerified, isFalse);
    expect(auth.deviceListError, isNotNull);
    fail = false;
    await auth.fetchDevices();
    expect(auth.deviceListVerified, isTrue);
    expect(auth.deviceListLoading, isFalse);
    expect(auth.deviceListError, isNull);
    expect(auth.primaryMac, '112233445566');
  });

  test(
    'older same-session device reply cannot overwrite a newer discovery',
    () async {
      final older = Completer<http.Response>();
      var calls = 0;
      final auth = await restored((_) async {
        if (calls++ == 0) return older.future;
        return http.Response('{"ok":true,"devices":[]}', 200);
      });
      final pending = auth.fetchDevices();
      await auth.fetchDevices();
      older.complete(
        http.Response('{"ok":true,"devices":[{"mac":"112233445566"}]}', 200),
      );
      await pending;
      expect(auth.deviceMacs, isEmpty);
      expect(auth.deviceListVerified, isTrue);
      expect(auth.deviceListLoading, isFalse);
    },
  );

  for (final status in [200, 409]) {
    test(
      'late deletion $status cannot retry or sign out a newer account',
      () async {
        final deletion = Completer<http.Response>();
        final requests = <http.Request>[];
        final auth = await restored((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/account/delete')) {
            return deletion.future;
          }
          if (request.url.path.endsWith('/auth/login')) return session();
          return http.Response('{"ok":true,"devices":[]}', 200);
        });
        final pending = auth.deleteAccount();
        expect(
          await auth.signInWithEmail('b@example.com', 'fixture-password'),
          EmailAuthOutcome.success,
        );
        deletion.complete(
          http.Response(
            status == 200
                ? '{"ok":true}'
                : '{"error":"apple_reauthorization_required"}',
            status,
          ),
        );
        expect(await pending, isNotNull);
        final deletes = requests
            .where((r) => r.url.path.endsWith('/account/delete'))
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.headers['Authorization'], 'Bearer account-a');
        expect(auth.token, 'account-b');
        expect(secure['auth_token'], 'account-b');
      },
    );
  }

  for (final reply in [
    http.Response('{}', 200),
    http.Response('{"ok":false}', 200),
    http.Response('{"error":"partial_cleanup"}', 503),
  ]) {
    test(
      'deletion ${reply.statusCode}/${reply.body} retains session for retry',
      () async {
        final auth = await restored((_) async => reply);
        expect(await auth.deleteAccount(), isNotNull);
        expect(auth.token, 'account-a');
        expect(auth.isAuthenticated, isTrue);
        expect(secure['auth_token'], 'account-a');
      },
    );
  }

  test(
    'Apple deletion reauthorization cannot post using a newer token',
    () async {
      final entered = Completer<void>();
      final credential = Completer<Object?>();
      apple = (_) {
        entered.complete();
        return credential.future;
      };
      final deletionMethods = <String>[];
      final auth = await restored((request) async {
        if (request.url.path.endsWith('/account/delete')) {
          deletionMethods.add(request.method);
          return http.Response(
            '{"error":"apple_reauthorization_required"}',
            409,
          );
        }
        if (request.url.path.endsWith('/auth/login')) return session();
        return http.Response('{"ok":true,"devices":[]}', 200);
      });
      final pending = auth.deleteAccount();
      await entered.future;
      expect(
        await auth.signInWithEmail('b@example.com', 'fixture-password'),
        EmailAuthOutcome.success,
      );
      credential.complete({
        'type': 'appleid',
        'authorizationCode': 'fixture-code',
        'identityToken': 'fixture-identity',
      });
      expect(await pending, isNotNull);
      expect(deletionMethods, ['DELETE']);
      expect(auth.token, 'account-b');
    },
  );

  for (final provider in ['apple', 'google']) {
    for (final token in [null, '', '   ', 42]) {
      test(
        '$provider rejects malformed backend token $token without replacing session',
        () async {
          final auth = await restored(
            (_) async =>
                http.Response(jsonEncode({'ok': true, 'token': token}), 200),
          );
          if (provider == 'apple') {
            expect(await auth.signInWithApple(), isNotNull);
          } else {
            expect(await auth.signInWithGoogle(), isFalse);
          }
          expect(auth.token, 'account-a');
          expect(auth.deviceMacs, ['aabbccddeeff']);
          expect(secure['auth_token'], 'account-a');
        },
      );
    }
  }

  testWidgets('Google backend deadline ends loading and ignores a late reply', (
    tester,
  ) async {
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    final auth = AuthService(
      httpClient: MockClient((_) {
        entered.complete();
        return response.future;
      }),
    );
    addTearDown(auth.dispose);
    final pending = auth.signInWithGoogle();
    for (var i = 0; i < 20 && !entered.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(entered.isCompleted, isTrue);
    await tester.pump(const Duration(seconds: 31));
    expect(await pending, isFalse);
    expect(auth.isLoading, isFalse);
    expect(auth.error, contains('timed out'));
    response.complete(session());
    await tester.pump();
    expect(auth.token, isNull);
  });

  testWidgets(
    'leaving verification cancels its pending login before route disposal',
    (tester) async {
      final reply = Completer<http.Response>();
      final entered = Completer<void>();
      final auth = AuthService(
        httpClient: MockClient((_) {
          entered.complete();
          return reply.future;
        }),
      );
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const VerifyEmailScreen(email: 'a@example.com'),
                    ),
                  ),
                  child: const Text('Open verification'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open verification'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(entered.isCompleted, isTrue);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      reply.complete(session());
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(find.text('Open verification'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final reset in [false, true]) {
    for (final reply in [
      http.Response('{"ok":true}', 200),
      http.Response('{}', 200),
      http.Response('{"ok":false}', 200),
      http.Response('{"error":"unavailable"}', 503),
    ]) {
      test(
        '${reset ? 'reset' : 'verification'} code send requires confirmed success ${reply.statusCode}/${reply.body}',
        () async {
          final auth = await restored((_) async => reply);
          final sent = reset
              ? await auth.requestPasswordReset('a@example.com')
              : await auth.resendVerificationCode('a@example.com');
          final accepted =
              reply.statusCode == 200 && jsonDecode(reply.body)['ok'] == true;
          expect(sent, accepted);
          expect(auth.error, accepted ? isNull : isNotNull);
          expect(auth.isLoading, isFalse);
          expect(auth.token, 'account-a');
        },
      );
    }
  }

  testWidgets(
    'failed reset-code send stays on email and permits immediate retry',
    (tester) async {
      var sends = 0;
      final auth = AuthService(
        httpClient: MockClient((_) async {
          sends++;
          return sends == 1
              ? http.Response('{"error":"unavailable"}', 503)
              : http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: const MaterialApp(
            home: ResetPasswordScreen(initialEmail: 'a@example.com'),
          ),
        ),
      );
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      expect(
        find.text('Could not send the code. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Request accepted.'), findsNothing);
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(sends, 2);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('Request accepted.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed verification resend avoids false sent notice and cooldown',
    (tester) async {
      var sends = 0;
      final auth = AuthService(
        httpClient: MockClient((_) async {
          sends++;
          return sends == 1
              ? http.Response('{"error":"unavailable"}', 503)
              : http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: const MaterialApp(
            home: VerifyEmailScreen(email: 'a@example.com'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 46));
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not send the code. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Request accepted.'), findsNothing);
      expect(find.text('Resend code'), findsOneWidget);
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(sends, 2);
      expect(find.textContaining('Request accepted.'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
