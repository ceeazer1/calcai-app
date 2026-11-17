import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

// Local fixtures only. All operational BLE calls use in-memory overrides.
const _rawFailure = 'fixture-private-error-not-for-display';
const _savedSsid = 'Fixture retained network';
const _mac = 'ca1ca1000001';

enum _ScanResult { empty, pending, nativeFailure, thrownFailure, candidate }

class _ProofCloud extends FakeCloudService {
  int proofCalls = 0;
  final nonces = <String>[];
  Future<String?> Function(int call)? reply;

  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) {
    nonces.add(nonce);
    final call = ++proofCalls;
    return reply?.call(call) ?? Future.value('fixture-proof');
  }
}

class _Ble extends BleService {
  _Ble({bool startReady = false}) {
    if (startReady) {
      state = DeviceConnectionState.ready;
      currentDevice = fixtureDevice;
    }
  }

  final fixtureDevice = CalcAiDevice(
    device: BluetoothDevice.fromId('fixture-peripheral'),
    rssi: -40,
    advertisementName: 'CALCAI-FIXTURE',
  );
  final candidates = <CalcAiDevice>[];
  final pendingScan = Completer<void>();
  final proofs = <String>[];
  _ScanResult scanResult = _ScanResult.empty;
  DeviceConnectionState state = DeviceConnectionState.disconnected;
  CalcAiDevice? currentDevice;
  String? owner;
  String? failure;
  bool permissions = true, adapterOn = true, scanning = false, alive = true;
  bool connectSucceeds = true, knownReconnect = false;
  bool knownReconnectStartsReady = true, stopScanThrows = false;
  bool stopCompletesPendingScan = true;
  bool scanCompleted = false;
  int generation = 1;
  int scans = 0, scanStops = 0, connects = 0, reconnects = 0;
  int nonceCalls = 0, helloCalls = 0, disconnects = 0, wifiModeCalls = 0;
  int claimCalls = 0;
  Completer<bool>? knownReconnectReply;
  Completer<void>? stopScanReply;
  Future<({String mac, String nonce})?> Function()? nonceReply;
  Future<bool> Function()? helloReply;

  @override
  int get connectionGeneration => generation;
  @override
  DeviceConnectionState get connectionState => state;
  @override
  CalcAiDevice? get connectedDevice => currentDevice;
  @override
  String? get pairedOwner => owner;
  @override
  String? get error => failure;
  @override
  bool get isScanning => scanning;
  @override
  List<CalcAiDevice> get devices => List.unmodifiable(candidates);
  @override
  List<String> get savedNetworks => const [_savedSsid];
  @override
  String? get deviceMac => _mac;
  @override
  Future<bool> requestPermissions() async => permissions;
  @override
  Future<bool> isBluetoothOn() async => adapterOn;

  @override
  Future<bool> reconnectKnownDevice() async {
    reconnects++;
    if (!knownReconnect) return false;
    state = knownReconnectStartsReady
        ? DeviceConnectionState.ready
        : DeviceConnectionState.connecting;
    if (knownReconnectStartsReady) currentDevice = fixtureDevice;
    notifyListeners();
    if (knownReconnectReply != null) return knownReconnectReply!.future;
    return state.isConnected;
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    scans++;
    failure = null;
    scanCompleted = false;
    scanning = true;
    candidates.clear();
    notifyListeners();
    switch (scanResult) {
      case _ScanResult.pending:
        await pendingScan.future;
        if (!alive) return;
      case _ScanResult.empty:
        break;
      case _ScanResult.nativeFailure:
        // Real BleService catches native errors, completes normally and
        // exposes the error through its getter; it does not rethrow them.
        failure = 'Scan failed: $_rawFailure';
      case _ScanResult.thrownFailure:
        scanning = false;
        throw StateError(_rawFailure);
      case _ScanResult.candidate:
        candidates.add(fixtureDevice);
        notifyListeners();
    }
    scanning = false;
    scanCompleted = true;
    if (alive) notifyListeners();
  }

