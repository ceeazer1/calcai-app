import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/screens/dashboard_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

void main() {
  testWidgets('new OpenAI models can be selected and saved from the dashboard', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuthService();
    await auth.init();
    final cloud = FakeCloudService();
    final ble = SetupTestAppBle();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<CloudService>.value(value: cloud),
      ChangeNotifierProvider<BleService>.value(value: ble),
    ], child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: DashboardScreen()))));
    await tester.pumpAndSettle();
    for (final model in ['gpt-6-astra', 'gpt-6.1-sol', 'gpt-6-luna']) {
      final current = cloud.currentModel ?? 'Not set';
      await tester.ensureVisible(find.text(current).first);
      await tester.tap(find.text(current).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(model).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(model).last);
      await tester.pumpAndSettle();
      expect(cloud.currentModel, model);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    auth.dispose(); cloud.dispose(); ble.dispose();
  });
}
