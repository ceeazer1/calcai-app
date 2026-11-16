import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/wifi_network.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
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

import 'pairing_v2_test.dart' show PairBle, mac;
import 'support/fake_auth_service.dart';

// Response contracts selected only by this offline fixture. The app does not
// configure backend eligibility, and these responses are not live-server proof.
enum _Contract { livePublicOff404, proposedEnabledV2 }

class _Auth extends FakeAuthService {
  _Auth(this.events);
  final List<String> events;
  String? claimed;
  int adds = 0;
  @override
  String? get primaryMac => claimed;
  @override
  List<String> get deviceMacs => claimed == null ? [] : [claimed!];
  @override
  Future<void> addDevice(String mac, {bool announce = true}) async {
    expectSync(events, contains('ble:completion-ack'));
    events.add('auth:owned');
    claimed = mac;
    adds++;
  }
}

class _Ble extends PairBle {
  _Ble(this.vector, this.events) {
    connected = false;
  }
  final Map<String, dynamic> vector;
  final List<String> events;
  final completionAck = Completer<void>();
  final wifiJoin = Completer<bool>();
  bool found = false, wifiMode = false;
  int persists = 0, wifiScans = 0, joins = 0;
  ProvisioningState provision = ProvisioningState.idle;
  final candidate = CalcAiDevice(
    device: BluetoothDevice.fromId(mac),
    rssi: -40,
    advertisementName: 'Synthetic public V2 fixture',
  );
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
  Future<bool?> isDevicePaired() async => false;
  @override
  Future<Map<String, dynamic>?> sendPairingCommand(
    Map<String, dynamic> command,
  ) async {
    commands.add(command);
    events.add('ble:${command['cmd']}');
    switch (command['cmd']) {
      case 'capabilities':
        return capabilities;
      case 'pairapprove':
        expectSync(command, {
          'cmd': 'pairapprove',
          ...vector['offer'] as Map<String, dynamic>,
          'code': '123456',
        });
        return {
          'ok': true,
          'cmd': 'pairapprove',
          ...vector['approval'] as Map<String, dynamic>,
        };
      case 'paircomplete':
        expectSync(command['completion'], vector['completion']);
        await completionAck.future;
        events.add('ble:completion-ack');
        return {
          'ok': true,
          'cmd': 'paircomplete',
          'protocol': 2,
          'mac': mac,
          'challengeId': (vector['offer'] as Map)['challengeId'],
          'ownershipId': (vector['completion'] as Map)['ownershipId'],
        };
      default:
        throw StateError('Unexpected synthetic command $command');
    }
  }

  @override
  Future<void> setPersistMac(String? value) async {
    expectSync(value, mac);
    expectSync(events, contains('ble:completion-ack'));
    persists++;
    events.add('persist:mac');
  }

  @override
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
    if (enabled) expectSync(events, contains('auth:owned'));
    wifiMode = enabled;
    events.add('wifi:mode:$enabled');
    return true;
  }

  @override
  Future<void> requestWifiScan() async {
    expectSync(wifiMode, isTrue);
    wifiScans++;
    notifyListeners();
  }

  @override
  List<WifiNetwork> get wifiNetworks => wifiScans == 0
      ? []
      : const [
          WifiNetwork(ssid: 'Synthetic Wi-Fi', rssi: -45, isSecured: true),
        ];
  @override
  ProvisioningState get provisioningState => provision;
  @override
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    expectSync(ssid, 'Synthetic Wi-Fi');
    expectSync(password, 'synthetic-password');
    expectSync(events, contains('auth:owned'));
    joins++;
    provision = ProvisioningState.waitingForConnection;
    notifyListeners();
    final joined = await wifiJoin.future;
    provision = joined ? ProvisioningState.success : ProvisioningState.failed;
    events.add('wifi:join:$joined');
    notifyListeners();
    return joined;
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  Map<String, Object?> proof,
) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      await File(
        '$dir/$name.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(proof));
    } finally {
      image.dispose();
    }
  });
}