  @override
  Future<void> stopScan() async {
    scanStops++;
    scanning = false;
    if (stopScanReply != null) await stopScanReply!.future;
    if (stopCompletesPendingScan && !pendingScan.isCompleted) {
      pendingScan.complete();
    }
    if (stopScanThrows) throw StateError(_rawFailure);
  }

  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    connects++;
    currentDevice = device;
    state = DeviceConnectionState.connecting;
    notifyListeners();
    await Future<void>.value();
    if (!alive) return;
    state = connectSucceeds
        ? DeviceConnectionState.ready
        : DeviceConnectionState.error;
    if (!connectSucceeds) failure = 'Connection failed: $_rawFailure';
    notifyListeners();
  }

  @override
  Future<({String mac, String nonce})?> requestAuthNonce() async {
    nonceCalls++;
    if (nonceReply != null) return nonceReply!();
    return (mac: _mac, nonce: 'fixture-nonce');
  }

  @override
  Future<bool> proveOwnership(
    String nonce,
    String response,
    String account,
  ) async {
    helloCalls++;
    proofs.add(response);
    final started = generation;
    final accepted = await (helloReply?.call() ?? Future.value(true));
    if (alive && generation == started && accepted) {
      owner = account;
      notifyListeners();
    }
    return accepted;
  }

  @override
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
    if (enabled) wifiModeCalls++;
    if (alive) notifyListeners();
    return true;
  }

  @override
  Future<void> endWifiUiMode() async {}

  @override
  Future<void> disconnect() async {
    disconnects++;
    generation++;
    state = DeviceConnectionState.disconnected;
    currentDevice = null;
    owner = null;
    if (alive) notifyListeners();
  }

  @override
  Future<String?> submitPairingCode(String code, String account) async {
    claimCalls++;
    throw StateError('A failed retained-owner proof must not claim a device.');
  }

  void replaceReadyConnection() {
    generation++;
    state = DeviceConnectionState.ready;
    currentDevice = fixtureDevice;
    owner = null;
    notifyListeners();
  }

  void dropConnection() {
    generation++;
    state = DeviceConnectionState.disconnected;
    currentDevice = null;
    owner = null;
    notifyListeners();
  }

  void pulse() => notifyListeners();

  @override
  void dispose() {
    alive = false;
    if (!pendingScan.isCompleted) pendingScan.complete();
    if (stopScanReply case final reply? when !reply.isCompleted) {
      reply.complete();
    }
    if (knownReconnectReply case final reply? when !reply.isCompleted) {
      reply.complete(false);
    }
    super.dispose();
  }
}

