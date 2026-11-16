import 'package:calcai_app/screens/settings_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/code_input.dart';
import 'package:calcai_app/widgets/scanning_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

void _expectFullParagraph(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(
    paragraph.size.height + 0.01,
    greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(paragraph.size.width)),
  );
}

void main() {
  testWidgets('Settings rows wrap on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final value in ['Test User', 'test@example.com', 'TI-84 Plus']) {
      await tester.scrollUntilVisible(
        find.text(value),
        150,
        scrollable: find.byType(Scrollable),
      );
      await tester.ensureVisible(find.text(value));
      await tester.pumpAndSettle();
      _expectFullParagraph(tester, find.text(value));
      expect(find.text(value).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.scrollUntilVisible(
      find.text('MAC Address'),
      150,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(find.text('••:••:••:••:••:••'));
    await tester.pumpAndSettle();
    _expectFullParagraph(tester, find.text('••:••:••:••:••:••'));
    await tester.tap(find.text('••:••:••:••:••:••'));
    await tester.pumpAndSettle();
    expect(find.text('ca1ca1000001'), findsOneWidget);
    _expectFullParagraph(tester, find.text('ca1ca1000001'));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('ca1ca1000001'));
    await tester.tap(find.text('ca1ca1000001'));
    await tester.pumpAndSettle();
    expect(find.text('ca1ca1000001'), findsNothing);
    expect(find.text('••:••:••:••:••:••'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Terms of Service'),
      250,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(find.text('Terms of Service'));
    await tester.pumpAndSettle();
    _expectFullParagraph(tester, find.text('Terms of Service'));
    expect(find.text('Terms of Service').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      'scanner honors ${accessibleNavigation ? 'accessible navigation' : 'Reduce Motion'} '
      'at mount and when the preference changes',
      (tester) async {
        late StateSetter rebuild;
        var reduceMotion = true;
        var scanning = true;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: !accessibleNavigation && reduceMotion,
                    accessibleNavigation: accessibleNavigation && reduceMotion,
                  ),
                  child: ScanningAnimation(isScanning: scanning),
                );
              },
            ),
          ),
        );
        await tester.pump();
        CustomPainter painter() => tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(ScanningAnimation),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!;
        final initial = painter();
        await tester.pump(const Duration(seconds: 4));
        expect(painter(), same(initial));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);

        rebuild(() => reduceMotion = false);
        await tester.pump();
        final beforeAnimation = painter();
        await tester.pump(const Duration(milliseconds: 700));
        expect(painter().shouldRepaint(beforeAnimation), isTrue);
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        rebuild(() => reduceMotion = true);
        await tester.pump();
        final stopped = painter();
        await tester.pump(const Duration(seconds: 4));
        expect(painter(), same(stopped));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);

        rebuild(() {
          reduceMotion = false;
          scanning = false;
        });
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        rebuild(() => scanning = true);
        await tester.pump();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        rebuild(() => scanning = false);
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final label in [
    'Pairing code',
    'Email verification code',
    'Password reset code',
  ]) {
    testWidgets('code field announces $label and keeps one-time-code entry', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: '12');
      final completed = <String>[];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: label == 'Pairing code'
                  ? CodeInput(
                      controller: controller,
                      autofocus: false,
                      onCompleted: completed.add,
                    )
                  : CodeInput(
                      controller: controller,
                      autofocus: false,
                      semanticLabel: label,
                      onCompleted: completed.add,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.semantics.byLabel(RegExp('^$label\$'));
        expect(field, findsOne);
        final data = field.evaluate().single.getSemanticsData();
        expect(data.flagsCollection.isTextField, isTrue);
        expect(data.value, '12');
        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.autofillHints, contains(AutofillHints.oneTimeCode));
        expect(textField.keyboardType, TextInputType.number);
        await tester.enterText(find.byType(TextField), '12a3456');
        await tester.pumpAndSettle();
        expect(controller.text, '123456');
        expect(completed, ['123456']);
        expect(field.evaluate().single.getSemanticsData().value, '123456');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        semantics.dispose();
      }
    });
  }
}
