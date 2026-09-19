import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/setup_preview.dart';

void main() {
  for (final allow in [true, false]) {
    testWidgets('demo completes first setup with AI sharing $allow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SetupPreview());
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Welcome,'), findsOneWidget);
      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guest network'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.text('Device paired'), findsNothing);
      final choice = find.text(
        allow ? 'Allow AI sharing' : 'Continue with AI off',
      );
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      if (!allow) {
        await tester.tap(find.text('Keep AI off'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Device paired'), findsOneWidget);
      await tester.tap(find.text('Home page'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Welcome,'), findsOneWidget);
      expect(find.text('AI, your choice'), findsNothing);
    });
  }
}
