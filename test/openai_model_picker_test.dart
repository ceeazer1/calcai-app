import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcai_app/models/ai_model.dart';
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
  testWidgets(
    'provider models and a future server model can be selected and saved',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthService();
      await auth.init();
      final cloud = FakeCloudService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'models': [
                for (final m in [
                  ...fallbackAiModels,
                  const AiModel('claude-test-future', 'anthropic', free: true),
                ])
                  {
                    'id': m.id,
                    'provider': m.provider,
                    'tier': m.free ? 'free' : 'pro',
                    'fastMode': m.fastMode,
                  },
              ],
            }),
            200,
          ),
        ),
      );
      final ble = SetupTestAppBle();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            ChangeNotifierProvider<BleService>.value(value: ble),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in [
        ('OpenAI', 'gpt-6-astra'),
        ('OpenAI', 'gpt-6.1-sol'),
        ('OpenAI', 'gpt-6-luna'),
        ('Google', 'gemini-3.8-flash'),
        ('Google', 'gemini-3.7-flash'),
        ('Anthropic', 'claude-opus-5-5'),
        ('Anthropic', 'claude-sonnet-5-5'),
        ('Anthropic', 'claude-fable-5-1'),
        ('Anthropic', 'claude-test-future'),
      ]) {
        final model = entry.$2;
        final current = cloud.currentModel ?? 'Not set';
        await tester.ensureVisible(find.text(current).first);
        await tester.tap(find.text(current).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$1));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(model),
          150,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(find.text(model).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(model).last);
        await tester.pumpAndSettle();
        expect(cloud.currentModel, model);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      cloud.dispose();
      ble.dispose();
    },
  );
}
