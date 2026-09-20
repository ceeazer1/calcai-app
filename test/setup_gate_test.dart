import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/app.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/ai_consent_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'support/setup_test_app.dart';

void main() {
  testWidgets('provider refresh after a claim cannot skip Wi-Fi onboarding', (
    tester,
  ) async {
    final auth = SetupTestAppAuth();
    await auth.init();
    final cloud = SetupTestAppCloud();
    final ble = SetupTestAppBle();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          ChangeNotifierProvider<BleService>.value(value: ble),
        ],
        child: const MaterialApp(home: AppGate(restoreSession: false)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LinkDeviceScreen), findsOneWidget);
    await auth.addDevice('ca1ca1000001');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LinkDeviceScreen), findsOneWidget);
    expect(find.byType(AiConsentGate), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    cloud.dispose();
    ble.dispose();
  });
}
