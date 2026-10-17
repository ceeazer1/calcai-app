import 'package:calcai_app/screens/custom_instructions_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

Future<FakeCloudService> openEditor(WidgetTester tester) async {
  final auth = FakeAuthService();
  await auth.init();
  final cloud = FakeCloudService();
  addTearDown(auth.dispose);
  addTearDown(cloud.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomInstructionsScreen(),
                ),
              ),
              child: const Text('Open instructions'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open instructions'));
  await tester.pumpAndSettle();
  return cloud;
}

void main() {
  for (final length in [1999, 2000, 2001]) {
    testWidgets('instructions pasted at $length stay within the saved limit', (
      tester,
    ) async {
      final cloud = await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'x' * length);
      await tester.pump();
      final expected = length > 2000 ? 2000 : length;
      expect(find.text('$expected/2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(cloud.customContext, 'x' * expected);
      expect(find.byType(CustomInstructionsScreen), findsNothing);
    });
  }

  testWidgets(
    'example chips cannot exceed the limit or overwrite existing text',
    (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'x' * 1990);
      await tester.pump();
      final example = find.text('Always show the formula before the numbers.');
      await tester.ensureVisible(example);
      await tester.tap(example);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'x' * 1990,
      );
      expect(
        find.text(
          'Not enough space for this example. Limit: 2,000 characters.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Unicode respects the server limit without splitting a character',
    (tester) async {
      final cloud = await openEditor(tester);
      await tester.enterText(find.byType(TextField), '${'x' * 1998}😀z');
      await tester.pump();
      expect(find.text('2000/2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(cloud.customContext, '${'x' * 1998}😀');
    },
  );

  for (final character in ['😀', 'e\u0301']) {
    testWidgets('a partial $character at the limit is never saved', (
      tester,
    ) async {
      final cloud = await openEditor(tester);
      await tester.enterText(find.byType(TextField), '${'x' * 1999}$character');
      await tester.pump();
      expect(find.text('1999/2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(cloud.customContext, 'x' * 1999);
    });
  }

  testWidgets('an unfinished over-limit composition cannot be saved', (
    tester,
  ) async {
    final cloud = await openEditor(tester);
    final composing = TextEditingValue(
      text: 'x' * 2001,
      selection: const TextSelection.collapsed(offset: 2001),
      composing: const TextRange(start: 2000, end: 2001),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(cloud.customContext, isEmpty);
    tester.testTextInput.updateEditingValue(
      composing.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(cloud.customContext.length, 2000);
  });
}
