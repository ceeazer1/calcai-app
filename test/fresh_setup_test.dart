import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/app.dart';
import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/wifi_network.dart';
import 'package:calcai_app/screens/auth_screen.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/services/local_bench_profile.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_wifi_reply_test.dart' show ReplyCharacteristic, jsonBytes;
import 'pairing_v2_test.dart' show PairBle, mac, offerData, completionData;

const _storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _network = 'Fixture Wi-Fi';

class _SetupBle extends PairBle {
  _SetupBle() {
    connected = false;
  }

  final _candidate = CalcAiDevice(
    device: BluetoothDevice.fromId('ca1ca1000001'),
    rssi: -45,
    advertisementName: 'CalcAI fixture',
  );
  bool _found = false;
  bool wifiMode = false;
  int wifiScans = 0;
  ProvisioningState _provisioning = ProvisioningState.idle;
  final attempts = <({String ssid, String password})>[];
  Completer<bool>? _join;

  @override
  List<CalcAiDevice> get devices => _found ? [_candidate] : [];
  @override
  ProvisioningState get provisioningState => _provisioning;
  @override
  List<WifiNetwork> get wifiNetworks => wifiScans < 2
      ? const []
      : const [WifiNetwork(ssid: _network, rssi: -45, isSecured: true)];

  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _found = true;
    notifyListeners();
  }

  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    expectSync(device, same(_candidate));
    connected = true;
    notifyListeners();
  }

  @override
  Future<bool?> isDevicePaired() async => false;
  @override
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
    wifiMode = enabled;
    return true;
  }

  @override
  Future<void> requestWifiScan() async {
    expectSync(wifiMode, isTrue);
    wifiScans++;
    _provisioning = ProvisioningState.idle;
    notifyListeners();
  }

  @override
  String? get error => _provisioning == ProvisioningState.failed
      ? 'Fixture Wi-Fi connection failed'
      : null;

  @override
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    attempts.add((ssid: ssid, password: password));
    _join = Completer<bool>();
    _provisioning = ProvisioningState.waitingForConnection;
    notifyListeners();
    final joined = await _join!.future;
    _provisioning = joined
        ? ProvisioningState.success
        : ProvisioningState.failed;
    notifyListeners();
    return joined;
  }

  void finishJoin(bool joined) => _join!.complete(joined);
}

class _Board {
  bool paired = true;
  int releaseNonces = 0;
  final reads = <bool>[];
  String? releaseNonce;
}

class _RecoveryBle extends _SetupBle {
  _RecoveryBle(this.board) {
    characteristic.reply = (command, _) async => jsonBytes(switch (command) {
      'pairinfo' => {'cmd': command, 'mac': mac, 'paired': board.paired},
      'authnonce' || 'relnonce' => {
        'cmd': command,
        'mac': mac,
        'nonce': command == 'authnonce'
            ? 'a' * 32
            : board.releaseNonce =
                  (++board.releaseNonces == 1 ? 'b' : 'c') * 32,
      },
      'release' => {
        'cmd': command,
        'ok': characteristic.releaseNonces.last == board.releaseNonce,
      },
      _ => throw StateError('Unexpected recovery command: $command'),
    });
  }

  final _Board board;
  final characteristic = _RecoveryCharacteristic();
  @override
  BluetoothCharacteristic get commandCharacteristic => characteristic;

  @override
  Future<bool?> isDevicePaired() async {
    await characteristic.write(jsonBytes({'cmd': 'pairinfo'}));
    final reply = jsonDecode(utf8.decode(await characteristic.read())) as Map;
    final paired = reply['paired'] as bool;
    board.reads.add(paired);
    return paired;
  }

  @override
  Future<void> disconnect() async {
    board.releaseNonce = null;
    await super.disconnect();
  }

  @override
  Future<bool> releaseOwnership(String nonce, String response) async {
    final released = await super.releaseOwnership(nonce, response);
    if (released) board.paired = false;
    return released;
  }

  @override
  Future<Map<String, dynamic>?> sendPairingCommand(
    Map<String, dynamic> command,
  ) async {
    final reply = await super.sendPairingCommand(command);
    if (command['cmd'] == 'paircomplete' && reply?['ok'] == true) {
      board.paired = true;
    }
    return reply;
  }
}

class _RecoveryCharacteristic extends ReplyCharacteristic {
  final releaseNonces = <String>[];
  final releaseSignatures = <String>[];

