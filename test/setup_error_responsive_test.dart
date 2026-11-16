import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/pair_device_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/silver_shimmer_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'pairing_v2_test.dart' show PairAuth, PairBle, offerData, completionData;
import 'support/setup_test_app.dart';

class _NamedAuth extends SetupTestAppAuth {
  _NamedAuth(this.name);
  final String name;
  @override
  String get username => name;
}

class _DeniedBle extends SetupTestAppBle {
  _DeniedBle() : super(delay: Duration.zero);
  @override
  Future<bool> requestPermissions() async => false;
}

final _boundary = GlobalKey();

Future<void> _show(
  WidgetTester tester,
  Widget screen,
  AuthService auth,
  BleService ble,
  CloudService cloud,
  double scale, {
  bool keyboard = false,
  bool push = false,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 216 : 0);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(auth.dispose);
  addTearDown(ble.dispose);
  addTearDown(cloud.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: push
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                      child: const Text('Start error fixture'),
                    ),
                  ),
                )
              : screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (push) {
    await tester.tap(find.text('Start error fixture'));
    await tester.pumpAndSettle();
  }
}

List<double> _rect(Rect r) => [r.left, r.top, r.right, r.bottom];

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      img.dispose();
    }
  });
}

Future<void> _save(
  WidgetTester tester,
  String name,
  Map<String, Object?> data,
) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir != null) {
    await tester.runAsync(() async {
      await File(
        '$dir/$name.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    });
  }
}

Future<Map<String, Object?>> _observe(
  WidgetTester tester,
  Finder text,
  double fontSize,
  double scale,
  String id,
  List<String> problems,
) async {
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final rect = tester.getRect(text);
  final scrolls = find.ancestor(
    of: text,
    matching: find.byType(SingleChildScrollView),
  );
  final viewport = scrolls.evaluate().isEmpty
      ? Rect.fromLTWH(0, 0, 320, 568 - tester.view.viewInsets.bottom)
      : tester.getRect(scrolls.first);
  final intrinsic = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
  final actualScale = paragraph.textScaler.scale(fontSize) / fontSize;
  if (paragraph.size.height + 0.01 < intrinsic) {
    problems.add('$id text clipped');
  }
  if ((actualScale - scale).abs() > 0.001) {
    problems.add('$id requested text size changed');
  }
  if (find
      .ancestor(of: text, matching: find.byType(FittedBox))
      .evaluate()
      .isNotEmpty) {
    problems.add('$id fitted/scaled down');
  }
  if (rect.left < viewport.left - 0.1 ||
      rect.right > viewport.right + 0.1 ||
      rect.top < viewport.top - 0.1 ||
      rect.bottom > viewport.bottom + 0.1) {
    problems.add('$id full text not reachable inside viewport');
  }
  final semantics = tester.getSemantics(text).getSemanticsData();
  return {
    'id': id,
    'rectAfterScroll': _rect(rect),
    'viewport': _rect(viewport),
    'height': paragraph.size.height,
    'intrinsicHeight': intrinsic,
    'requestedScale': scale,
    'actualScale': actualScale,
    'semanticLabel': semantics.label,
  };
}

Future<void> main() async {
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  for (final scale in [1.0, 2.0]) {
    for (final name in ['Chris', 'Alexandria']) {
      testWidgets(
        'denied setup full text has no overlap and is scroll reachable: $name scale $scale',
        (tester) async {
          final auth = _NamedAuth(name);
          await auth.init();
          await _show(
            tester,
            const LinkDeviceScreen(),
            auth,
            _DeniedBle(),
            SetupTestAppCloud(),
            scale,
          );
          final semantics = tester.ensureSemantics();
          try {
            await tester.ensureVisible(find.text('Scan'));
            await tester.pumpAndSettle();
            expect(find.text('Scan').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Scan'));
            await tester.pumpAndSettle();
            final scrollables = find.byType(Scrollable);
            if (scrollables.evaluate().isNotEmpty) {
              tester
                  .state<ScrollableState>(scrollables.first)
                  .position
                  .jumpTo(0);
              await tester.pumpAndSettle();
            }
            final welcome = find.text('Welcome,');
            final nameText = find
                .descendant(
                  of: find.byType(SilverShimmerName),
                  matching: find.byType(Text),
                )
                .last;
            final intro = find.text('Let’s pair your new CalcAI device.');
            final error = find.text(
              'CalcAI needs Bluetooth access to find your calculator.',
            );
            final settings = find.text('Open Settings');
            final scan = find.text('Scan');
            final ids = [
              'welcome',
              'name',
              'intro',
              'error',
              'settings',
              'scan',
            ];
            final targets = [welcome, nameText, intro, error, settings, scan];
            final sizes = [42.0, 42.0, 15.0, 13.0, 14.0, 16.0];
            final initial = targets.map(tester.getRect).toList();
            final problems = <String>[];
            for (var i = 0; i < initial.length - 1; i++) {
              if (initial[i].bottom > initial[i + 1].top + 0.1) {
                problems.add('${ids[i]} overlaps ${ids[i + 1]}');
              }
            }
            final prefix = 'denied-$name-${scale == 1 ? 'normal' : 'large'}';
            await _capture(tester, '$prefix-top');
            final observations = <Map<String, Object?>>[];
            for (var i = 0; i < targets.length; i++) {
              observations.add(
                await _observe(
                  tester,
                  targets[i],
                  sizes[i],
                  scale,
                  ids[i],
                  problems,
                ),
              );
              if (i == 1 || i == 3 || i == 5) {
                await _capture(tester, '$prefix-${ids[i]}');
              }
            }
            if (!observations[1]['semanticLabel'].toString().contains(name)) {
              problems.add('name missing from accessibility text');
            }
            if (scan.hitTestable().evaluate().isEmpty) {
              problems.add('Scan not reachable');
            }
            final renderError = tester.takeException();
            if (renderError != null) problems.add(renderError.toString());
            await _save(tester, prefix, {
              'problems': problems,
              'initialRects': {
                for (var i = 0; i < ids.length; i++) ids[i]: _rect(initial[i]),
              },
              'text': observations,
            });
            expect(auth.primaryMac, isNull);
            expect(find.byType(PairDeviceScreen), findsNothing);
            expect(problems, isEmpty);
          } finally {
            semantics.dispose();
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }
    for (final failure in ['unavailable', 'timeout', 'client', 'disabled404']) {
      testWidgets('pairing error full text and action agree: $failure scale $scale', (
        tester,
      ) async {
        final auth = PairAuth();
        await auth.init();
        final ble = PairBle();
        final paths = <String>[];
        final cloud = CloudService(
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (paths.length == 1) {
              if (failure == 'timeout') {
                throw TimeoutException('offline fixture');
              }
              if (failure == 'client') {
                throw http.ClientException('offline fixture');
              }
              return http.Response(
                jsonEncode({
                  'error': failure == 'disabled404'
                      ? 'pairing_v2_disabled'
                      : 'unavailable',
                }),
                failure == 'disabled404' ? 404 : 503,
              );
            }
            return http.Response(
              jsonEncode(
                r.url.path.endsWith('challenge')
                    ? offerData()
                    : completionData(),
              ),
              200,
            );
          }),
        );
        await _show(
          tester,
          const PairDeviceScreen(),
          auth,
          ble,
          cloud,
          scale,
          keyboard: true,
          push: true,
        );
        final semantics = tester.ensureSemantics();
        try {
          expect(find.text('Pair'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '123456');
          await tester.pumpAndSettle();
          final message = switch (failure) {
            'timeout' =>
              'Pairing timed out. Keep the calculator connected and tap Retry.',
            'client' =>
              'Could not reach CalcAI. Keep the calculator connected and tap Retry.',
            'disabled404' =>
              'Secure pairing is not available for this calculator yet. Contact CalcAI support.',
            _ =>
              'Could not finish pairing. Keep the calculator connected and tap Retry.',
          };
          final action = find.descendant(
            of: find.byType(ElevatedButton),
            matching: find.byType(Text),
          );
          final actionLabel = tester.widget<Text>(action).data;
          final problems = <String>[];
          final prefix =
              'pair-error-$failure-${scale == 1 ? 'normal' : 'large'}';
          await _capture(tester, '$prefix-top');
          final observations = <Map<String, Object?>>[];
          for (final (text, fontSize, id) in [
            (find.text('Enter code'), 32.0, 'heading'),
            (
              find.text('Enter the code shown on your calculator.'),
              15.0,
              'intro',
            ),
            (find.text(message), 13.0, 'error'),
            (action, 16.0, 'action'),
          ]) {
            observations.add(
              await _observe(tester, text, fontSize, scale, id, problems),
            );
            if (id == 'error' || id == 'action') {
              await _capture(tester, '$prefix-$id');
            }
          }
          final expectedAction = failure == 'disabled404' ? 'Pair' : 'Retry';
          if (actionLabel != expectedAction) {
            problems.add(
              'Message/action mismatch: expected $expectedAction, saw $actionLabel',
            );
          }
          final renderError = tester.takeException();
          if (renderError != null) problems.add(renderError.toString());
          await _save(tester, prefix, {
            'failure': failure,
            'problems': problems,
            'message': message,
            'actionLabel': actionLabel,
            'text': observations,
          });
          expect(auth.adds, 0);
          expect(paths, ['/ai/pair/challenge']);
          expect(ble.pairingApprovalVersion, 2);
          expect(ble.commands.map((c) => c['cmd']), ['capabilities']);
          expect(problems, isEmpty);
          final button = tester.widget<ElevatedButton>(
            find.byType(ElevatedButton),
          );
          if (failure == 'disabled404') {
            expect(button.onPressed, isNull);
            expect(
              await ble.submitPairingCode('123456', 'fixture@example.com'),
              contains('requires secure pairing'),
            );
          } else {
            expect(button.onPressed, isNotNull);
            expect(find.text('Retry').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Retry'));
            await tester.pumpAndSettle();
            expect(auth.adds, 1);
            expect(find.byType(PairDeviceScreen), findsNothing);
            expect(paths, [
              '/ai/pair/challenge',
              '/ai/pair/challenge',
              '/ai/pair/claim',
            ]);
            expect(ble.commands.any((c) => c['cmd'] == 'paircode'), isFalse);
            expect(ble.commands.any((c) => c['cmd'] == 'paircomplete'), isTrue);
          }
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
