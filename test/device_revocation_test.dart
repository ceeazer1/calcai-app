import 'dart:async';

import 'package:calcai_app/app.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

const _firstMac = 'ca1ca1000001';
const _secondMac = 'ca1ca1000002';

class _GateAuth extends FakeAuthService {
  String? session = 'account-a';
  String? mac = _firstMac;
  int forgotten = 0;
  @override
  String? get token => session;
  @override
  String? get primaryMac => mac;
  @override
  List<String> get deviceMacs => mac == null ? [] : [mac!];
  @override
  bool get hasDevices => mac != null;
  @override
  bool get isAuthenticated => session != null;
  @override
  bool get setupSkipped => true;

  void replace(String? token, String? device) {
    session = token;
    mac = device;
    notifyListeners();
  }

  @override
  Future<void> forgetDevice() async {
    forgotten++;
    mac = null;
    notifyListeners();
  }
}

class _GateCloud extends FakeCloudService {
  bool revoked = false;
  int resets = 0;
  int confirmations = 0;
  late Future<bool?> Function(String token, String mac) confirm;
  VoidCallback? onReset;
  @override
  bool get deviceRevoked => revoked;
  @override
  Future<Map<String, dynamic>> getUsage(String token, [String? mac]) async =>
      {};
  void revoke() {
    revoked = true;
    notifyListeners();
  }

  @override
  void clearDeviceRevoked() => revoked = false;

  @override
  Future<bool?> confirmDeviceOwnership(String token, String mac) {
    confirmations++;
    return confirm(token, mac);
  }

  @override
  void reset() {
    resets++;
    revoked = false;
    super.reset();
    onReset?.call();
  }
}

