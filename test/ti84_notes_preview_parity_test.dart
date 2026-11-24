import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calc_note.dart';
import 'package:calcai_app/screens/notes_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/ti84_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

// Firmware-owner reproducer reported through Master: seven explicit lines of
// exactly 16 characters occupy one seven-text-row calculator page. The footer
// uses the eighth LCD row. This must not count each line terminator twice.
final exactWidthSevenLines = List.filled(7, '1234567890123456').join('\n');

Future<void> capturePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['CALCAI_NOTES_PREVIEW_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> main() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final reference =
      jsonDecode(
            File(
              'test/fixtures/ti84_firmware_148_text_parity.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final raw in reference['cases'] as List) {
    final fixture = raw as Map<String, dynamic>;
    test('signed firmware text parity: ${fixture['name']}', () {
      final expected = (fixture['paddedPages'] as List).cast<String>();
      final actual = paginateForTi84(fixture['input'] as String);
      if (expected.isEmpty) {
        // The editor deliberately keeps one blank preview for an empty note;
        // the firmware returns no page when there are no display text lines.
        expect(actual, [<String>[]]);
        return;
      }
      expect(actual.length, expected.length);
      final padded = actual.map((page) {
        expect(page.length, lessThanOrEqualTo(7));
        for (final line in page) {
          expect(line.length, lessThanOrEqualTo(16));
          expect(line.codeUnits.every((c) => c >= 32 && c <= 126), isTrue);
        }
        return [
          ...page.map((line) => line.padRight(16)),
          ...List.filled(7 - page.length, ' ' * 16),
        ].join('\n');
      }).toList();
      expect(padded, expected);
    });
  }

  test('seven exact-width lines occupy one calculator text page', () {
    expect(
      wrapForTi84(exactWidthSevenLines),
      List.filled(7, '1234567890123456'),
    );
    expect(paginateForTi84(exactWidthSevenLines), [
      List.filled(7, '1234567890123456'),
    ]);
  });

  testWidgets('the real Notes editor describes seven text rows and a footer', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final captureKey = GlobalKey();
    final auth = FakeAuthService();
    await auth.init();
    final cloud = FakeCloudService();
    addTearDown(auth.dispose);
    addTearDown(cloud.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
            home: const Scaffold(body: NotesScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), exactWidthSevenLines);
    await tester.pumpAndSettle();
    final copy = find.text(
      '96x64 screen — 16 chars per line, 7 text lines plus navigation.',
    );
    expect(copy, findsOneWidget);
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    expect(find.text('Screen 1 of 1  ·  7/7 lines'), findsOneWidget);
    expect(find.text('< | >  Pg:1'), findsOneWidget);
    expect(find.textContaining('8 lines each'), findsNothing);
    expect(
      tester.getRect(copy).bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Next page',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await capturePreview(tester, captureKey, 'exact-width-seven-lines');
  });

  testWidgets('preview transforms math without changing the saved note body', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final captureKey = GlobalKey();
    final auth = FakeAuthService();
    await auth.init();
    final cloud = FakeCloudService();
    addTearDown(auth.dispose);
    addTearDown(cloud.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
            home: const Scaffold(body: NotesScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    const original = 'π × 2 ≤ 8';
    await tester.enterText(find.byType(TextField).at(1), original);
    await tester.pumpAndSettle();
    expect(find.text('pi * 2 <= 8'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      original,
    );
    await tester.ensureVisible(find.byType(Ti84Pager));
    await capturePreview(tester, captureKey, 'unicode-display-copy');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(CalcNote.parseStored(cloud.notes!).single.body, original);
    expect(find.text('Saved to your account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
