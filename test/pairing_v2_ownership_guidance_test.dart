import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/pairing_v2.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/screens/pair_device_screen.dart';
import 'package:calcai_app/screens/success_screen.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'pairing_v2_test.dart'
    show PairAuth, PairBle, mac, offerData, approvalData;

const _guidance =
    'This CalcAI is already linked to another account. '
    'Sign in with that account, or contact CalcAI support for help.';
const _staleAttempt =
    'This pairing attempt is no longer valid. Leave setup and reconnect.';
const _disabled =
    'Secure pairing is not available for this calculator yet. Contact CalcAI support.';

class _UnpairedAuth extends PairAuth {
  @override
  String? get primaryMac => null;
  @override
  List<String> get deviceMacs => const [];
}

class _UnpairedEntryBle extends PairBle {
  _UnpairedEntryBle() {
    connected = false;
  }
  final candidate = CalcAiDevice(
    device: BluetoothDevice.fromId(mac),
    rssi: -45,
    advertisementName: 'CalcAI offline fixture',
  );
  bool found = false;
  int pairStateReads = 0, persists = 0, wifiModes = 0, releases = 0;
  @override
  List<CalcAiDevice> get devices => found ? [candidate] : [];
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    found = true;
    notifyListeners();
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    expectSync(device, same(candidate));
    connected = true;
    notifyListeners();
  }

  @override
  Future<bool?> isDevicePaired() async {
    pairStateReads++;
    return false;
  }

  @override
  Future<void> setPersistMac(String? mac) async {
    persists++;
  }

  @override
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
    wifiModes++;
    return true;
  }

  @override
  Future<bool> releaseOwnership(String nonce, String response) async {
    releases++;
    throw StateError(
      'Ownership conflict must never release or reset the fixture',
    );
  }
}

class _NavigationProbe extends NavigatorObserver {
  int pushes = 0, pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

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
    final img = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      await File(
        '$dir/$name.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } finally {
      img.dispose();
    }
  });
}