Future<void> _showGate(
  WidgetTester tester,
  _GateAuth auth,
  _GateCloud cloud,
) async {
  final ble = SetupTestAppBle();
  addTearDown(auth.dispose);
  addTearDown(cloud.dispose);
  addTearDown(ble.dispose);
  await auth.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
        ChangeNotifierProvider<BleService>.value(value: ble),
      ],
      child: const MaterialApp(home: AppGate(restoreSession: false)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

void main() {
  test('a malformed successful ownership response remains unknown', () async {
    final cloud = CloudService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(cloud.dispose);
    expect(await cloud.confirmDeviceOwnership('account-a', _firstMac), isNull);
  });

  for (final accountChanges in [false, true]) {
    testWidgets(
      'a delayed revocation cannot forget a newer ${accountChanges ? 'account' : 'calculator'}',
      (tester) async {
        final auth = _GateAuth();
        final result = Completer<bool?>();
        final cloud = _GateCloud()
          ..confirm = (token, mac) {
            expect(token, 'account-a');
            expect(mac, _firstMac);
            return result.future;
          };
        await _showGate(tester, auth, cloud);
        cloud.revoke();
        await tester.pump();
        expect(cloud.confirmations, 1);
        auth.replace(accountChanges ? 'account-b' : 'account-a', _secondMac);
        await tester.pump();
        result.complete(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
        expect(auth.mac, _secondMac);
        expect(auth.forgotten, 0);
        expect(cloud.resets, 0);
      },
    );
  }

  for (final result in [true, null]) {
    testWidgets(
      'a ${result == true ? 'retained' : 'unknown'} ownership result preserves the current calculator',
      (tester) async {
        final auth = _GateAuth();
        final cloud = _GateCloud()..confirm = (_, _) async => result;
        await _showGate(tester, auth, cloud);
        cloud.revoke();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(auth.mac, _firstMac);
        expect(auth.forgotten, 0);
        expect(cloud.resets, 0);
        expect(cloud.confirmations, 1);
      },
    );
  }

  testWidgets(
    'an authoritative loss forgets only the unchanged current calculator',
    (tester) async {
      final auth = _GateAuth();
      final cloud = _GateCloud()..confirm = (_, _) async => false;
      await _showGate(tester, auth, cloud);
      cloud.revoke();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(auth.mac, isNull);
      expect(auth.forgotten, 1);
      expect(cloud.resets, 1);
    },
  );

  testWidgets(
    'a thrown confirmation preserves pairing and releases the guard for another event',
    (tester) async {
      final auth = _GateAuth();
      final cloud = _GateCloud()
        ..confirm = (_, _) async => throw StateError('Fixture failure');
      await _showGate(tester, auth, cloud);
      cloud.revoke();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(auth.mac, _firstMac);
      cloud.confirm = (_, _) async => false;
      cloud.revoke();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(cloud.confirmations, 2);
      expect(auth.forgotten, 1);
    },
  );

  testWidgets('an unmounted gate cannot apply a pending ownership result', (
    tester,
  ) async {
    final auth = _GateAuth();
    final result = Completer<bool?>();
    final cloud = _GateCloud()..confirm = (_, _) => result.future;
    await _showGate(tester, auth, cloud);
    cloud.revoke();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    result.complete(false);
    await tester.pump();
    expect(auth.forgotten, 0);
    expect(cloud.resets, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a synchronous account change during reset cannot forget its new device',
    (tester) async {
      final auth = _GateAuth();
      final cloud = _GateCloud()..confirm = (_, _) async => false;
      cloud.onReset = () => auth.replace('account-b', _secondMac);
      await _showGate(tester, auth, cloud);
      cloud.revoke();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(auth.mac, _secondMac);
      expect(auth.forgotten, 0);
      expect(cloud.resets, 1);
    },
  );

  testWidgets(
    'a queued callback cannot revive an already cleared old revocation',
    (tester) async {
      final auth = _GateAuth();
      final cloud = _GateCloud()..confirm = (_, _) async => false;
      await _showGate(tester, auth, cloud);
      cloud.revoke();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        auth.replace('account-b', _secondMac);
        cloud.clearDeviceRevoked();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(auth.mac, _secondMac);
      expect(auth.forgotten, 0);
      expect(cloud.confirmations, 0);
    },
  );

  testWidgets('a newer revocation is not lost behind an older pending check', (
    tester,
  ) async {
    final auth = _GateAuth();
    final first = Completer<bool?>();
    final checked = <String>[];
    final cloud = _GateCloud()
      ..confirm = (token, mac) {
        checked.add('$token/$mac');
        return token == 'account-a' ? first.future : Future<bool?>.value(true);
      };
    await _showGate(tester, auth, cloud);
    cloud.revoke();
    await tester.pump();
    auth.replace('account-b', _secondMac);
    cloud.revoke();
    await tester.pump();
    expect(cloud.confirmations, 1);
    first.complete(false);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(checked, ['account-a/$_firstMac', 'account-b/$_secondMac']);
    expect(auth.mac, _secondMac);
    expect(auth.forgotten, 0);
  });

  test(
    'ownership confirmation rejects malformed success and old list shapes',
    () async {
      var body = '';
      final cloud = CloudService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(cloud.dispose);
      for (final malformed in [
        '',
        '{}',
        '[]',
        '{"ok":false,"context":""}',
        '{"ok":false,"devices":[]}',
        '{"ok":true}',
        '{"ok":true,"context":null}',
        '{"ok":true,"context":5}',
        '{"ok":true,"devices":null}',
        '{"ok":true,"devices":["ca1ca1000001"]}',
        '{"ok":true,"devices":[{}]}',
        '{"ok":true,"devices":[{"mac":"not-a-mac"}]}',
        '{"ok":true,"devices":[{"mac":"ca1ca1000001"},{}]}',
      ]) {
        body = malformed;
        expect(
          await cloud.confirmDeviceOwnership('account-a', _firstMac),
          isNull,
          reason: malformed,
        );
      }
    },
  );

  test(
    'targeted ownership check distinguishes existing empty context from explicit revocation',
    () async {
      var body = '{"ok":true,"context":""}';
      var status = 200;
      final cloud = CloudService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/ai/context/get');
          expect(request.url.queryParameters['mac'], _firstMac);
          expect(request.headers['Authorization'], 'Bearer account-a');
          return http.Response(body, status);
        }),
      );
      addTearDown(cloud.dispose);
      expect(
        await cloud.confirmDeviceOwnership('account-a', _firstMac),
        isTrue,
      );
      body = '{"ok":true,"context":"Private saved text"}';
      expect(
        await cloud.confirmDeviceOwnership('account-a', _firstMac),
        isTrue,
      );
      expect(cloud.customContext, isEmpty);
      status = 403;
      body = '{"ok":false,"error":"device_not_owned"}';
      expect(
        await cloud.confirmDeviceOwnership('account-a', _firstMac),
        isFalse,
      );
    },
  );

  test('only an explicit ownership403 can confirm revocation', () async {
    var response = http.Response('{"ok":false,"error":"not_genuine"}', 403);
    final cloud = CloudService(client: MockClient((_) async => response));
    addTearDown(cloud.dispose);
    for (final candidate in [
      http.Response('{"ok":false,"error":"not_genuine"}', 403),
      http.Response('{"ok":true,"error":"device_not_owned"}', 403),
      http.Response('{"error":"device_not_owned"}', 403),
      http.Response('device_not_owned', 403),
      http.Response('{"ok":false,"error":"device_not_owned"}', 401),
      http.Response('{"ok":false,"error":"device_not_owned"}', 500),
      http.Response('{"ok":false,"error":"device_not_owned"}', 200),
      http.Response('', 204),
    ]) {
      response = candidate;
      expect(
        await cloud.confirmDeviceOwnership('account-a', _firstMac),
        isNull,
      );
    }
    expect(cloud.deviceRevoked, isFalse);
  });

  test(
    'a reset during ownership confirmation leaves the result unknown',
    () async {
      final result = Completer<http.Response>();
      final cloud = CloudService(client: MockClient((_) => result.future));
      addTearDown(cloud.dispose);
      final pending = cloud.confirmDeviceOwnership('account-a', _firstMac);
      cloud.reset();
      result.complete(
        http.Response('{"ok":false,"error":"device_not_owned"}', 403),
      );
      expect(await pending, isNull);
    },
  );

  group('device revocation response', () {
    test('accepts only the explicit ownership error', () {
      expect(
        isDeviceOwnershipRevocation(
          http.Response('{"ok":false,"error":"device_not_owned"}', 403),
        ),
        isTrue,
      );
    });

    test('does not mistake another security rejection for an unpair', () {
      expect(
        isDeviceOwnershipRevocation(
          http.Response('{"ok":false,"error":"not_genuine"}', 403),
        ),
        isFalse,
      );
      expect(
        isDeviceOwnershipRevocation(http.Response('invalid proof', 403)),
        isFalse,
      );
    });

    test('does not treat non-403 responses as an unpair', () {
      expect(
        isDeviceOwnershipRevocation(
          http.Response('{"error":"device_not_owned"}', 401),
        ),
        isFalse,
      );
    });
  });
}
