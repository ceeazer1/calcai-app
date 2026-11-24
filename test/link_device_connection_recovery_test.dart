import 'dart:async';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/pair_device_screen.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/setup_test_app.dart';

class _ControlledConnectionBle extends SetupTestAppBle {
  _ControlledConnectionBle() : super(delay: Duration.zero);

  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  String? _error;
  Completer<void>? _connectionDone;
  int connectCalls = 0;
  int handshakeCalls = 0;

  @override
  DeviceConnectionState get connectionState => _state;

  @override
  String? get error => _error;

  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) {
    connectCalls++;
    _connectionDone = Completer<void>();
    emitState(DeviceConnectionState.connecting);
    return _connectionDone!.future;
  }

  void emitState(DeviceConnectionState state, {String? error}) {
    _state = state;
    _error = error;
    notifyListeners();
    if (state == DeviceConnectionState.error ||
        state == DeviceConnectionState.disconnected ||
        state == DeviceConnectionState.ready) {
      final done = _connectionDone;
      if (done != null && !done.isCompleted) done.complete();
    }
  }

  @override
  Future<int> negotiatePairing() async {
    handshakeCalls++;
    return 1;
  }
}

class _ScanBle extends SetupTestAppBle {
  _ScanBle() : super(delay: Duration.zero);

  final deniedPermission = Completer<bool>();
  bool radioOn = false;
  bool calculatorInRange = false;
  int permissionRequests = 0;
  int scans = 0;

  @override
  Future<bool> requestPermissions() {
    permissionRequests++;
    return deniedPermission.isCompleted
        ? Future.value(true)
        : deniedPermission.future;
  }

  @override
  Future<bool> isBluetoothOn() async => radioOn;

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    scans++;
    if (calculatorInRange) await super.startScan(timeout: timeout);
  }
}

void main() {
  testWidgets(
    'one discovery request per tap through Bluetooth and scan recovery',
    (tester) async {
      final auth = SetupTestAppAuth();
      await auth.init();
      final cloud = SetupTestAppCloud();
      final ble = _ScanBle();
      addTearDown(auth.dispose);
      addTearDown(cloud.dispose);
      addTearDown(ble.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            ChangeNotifierProvider<BleService>.value(value: ble),
          ],
          child: const MaterialApp(home: LinkDeviceScreen()),
        ),
      );

      final scan = find.text('Scan');
      final point = tester.getCenter(scan);
      await tester.tapAt(point);
      await tester.tapAt(point);
      await tester.pump();
      final requestsFromDoubleTap = ble.permissionRequests;
      expect(find.text('Looking for your calculator'), findsOneWidget);
      ble.deniedPermission.complete(false);
      await tester.pump();
      expect(find.text('Open Settings'), findsOneWidget);
      expect(ble.scans, 0);

      await tester.tap(scan);
      await tester.pump();
      expect(
        find.text('Turn on Bluetooth, then tap Scan again.'),
        findsOneWidget,
      );
      expect(ble.scans, 0);

      ble.radioOn = true;
      await tester.tap(scan);
      await tester.pump();
      expect(find.textContaining('No calculator found.'), findsOneWidget);
      expect(find.byType(PairDeviceScreen), findsNothing);
      expect(ble.scans, 1);

      ble.calculatorInRange = true;
      await tester.tap(scan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(PairDeviceScreen), findsOneWidget);
      expect(ble.scans, 2);
      expect(requestsFromDoubleTap, 1);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  const fallback =
      'The Bluetooth connection ended. Open Settings > Bluetooth on your calculator, then scan again.';
  for (final scenario in [
    (
      name: 'connection error preserves its explanation',
      state: DeviceConnectionState.error,
      error: '  Connection failed: calculator timed out.  ',
      expected: 'Connection failed: calculator timed out.',
    ),
    (
      name: 'connection error with a blank explanation uses recovery advice',
      state: DeviceConnectionState.error,
      error: '   ',
      expected: fallback,
    ),
    (
      name: 'disconnection uses recovery advice',
      state: DeviceConnectionState.disconnected,
      error: null,
      expected: fallback,
    ),
  ]) {
    testWidgets('${scenario.name}; only a fresh Scan can start pairing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final auth = SetupTestAppAuth();
      await auth.init();
      final cloud = SetupTestAppCloud();
      final ble = _ControlledConnectionBle();
      addTearDown(auth.dispose);
      addTearDown(cloud.dispose);
      addTearDown(ble.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            ChangeNotifierProvider<BleService>.value(value: ble),
          ],
          child: const MaterialApp(home: LinkDeviceScreen()),
        ),
      );

      ElevatedButton scanButton() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Scan'),
      );

      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(ble.connectCalls, 1);
      expect(find.text('Connecting'), findsOneWidget);
      expect(scanButton().onPressed, isNull);

      ble.emitState(scenario.state, error: scenario.error);
      await tester.pump();
      expect(find.text(scenario.expected), findsOneWidget);
      expect(find.text('Connecting'), findsNothing);
      expect(scanButton().onPressed, isNotNull);
      expect(find.byType(PairDeviceScreen), findsNothing);
      expect(find.byType(WifiSetupScreen), findsNothing);
      expect(ble.handshakeCalls, 0);

      // A notification from the failed attempt cannot resume setup by itself.
      ble.emitState(DeviceConnectionState.ready);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(scenario.expected), findsOneWidget);
      expect(find.byType(PairDeviceScreen), findsNothing);
      expect(find.byType(WifiSetupScreen), findsNothing);
      expect(scanButton().onPressed, isNotNull);
      expect(ble.handshakeCalls, 0);
      expect(ble.connectCalls, 1);

      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(ble.connectCalls, 2);
      expect(find.text(scenario.expected), findsNothing);
      expect(find.text('Connecting'), findsOneWidget);
      expect(scanButton().onPressed, isNull);

      // These are expected progress states, rather than terminal failures.
      for (final state in [
        DeviceConnectionState.connected,
        DeviceConnectionState.discovering,
      ]) {
        ble.emitState(state);
        await tester.pump();
        expect(find.text('Connecting'), findsOneWidget);
        expect(scanButton().onPressed, isNull);
        expect(ble.handshakeCalls, 0);
      }

      ble.emitState(DeviceConnectionState.ready);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(ble.handshakeCalls, 1);
      expect(find.byType(PairDeviceScreen), findsOneWidget);
      expect(find.text('Enter code'), findsOneWidget);
      expect(find.byType(WifiSetupScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
