import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/screens/settings_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'support/fake_auth_service.dart';
import 'support/setup_test_app.dart';

void main() {
  for (final provider in ['OpenAI', 'Anthropic']) {
    testWidgets(
      '$provider custom field blocks Gemini and only confirms accepted saves',
      (tester) async {
        tester.view.physicalSize = const Size(393, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var reject = true;
        final posts = <http.Request>[];
        final cloud = CloudService(
          client: MockClient((r) async {
            Object data;
            var status = 200;
            if (r.url.path == '/ai/apikey/list') {
              data = {
                'ok': true,
                'keys': {
                  'openai': {'active': true, 'enabled': true, 'last4': '1234'},
                  'anthropic': {
                    'active': true,
                    'enabled': true,
                    'last4': '5678',
                  },
                  'google': {
                    'active': true,
                    'enabled': false,
                    'available': false,
                    'last4': 'abcd',
                  },
                },
              };
            } else if (r.url.path == '/ai/model/get') {
              data = {'model': 'gpt-5.6-luna', 'style': 'small'};
            } else if (r.url.path == '/ai/model/set') {
              posts.add(r);
              status = reject ? 409 : 200;
              data = reject
                  ? {'ok': false, 'error': 'provider_unavailable'}
                  : jsonDecode(r.body);
            } else {
              data = {'ok': true, 'reviewed': true, 'allowed': false};
            }
            return http.Response(jsonEncode(data), status);
          }),
        );
        final auth = FakeAuthService();
        await auth.init();
        await cloud.listApiKeys(auth.token!);
        await cloud.getModel(auth.token!, auth.primaryMac!);
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
              home: const Scaffold(body: SettingsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('API Keys'));
        await tester.tap(find.text('API Keys'));
        await tester.pumpAndSettle();
        expect(find.text('Google'), findsNothing);
        expect(find.text('Remove saved Google key'), findsOneWidget);
        final row = provider == 'OpenAI'
            ? find.text('Custom model').first
            : find.text('Custom model').last;
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        for (final id in [
          'gemini-future',
          'google/gemini-future',
          'Gemini-future',
        ]) {
          await tester.enterText(find.byType(TextField), id);
          await tester.tap(find.text('Apply'));
          await tester.pumpAndSettle();
          expect(posts, isEmpty);
          expect(
            find.text('Enter a supported $provider model ID.'),
            findsOneWidget,
          );
          expect(find.text('$provider Custom Model'), findsOneWidget);
          expect(find.textContaining('Model set to'), findsNothing);
        }
        final supported = provider == 'OpenAI' ? 'gpt-future' : 'claude-future';
        await tester.enterText(find.byType(TextField), supported);
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(posts, hasLength(1));
        expect(find.text('$provider Custom Model'), findsOneWidget);
        expect(find.textContaining('Model set to'), findsNothing);
        expect(
          find.textContaining('Choose an OpenAI or Anthropic'),
          findsOneWidget,
        );
        reject = false;
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(posts, hasLength(2));
        expect(find.text('$provider Custom Model'), findsNothing);
        expect(find.text('Model set to $supported'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        cloud.dispose();
        ble.dispose();
      },
    );
  }
}