  @override
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    final payload = jsonDecode(utf8.decode(value)) as Map;
    if (payload['cmd'] == 'release') {
      releaseNonces.add(payload['nonce'] as String);
      releaseSignatures.add(payload['response'] as String);
    }
    await super.write(
      value,
      withoutResponse: withoutResponse,
      allowLongWrite: allowLongWrite,
      timeout: timeout,
    );
  }
}

class _SetupBackend {
  int signIns = 0;
  int lookups = 0;
  bool aiChoiceReviewed = false;
  bool ownsBoard = false;
  final releaseRequests = <String>[];
  Completer<http.Response>? heldRelease;
  final pairRequests = <String>[];
  final login = Completer<http.Response>();

  AuthService auth() {
    final service = AuthService(
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/ai/auth/login':
            signIns++;
            expectSync(jsonDecode(request.body), {
              'email': 'fixture@example.com',
              'password': 'fixture-login-password',
            });
            return login.future;
          case '/ai/user/devices':
            lookups++;
            return _reply({
              'ok': true,
              'devices': [
                if (ownsBoard) {'mac': mac},
              ],
            });
        }
        throw StateError('Unexpected auth request to ${request.url.path}');
      }),
    );
    addTearDown(service.dispose);
    return service;
  }

  CloudService cloud(AuthService auth) {
    final service = CloudService(
      auth: auth,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/ai/pair/hello':
            pairRequests.add(request.url.path);
            return http.Response(
              '{"ok":false,"error":"device_not_owned"}',
              403,
            );
          case '/ai/pair/release':
            pairRequests.add(request.url.path);
            expectSync(ownsBoard, isFalse);
            expectSync(
              request.headers['Authorization'],
              'Bearer fixture-session',
            );
            final payload = jsonDecode(request.body) as Map;
            expectSync(payload['mac'], mac);
            releaseRequests.add(payload['nonce'] as String);
            final held = heldRelease;
            heldRelease = null;
            if (held != null) return held.future;
            return _reply({'ok': true, 'response': 'e' * 64});
          case '/ai/context/get':
            if (!ownsBoard) {
              return http.Response(
                '{"ok":false,"error":"device_not_owned"}',
                403,
              );
            }
            return _reply({
              'ok': true,
              'context': '',
              'rev': 0,
              'etag': '"fixture-0"',
            });
          case '/ai/pair/challenge':
            pairRequests.add(request.url.path);
            expectSync(jsonDecode(request.body), {'mac': mac});
            return _reply(offerData());
          case '/ai/pair/claim':
            pairRequests.add(request.url.path);
            expectSync((jsonDecode(request.body) as Map)['protocol'], 2);
            ownsBoard = true;
            return _reply(completionData());
          case '/ai/user/ai-consent':
            if (request.method == 'PUT') {
              expectSync(jsonDecode(request.body), {
                'version': CloudService.aiConsentVersion,
                'allowed': false,
              });
              aiChoiceReviewed = true;
            }
            return _reply({
              'ok': true,
              'version': CloudService.aiConsentVersion,
              'reviewed': aiChoiceReviewed,
              'allowed': false,
            });
          case '/ai/notes/raw':
            return _reply({
              'ok': true,
              'text': '',
              'rev': 0,
              'etag': '"fixture-notes-0"',
            });
          case '/ai/logs/recent':
            return _reply({'ok': true, 'items': []});
        }
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );
    addTearDown(service.dispose);
    return service;
  }

  void finishLogin() => login.complete(
    _reply({
      'ok': true,
      'token': 'fixture-session',
      'email': 'fixture@example.com',
    }),
  );
}

http.Response _reply(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200);

Future<void> _show(
  WidgetTester tester,
  AuthService auth,
  CloudService cloud,
  _SetupBle ble,
) async {
  addTearDown(ble.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
        ChangeNotifierProvider<BleService>.value(value: ble),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: const AppGate()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _signInAndPair(
  WidgetTester tester,
  _SetupBackend backend,
  AuthService auth,
  _SetupBle ble,
) async {
  await _show(tester, auth, backend.cloud(auth), ble);
  expect(find.byType(AuthScreen), findsOneWidget);
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'fixture@example.com');
  await tester.enterText(fields.at(1), 'fixture-login-password');
  final login = find.text('Login').hitTestable();
  await tester.ensureVisible(login);
  final loginPoint = tester.getCenter(login);
  await tester.tapAt(loginPoint);
  await tester.tapAt(loginPoint);
  await tester.pump();
  expect(backend.signIns, 1);
  backend.finishLogin();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));

  expect(find.byType(LinkDeviceScreen), findsOneWidget);
  expect(backend.lookups, 1);
  expect(auth.primaryMac, isNull);
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
  expect(find.text('Enter code'), findsOneWidget);
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pumpAndSettle();
  expect(find.byType(WifiSetupScreen), findsOneWidget);
  expect(backend.pairRequests, ['/ai/pair/challenge', '/ai/pair/claim']);
  expect(ble.commands.map((command) => command['cmd']), [
    'capabilities',
    'pairapprove',
    'paircomplete',
  ]);
  expect(auth.primaryMac, mac);
}

