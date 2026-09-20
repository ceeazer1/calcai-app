import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/widgets/ble_portal_status.dart';
import 'package:calcai_app/screens/dashboard_screen.dart';
import 'support/setup_test_app.dart';

class PortalBle extends SetupTestAppBle {
  PortalBle() : super(paired: true, delay: Duration.zero);
  DeviceConnectionState state = DeviceConnectionState.ready;
  int failures = 0;
  int resetAttempts = 0;
  bool disconnected = false;
  @override
  DeviceConnectionState get connectionState => state;
  @override
  Future<bool> setWifiUiMode(bool enabled) async {
    if (!enabled) resetAttempts++;
    return resetAttempts > failures;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    state = DeviceConnectionState.disconnected;
    notifyListeners();
  }
}

void main() {
  test(
    'mode cleanup retries transient failures and retains a healthy link',
    () async {
      final ble = PortalBle()..failures = 1;
      await ble.endWifiUiMode();
      expect(ble.resetAttempts, 2);
      expect(ble.disconnected, isFalse);
      ble.dispose();
    },
  );
  test(
    'unacknowledged cleanup releases the link instead of leaving a lock',
    () async {
      final ble = PortalBle()..failures = 2;
      await ble.endWifiUiMode();
      expect(ble.resetAttempts, 2);
      expect(ble.disconnected, isTrue);
      await ble.endWifiUiMode();
      expect(ble.resetAttempts, 2);
      ble.dispose();
    },
  );
  testWidgets('iOS portal bar tracks live BLE and vanishes on disconnect', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ble = PortalBle();
    await tester.pumpWidget(
      ChangeNotifierProvider<BleService>.value(
        value: ble,
        child: const MaterialApp(home: Scaffold(body: BlePortalStatus())),
      ),
    );
    expect(find.text('Bluetooth portal active'), findsOneWidget);
    await ble.disconnect();
    await tester.pump();
    expect(find.text('Bluetooth portal active'), findsNothing);
    // Stored networks remain present, but cannot make the banner return.
    expect(ble.savedNetworks, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('portal bar is hidden outside iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ble = PortalBle();
    await tester.pumpWidget(
      ChangeNotifierProvider<BleService>.value(
        value: ble,
        child: const MaterialApp(home: Scaffold(body: BlePortalStatus())),
      ),
    );
    expect(find.text('Bluetooth portal active'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'portal controls stay visible while home scrolls and close only on confirmation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.view.physicalSize = const Size(393, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const SetupTestApp(startAtHome: true));
        await tester.pumpAndSettle();
        final ble =
            tester.element(find.byType(DashboardScreen)).read<BleService>()
                as SetupTestAppBle;
        final connect = ble.reconnectKnownDevice();
        await tester.pump(const Duration(seconds: 2));
        await connect;
        await tester.pumpAndSettle();
        final indicator = find.text('Bluetooth portal active');
        final position = tester.getTopLeft(indicator);
        await tester.drag(
          find.descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(ListView),
          ),
          const Offset(0, -450),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(indicator), position);
        await tester.tap(indicator);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep open'));
        await tester.pumpAndSettle();
        expect(ble.portalClosed, isFalse);
        expect(indicator, findsOneWidget);
        ble.canClosePortal = false;
        await tester.tap(indicator);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close portal'));
        await tester.pumpAndSettle();
        expect(indicator, findsOneWidget);
        expect(
          find.textContaining('Could not close the portal.'),
          findsOneWidget,
        );
        ble.canClosePortal = true;
        await tester.tap(indicator);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close portal'));
        await tester.pumpAndSettle();
        expect(ble.portalClosed, isTrue);
        expect(indicator, findsNothing);
        expect(ble.savedNetworks, isNotEmpty);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
