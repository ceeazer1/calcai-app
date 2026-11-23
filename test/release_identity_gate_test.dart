// Real LinkDeviceScreen and BleService.ensureDeviceVerified, with in-memory
// discovery, challenge, verifier/backend responses and release boundary only.
import 'dart:async';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/pairing_v2.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/pair_device_screen.dart';
import 'package:calcai_app/screens/success_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

const _mac = '112233aabbcc';

class _EntryAuth extends FakeAuthService {
  int adds = 0;
  @override
  String? get primaryMac => null;
  @override
  List<String> get deviceMacs => const [];
  @override
  Future<void> addDevice(String mac, {bool announce = true}) async {
    adds++;
  }
}

class _EntryCloud extends FakeCloudService {
  int releases = 0;
  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) async => null;
  @override
  Future<String?> requestPairingRelease(
    String token,
    String mac,
    String nonce,
  ) async {
    releases++;
    return 'f' * 64;
  }

  @override
  Future<PairingOffer> requestPairingOffer(String token, String mac) async =>
      throw const PairingV2Exception('Fixture awaits a new pairing offer.');
}

class _EntryBle extends BleService {
  _EntryBle() {
    deviceVerifier = (_) {
      verifierCalls++;
      return verification?.future ?? Future.value(identityAccepted);
    };
  }
  final candidate = CalcAiDevice(
    device: BluetoothDevice.fromId('offline-release-identity'),
    rssi: -40,
    advertisementName: 'Offline CalcAI fixture',
  );
  bool found = false, connected = false, identityAccepted = true;
  bool releaseAccepted = false;
  String identityMac = _mac;
  int epoch = 1, verifierCalls = 0, nonceCalls = 0, releaseCalls = 0;
  Completer<bool>? verification;

  @override
  List<CalcAiDevice> get devices => found ? [candidate] : [];
  @override
  CalcAiDevice? get connectedDevice => connected ? candidate : null;
  @override
  int get connectionGeneration => epoch;
  @override
  DeviceConnectionState get connectionState => connected
      ? DeviceConnectionState.ready
      : DeviceConnectionState.disconnected;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    found = true;
    notifyListeners();
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    connected = true;
    epoch++;
    notifyListeners();
  }

  @override
  Future<int> negotiatePairing() async => 2;
  @override
  Future<bool?> isDevicePaired() async => true;
  @override
  Future<({String mac, String nonce})?> requestAuthNonce() async =>
      (mac: _mac, nonce: 'a' * 32);
  @override
  Future<DeviceChallenge?> requestIdentityChallenge() async =>
      DeviceChallenge(mac: identityMac, nonce: 'b' * 32, response: 'c' * 64);
  @override
  Future<({String mac, String nonce})?> requestReleaseNonce() async {
    nonceCalls++;
    return (mac: _mac, nonce: 'd' * 32);
  }

  @override
  Future<bool> releaseOwnership(String nonce, String response) async {
    releaseCalls++;
    return releaseAccepted;
  }

  void replaceConnection() {
    epoch++;
    notifyListeners();
  }
}

class _Fixture {
  final auth = _EntryAuth();
  final cloud = _EntryCloud();
  final ble = _EntryBle();
  Future<void> open(WidgetTester tester) async {
    await auth.init();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      ble.dispose();
      auth.dispose();
      cloud.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<BleService>.value(value: ble),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const LinkDeviceScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Scan'));
    await advance(tester);
  }

  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectStopped({required int nonceCalls}) {
    expect(ble.nonceCalls, nonceCalls);
    expect(
      cloud.releases,
      0,
      reason:
          'No signed reset requested before identity is verified and matched',
    );
    expect(ble.releaseCalls, 0);
    expect(auth.adds, 0);
    expect(find.byType(PairDeviceScreen), findsNothing);
    expect(find.byType(SuccessScreen), findsNothing);
    expect(find.byType(LinkDeviceScreen), findsOneWidget);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'failed real identity verifier cannot request or send a release',
    (tester) async {
      final f = _Fixture();
      f.ble.identityAccepted = false;
      await f.open(tester);
      f.expectStopped(nonceCalls: 0);
      expect(f.ble.verifierCalls, 1);
      expect(f.ble.verifiedChallenge, isNull);
      expect(
        find.textContaining(
          'Could not verify this calculator for a pairing reset.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'verified MAC mismatch stops before backend authorization or release',
    (tester) async {
      final f = _Fixture();
      f.ble.identityMac = '112233aabbcd';
      await f.open(tester);
      f.expectStopped(nonceCalls: 1);
      expect(f.ble.verifierCalls, 1);
      expect(f.ble.verifiedChallenge?.mac, '112233aabbcd');
      expect(
        find.textContaining('identity did not match the pairing reset'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'reconnect during verification cannot release either connection',
    (tester) async {
      final f = _Fixture();
      final pending = Completer<bool>();
      f.ble.verification = pending;
      await f.open(tester);
      expect(f.ble.verifierCalls, 1);
      f.ble.replaceConnection();
      pending.complete(true);
      await f.advance(tester);
      f.expectStopped(nonceCalls: 0);
      expect(f.ble.verifiedChallenge, isNull);
      expect(
        find.text(
          'The Bluetooth connection changed. Scan again to continue setup.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'matching verified identity preserves normal recovery into fresh pairing',
    (tester) async {
      final f = _Fixture();
      f.ble.releaseAccepted = true;
      await f.open(tester);
      await f.advance(tester);
      expect(
        f.ble.verifierCalls,
        1,
        reason: 'Same-generation verification is reused on the code page',
      );
      expect(f.ble.verifiedChallenge?.mac, _mac);
      expect(f.ble.nonceCalls, 1);
      expect(f.cloud.releases, 1);
      expect(f.ble.releaseCalls, 1);
      expect(find.byType(PairDeviceScreen), findsOneWidget);
      expect(find.byType(SuccessScreen), findsNothing);
      expect(f.auth.adds, 0, reason: 'Release is not claim success');
    },
  );
}