void main() {
  late Map<String, String> secure;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_storage, (call) async {
      final arguments = call.arguments as Map;
      final key = arguments['key'] as String;
      switch (call.method) {
        case 'read':
          return secure[key];
        case 'write':
          secure[key] = arguments['value'] as String;
          return null;
        case 'delete':
          secure.remove(key);
          return null;
        default:
          throw UnsupportedError(call.method);
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_storage, null));
  });

  testWidgets(
    'fresh email sign-in and V2 setup can retry Wi-Fi and relaunch',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(428, 926);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final backend = _SetupBackend();
      final auth = backend.auth();
      final ble = _SetupBle();
      await _signInAndPair(tester, backend, auth, ble);

      expect(find.text('No networks found'), findsOneWidget);
      await tester.tap(find.text('Scan Again'));
      await tester.pumpAndSettle();
      expect(ble.wifiScans, 2);
      final network = find.text(_network);
      await tester.tap(network);
      await tester.pumpAndSettle();
      final password = find.byType(TextField);
      await tester.enterText(password, 'canceled-password');
      await tester.tap(network);
      await tester.pumpAndSettle();
      expect(password, findsNothing);
      expect(ble.attempts, isEmpty);

      await tester.tap(network);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      await tester.enterText(password, 'fixture-wrong-password');
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).obscureText, isTrue);

      final connect = find.text('Connect');
      await tester.ensureVisible(connect);
      final connectPoint = tester.getCenter(connect);
      await tester.tapAt(connectPoint);
      await tester.tapAt(connectPoint);
      await tester.pump();
      expect(find.text('Connecting to $_network'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(WifiSetupScreen), findsOneWidget);
      expect(ble.wifiMode, isTrue);
      expect(ble.attempts, [
        (ssid: _network, password: 'fixture-wrong-password'),
      ]);
      ble.finishJoin(false);
      await tester.pumpAndSettle();
      expect(find.text('Fixture Wi-Fi connection failed'), findsOneWidget);
      expect(find.text('Device paired'), findsNothing);
      expect(ble.wifiMode, isTrue);

      await tester.enterText(password, 'fixture-correct-password');
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pump();
      ble.finishJoin(true);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('Device paired'), findsOneWidget);
      expect(ble.wifiMode, isFalse);
      expect(ble.attempts, [
        (ssid: _network, password: 'fixture-wrong-password'),
        (ssid: _network, password: 'fixture-correct-password'),
      ]);
      await tester.tap(find.text('Home page').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.byType(MainShell), findsOneWidget);
      await tester.ensureVisible(find.text('Continue with AI off'));
      await tester.pumpAndSettle();
      final aiOff = find.widgetWithText(OutlinedButton, 'Continue with AI off');
      expect(tester.widget<OutlinedButton>(aiOff).onPressed, isNotNull);
      await tester.tap(aiOff.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep AI off'));
      await tester.pumpAndSettle();
      expect(backend.aiChoiceReviewed, isTrue);
      await tester.tap(find.text('Notes').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('0/5'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(ble.connected, isFalse);

      await tester.pumpWidget(const SizedBox());
      final restoredAuth = backend.auth();
      final restoredBle = _SetupBle();
      await _show(
        tester,
        restoredAuth,
        backend.cloud(restoredAuth),
        restoredBle,
      );
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(restoredAuth.primaryMac, mac);
      expect(restoredAuth.deviceMacs, [mac]);
      expect(backend.signIns, 1);
      expect(backend.lookups, 1);
      expect(backend.pairRequests, ['/ai/pair/challenge', '/ai/pair/claim']);
      expect(restoredBle.wifiScans, 0);
      expect(restoredBle.attempts, isEmpty);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'signed release is resumable across app relaunch with the same account',
    (tester) async {
      secure['${LocalBenchProfile.storagePrefix}auth_token'] =
          'fixture-session';
      final prefs = await AppPreferences.getInstance();
      await prefs.setString('email', 'fixture@example.com');
      await prefs.setBool('session_valid', true);
      await prefs.setString('device_macs', jsonEncode([mac]));
      await prefs.setString('primary_mac', mac);
      await prefs.setString('unrelated_fixture_pref', 'preserved');

      final backend = _SetupBackend()
        ..ownsBoard = true
        ..aiChoiceReviewed = true;
      final board = _Board();
      final auth = backend.auth();
      final ble = _RecoveryBle(board);
      await _show(tester, auth, backend.cloud(auth), ble);
      expect(find.byType(MainShell), findsOneWidget);
      expect(auth.primaryMac, mac);

      // A device-scoped read confirms cloud unpair and persists local absence.
      backend.ownsBoard = false;
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refresh.onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Calculator unpaired'), findsOneWidget);
      expect(auth.primaryMac, isNull);
      expect(auth.deviceMacs, isEmpty);
      expect(auth.token, 'fixture-session');
      expect(prefs.getString('primary_mac'), isNull);
      expect(prefs.getString('device_macs'), '[]');
      expect(prefs.getBool('session_valid'), isTrue);
      expect(ble.characteristic.commands, isEmpty);

      Future<void> scan(Finder button) async {
        await tester.tap(button);
        await tester.pump();
        for (var command = 0; command < 3; command++) {
          await tester.pump(const Duration(milliseconds: 260));
        }
      }

      final heldRelease = backend.heldRelease = Completer<http.Response>();
      await scan(find.text('Re-pair'));
      expect(backend.releaseRequests, ['b' * 32]);
      await ble.disconnect();
      // A replacement link must not receive the old connection's release.
      ble.connected = true;
      heldRelease.complete(_reply({'ok': true, 'response': 'e' * 64}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(ble.characteristic.commands, [
        'pairinfo',
        'authnonce',
        'relnonce',
      ]);
      expect(ble.characteristic.releaseNonces, isEmpty);
      expect(board.paired, isTrue);
      expect(find.text('Enter code'), findsNothing);

      await scan(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(backend.releaseRequests, ['b' * 32, 'c' * 32]);
      expect(ble.characteristic.releaseNonces, ['c' * 32]);
      expect(ble.characteristic.releaseSignatures, ['e' * 64]);
      expect(find.text('Enter code'), findsOneWidget);
      expect(board.paired, isFalse);
      expect(board.reads, [true, true]);

      // Leave before submitting a code. Relaunch with fresh service instances.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave setup'));
      await tester.pumpAndSettle();
      expect(ble.connected, isFalse);
      expect(board.paired, isFalse);
      await tester.pumpWidget(const SizedBox());
      final restoredAuth = backend.auth();
      final restoredBle = _RecoveryBle(board);
      await _show(
        tester,
        restoredAuth,
        backend.cloud(restoredAuth),
        restoredBle,
      );
      expect(find.byType(LinkDeviceScreen), findsOneWidget);
      expect(restoredAuth.token, 'fixture-session');
      expect(restoredAuth.primaryMac, isNull);
      expect(restoredAuth.deviceListVerified, isTrue);
      expect(prefs.getString('unrelated_fixture_pref'), 'preserved');

      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Enter code'), findsOneWidget);
      expect(board.reads, [true, true, false]);
      expect(restoredBle.characteristic.commands, ['pairinfo']);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      expect(find.byType(WifiSetupScreen), findsOneWidget);
      expect(restoredAuth.primaryMac, mac);
      expect(board.paired, isTrue);
      expect(backend.ownsBoard, isTrue);
      expect(backend.pairRequests, [
        '/ai/pair/hello',
        '/ai/pair/release',
        '/ai/pair/hello',
        '/ai/pair/release',
        '/ai/pair/challenge',
        '/ai/pair/claim',
      ]);
      expect(backend.signIns, 0);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Back from first-time Wi-Fi setup keeps the claim and opens Home',
    (tester) async {
      final backend = _SetupBackend();
      final auth = backend.auth();
      final ble = _SetupBle();
      await _signInAndPair(tester, backend, auth, ble);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(WifiSetupScreen), findsNothing);
      expect(auth.primaryMac, mac);
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(ble.attempts, isEmpty);
      expect(ble.wifiMode, isFalse);
      expect(ble.connected, isFalse);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
