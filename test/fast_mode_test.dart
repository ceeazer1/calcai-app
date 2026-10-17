import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/fast_mode_card.dart';
import 'package:calcai_app/widgets/provider_funding_label.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('current OpenAI models support opt-in fast mode', () {
    for (final model in ['gpt-6-astra', 'gpt-6.1-sol', 'gpt-6-luna']) {
      expect(fastModeProvider(model), 'openai');
    }
    expect(fastModeProvider('gpt-6-made-up'), isNull);
  });
  testWidgets('supported mode follows availability and exposes its cost', (
    tester,
  ) async {
    bool? picked;
    Future<void> show(String model, bool key) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: FastModeCard(
            model: model,
            enabled: false,
            available: key,
            costLabel: 'Uses more CalcAI allowance',
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );
    await show('gpt-5.6-sol', false);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await show('gpt-5.6-sol', true);
    expect(find.text('Uses more CalcAI allowance'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(picked, true);
    for (final model in [
      'gemini-3.8-flash',
      'claude-sonnet-5',
      'unknown-model',
    ]) {
      await show(model, true);
      expect(find.text('Fast mode'), findsNothing);
      expect(find.text('Uses more CalcAI allowance'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    }
    await show('claude-opus-5', true);
    expect(find.text('Fast mode'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });
  testWidgets('card fits a small phone at large text size', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: FastModeCard(
                model: 'claude-opus-5',
                enabled: true,
                available: true,
                costLabel: 'High API cost · billed to your provider',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an enabled Fast mode can still be turned off when unavailable', (
    tester,
  ) async {
    bool? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FastModeCard(
            model: 'gpt-6.1-sol',
            enabled: true,
            available: false,
            costLabel: 'Fast mode is temporarily unavailable',
            onChanged: (value) => picked = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    expect(picked, false);
  });

  testWidgets(
    'provider payer label fits narrow phone and excludes disabled keys',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var enabled = true;
      final cloud = CloudService(
        client: MockClient(
          (_) async => http.Response(
            '{"ok":true,"keys":{"openai":{"active":true,"last4":"1234","enabled":$enabled}}}',
            200,
          ),
        ),
      );
      addTearDown(cloud.dispose);
      await cloud.listApiKeys('session');
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(30),
                child: ProviderFundingLabel(cloud: cloud, provider: 'openai'),
              ),
            ),
          ),
        ),
      );
      await show();
      expect(find.text('Using your OpenAI key ••••1234'), findsOneWidget);
      expect(
        find.textContaining('does not use your CalcAI allowance'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      enabled = false;
      await cloud.listApiKeys('session');
      await show();
      expect(find.text('Using CalcAI allowance'), findsOneWidget);
      expect(find.textContaining('Using your OpenAI key'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