Future<void> main() async {
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  final vector =
      jsonDecode(
            File('test/fixtures/pairing-v2-contract.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final contract in _Contract.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('synthetic ${contract.name} actual public setup text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final enabled = contract == _Contract.proposedEnabledV2;
        final events = <String>[];
        final requests = <http.Request>[];
        final auth = _Auth(events);
        await auth.init();
        final ble = _Ble(vector, events);
        final cloud = CloudService(
          client: MockClient((r) async {
            requests.add(r);
            events.add('http:${r.url.path}');
            expectSync(r.method, 'POST');
            expectSync(r.headers['Authorization'], 'Bearer test-token');
            if (r.url.path == '/ai/pair/challenge') {
              expectSync(jsonDecode(r.body), {'mac': mac});
              if (!enabled) {
                return http.Response(
                  '{"ok":false,"error":"pairing_v2_disabled"}',
                  404,
                );
              }
              return http.Response(
                jsonEncode({
                  'ok': true,
                  ...vector['offer'] as Map<String, dynamic>,
                }),
                200,
              );
            }
            expectSync(enabled, isTrue);
            expectSync(r.url.path, '/ai/pair/claim');
            expectSync(jsonDecode(r.body), vector['approval']);
            return http.Response(
              jsonEncode({
                'ok': true,
                'protocol': 2,
                'mac': mac,
                'completion': vector['completion'],
              }),
              200,
            );
          }),
        );
        addTearDown(auth.dispose);
        addTearDown(ble.dispose);
        addTearDown(cloud.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              ChangeNotifierProvider<BleService>.value(value: ble),
              ChangeNotifierProvider<CloudService>.value(value: cloud),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: AppTheme.darkTheme.copyWith(
                  platform: TargetPlatform.iOS,
                ),
                debugShowCheckedModeBanner: false,
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
        final name =
            'contract-${enabled ? 'enabled-v2' : 'off-404'}-${scale == 1 ? 'normal' : 'large'}';
        try {
          expect(auth.primaryMac, isNull);
          await tester.ensureVisible(find.text('Scan'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Scan'));
          await tester.pumpAndSettle();
          expect(find.byType(PairDeviceScreen), findsOneWidget);
          tester.view.viewInsets = const FakeViewPadding(bottom: 216);
          await tester.enterText(find.byType(TextField), '123456');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          expect(ble.pairingApprovalVersion, 2);
          expect(
            await ble.submitPairingCode('123456', 'test@example.com'),
            contains('requires secure pairing'),
          );
          expect(auth.adds, 0);
          expect(ble.persists, 0);
          expect(ble.wifiScans, 0);
          expect(find.byType(WifiSetupScreen), findsNothing);
          expect(find.byType(SuccessScreen), findsNothing);
          if (!enabled) {
            await tester.pumpAndSettle();
            expect(requests.map((r) => r.url.path), ['/ai/pair/challenge']);
            expect(ble.commands.map((c) => c['cmd']), ['capabilities']);
            const message =
                'Secure pairing is not available for this calculator yet. Contact CalcAI support.';
            await tester.ensureVisible(find.text(message));
            await tester.pumpAndSettle();
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(message),
            );
            final rect = tester.getRect(find.text(message));
            final viewport = tester.getRect(find.byType(SingleChildScrollView));
            expect(paragraph.textScaler.scale(13), closeTo(13 * scale, 0.01));
            expect(
              paragraph.size.height + 0.01,
              greaterThanOrEqualTo(
                paragraph.getMaxIntrinsicHeight(paragraph.size.width),
              ),
            );
            expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.1));
            expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
            expect(
              tester.getSemantics(find.text(message)).getSemanticsData().label,
              contains(message),
            );
            expect(
              tester
                  .widget<ElevatedButton>(find.byType(ElevatedButton))
                  .onPressed,
              isNull,
            );
            await _capture(tester, boundary, '$name-guidance', {
              'contract': contract.name,
              'synthetic': true,
              'httpStatus': 404,
              'error': 'pairing_v2_disabled',
              'v2Pinned': ble.pairingApprovalVersion,
              'claimRequests': 0,
              'localOwnershipWrites': auth.adds,
              'textScale': scale,
              'height': paragraph.size.height,
              'intrinsicHeight': paragraph.getMaxIntrinsicHeight(
                paragraph.size.width,
              ),
              'textRect': [rect.top, rect.bottom],
              'viewport': [viewport.top, viewport.bottom],
              'events': events,
            });
            await tester.ensureVisible(find.text('Pair'));
            await tester.pumpAndSettle();
            expect(find.text('Pair').hitTestable(), findsOneWidget);
          } else {
            expect(requests.map((r) => r.url.path), [
              '/ai/pair/challenge',
              '/ai/pair/claim',
            ]);
            expect(ble.commands.map((c) => c['cmd']), [
              'capabilities',
              'pairapprove',
              'paircomplete',
            ]);
            expect(events, isNot(contains('ble:completion-ack')));
            ble.completionAck.complete();
            await tester.pumpAndSettle();
            expect(auth.adds, 1);
            expect(auth.primaryMac, mac);
            expect(ble.persists, 1);
            expect(find.byType(WifiSetupScreen), findsOneWidget);
            expect(find.text('Device paired'), findsNothing);
            tester.testTextInput.hide();
            FocusManager.instance.primaryFocus?.unfocus();
            tester.view.viewInsets = const FakeViewPadding();
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Synthetic Wi-Fi'));
            await tester.tap(find.text('Synthetic Wi-Fi'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField),
              'synthetic-password',
            );
            tester.view.viewInsets = const FakeViewPadding(bottom: 216);
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Connect'));
            await tester.pumpAndSettle();
            expect(find.text('Connect').hitTestable(), findsOneWidget);
            final label = tester.renderObject<RenderParagraph>(
              find.text('Connect'),
            );
            expect(label.textScaler.scale(14), closeTo(14 * scale, 0.01));
            expect(
              label.size.height + 0.01,
              greaterThanOrEqualTo(
                label.getMaxIntrinsicHeight(label.size.width),
              ),
            );
            await _capture(tester, boundary, '$name-wifi', {
              'contract': contract.name,
              'synthetic': true,
              'protocol': 2,
              'completionAcknowledged': true,
              'localOwnershipWrites': auth.adds,
              'wifiJoins': ble.joins,
              'honestCompletion': false,
              'textScale': scale,
              'connectHeight': label.size.height,
              'connectIntrinsicHeight': label.getMaxIntrinsicHeight(
                label.size.width,
              ),
              'events': events,
            });
            await tester.tap(find.text('Connect'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(ble.joins, 1);
            expect(find.byType(SuccessScreen), findsNothing);
            expect(find.text('Device paired'), findsNothing);
            ble.wifiJoin.complete(true);
            tester.testTextInput.hide();
            tester.view.viewInsets = const FakeViewPadding();
            await tester.pumpAndSettle();
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
            expect(find.byType(SuccessScreen), findsOneWidget);
            expect(find.text('Device paired'), findsOneWidget);
            expect(ble.wifiMode, isFalse);
            expect(requests.length, 2);
            expect(auth.adds, 1);
            await tester.ensureVisible(find.text('Device paired'));
            await tester.pumpAndSettle();
            final title = tester.renderObject<RenderParagraph>(
              find.text('Device paired'),
            );
            final deviceWordBoxes = title
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 6),
                )
                .length;
            await _capture(tester, boundary, '$name-complete', {
              'contract': contract.name,
              'synthetic': true,
              'protocol': 2,
              'challengeRequests': 1,
              'claimRequests': 1,
              'localOwnershipWrites': auth.adds,
              'wifiJoins': ble.joins,
              'honestCompletion': true,
              'deviceWordLineBoxes': deviceWordBoxes,
              'titleTextScale': title.textScaler.scale(44) / 44,
              'events': events,
            });
            expect(
              deviceWordBoxes,
              1,
              reason: 'Device must occupy one line at the requested text size',
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
