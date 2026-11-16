import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/screens/dashboard_screen.dart';
import 'package:calcai_app/screens/custom_instructions_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/response_style_usage_dots.dart';
import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

class _SavedGeminiCloud extends FakeCloudService {
  final preferenceEdits = <Map<String, String>>[];
  @override
  bool get modelUnavailable => true;
  @override
  String? get currentModel => null;
  @override
  Future<void> updateModelPreferences(
    String token,
    String mac, {
    String? style,
    String? effort,
  }) async {
    preferenceEdits.add({
      if (style != null) 'style': style,
      if (effort != null) 'effort': effort,
    });
    await super.updateModelPreferences(
      token,
      mac,
      style: style,
      effort: effort,
    );
  }
}

Future<void> main() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  testWidgets(
    'saved Gemini permits preference edits and Custom Instructions without a replacement model',
    (tester) async {
      tester.view.physicalSize = const Size(393, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthService();
      await auth.init();
      final cloud = _SavedGeminiCloud();
      await cloud.setModel('fixture', 'ca1ca1000001', 'gemini-old', 'detailed');
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
            home: const Scaffold(body: DashboardScreen(isActive: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose an available AI model'), findsOneWidget);
      await tester.ensureVisible(find.text('Response style'));
      await tester.tap(find.text('Response style'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Brief explanation'));
      await tester.tap(find.text('Brief explanation'));
      await tester.pumpAndSettle();
      expect(cloud.preferenceEdits, [
        {'style': 'small'},
      ]);
      expect(cloud.modelInfo?['model'], 'gemini-old');
      await tester.tap(find.text('Response style'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add your own'));
      await tester.tap(find.text('Add your own'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomInstructionsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Thinking'));
      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Balanced'));
      await tester.tap(find.text('Balanced'));
      await tester.pumpAndSettle();
      expect(cloud.preferenceEdits.last, {'effort': 'balanced'});
      expect(cloud.modelInfo?['model'], 'gemini-old');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      cloud.dispose();
      ble.dispose();
    },
  );
  for (final variant in [
    (name: 'normal', size: const Size(393, 852), textScale: 1.0),
    (name: 'small', size: const Size(320, 780), textScale: 1.0),
    (name: 'small-large-text', size: const Size(320, 900), textScale: 1.7),
  ]) {
    testWidgets('response style titles and usage dots: ${variant.name}', (
      tester,
    ) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final auth = FakeAuthService();
      await auth.init();
      final cloud = FakeCloudService();
      await cloud.setModel('fixture', 'ca1ca1000001', 'gpt-5.6-luna', 'small');
      final ble = SetupTestAppBle();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            ChangeNotifierProvider<BleService>.value(value: ble),
          ],
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(variant.textScale)),
                child: child!,
              ),
              home: const Scaffold(body: DashboardScreen(isActive: false)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Response style'));
      await tester.tap(find.text('Response style'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Response style')),
        alignment: 0.15,
      );
      await tester.pumpAndSettle();
      expect(find.text('Just the final answers'), findsNothing);
      expect(find.text('Answers with short work'), findsNothing);
      expect(find.text('Full step-by-step work'), findsNothing);
      expect(find.text('Tell the AI how you want answers'), findsNothing);
      expect(find.byType(ResponseStyleUsageDots), findsNWidgets(5));
      expect(find.text('Answers only'), findsOneWidget);
      expect(find.text('Brief explanation'), findsNWidgets(2));
      expect(find.text('Detailed explanation'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Relative AI usage 2 of 3; actual usage varies'),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.text('Brief explanation').last,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Detailed explanation'));
      await tester.tap(find.text('Detailed explanation'));
      await tester.pumpAndSettle();
      expect(cloud.responseStyle, 'detailed');
      await tester.ensureVisible(find.text('Response style'));
      await tester.tap(find.text('Response style'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Response style')),
        alignment: 0.15,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final output = Platform.environment['CALCAI_UI_PREVIEW_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$output/response-style-${variant.name}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
              data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      cloud.dispose();
      ble.dispose();
      semantics.dispose();
    });
  }
}
