import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/fast_mode_card.dart';

void main() {
  testWidgets('supported mode requires a personal key and exposes its cost', (tester) async {
    bool? picked;
    Future<void> show(String model, bool key) => tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme, home: Scaffold(body: FastModeCard(
        model: model, enabled: false, hasPersonalKey: key, onChanged: (v) => picked = v))));
    await show('gpt-5.6-sol', false);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await show('gpt-5.6-sol', true);
    expect(find.text('High API Cost'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(picked, true);
    await show('claude-sonnet-5', true);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });
  testWidgets('card fits a small phone at large text size', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme,
      home: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child:
          FastModeCard(model: 'claude-opus-5', enabled: true, hasPersonalKey: true, onChanged: (_) {}))))));
    expect(tester.takeException(), isNull);
  });
}
