import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/models/wifi_network.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/wifi_network_tile.dart';
import 'support/setup_test_app.dart';

const meshScan = [
  WifiNetwork(ssid: 'Home Wi-Fi', rssi: -55, isSecured: true),
  WifiNetwork(ssid: 'Home Wi-Fi', rssi: -42, isSecured: true),
  WifiNetwork(ssid: 'Home Wi-Fi', rssi: -70, isSecured: true),
  WifiNetwork(ssid: 'Guest', rssi: -60, isSecured: false),
  WifiNetwork(ssid: 'Guest', rssi: -80, isSecured: false),
  WifiNetwork(ssid: 'Office', rssi: -65, isSecured: true),
  WifiNetwork(ssid: 'Printer', rssi: -67, isSecured: true),
  WifiNetwork(ssid: 'Neighbor', rssi: -70, isSecured: true),
  WifiNetwork(ssid: 'Phone', rssi: -75, isSecured: true),
  WifiNetwork(ssid: 'Phone', rssi: -85, isSecured: true),
];

class MeshScanBle extends SetupTestAppBle {
  MeshScanBle({required bool saved})
    : super(paired: saved, delay: Duration.zero);
  @override
  List<WifiNetwork> get wifiNetworks => meshScan;
  @override
  Future<void> requestWifiScan() async => notifyListeners();
}

void main() {
  test('mesh results keep the strongest signal once per exact SSID', () {
    final networks = WifiNetwork.uniqueBySsid(meshScan);
    expect(networks.length, 6);
    expect(networks.first.ssid, 'Home Wi-Fi');
    expect(networks.first.rssi, -42);
    expect(networks.map((n) => n.ssid).toSet().length, 6);
    expect(meshScan.length, 10);
  });

  test('same-name open radios do not remove the password requirement', () {
    final networks = WifiNetwork.uniqueBySsid(const [
      WifiNetwork(ssid: 'Home', rssi: -25, isSecured: false),
      WifiNetwork(ssid: 'Home', rssi: -60, isSecured: true),
      WifiNetwork(ssid: 'Home', rssi: -50, isSecured: true),
    ]);
    expect(networks.single.isSecured, isTrue);
    expect(networks.single.rssi, -50);
  });

  test('hidden SSIDs are omitted but case and spaces remain distinct', () {
    final networks = WifiNetwork.uniqueBySsid(const [
      WifiNetwork(ssid: '', rssi: -10, isSecured: false),
      WifiNetwork(ssid: 'Home', rssi: -50, isSecured: true),
      WifiNetwork(ssid: 'home', rssi: -50, isSecured: true),
      WifiNetwork(ssid: 'Home ', rssi: -50, isSecured: true),
    ]);
    expect(networks.map((n) => n.ssid).toSet(), {'Home', 'home', 'Home '});
  });

  for (final saved in [false, true]) {
    testWidgets(
      'mesh scan renders, expands and scrolls (saved networks: $saved)',
      (tester) async {
        tester.view.physicalSize = const Size(393, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final ble = MeshScanBle(saved: saved);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>(
                create: (_) => SetupTestAppAuth(paired: true)..init(),
              ),
              ChangeNotifierProvider<BleService>.value(value: ble),
              ChangeNotifierProvider<CloudService>(
                create: (_) => SetupTestAppCloud(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: const WifiSetupScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('6'), findsOneWidget);
        expect(find.byType(WifiNetworkTile), findsNWidgets(6));
        expect(
          ble.savedNetworks,
          saved ? ['Home Wi-Fi', 'My iPhone'] : isEmpty,
        );
        await tester.tap(find.text('Home Wi-Fi'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'existing-network-password',
        );
        await tester.ensureVisible(find.text('Phone'));
        await tester.tap(find.text('Phone'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<WifiNetworkTile>(find.byType(WifiNetworkTile).first)
              .network
              .ssid,
          'Phone',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.enterText(find.byType(TextField), 'phone-password');
        await tester.ensureVisible(find.text('Connect'));
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(ble.connectedSsid, 'Phone');
        expect(find.text('Device paired'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        ble.dispose();
      },
    );
  }
}