Future<void> main() async {
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  for (final stage in ['challenge', 'claim']) {
    test(
      'exact V2 ${stage}409 device_already_paired rejects with owning-account/support guidance',
      () async {
        final requests = <http.Request>[];
        final cloud = CloudService(
          client: MockClient((r) async {
            requests.add(r);
            return http.Response('{"error":"device_already_paired"}', 409);
          }),
        );
        addTearDown(cloud.dispose);
        final offer = PairingOffer.fromJson(offerData(), mac);
        final operation = stage == 'challenge'
            ? cloud.requestPairingOffer('fixture-token', mac)
            : cloud.claimApprovedDevice(
                'fixture-token',
                offer,
                PairingApproval.fromJson(approvalData(), offer),
              );
        await expectLater(
          operation,
          throwsA(
            isA<PairingV2Exception>()
                .having((e) => e.message, 'ownership guidance', _guidance)
                .having((e) => e.restartRequired, 'attempt must stop', isTrue),
          ),
        );
        expect(requests.map((r) => r.url.path), ['/ai/pair/$stage']);
        if (stage == 'challenge') {
          expect(jsonDecode(requests.single.body), {'mac': mac});
        } else {
          expect(jsonDecode(requests.single.body), containsPair('protocol', 2));
        }
      },
    );
  }
  for (final (status, code, expected) in [
    (409, 'pairing_challenge_consumed', _staleAttempt),
    (403, 'device_already_paired', _staleAttempt),
    (404, 'pairing_v2_disabled', _disabled),
    (401, 'device_already_paired', 'Sign in again before pairing.'),
  ]) {
    test(
      'ownership guidance matches only exact409 code: $status $code',
      () async {
        var calls = 0;
        final cloud = CloudService(
          client: MockClient((_) async {
            calls++;
            return http.Response(jsonEncode({'error': code}), status);
          }),
        );
        addTearDown(cloud.dispose);
        await expectLater(
          cloud.requestPairingOffer('fixture-token', mac),
          throwsA(
            isA<PairingV2Exception>()
                .having((e) => e.message, 'unchanged rejection', expected)
                .having((e) => e.restartRequired, 'attempt must stop', isTrue),
          ),
        );
        expect(calls, 1);
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'locally unpaired and cloud-owned elsewhere stops actual setup route at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final auth = _UnpairedAuth();
        await auth.init();
        final ble = _UnpairedEntryBle();
        final paths = <String>[];
        final cloud = CloudService(
          client: MockClient((r) async {
            paths.add(r.url.path);
            expectSync(jsonDecode(r.body), {'mac': mac});
            return http.Response('{"error":"device_already_paired"}', 409);
          }),
        );
        addTearDown(auth.dispose);
        addTearDown(ble.dispose);
        addTearDown(cloud.dispose);
        final key = GlobalKey();
        final navigation = _NavigationProbe();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              ChangeNotifierProvider<BleService>.value(value: ble),
              ChangeNotifierProvider<CloudService>.value(value: cloud),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: AppTheme.darkTheme.copyWith(
                  platform: TargetPlatform.iOS,
                ),
                debugShowCheckedModeBanner: false,
                navigatorObservers: [navigation],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: const LinkDeviceScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        try {
          expect(auth.primaryMac, isNull);
          await tester.ensureVisible(find.text('Scan'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Scan'));
          await tester.pumpAndSettle();
          expect(ble.pairStateReads, 1);
          expect(find.byType(PairDeviceScreen), findsOneWidget);
          final pushesAtPair = navigation.pushes;
          tester.view.viewInsets = const FakeViewPadding(bottom: 216);
          await tester.enterText(find.byType(TextField), '123456');
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 3));
          expect(paths, ['/ai/pair/challenge']);
          expect(ble.commands.map((c) => c['cmd']), ['capabilities']);
          expect(ble.pairingApprovalVersion, 2);
          expect(
            await ble.submitPairingCode('123456', 'fixture@example.com'),
            contains('requires secure pairing'),
          );
          expect(auth.adds, 0);
          expect(auth.deviceMacs, isEmpty);
          expect(auth.primaryMac, isNull);
          expect(ble.persists, 0);
          expect(ble.wifiModes, 0);
          expect(ble.releases, 0);
          expect(navigation.pushes, pushesAtPair);
          expect(navigation.pops, 0);
          expect(find.byType(PairDeviceScreen), findsOneWidget);
          expect(find.byType(WifiSetupScreen), findsNothing);
          expect(find.byType(SuccessScreen), findsNothing);
          expect(find.byType(MainShell), findsNothing);
          expect(find.text('Device paired'), findsNothing);
          expect(
            tester
                .widget<ElevatedButton>(find.byType(ElevatedButton))
                .onPressed,
            isNull,
          );
          await _capture(
            tester,
            key,
            'ownership-${scale == 1 ? 'normal' : 'large'}-initial',
            {
              'paths': paths,
              'bleCommands': ble.commands,
              'localOwnershipWrites': auth.adds,
              'persistCalls': ble.persists,
              'wifiModeCalls': ble.wifiModes,
              'releaseCalls': ble.releases,
              'navigationPushesAfterError': navigation.pushes - pushesAtPair,
              'navigationPops': navigation.pops,
              'visibleText': tester
                  .widgetList<Text>(find.byType(Text))
                  .map((t) => t.data)
                  .toList(),
            },
          );
          expect(find.text(_guidance), findsOneWidget);
          expect(
            find.textContaining('Leave setup and reconnect'),
            findsNothing,
          );
          expect(find.textContaining('tap Retry'), findsNothing);
          await tester.ensureVisible(find.text(_guidance));
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(_guidance),
          );
          final rect = tester.getRect(find.text(_guidance));
          final viewport = tester.getRect(find.byType(SingleChildScrollView));
          expect(
            paragraph.size.height + 0.01,
            greaterThanOrEqualTo(
              paragraph.getMaxIntrinsicHeight(paragraph.size.width),
            ),
          );
          expect(paragraph.textScaler.scale(13), closeTo(13 * scale, 0.01));
          expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.1));
          expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
          expect(
            tester.getSemantics(find.text(_guidance)).getSemanticsData().label,
            contains(_guidance),
          );
          await _capture(
            tester,
            key,
            'ownership-${scale == 1 ? 'normal' : 'large'}-guidance',
            {
              'guidance': _guidance,
              'textScale': scale,
              'height': paragraph.size.height,
              'intrinsicHeight': paragraph.getMaxIntrinsicHeight(
                paragraph.size.width,
              ),
              'textRect': [rect.top, rect.bottom],
              'viewport': [viewport.top, viewport.bottom],
            },
          );
          await tester.ensureVisible(find.text('Pair'));
          await tester.pumpAndSettle();
          expect(find.text('Pair').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
