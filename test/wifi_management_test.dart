import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'support/setup_test_app.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/models/calcai_device.dart';

void main() {
  testWidgets(
    'unconfirmed saved networks show retry instead of a false empty list',
    (tester) async {
      final ble = _UnconfirmedNetworks();
      await tester.pumpWidget(
        ChangeNotifierProvider<BleService>.value(
          value: ble,
          child: const MaterialApp(home: WifiScreen(isActive: false)),
        ),
      );
      await tester.pump();
      expect(find.text('Could not confirm saved networks.'), findsOneWidget);
      expect(find.text('No networks saved yet'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(ble.refreshed, isTrue);
      expect(find.text('Home Wi-Fi'), findsOneWidget);
      expect(find.text('Could not confirm saved networks.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      ble.dispose();
    },
  );
  testWidgets('Wi-Fi failure exposes an actionable Back button', (
    tester,
  ) async {
    final ble = _UnavailableBluetooth();
    addTearDown(ble.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<BleService>.value(
        value: ble,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WifiScreen()),
                ),
                child: const Text('Open Wi-Fi'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth disconnected'), findsOneWidget);
    final back = find.byTooltip('Back');
    final data = tester.getSemantics(back).getSemanticsData();
    expect(data.tooltip, 'Back');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(WifiScreen), findsNothing);
    expect(find.text('Open Wi-Fi'), findsOneWidget);
  });
  testWidgets('Home Wi-Fi edits, adds and removes saved networks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The management page intentionally has a continuous Bluetooth glow.
    Future<void> advance() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await tester.pumpWidget(const SetupTestApp(startAtHome: true));
    await advance();
    final manage = find.text('Edit network');
    await tester.ensureVisible(manage);
    await advance();
    await tester.tap(manage);
    await advance();
    expect(find.text('Saved Networks'), findsOneWidget);
    final ble = tester.element(find.byType(WifiScreen)).read<BleService>();
    expect((ble as SetupTestAppBle).wifiUiMode, isTrue);
    expect(ble.savedNetworks, ['Home Wi-Fi', 'My iPhone']);

    await tester.tap(find.text('My iPhone'));
    await advance();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Phone hotspot'), findsOneWidget);
    expect(tester.getSize(find.byType(SwitchListTile)).height, lessThan(140));
    await tester.tap(find.text('Learn more'));
    await advance();
    expect(find.textContaining('occasional small requests'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await advance();
    await tester.tap(find.byType(SwitchListTile));
    await advance();
    expect(ble.isIphoneHotspotNetwork('My iPhone'), isFalse);
    await tester.tap(find.text('Update password'));
    await advance();
    await tester.enterText(find.byType(TextField), 'new-demo-password');
    await tester.tap(find.text('Connect'));
    await advance();
    expect(ble.connectedSsid, 'My iPhone');
    expect(ble.savedNetworks.length, 2);

    await tester.tap(find.byTooltip('Scan network'));
    await advance();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Saved Networks'), findsOneWidget);
    expect(find.text('Available networks'), findsOneWidget);
    await tester.ensureVisible(find.text('Guest network'));
    await tester.tap(find.text('Guest network'));
    await advance();
    expect(find.text('No password needed.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Connect'));
    await advance();
    expect(ble.connectedSsid, 'Guest network');
    expect(ble.wifiUiMode, isTrue);

    await tester.tap(find.text('Add network manually'));
    await advance();
    await tester.enterText(find.byType(TextField).first, 'Office Wi-Fi');
    await tester.enterText(find.byType(TextField).last, 'demo-password');
    await tester.tap(find.text('Connect'));
    await advance();
    expect(ble.savedNetworks, contains('Office Wi-Fi'));
    expect(ble.connectedSsid, 'Office Wi-Fi');
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await advance();
    await tester.tap(find.text('Remove'));
    await advance();
    expect(ble.savedNetworks, isNot(contains('Office Wi-Fi')));
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await advance();
    expect(find.text('Leave Bluetooth open?'), findsOneWidget);
    await tester.tap(find.text('Keep open'));
    await advance();
    expect(find.byType(WifiScreen), findsNothing);
    expect(ble.wifiUiMode, isFalse);
    expect(ble.connectionState.isConnected, isTrue);
    expect(ble.portalClosed, isFalse);
    expect(find.text('Office Wi-Fi'), findsNothing);
    expect(find.text('Home Wi-Fi'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit network'));
    await tester.tap(find.text('Edit network'));
    await advance();
    expect(ble.wifiUiMode, isTrue);
    ble.canClosePortal = false;
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await advance();
    await tester.tap(find.text('Close BLE portal'));
    await advance();
    expect(find.byType(WifiScreen), findsOneWidget);
    expect(ble.connectionState.isConnected, isTrue);
    expect(ble.portalClosed, isFalse);
    expect(find.textContaining('Could not close the portal.'), findsOneWidget);
    ble.canClosePortal = true;
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await advance();
    await tester.tap(find.text('Close BLE portal'));
    await advance();
    expect(find.byType(WifiScreen), findsNothing);
    expect(ble.connectionState.isConnected, isFalse);
    expect(ble.portalClosed, isTrue);
    expect(ble.savedNetworks, isNotEmpty);
  });
}

class _UnconfirmedNetworks extends SetupTestAppBle {
  _UnconfirmedNetworks() : super(paired: true, delay: Duration.zero);
  bool refreshed = false;
  @override
  DeviceConnectionState get connectionState => DeviceConnectionState.ready;
  @override
  String get pairedOwner => 'test-owner';
  @override
  String? get savedNetworksError =>
      refreshed ? null : 'Could not confirm saved networks.';
  @override
  List<String> get savedNetworks => refreshed ? ['Home Wi-Fi'] : [];
  @override
  Future<void> requestSavedNetworks() async {
    refreshed = true;
    notifyListeners();
  }

  @override
  Future<void> endWifiUiMode() async {}
}

class _UnavailableBluetooth extends SetupTestAppBle {
  _UnavailableBluetooth() : super(delay: Duration.zero);
  @override
  Future<bool> requestPermissions() async => false;
}
