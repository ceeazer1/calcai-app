import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/screens/success_screen.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/gradient_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
  Map<String, Object?> data,
) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      await File(
        '$dir/$name.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } finally {
      image.dispose();
    }
  });
}

Future<void> main() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  for (final (scale, height) in [(1.0, 568.0), (2.0, 568.0), (2.0, 400.0)]) {
    testWidgets(
      'completion title and Home preserve full text at scale $scale height $height',
      (tester) async {
        tester.view.physicalSize = Size(320, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const SuccessScreen(securePairing: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        try {
          final titleFinder = find.text('Device paired');
          final action = find.text('Home page');
          await tester.ensureVisible(titleFinder);
          await tester.pumpAndSettle();
          final title = tester.renderObject<RenderParagraph>(titleFinder);
          final deviceWordBoxes = title
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 6),
              )
              .length;
          final rect = tester.getRect(titleFinder);
          final buttonRect = tester.getRect(find.byType(GradientButton));
          final name =
              'completion-text${scale.toInt()}-height${height.toInt()}';
          await _capture(tester, key, '$name-title', {
            'textScale': scale,
            'height': height,
            'deviceWordLineBoxes': deviceWordBoxes,
            'titleFontSize': title.textScaler.scale(44),
            'titleHeight': title.size.height,
            'intrinsicHeight': title.getMaxIntrinsicHeight(title.size.width),
            'titleRect': [rect.top, rect.bottom],
            'homeRect': [buttonRect.top, buttonRect.bottom],
            'titleHomeGap': buttonRect.top - rect.bottom,
          });
          expect(deviceWordBoxes, 1, reason: 'Device must not wrap mid-word');
          expect(title.textScaler.scale(44), closeTo(44 * scale, 0.01));
          expect(
            title.size.height + 0.01,
            greaterThanOrEqualTo(title.getMaxIntrinsicHeight(title.size.width)),
          );
          expect(rect.top, greaterThanOrEqualTo(-0.1));
          expect(rect.bottom, lessThanOrEqualTo(height + 0.1));
          expect(
            buttonRect.top,
            greaterThanOrEqualTo(rect.bottom + 15),
            reason: 'Completion title must leave space before Home',
          );
          expect(
            tester.getSemantics(titleFinder).getSemanticsData().label,
            'Device paired',
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          final homeRect = tester.getRect(find.byType(GradientButton));
          expect(homeRect.top, greaterThanOrEqualTo(-0.1));
          expect(homeRect.bottom, lessThanOrEqualTo(height + 0.1));
          final home = tester.renderObject<RenderParagraph>(action);
          expect(
            home.size.height + 0.01,
            greaterThanOrEqualTo(home.getMaxIntrinsicHeight(home.size.width)),
          );
          await _capture(tester, key, '$name-action', {
            'textScale': scale,
            'height': height,
            'homeRect': [homeRect.top, homeRect.bottom],
            'homeTextHeight': home.size.height,
            'homeIntrinsicHeight': home.getMaxIntrinsicHeight(home.size.width),
            'scrollReachable': true,
          });
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
