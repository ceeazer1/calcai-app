import 'dart:async';

import 'package:calcai_app/services/auth_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> secure;
  Future<void> Function()? beforeWrite;
  bool failDelete = false;

  setUp(() {
    secure = {'auth_token': 'account-a'};
    beforeWrite = null;
    failDelete = false;
    SharedPreferences.setMockInitialValues({
      'session_valid': true,
      'email': 'a@example.com',
      'device_macs': '["aabbccddeeff"]',
      'primary_mac': 'aabbccddeeff',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return secure[key];
            case 'write':
              await beforeWrite?.call();
              secure[key] = args['value'] as String;
              return null;
            case 'delete':
              if (failDelete) throw PlatformException(code: 'locked');
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

  Future<AuthService> createAuth(http.Client client) async {
    final auth = AuthService(
      secureStorage: const FlutterSecureStorage(),
      httpClient: client,
    );
    addTearDown(auth.dispose);
    await auth.init();
    return auth;
  }

  test('late device response cannot restore pairing after sign-out', () async {
    final reply = Completer<http.Response>();
    final auth = await createAuth(MockClient((_) => reply.future));
    final pending = auth.fetchDevices();
    await auth.signOut();
    reply.complete(http.Response('["112233445566"]', 200));
    await pending;
    expect(auth.deviceMacs, isEmpty);
    expect(auth.primaryMac, isNull);
    expect(auth.isAuthenticated, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('session_valid'), isNull);
    expect(prefs.getString('device_macs'), isNull);
  });

  test(
    'sign-out waits for an older storage write and removes its token',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      beforeWrite = () async {
        entered.complete();
        await release.future;
      };
      final auth = await createAuth(
        MockClient((_) async => http.Response('["112233445566"]', 200)),
      );
      final refresh = auth.fetchDevices();
      await entered.future;
      var signedOutNotification = false;
      auth.addListener(() {
        if (!auth.isAuthenticated) signedOutNotification = true;
      });
      final logout = auth.signOut();
      expect(signedOutNotification, isTrue);
      release.complete();
      await Future.wait([refresh, logout]);
      expect(secure, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_valid'), isNull);
      expect(prefs.getString('device_macs'), isNull);
    },
  );

  test(
    'failed Keychain deletion cannot restore a signed-out session',
    () async {
      final auth = await createAuth(
        MockClient((_) async => http.Response('[]', 200)),
      );
      failDelete = true;
      await expectLater(auth.signOut(), throwsA(isA<PlatformException>()));
      expect(auth.isAuthenticated, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('session_valid'),
        isNull,
      );
      failDelete = false;
      final restored = await createAuth(
        MockClient((_) async => http.Response('[]', 200)),
      );
      expect(restored.isAuthenticated, isFalse);
      expect(secure, isEmpty);
    },
  );

  testWidgets('device lookup deadline preserves the last known pairing', (
    tester,
  ) async {
    final reply = Completer<http.Response>();
    final auth = await createAuth(MockClient((_) => reply.future));
    var completed = false;
    final pending = auth.fetchDevices().then((_) => completed = true);
    await tester.pump(const Duration(seconds: 16));
    expect(completed, isTrue);
    expect(auth.deviceMacs, ['aabbccddeeff']);
    reply.complete(http.Response('["112233445566"]', 200));
    await pending;
    await tester.pump();
    expect(auth.deviceMacs, ['aabbccddeeff']);
  });
}
