import 'dart:async';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

class _ProofCloud extends FakeCloudService {
  final requests = <Completer<String?>>[];
  final nonces = <String>[];
  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) {
    nonces.add(nonce);
    final response = Completer<String?>();
    requests.add(response);
    return response.future;
  }
}

class _AuthBle extends SetupTestAppBle {
  _AuthBle() : super(paired: true, delay: Duration.zero);
  int generation = 1, nonceCalls = 0, disconnectCalls = 0, wifiModeCalls = 0;
  String peripheral = 'ca1ca1000001';
  String? owner;
  bool connected = true;
  final helloProofs = <String>[];
  Completer<bool>? wifiModeReply;
  Future<bool> Function()? helloReply;
  Future<({String mac, String nonce})?> Function(int)? nonceReply;

  @override
  int get connectionGeneration => generation;
  @override
  DeviceConnectionState get connectionState => connected
      ? DeviceConnectionState.ready
      : DeviceConnectionState.disconnected;
  @override
  CalcAiDevice? get connectedDevice => !connected
      ? null
      : CalcAiDevice(
          device: BluetoothDevice.fromId(peripheral),
          rssi: -40,
          advertisementName: 'CalcAI',
        );
  @override
  String? get pairedOwner => owner;
  @override
  Future<({String mac, String nonce})?> requestAuthNonce() async {
    final call = ++nonceCalls;
    if (nonceReply != null) return nonceReply!(call);
    return (mac: 'ca1ca1000001', nonce: 'nonce-$call');
  }

  @override
  Future<bool> proveOwnership(
    String nonce,
    String response,
    String owner,
  ) async {
    final started = generation;
    helloProofs.add(response);
    final ok = await (helloReply?.call() ?? Future.value(true));
    if (started == generation && ok) {
      this.owner = owner;
      notifyListeners();
    }
    return ok;
  }

  @override
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
    if (!enabled) return true;
    wifiModeCalls++;
    notifyListeners();
    return wifiModeReply?.future ?? true;
  }

  void replaceConnection({bool newGeneration = true, String? device}) {
    if (newGeneration) generation++;
    if (device != null) peripheral = device;
    owner = null;
    connected = true;
    notifyListeners();
  }

  void pulse() => notifyListeners();
  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    generation++;
    connected = false;
    owner = null;
    notifyListeners();
  }
}

Future<void> _open(
  WidgetTester tester,
  _AuthBle ble,
  _ProofCloud cloud,
  FakeAuthService auth,
) async {
  await auth.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: const MaterialApp(home: WifiScreen()),
    ),
  );
  await tester.pump();
}

Future<void> _close(
  WidgetTester tester,
  _AuthBle ble,
  _ProofCloud cloud,
  FakeAuthService auth,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  ble.dispose();
  cloud.dispose();
  auth.dispose();
}

