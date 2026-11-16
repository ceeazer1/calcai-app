import 'dart:ui' show SemanticsAction;

import 'package:calcai_app/screens/dashboard_screen.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

void main() {
  for (final saved in [
    <String>[],
    ['Home Wi-Fi', 'My iPhone'],
  ]) {
    testWidgets(
      'Home Edit network is a distinct accessible button with ${saved.length} saved networks',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final auth = FakeAuthService();
        await auth.init();
        final cloud = FakeCloudService();
        final ble = _DashboardWifiBle(saved);
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
            child: MaterialApp(
              theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
              home: const Scaffold(body: DashboardScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Edit network'),
          250,
          scrollable: find.descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.ensureVisible(find.text('Edit network'));
        await tester.pumpAndSettle();

        final button = find.semantics.byLabel(RegExp(r'^Edit network$'));
        expect(button, findsOne);
        final node = button.evaluate().single;
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        final actionRow = find
            .ancestor(
              of: find.text('Edit network'),
              matching: find.byType(InkWell),
            )
            .first;
        expect(node.rect.size, tester.getSize(actionRow));
        expect(node.rect.height, 44);
        for (final label in saved.isEmpty ? ['No networks saved yet'] : saved) {
          expect(find.semantics.byLabel(RegExp(label)), findsOne);
          expect(
            find.semantics.byLabel(RegExp('$label[\\s\\S]*Edit network')),
            findsNothing,
          );
        }

        // Exercise the action used by assistive technology, not a text tap.
        tester.semantics.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(WifiScreen), findsOneWidget);
        expect(find.text('Bluetooth disconnected'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}

class _DashboardWifiBle extends SetupTestAppBle {
  _DashboardWifiBle(this.networks) : super(paired: true, delay: Duration.zero);

  final List<String> networks;

  @override
  List<String> get savedNetworks => networks;

  @override
  Future<bool> requestPermissions() async => false;
}
