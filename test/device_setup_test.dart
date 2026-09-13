import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/setup_test_app.dart';
import 'package:calcai_app/widgets/wifi_network_tile.dart';

void main() {
  testWidgets('setup pairs and provisions Wi-Fi', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SetupTestApp());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Welcome,'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('Enter code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Leave device setup?'), findsOneWidget);
    await tester.tap(find.text('Keep setting up'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123',
    );
    // System back uses the same confirmation as the visible back arrow.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave device setup?'), findsOneWidget);
    await tester.tap(find.text('Leave setup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Welcome,'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('Enter code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect pairing code.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('Home Wi-Fi'), findsOneWidget);

    final iphoneCard = find.byWidgetPredicate(
      (widget) =>
          widget is WifiNetworkTile && widget.network.ssid == 'My iPhone',
    );
    final beforeRise = tester.getTopLeft(iphoneCard).dy;
    await tester.tap(find.text('My iPhone'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final duringRise = tester.getTopLeft(iphoneCard).dy;
    expect(duringRise, lessThan(beforeRise));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(iphoneCard).dy, lessThan(duringRise));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester
          .widget<WifiNetworkTile>(find.byType(WifiNetworkTile).first)
          .network
          .ssid,
      'My iPhone',
    );
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'temporary-password');
    await tester.tap(find.text('My iPhone'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Guest network'));
    await tester.pumpAndSettle();
    expect(find.text('No password needed.'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Device paired'), findsNothing);
    await tester.ensureVisible(find.text('Home Wi-Fi'));

    await tester.tap(find.text('Home Wi-Fi'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the network password.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'demo-password');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Connecting to Home Wi-Fi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Please wait while your device connects…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('Device paired'), findsOneWidget);
    await tester.tap(find.text('Home page'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sign Out'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
}
