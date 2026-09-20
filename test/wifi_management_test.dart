import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'support/setup_test_app.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/screens/wifi_screen.dart';

void main() {
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
