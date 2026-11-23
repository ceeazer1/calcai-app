// Synthetic lifecycle at the UI/service boundary. The real command decoder and
// exact accepted/rejected/missing ACKs are covered by portal_close_ack_contract_test.
// No device, backend, account or assertion of physical radio/TI closure.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

class _CloseBle extends BleService {
  DeviceConnectionState state = DeviceConnectionState.ready;
  String? owner = 'test@example.com';
  int closeCalls = 0, disconnects = 0;
  final closeAccepted = Completer<bool>();
  final returnAfterDisconnect = Completer<void>();

  @override
  DeviceConnectionState get connectionState => state;
  @override
  String? get pairedOwner => owner;
  @override
  List<String> get savedNetworks => const ['Fixture retained network'];
  @override
  Future<void> stopScan() async {}
  @override
  Future<({String mac, String nonce})?> requestAuthNonce() async =>
      (mac: 'ca1ca1000001', nonce: 'fixture-nonce');
  @override
  Future<bool> proveOwnership(
    String nonce,
    String proof,
    String account,
  ) async => true;
  @override
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async => true;
  @override
  Future<void> endWifiUiMode() async {}

  @override
  Future<void> disconnect() async {
    disconnects++;
    state = DeviceConnectionState.disconnected;
    owner = null;
    notifyListeners();
  }

  @override
  Future<bool> closeBlePortal() async {
    closeCalls++;
    if (!await closeAccepted.future) return false;
    await disconnect();
    // Real disconnect notifies before its Future returns. Hold that boundary
    // explicitly so the test can inspect a frame before Navigator.pop starts.
    await returnAfterDisconnect.future;
    return true;
  }
}

class _CloseCloud extends FakeCloudService {
  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) async => 'fixture-proof';
}

class _Fixture {
  final ble = _CloseBle();
  final auth = FakeAuthService();
  final cloud = _CloseCloud();
  final boundary = GlobalKey();

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = scale == 1
        ? const Size(390, 844)
        : const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      ble.dispose();
      auth.dispose();
      cloud.dispose();
    });
    await auth.init();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BleService>.value(value: ble),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const WifiScreen()),
                  ),
                  child: const Text('Fixture Home'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fixture Home'));
    // The Bluetooth glow runs continuously; pumpAndSettle would never finish.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Saved Networks'), findsOneWidget);
    expect(find.text('Fixture retained network'), findsOneWidget);
  }

  Future<void> chooseClose(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave Bluetooth open?'), findsOneWidget);
    await tester.tap(find.text('Close BLE portal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ble.closeCalls, 1);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['CALCAI_CLOSE_PREVIEW_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

void _expectNoFalseFailure() {
  expect(
    find.text('Could not connect to calculator'),
    findsNothing,
    reason: 'An intentional ACK-driven disconnect is not a failed connection',
  );
  expect(find.text('Try again'), findsNothing);
  expect(find.text('Bluetooth disconnected'), findsNothing);
  expect(find.text('Leaving WiFi Networks…'), findsOneWidget);
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'intentional close has no failure before or during pop scale=$scale',
      (tester) async {
        final fixture = _Fixture();
        await fixture.open(tester, scale: scale);
        await fixture.chooseClose(tester);
        fixture.ble.closeAccepted.complete(true);
        await tester.pump();
        expect(fixture.ble.disconnects, 1);
        expect(find.byType(WifiScreen), findsOneWidget);
        // Capture and assert while disconnect has notified but close has not yet
        // returned. The unchanged c3d24a0 builder shows the false failure here.
        await fixture.capture(tester, 'disconnect-before-pop-$scale');
        _expectNoFalseFailure();
        fixture.ble.returnAfterDisconnect.complete();
        await tester.pump();
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(WifiScreen), findsOneWidget);
          _expectNoFalseFailure();
          expect(tester.takeException(), isNull);
          if (frame == 3) {
            await fixture.capture(tester, 'pop-frame-$scale');
          }
        }
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(WifiScreen), findsNothing);
        expect(find.text('Fixture Home'), findsOneWidget);
        expect(fixture.ble.closeCalls, 1);
        expect(fixture.ble.disconnects, 1);
      },
    );
  }

  testWidgets('unaccepted close stays on page and permits an explicit retry', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    await fixture.chooseClose(tester);
    fixture.ble.closeAccepted.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WifiScreen), findsOneWidget);
    expect(find.text('Saved Networks'), findsOneWidget);
    expect(find.textContaining('Could not close the portal.'), findsOneWidget);
    expect(find.text('Leaving WiFi Networks…'), findsNothing);
    expect(fixture.ble.disconnects, 0);
    await fixture.capture(tester, 'close-rejected');
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Close BLE portal'), findsOneWidget);
    expect(fixture.ble.closeCalls, 1, reason: 'No automatic close retry');
  });

  testWidgets('unexpected disconnect retains error and actionable retry', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    await fixture.ble.disconnect();
    await tester.pump();
    expect(find.byType(WifiScreen), findsOneWidget);
    expect(find.text('Could not connect to calculator'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Leaving WiFi Networks…'), findsNothing);
    expect(find.text('Saved Networks'), findsNothing);
    expect(fixture.ble.closeCalls, 0);
    await fixture.capture(tester, 'unexpected-disconnect');
  });

  testWidgets(
    'opening then cancelling the choice cannot mask a later failure',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Leave Bluetooth open?'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await fixture.ble.disconnect();
      await tester.pump();
      expect(find.text('Could not connect to calculator'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Leaving WiFi Networks…'), findsNothing);
      expect(fixture.ble.closeCalls, 0);
    },
  );
}
