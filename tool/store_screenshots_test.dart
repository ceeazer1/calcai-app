// Opt-in screenshot drafts of real widgets with local sample data.
// Run: flutter test tool/store_screenshots_test.dart
// Not imported by the app and not part of normal test discovery.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/models/ai_funding.dart';
import 'package:calcai_app/models/calc_note.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/fast_mode_card.dart';
import '../test/flutter_test_config.dart' as fonts;
import '../test/support/fake_auth_service.dart';
import '../test/support/setup_test_app.dart';

const _noteExamples = [
  (
    title: 'Integration by parts',
    body:
        'Integral u dv = uv - Integral v du\nChoose u to simplify when differentiated.',
  ),
  (
    title: 'Projectile motion',
    body: 'vx=v*cos(a)\nvy=v*sin(a)\nh=vy^2/(2*g)\ng=9.8 m/s^2',
  ),
  (
    title: 'Unit conversions',
    body: '1 km = 1000 m\n1 hour = 3600 s\n1 N = 1 kg m/s^2',
  ),
];

class _StoreAuth extends FakeAuthService {
  @override
  String get username => 'Alex';
  @override
  String get email => 'alex@example.com';
}

class _StoreCloud extends SetupTestAppCloud {
  // Complete local sample state. Production readiness checks remain unchanged.
  static const _sampleModel = <String, dynamic>{
    'model': 'gpt-5.6-luna',
    'style': 'small',
    'effort': 'fast',
    'fastMode': false,
    'fastModeFunding': 'allowance',
    'fastModeCapability': {
      'supported': true,
      'available': true,
      'funding': 'allowance',
    },
  };

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
  Map<String, dynamic> get modelInfo => _sampleModel;
  @override
  String get currentModel => _sampleModel['model'] as String;
  @override
  String get responseStyle => _sampleModel['style'] as String;
  @override
  String get thinkingEffort => _sampleModel['effort'] as String;
  @override
  AiFunding get currentModelFunding => AiFunding.allowance;
  @override
  AiFunding providerFunding(String provider) => AiFunding.allowance;
  @override
  FastModeCapability get fastModeCapability =>
      FastModeCapability.parse(_sampleModel['fastModeCapability'])!;
}

final _pngCrcTable = List<int>.generate(256, (value) {
  var crc = value;
  for (var bit = 0; bit < 8; bit++) {
    crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
  }
  return crc;
});

Uint8List _pngChunk(String type, List<int> data) {
  final payload = Uint8List(4 + data.length)
    ..setRange(0, 4, ascii.encode(type))
    ..setRange(4, 4 + data.length, data);
  var crc = 0xffffffff;
  for (final byte in payload) {
    crc = (crc >>> 8) ^ _pngCrcTable[(crc ^ byte) & 0xff];
  }
  final chunk = Uint8List(12 + data.length);
  ByteData.sublistView(chunk).setUint32(0, data.length, Endian.big);
  chunk.setRange(4, 8 + data.length, payload);
  ByteData.sublistView(
    chunk,
  ).setUint32(8 + data.length, crc ^ 0xffffffff, Endian.big);
  return chunk;
}

// Apple disallows alpha channels even when every pixel is opaque. Encode RGB
// without resizing or changing pixels, and reject unexpected transparency.
Uint8List _opaqueRgbPng(ByteData rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.lengthInBytes != width * height * 4) {
    throw ArgumentError('Unexpected screenshot dimensions or pixel length.');
  }
  final pixels = rgba.buffer.asUint8List(
    rgba.offsetInBytes,
    rgba.lengthInBytes,
  );
  final scanlines = Uint8List(height * (1 + width * 3));
  var source = 0;
  var target = 0;
  for (var y = 0; y < height; y++) {
    scanlines[target++] = 0; // PNG filter: None.
    for (var x = 0; x < width; x++) {
      if (pixels[source + 3] != 255) {
        throw StateError('Screenshot has a transparent pixel at ($x, $y).');
      }
      scanlines[target++] = pixels[source++];
      scanlines[target++] = pixels[source++];
      scanlines[target++] = pixels[source++];
      source++; // Drop the verified opaque alpha byte.
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8) // Bit depth.
    ..setUint8(9, 2); // Truecolor RGB, no alpha or transparency chunk.
  return (BytesBuilder(copy: false)
        ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
        ..add(_pngChunk('IHDR', header.buffer.asUint8List()))
        ..add(_pngChunk('IDAT', ZLibEncoder().convert(scanlines)))
        ..add(_pngChunk('IEND', const [])))
      .takeBytes();
}