void main() {
  testWidgets('skip then retry on the same link cannot revive an old proof', (
    tester,
  ) async {
    final ble = _AuthBle();
    final cloud = _ProofCloud();
    final auth = FakeAuthService();
    await _open(tester, ble, cloud, auth);
    await tester.tap(find.text('skip'));
    await tester.pump();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(cloud.requests.length, 2);
    cloud.requests.first.complete('cancelled-proof');
    await tester.pump();
    expect(ble.helloProofs, isEmpty);
    ble.pulse();
    await tester.pump();
    expect(cloud.requests.length, 2);
    cloud.requests.last.complete('new-proof');
    await tester.pump();
    expect(ble.helloProofs, ['new-proof']);
    expect(ble.disconnectCalls, 0);
    await _close(tester, ble, cloud, auth);
  });
  testWidgets(
    'ready notifications stay single-flight through Wi-Fi mode acknowledgement',
    (tester) async {
      final ble = _AuthBle()..wifiModeReply = Completer<bool>();
      final cloud = _ProofCloud();
      final auth = FakeAuthService();
      await _open(tester, ble, cloud, auth);
      ble.pulse();
      ble.pulse();
      await tester.pump();
      expect(cloud.requests.length, 1);
      cloud.requests.single.complete('proof');
      await tester.pump();
      expect(ble.wifiModeCalls, 1);
      for (var i = 0; i < 4; i++) {
        ble.pulse();
        await tester.pump();
      }
      expect(ble.nonceCalls, 1);
      expect(ble.helloProofs, ['proof']);
      ble.wifiModeReply!.complete(true);
      await tester.pump();
      expect(ble.disconnectCalls, 0);
      await _close(tester, ble, cloud, auth);
    },
  );

  for (final sameDevice in [true, false]) {
    testWidgets(
      'stale cloud proof cannot enter replacement connection (same device: $sameDevice)',
      (tester) async {
        final ble = _AuthBle();
        final cloud = _ProofCloud();
        final auth = FakeAuthService();
        await _open(tester, ble, cloud, auth);
        ble.replaceConnection(
          newGeneration: sameDevice,
          device: sameDevice ? null : 'ca1ca1000002',
        );
        await tester.pump();
        expect(cloud.requests.length, 2);
        cloud.requests.first.complete('old-proof');
        await tester.pump();
        expect(ble.helloProofs, isEmpty);
        // Old finally must not release the NEW attempt's guard.
        ble.pulse();
        await tester.pump();
        expect(ble.nonceCalls, 2);
        cloud.requests.last.complete('new-proof');
        await tester.pump();
        expect(ble.helloProofs, ['new-proof']);
        expect(ble.disconnectCalls, 0);
        expect(ble.owner, auth.email);
        await _close(tester, ble, cloud, auth);
      },
    );
  }

  testWidgets(
    'old nonce completion never requests a cloud proof for new connection',
    (tester) async {
      final firstNonce = Completer<({String mac, String nonce})?>();
      final ble = _AuthBle()
        ..nonceReply = (call) async => call == 1
            ? firstNonce.future
            : (mac: 'ca1ca1000001', nonce: 'new-nonce');
      final cloud = _ProofCloud();
      final auth = FakeAuthService();
      await _open(tester, ble, cloud, auth);
      ble.replaceConnection();
      await tester.pump();
      firstNonce.complete((mac: 'ca1ca1000001', nonce: 'old-nonce'));
      await tester.pump();
      expect(cloud.nonces, ['new-nonce']);
      cloud.requests.single.complete('new-proof');
      await tester.pump();
      expect(ble.helloProofs, ['new-proof']);
      expect(ble.disconnectCalls, 0);
      await _close(tester, ble, cloud, auth);
    },
  );

  testWidgets(
    'old rejected hello cannot disconnect new link or clear its auth guard',
    (tester) async {
      final oldHello = Completer<bool>();
      var helloCount = 0;
      final ble = _AuthBle()
        ..helloReply = () =>
            ++helloCount == 1 ? oldHello.future : Future.value(true);
      final cloud = _ProofCloud();
      final auth = FakeAuthService();
      await _open(tester, ble, cloud, auth);
      cloud.requests.first.complete('old-proof');
      await tester.pump();
      ble.replaceConnection();
      await tester.pump();
      oldHello.complete(false);
      await tester.pump();
      expect(ble.disconnectCalls, 0);
      ble.pulse();
      await tester.pump();
      expect(cloud.requests.length, 2);
      cloud.requests.last.complete('new-proof');
      await tester.pump();
      expect(ble.owner, auth.email);
      expect(ble.wifiModeCalls, 1);
      await _close(tester, ble, cloud, auth);
    },
  );

  testWidgets('late Wi-Fi mode reply cannot finish a replacement handshake', (
    tester,
  ) async {
    final ble = _AuthBle()..wifiModeReply = Completer<bool>();
    final cloud = _ProofCloud();
    final auth = FakeAuthService();
    await _open(tester, ble, cloud, auth);
    cloud.requests.first.complete('old-proof');
    await tester.pump();
    final oldMode = ble.wifiModeReply!;
    ble.replaceConnection();
    await tester.pump();
    oldMode.complete(true);
    await tester.pump();
    ble.pulse();
    await tester.pump();
    expect(cloud.requests.length, 2);
    ble.wifiModeReply = null;
    cloud.requests.last.complete('new-proof');
    await tester.pump();
    expect(ble.helloProofs, ['old-proof', 'new-proof']);
    expect(ble.wifiModeCalls, 2);
    expect(ble.disconnectCalls, 0);
    await _close(tester, ble, cloud, auth);
  });

  testWidgets('sign-out discards pending cloud proof without sending hello', (
    tester,
  ) async {
    final ble = _AuthBle();
    final cloud = _ProofCloud();
    final auth = FakeAuthService();
    await _open(tester, ble, cloud, auth);
    await auth.signOut();
    cloud.requests.single.complete('old-account-proof');
    await tester.pump();
    expect(ble.helloProofs, isEmpty);
    expect(ble.wifiModeCalls, 0);
    expect(ble.disconnectCalls, 0);
    await _close(tester, ble, cloud, auth);
  });

  testWidgets(
    'current ownership rejection still disconnects and never enters Wi-Fi mode',
    (tester) async {
      final ble = _AuthBle();
      final cloud = _ProofCloud();
      final auth = FakeAuthService();
      await _open(tester, ble, cloud, auth);
      cloud.requests.single.complete(null);
      await tester.pump();
      expect(ble.helloProofs, isEmpty);
      expect(ble.wifiModeCalls, 0);
      expect(ble.disconnectCalls, 1);
      expect(ble.connected, false);
      await _close(tester, ble, cloud, auth);
    },
  );

  testWidgets(
    'old Wi-Fi teardown does not retry or disconnect replacement generation',
    (tester) async {
      final reply = Completer<bool>();
      final ble = _TeardownBle(reply);
      final ending = ble.endWifiUiMode();
      ble.generation++;
      reply.complete(false);
      await ending;
      expect(ble.modeCalls, 1);
      expect(ble.disconnectCalls, 0);
      ble.dispose();
      await tester.pump();
    },
  );

  testWidgets('late native disconnect cleanup cannot erase a newer device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final oldNative = _NativeDevice('old');
    final newNative = _NativeDevice('new');
    final ble = _NativeBle();
    final old = CalcAiDevice(device: oldNative, rssi: 0);
    final newer = CalcAiDevice(device: newNative, rssi: 0);
    // Empty services deliberately ends connection setup in error. The device
    // handle/generation still let this test exercise the real disconnect path.
    await ble.connectToDevice(old);
    oldNative.disconnectReply = Completer<void>();
    final disconnect = ble.disconnect();
    await ble.connectToDevice(newer);
    final generation = ble.connectionGeneration;
    oldNative.disconnectReply!.complete();
    await disconnect;
    expect(ble.connectionGeneration, generation);
    expect(ble.connectedDevice, same(newer));
    expect(ble.connectionState, DeviceConnectionState.error);
    ble.dispose();
    await tester.pump();
  });
}

class _TeardownBle extends BleService {
  _TeardownBle(this.reply);
  final Completer<bool> reply;
  int generation = 1, modeCalls = 0, disconnectCalls = 0;
  @override
  int get connectionGeneration => generation;
  @override
  DeviceConnectionState get connectionState => DeviceConnectionState.ready;
  @override
  Future<bool> setWifiUiMode(bool enabled, {bool finishOnConnect = false}) {
    modeCalls++;
    return reply.future;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }
}

class _NativeBle extends BleService {
  @override
  Future<void> stopScan() async {}
}

class _NativeDevice implements BluetoothDevice {
  _NativeDevice(this.identifier);
  final String identifier;
  Completer<void>? disconnectReply;
  @override
  DeviceIdentifier get remoteId => DeviceIdentifier(identifier);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #connect) return Future<void>.value();
    if (invocation.memberName == #disconnect) {
      return disconnectReply?.future ?? Future<void>.value();
    }
    if (invocation.memberName == #connectionState) {
      return const Stream<BluetoothConnectionState>.empty();
    }
    if (invocation.memberName == #discoverServices) {
      return Future.value(<BluetoothService>[]);
    }
    return super.noSuchMethod(invocation);
  }
}