class _Fixture {
  _Fixture(this.ble, this.cloud);
  final _Ble ble;
  final _ProofCloud cloud;
  final auth = FakeAuthService();
  final boundary = GlobalKey();
  bool _closed = false;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(800, 1000),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Baseline assertions are expected to fail. Always remove the route and
    // cancel its discovery timer even when a test exits before explicit close.
    addTearDown(() => close(tester));
    await auth.init();
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
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const WifiScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void expectNoAuthorizedContent(WidgetTester tester) {
    expect(find.text('Saved Networks'), findsNothing);
    expect(find.text(_savedSsid), findsNothing);
    expect(find.text('Add network manually'), findsNothing);
    expect(find.textContaining(_rawFailure), findsNothing);
    expect(find.textContaining('belongs to another account'), findsNothing);
    expect(ble.owner, isNull);
    expect(ble.wifiModeCalls, 0);
    expect(ble.claimCalls, 0);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.deviceMacs, [_mac]);
  }

  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    ble.dispose();
    cloud.dispose();
    auth.dispose();
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['CALCAI_WIFI_FAILURE_PREVIEW_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/$name.png').writeAsBytes(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'completed empty discovery is a missing candidate, not a scan error',
    (tester) async {
      final fixture = _Fixture(_Ble(), _ProofCloud());
      await fixture.open(tester);
      expect(fixture.ble.scanCompleted, isTrue);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Calc not found'), findsOneWidget);
      expect(find.text('Could not search for calculator'), findsNothing);
      expect(fixture.ble.scans, 1);
      expect(fixture.ble.nonceCalls, 0);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'a still-pending scan deadline is not reported as empty discovery',
    (tester) async {
      final fixture = _Fixture(
        _Ble()..scanResult = _ScanResult.pending,
        _ProofCloud(),
      );
      await fixture.open(tester);
      await tester.pump(const Duration(milliseconds: 11900));
      expect(find.text('Searching…'), findsOneWidget);
      expect(fixture.ble.scanCompleted, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Could not search for calculator'), findsOneWidget);
      expect(find.text('Calc not found'), findsNothing);
      expect(fixture.ble.scanStops, greaterThanOrEqualTo(1));
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
    },
  );

  for (final outcome in [
    _ScanResult.nativeFailure,
    _ScanResult.thrownFailure,
  ]) {
    testWidgets('scan failure $outcome has accurate safe recovery copy', (
      tester,
    ) async {
      final fixture = _Fixture(_Ble()..scanResult = outcome, _ProofCloud());
      await fixture.open(tester);
      expect(find.text('Could not search for calculator'), findsOneWidget);
      expect(find.text('Calc not found'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(fixture.ble.nonceCalls, 0);
      fixture.expectNoAuthorizedContent(tester);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  testWidgets(
    'native scan cleanup failure cannot replace the original recovery state',
    (tester) async {
      final ble = _Ble()
        ..scanResult = _ScanResult.nativeFailure
        ..stopScanThrows = true;
      final fixture = _Fixture(ble, _ProofCloud());
      await fixture.open(tester);
      expect(find.text('Could not search for calculator'), findsOneWidget);
      expect(ble.scanStops, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a discovered device connection failure is not missing discovery',
    (tester) async {
      final fixture = _Fixture(
        _Ble()
          ..scanResult = _ScanResult.candidate
          ..connectSucceeds = false,
        _ProofCloud(),
      );
      await fixture.open(tester);
      expect(fixture.ble.connects, 1);
      expect(find.text('Could not connect to calculator'), findsOneWidget);
      expect(find.text('Calc not found'), findsNothing);
      expect(fixture.ble.nonceCalls, 0);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'retry waits for both old scan and delayed native cleanup before discovery',
    (tester) async {
      final cleanup = Completer<void>();
      final ble = _Ble()
        ..scanResult = _ScanResult.pending
        ..stopScanReply = cleanup
        ..stopCompletesPendingScan = false;
      final fixture = _Fixture(ble, _ProofCloud());
      await fixture.open(tester);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Could not search for calculator'), findsOneWidget);
      expect(ble.scanStops, 1);
      expect(ble.scans, 1);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      // A late native notification must not be consumed by the retry while
      // either the old subscription or its cleanup is still unresolved.
      ble.candidates.add(ble.fixtureDevice);
      ble.pulse();
      await tester.pump();
      expect(ble.scans, 1);
      expect(ble.connects, 0);
      expect(ble.nonceCalls, 0);
      cleanup.complete();
      await tester.pump();
      ble.pulse();
      await tester.pump();
      expect(
        ble.scans,
        1,
        reason: 'The old startScan Future still owns the run.',
      );
      expect(ble.connects, 0);
      ble.scanResult = _ScanResult.empty;
      ble.pendingScan.complete();
      await tester.pump();
      await tester.pump();
      expect(ble.scans, 2);
      expect(ble.candidates, isEmpty);
      expect(ble.connects, 0);
      expect(fixture.cloud.proofCalls, 0);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Calc not found'), findsOneWidget);
      fixture.expectNoAuthorizedContent(tester);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  for (final adapterOff in [false, true]) {
    testWidgets('Bluetooth gate failure adapterOff=$adapterOff is actionable', (
      tester,
    ) async {
      final ble = _Ble()
        ..permissions = adapterOff
        ..adapterOn = !adapterOff;
      final fixture = _Fixture(ble, _ProofCloud());
      await fixture.open(tester);
      expect(find.text('Bluetooth disconnected'), findsOneWidget);
      expect(find.text('Calc not found'), findsNothing);
      expect(ble.scans, 0);
      expect(ble.reconnects, 0);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
    });
  }

  for (final stage in [
    'cloud-null',
    'cloud-error',
    'nonce-null',
    'nonce-error',
    'hello-false',
    'hello-error',
  ]) {
    testWidgets('$stage cannot expose cached networks or authorize Wi-Fi', (
      tester,
    ) async {
      final ble = _Ble(startReady: true);
      final cloud = _ProofCloud();
      switch (stage) {
        case 'cloud-null':
          cloud.reply = (_) async => null;
        case 'cloud-error':
          cloud.reply = (_) async => throw StateError(_rawFailure);
        case 'nonce-null':
          ble.nonceReply = () async => null;
        case 'nonce-error':
          ble.nonceReply = () async => throw StateError(_rawFailure);
        case 'hello-false':
          ble.helloReply = () async => false;
        case 'hello-error':
          ble.helloReply = () async => throw StateError(_rawFailure);
      }
      final fixture = _Fixture(ble, cloud);
      await fixture.open(tester);
      expect(find.text('Could not verify access'), findsOneWidget);
      expect(find.text('Calc not found'), findsNothing);
      expect(ble.disconnects, 1);
      expect(ble.helloCalls, stage.startsWith('hello') ? 1 : 0);
      fixture.expectNoAuthorizedContent(tester);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  testWidgets('a ready link dropped during nonce verification is interrupted', (
    tester,
  ) async {
    final nonce = Completer<({String mac, String nonce})?>();
    final ble = _Ble(startReady: true)..nonceReply = () => nonce.future;
    final fixture = _Fixture(ble, _ProofCloud());
    await fixture.open(tester);
    expect(find.text('Verifying…'), findsOneWidget);
    ble.dropConnection();
    await tester.pump();
    expect(find.text('Bluetooth connection interrupted'), findsOneWidget);
    expect(find.text('Calc not found'), findsNothing);
    nonce.complete((mac: _mac, nonce: 'stale-nonce'));
    await tester.pump();
    expect(fixture.cloud.proofCalls, 0);
    fixture.expectNoAuthorizedContent(tester);
    await fixture.close(tester);
  });

  testWidgets('skip is explicit cancellation rather than a failed empty scan', (
    tester,
  ) async {
    final fixture = _Fixture(
      _Ble()..scanResult = _ScanResult.pending,
      _ProofCloud(),
    );
    await fixture.open(tester);
    await tester.tap(find.text('skip'));
    await tester.pump();
    expect(find.text('Search stopped'), findsOneWidget);
    expect(find.text('Calc not found'), findsNothing);
    fixture.expectNoAuthorizedContent(tester);
    await fixture.close(tester);
  });

  testWidgets(
    'explicit retry clears a prior access failure and authenticates once',
    (tester) async {
      final ble = _Ble(startReady: true);
      final cloud = _ProofCloud()
        ..reply = (call) async => call == 1 ? null : 'proof';
      final fixture = _Fixture(ble, cloud);
      await fixture.open(tester);
      expect(find.text('Could not verify access'), findsOneWidget);
      fixture.expectNoAuthorizedContent(tester);
      ble.scanResult = _ScanResult.candidate;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not verify access'), findsNothing);
      expect(find.text('Saved Networks'), findsOneWidget);
      expect(find.text(_savedSsid), findsOneWidget);
      expect(cloud.proofCalls, 2);
      expect(ble.wifiModeCalls, 1);
      expect(ble.owner, fixture.auth.email);
      expect(ble.claimCalls, 0);
      await fixture.close(tester);
    },
  );

  testWidgets('stale proof failure cannot overwrite a replacement success', (
    tester,
  ) async {
    final old = Completer<String?>(), current = Completer<String?>();
    final ble = _Ble(startReady: true);
    final cloud = _ProofCloud()
      ..reply = (call) => call == 1 ? old.future : current.future;
    final fixture = _Fixture(ble, cloud);
    await fixture.open(tester);
    expect(find.text(_savedSsid), findsNothing);
    ble.replaceReadyConnection();
    await tester.pump();
    expect(cloud.proofCalls, 2);
    current.complete('current-proof');
    await tester.pump();
    expect(find.text('Saved Networks'), findsOneWidget);
    old.completeError(StateError(_rawFailure));
    await tester.pump();
    expect(find.text('Saved Networks'), findsOneWidget);
    expect(find.text('Could not verify access'), findsNothing);
    expect(ble.owner, fixture.auth.email);
    expect(ble.proofs, ['current-proof']);
    expect(ble.wifiModeCalls, 1);
    expect(ble.disconnects, 0);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets(
    'rejected known reconnect must not silently start fallback scanning',
    (tester) async {
      final reconnect = Completer<bool>();
      final ble = _Ble()
        ..knownReconnect = true
        ..knownReconnectReply = reconnect;
      final cloud = _ProofCloud()..reply = (_) async => null;
      final fixture = _Fixture(ble, cloud);
      await fixture.open(tester);
      expect(cloud.proofCalls, 1);
      expect(ble.disconnects, 1);
      reconnect.complete(false);
      await tester.pump();
      await tester.pump();
      expect(ble.scans, 0);
      expect(find.text('Could not verify access'), findsOneWidget);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'stale candidates are ignored until a fresh discovery phase starts',
    (tester) async {
      final reconnect = Completer<bool>();
      final ble = _Ble()
        ..knownReconnect = true
        ..knownReconnectStartsReady = false
        ..knownReconnectReply = reconnect;
      // A previous scan's device list may survive while native reconnect waits.
      ble.candidates.add(ble.fixtureDevice);
      final fixture = _Fixture(ble, _ProofCloud());
      await fixture.open(tester);
      ble.pulse();
      await tester.pump();
      expect(ble.reconnects, 1);
      expect(ble.scans, 0);
      expect(ble.connects, 0);
      expect(ble.nonceCalls, 0);
      expect(fixture.cloud.proofCalls, 0);
      ble.state = DeviceConnectionState.error;
      ble.failure = 'Connection failed: $_rawFailure';
      ble.pulse();
      reconnect.complete(false);
      await tester.pump();
      await tester.pump();
      expect(ble.scans, 1);
      expect(ble.candidates, isEmpty);
      expect(ble.connects, 0);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Calc not found'), findsOneWidget);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'large access recovery text and retry remain whole and scroll-reachable',
    (tester) async {
      final fixture = _Fixture(
        _Ble(startReady: true),
        _ProofCloud()..reply = (_) async => null,
      );
      await fixture.open(tester, size: const Size(320, 568), scale: 2);
      final heading = tester.renderObject<RenderParagraph>(
        find.text('WiFi Networks'),
      );
      expect(
        heading.didExceedMaxLines,
        isFalse,
        reason: 'The page heading must wrap rather than ellipsize large text.',
      );
      expect(heading.textScaler.scale(10), closeTo(20, 0.001));
      expect(find.text('Could not verify access'), findsOneWidget);
      await tester.ensureVisible(find.text('Could not verify access'));
      await tester.pump(const Duration(milliseconds: 300));
      await fixture.capture(tester, 'access-recovery-large-top');
      final retry = find.text('Try again');
      final scroll = find
          .ancestor(
            of: retry,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView || widget is CustomScrollView,
            ),
          )
          .first;
      expect(scroll, findsOneWidget);
      final texts = find.descendant(of: scroll, matching: find.byType(Text));
      expect(texts.evaluate().length, greaterThanOrEqualTo(3));
      for (final element in texts.evaluate().toList()) {
        final text = find.byElementPredicate(
          (candidate) => identical(candidate, element),
        );
        await tester.ensureVisible(text);
        await tester.pump(const Duration(milliseconds: 300));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          paragraph.size.height + 0.01,
          greaterThanOrEqualTo(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width),
          ),
          reason: 'Recovery text must not clip at the requested text scale.',
        );
        expect(paragraph.textScaler.scale(10), closeTo(20, 0.001));
        expect(
          find.ancestor(of: text, matching: find.byType(FittedBox)),
          findsNothing,
        );
        final rect = tester.getRect(text), viewport = tester.getRect(scroll);
        expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.1));
        expect(rect.right, lessThanOrEqualTo(viewport.right + 0.1));
      }
      await tester.ensureVisible(retry);
      await tester.pump(const Duration(milliseconds: 300));
      expect(retry.hitTestable(), findsOneWidget);
      final label = tester.getRect(retry);
      final button = tester.getRect(
        find.ancestor(of: retry, matching: find.byType(ElevatedButton)).first,
      );
      expect(label.top, greaterThanOrEqualTo(button.top - 0.1));
      expect(label.bottom, lessThanOrEqualTo(button.bottom + 0.1));
      expect(tester.takeException(), isNull);
      fixture.expectNoAuthorizedContent(tester);
      await fixture.capture(tester, 'access-recovery-large-retry');
      await fixture.close(tester);
    },
  );
}