Future<void> main() async {
  await fonts.testExecutable(() async {
    test('RGB export rejects transparency instead of changing its pixels', () {
      final rgba = ByteData.sublistView(Uint8List.fromList([1, 2, 3, 254]));
      expect(() => _opaqueRgbPng(rgba, 1, 1), throwsStateError);
    });
    test(
      'RGB export preserves exact dimensions and opaque pixel values',
      () async {
        final original = Uint8List.fromList([
          1,
          2,
          3,
          255,
          250,
          128,
          64,
          255,
          0,
          255,
          0,
          255,
          42,
          99,
          200,
          255,
        ]);
        final png = _opaqueRgbPng(ByteData.sublistView(original), 2, 2);
        expect(ByteData.sublistView(png).getUint32(16, Endian.big), 2);
        expect(ByteData.sublistView(png).getUint32(20, Endian.big), 2);
        expect(png[24], 8);
        expect(png[25], 2);
        final codec = await ui.instantiateImageCodec(png);
        try {
          final decoded = (await codec.getNextFrame()).image;
          try {
            expect(decoded.width, 2);
            expect(decoded.height, 2);
            final decodedRgba = await decoded.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(
              decodedRgba!.buffer.asUint8List(
                decodedRgba.offsetInBytes,
                decodedRgba.lengthInBytes,
              ),
              original,
            );
          } finally {
            decoded.dispose();
          }
        } finally {
          codec.dispose();
        }
      },
    );
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
        final noteBase = await cloud.readNotesSnapshot(
          auth.token!,
          auth.primaryMac!,
        );
        final seeded = await cloud.writeNotesSnapshot(
          auth.token!,
          auth.primaryMac!,
          CalcNote.toEnvelope([
            for (final example in _noteExamples)
              CalcNote.create(title: example.title, body: example.body),
          ]),
          base: noteBase,
        );
        expect(
          seeded,
          isNotNull,
          reason: 'Screenshot notes must be seeded before capture.',
        );
        final stored = CalcNote.parseStored(
          (await cloud.readNotesSnapshot(auth.token!, auth.primaryMac!)).text,
        );
        expect(
          stored.map((note) => (title: note.title, body: note.body)).toList(),
          _noteExamples,
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
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason: '$name must capture its loaded state.',
          );
          switch (name) {
            case 'home':
              expect(find.text('AI Usage'), findsOneWidget);
              expect(find.text('gpt-5.6-luna'), findsOneWidget);
              expect(find.textContaining('Could not confirm'), findsNothing);
              expect(find.text('Using CalcAI allowance'), findsOneWidget);
              expect(find.text('Uses more CalcAI allowance'), findsOneWidget);
              final fast = tester.widget<FastModeCard>(
                find.byType(FastModeCard),
              );
              expect(fast.enabled, isFalse);
              expect(fast.available, isTrue);
              break;
            case 'notes':
              expect(find.text('3/5'), findsOneWidget);
              expect(find.text('No notes yet'), findsNothing);
              expect(find.text('Notes are unavailable'), findsNothing);
              for (final example in _noteExamples) {
                expect(find.text(example.title), findsOneWidget);
                expect(find.text(example.body), findsOneWidget);
              }
              // `byTooltip` resolves to Tooltip/RawTooltip in recent Flutter;
              // inspect the actionable control beneath it instead of casting
              // the wrapper itself to IconButton.
              final addNote = find.widgetWithIcon(
                IconButton,
                Icons.add_rounded,
              );
              expect(addNote, findsOneWidget);
              expect(tester.widget<IconButton>(addNote).onPressed, isNotNull);
              break;
            case 'settings':
              expect(find.text('Alex'), findsOneWidget);
              expect(find.text('alex@example.com'), findsOneWidget);
              break;
            case 'wifi':
              expect(find.text('WiFi Networks'), findsOneWidget);
              expect(find.text('Saved Networks'), findsOneWidget);
              expect(find.text('Home Wi-Fi'), findsOneWidget);
              expect(find.text('My iPhone'), findsOneWidget);
              break;
            default:
              fail('No screenshot-state assertions defined for $name.');
          }
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: size.scale);
            try {
              expect(image.width, (size.logical.width * size.scale).round());
              expect(image.height, (size.logical.height * size.scale).round());
              final rgba = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final png = _opaqueRgbPng(rgba!, image.width, image.height);
              expect(
                png[25],
                2,
                reason: 'Screenshots must have no alpha channel.',
              );
              expect(
                ByteData.sublistView(png).getUint32(16, Endian.big),
                image.width,
              );
              expect(
                ByteData.sublistView(png).getUint32(20, Endian.big),
                image.height,
              );
              final file = File(
                '../outputs/app-store-preparation-2026-09-21/screenshots-draft/${size.name}-$name.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png);
            } finally {
              image.dispose();
            }
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
