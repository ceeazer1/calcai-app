// Opt-in screenshot drafts of real widgets with local sample data.
// Run: flutter test tool/store_screenshots_test.dart
// Not imported by the app and not part of normal test discovery.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/models/calc_note.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import '../test/flutter_test_config.dart' as fonts;
import '../test/support/fake_auth_service.dart';
import '../test/support/setup_test_app.dart';

class _StoreAuth extends FakeAuthService {
  @override
  String get username => 'Alex';
  @override
  String get email => 'alex@example.com';
}

class _StoreCloud extends SetupTestAppCloud {
  _StoreCloud()
    : super(
        client: MockClient((r) async {
          final now = DateTime.now().toUtc();
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/usage/status')
                  ? {
                      'ok': true,
                      'usageVersion': 2,
                      'scope': 'account',
                      'plan': 'pro',
                      'serverTime': now.toIso8601String(),
                      'status': 'ready',
                      'period': {
                        'resetsAt': DateTime.utc(
                          now.year,
                          now.month,
                          now.day + 1,
                        ).toIso8601String(),
                      },
                      'allowance': {
                        'remainingPercent': 80,
                        'unlimited': false,
                        'exhausted': false,
                      },
                      'welcomeAllowance': {
                        'active': true,
                        'expiresAt': now
                            .add(const Duration(days: 25))
                            .toIso8601String(),
                      },
                      'models': [],
                    }
                  : {'keys': {}},
            ),
            200,
          );
        }),
      );
  @override
  String get currentModel => 'gpt-5.6-luna';
}

Future<void> main() async {
  await fonts.testExecutable(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    for (final size in [
      (name: 'iphone', logical: const Size(414, 896), scale: 3.0),
      (name: 'ipad', logical: const Size(1024, 1366), scale: 2.0),
    ]) {
      testWidgets('capture ${size.name} draft screenshots', (tester) async {
        tester.view.physicalSize = size.logical * size.scale;
        tester.view.devicePixelRatio = size.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = _StoreAuth();
        await auth.init();
        final cloud = _StoreCloud();
        await cloud.getUsage('sample');
        await cloud.setNotes(
          'sample',
          'ca1ca1000001',
          CalcNote.toEnvelope([
            CalcNote.create(
              title: 'Integration by parts',
              body:
                  'Integral u dv = uv - Integral v du\nChoose u to simplify when differentiated.',
            ),
            CalcNote.create(
              title: 'Projectile motion',
              body: 'vx=v*cos(a)\nvy=v*sin(a)\nh=vy^2/(2*g)\ng=9.8 m/s^2',
            ),
            CalcNote.create(
              title: 'Unit conversions',
              body: '1 km = 1000 m\n1 hour = 3600 s\n1 N = 1 kg m/s^2',
            ),
          ]),
        );
        final ble = SetupTestAppBle(paired: true, delay: Duration.zero);
        final key = GlobalKey();
        Widget app(Widget home) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            ChangeNotifierProvider<BleService>.value(value: ble),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
              home: home,
            ),
          ),
        );
        Future<void> capture(String name) async {
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: size.scale);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              '../outputs/app-store-preparation-2026-09-21/screenshots-draft/${size.name}-$name.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(app(const MainShell()));
        await capture('home');
        await tester.tap(find.text('Notes').last);
        await capture('notes');
        await tester.tap(find.text('Settings').last);
        await capture('settings');
        await tester.pumpWidget(app(const WifiScreen()));
        await tester.pump();
        await capture('wifi');
        await tester.pumpWidget(const SizedBox.shrink());
        cloud.dispose();
        auth.dispose();
        ble.dispose();
      });
    }
  });
}
