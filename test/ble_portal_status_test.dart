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
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
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
  testWidgets(
    'portal shimmer pauses for Reduce Motion, hidden tabs and background',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ble = PortalBle();
      addTearDown(ble.dispose);
      Widget app({bool reduceMotion = false, bool active = true}) =>
          ChangeNotifierProvider<BleService>.value(
            value: ble,
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: Scaffold(
                  body: TickerMode(
                    enabled: active,
                    child: const BlePortalStatus(),
                  ),
                ),
              ),
            ),
          );
      final shimmer = find.byKey(const ValueKey('ble-portal-shimmer'));
      Gradient? gradient() =>
          (tester.widget<DecoratedBox>(shimmer).decoration as BoxDecoration)
              .gradient;
      await tester.pumpWidget(app());
      final first = gradient();
      await tester.pump(const Duration(seconds: 2));
      expect(gradient(), isNot(first));
      await tester.pumpWidget(app(active: false));
      final hidden = gradient();
      await tester.pump(const Duration(seconds: 2));
      expect(gradient(), hidden);
      await tester.pumpWidget(app());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = gradient();
      await tester.pump(const Duration(seconds: 2));
      expect(gradient(), paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(gradient(), isNot(paused));
      await tester.pumpWidget(app(reduceMotion: true));
      await tester.pumpAndSettle();
      expect(shimmer, findsNothing);
      expect(find.text('Bluetooth portal active'), findsOneWidget);
      await tester.tap(find.text('Bluetooth portal active'));
      await tester.pumpAndSettle();
      expect(find.text('Close Bluetooth portal?'), findsOneWidget);
      await tester.tap(find.text('Keep open'));
      await tester.pumpAndSettle();
      expect(ble.disconnected, isFalse);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
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
        // Continuous decorative motion is checked separately above.
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
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
