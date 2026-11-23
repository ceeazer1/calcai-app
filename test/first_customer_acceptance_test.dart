import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calcai_app/app.dart';
import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/auth_screen.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/pair_device_screen.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'pairing_v2_test.dart'
    show PairBle, PairAuth, openPair, mac, offerData, completionData;
import 'support/setup_test_app.dart';

class _EntryAuth extends AuthService {
  int appleCalls = 0, googleCalls = 0, emailCalls = 0;
  @override
  String get error =>
      'Fixture sign-in failed. Check your connection and retry.';
  @override
  Future<String?> signInWithApple() async {
    appleCalls++;
    return null;
  }

  @override
  Future<bool> signInWithGoogle() async {
    googleCalls++;
    return false;
  }

  @override
  Future<EmailAuthOutcome> signInWithEmail(
    String email,
    String password,
  ) async {
    emailCalls++;
    return EmailAuthOutcome.failed;
  }
}

class _AdmissionBle extends SetupTestAppBle {
  _AdmissionBle() : super(delay: Duration.zero);
  bool granted = true, radio = true, discover = false, reject = false;
  int scans = 0, connections = 0;
  @override
  Future<bool> requestPermissions() async => granted;
  @override
  Future<bool> isBluetoothOn() async => radio;
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    scans++;
    if (discover) {
      await super.startScan(timeout: timeout);
    }
  }

  @override
  DeviceConnectionState get connectionState => reject && connections > 0
      ? DeviceConnectionState.error
      : super.connectionState;
  @override
  String? get error =>
      reject ? 'Could not verify this calculator. Scan again.' : null;
  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    connections++;
    if (reject) {
      notifyListeners();
      return;
    }
    await super.connectToDevice(device, timeout: timeout, attempts: attempts);
  }
}

class _OtherOwnerBle extends SetupTestAppBle {
  _OtherOwnerBle() : super(delay: Duration.zero, paired: true);
  int releases = 0;
  // This high-level fixture models a genuine but still-owned calculator.
  // The separate identity-gate fixtures exercise the actual verifier failures.
  @override
  Future<bool> ensureDeviceVerified() async => true;
  @override
  DeviceChallenge get verifiedChallenge =>
      DeviceChallenge(mac: mac, nonce: 'f' * 32, response: 'e' * 64);
  @override
  Future<({String mac, String nonce})?> requestReleaseNonce() async =>
      (mac: mac, nonce: 'a' * 32);
  @override
  Future<bool> releaseOwnership(String nonce, String response) async {
    releases++;
    throw StateError('A still-owned fixture must never receive a reset');
  }
}

class _OtherOwnerCloud extends SetupTestAppCloud {
  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) async => null;
  @override
  Future<String?> requestPairingRelease(
    String token,
    String mac,
    String nonce,
  ) async => null;
}

final _boundary = GlobalKey();
Future<void> _show(
  WidgetTester tester,
  Widget screen,
  AuthService auth,
  BleService ble,
  CloudService cloud, {
  double scale = 1,
  bool keyboard = false,
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
          home: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> main() async {
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  testWidgets('still-owned calculator cannot be reset or falsely completed', (
    tester,
  ) async {
    final auth = SetupTestAppAuth();
    await auth.init();
    final ble = _OtherOwnerBle();
    await _show(
      tester,
      const LinkDeviceScreen(),
      auth,
      ble,
      _OtherOwnerCloud(),
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(
      find.text('This calculator belongs to another account.'),
      findsOneWidget,
    );
    expect(ble.releases, 0);
    expect(auth.primaryMac, isNull);
    expect(find.byType(PairDeviceScreen), findsNothing);
    expect(find.byType(WifiSetupScreen), findsNothing);
    expect(find.text('Device paired'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'fresh customer Apple cancellation and Google/email failures never enter setup',
    (tester) async {
      final auth = _EntryAuth();
      await _show(
        tester,
        const AppGate(restoreSession: false),
        auth,
        _AdmissionBle(),
        SetupTestAppCloud(),
      );
      expect(find.byType(AuthScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Continue with Apple'));
      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
      expect(auth.appleCalls, 1);
      expect(auth.isAuthenticated, isFalse);
      expect(find.byType(LinkDeviceScreen), findsNothing);
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(auth.googleCalls, 1);
      expect(find.text(auth.error), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).at(0),
        'fixture@example.com',
      );
      await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Login'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(auth.emailCalls, 1);
      expect(auth.isAuthenticated, isFalse);
      expect(find.byType(WifiSetupScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'fresh sign-in actions have accessible roles at text scale $scale',
      (tester) async {
        await _show(
          tester,
          const AppGate(restoreSession: false),
          _EntryAuth(),
          _AdmissionBle(),
          SetupTestAppCloud(),
          scale: scale,
        );
        final semantics = tester.ensureSemantics();
        final roles = <String, bool>{};
        try {
          for (final label in [
            'Login',
            'Continue with Apple',
            'Continue with Google',
          ]) {
            final action = find.text(label);
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            final data = tester.getSemantics(action).getSemanticsData();
            expect(data.label, contains(label));
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
            roles[label] = data.flagsCollection.isButton;
          }
        } finally {
          semantics.dispose();
        }
        await _capture(
          tester,
          'signin-actions-${scale == 1 ? 'normal' : 'large'}',
        );
        expect(roles, {
          'Login': true,
          'Continue with Apple': true,
          'Continue with Google': true,
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final status in [404, 403, 409]) {
    testWidgets(
      'public non-C62E V2 with production gate disabled ($status) stops before approval or claim',
      (tester) async {
        final paths = <String>[];
        final ble = PairBle();
        final auth = PairAuth();
        final cloud = CloudService(
          client: MockClient((r) async {
            paths.add(r.url.path);
            expectSync(jsonDecode(r.body), {'mac': mac});
            return http.Response(
              '{"ok":false,"error":"pairing_v2_disabled"}',
              status,
            );
          }),
        );
        addTearDown(ble.dispose);
        addTearDown(auth.dispose);
        addTearDown(cloud.dispose);
        await openPair(tester, ble, auth, cloud);
        await tester.pumpAndSettle();
        expect(paths, ['/ai/pair/challenge']);
        expect(ble.pairingApprovalVersion, 2);
        expect(
          await ble.submitPairingCode('123456', 'fixture@example.com'),
          contains('requires secure pairing'),
        );
        await tester.pump(const Duration(seconds: 3));
        expect(paths, ['/ai/pair/challenge']);
        expect(auth.adds, 0);
        expect(ble.commands.map((c) => c['cmd']), ['capabilities']);
        expect(
          find.textContaining('Secure pairing is not available'),
          findsOneWidget,
        );
        expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull,
        );
        expect(find.byType(WifiSetupScreen), findsNothing);
        expect(find.text('Device paired'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final disconnectOnPause in [false, true]) {
    testWidgets(
      'background/resume during cloud claim, disconnect=$disconnectOnPause, cannot announce early completion',
      (tester) async {
        final pending = Completer<http.Response>();
        var claims = 0;
        final ble = PairBle();
        final auth = PairAuth();
        final cloud = CloudService(
          client: MockClient((r) async {
            if (r.url.path.endsWith('challenge')) {
              return http.Response(jsonEncode(offerData()), 200);
            }
            claims++;
            return pending.future;
          }),
        );
        addTearDown(ble.dispose);
        addTearDown(auth.dispose);
        addTearDown(cloud.dispose);
        await openPair(tester, ble, auth, cloud);
        await tester.pump(const Duration(milliseconds: 100));
        expect(claims, 1);
        expect(auth.adds, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        if (disconnectOnPause) {
          ble.connected = false;
        }
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        pending.complete(http.Response(jsonEncode(completionData()), 200));
        await tester.pumpAndSettle();
        expect(claims, 1);
        expect(auth.adds, disconnectOnPause ? 0 : 1);
        if (disconnectOnPause) {
          expect(find.textContaining('connection changed'), findsOneWidget);
          expect(ble.commands.any((c) => c['cmd'] == 'paircomplete'), isFalse);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    for (final scenario in ['denied', 'off', 'none', 'wrong']) {
      testWidgets('small setup $scenario accessible at text scale $scale', (
        tester,
      ) async {
        final auth = SetupTestAppAuth();
        await auth.init();
        final ble = _AdmissionBle()
          ..granted = scenario != 'denied'
          ..radio = scenario != 'off'
          ..discover = scenario == 'wrong'
          ..reject = scenario == 'wrong';
        await _show(
          tester,
          const LinkDeviceScreen(),
          auth,
          ble,
          SetupTestAppCloud(),
          scale: scale,
        );
        await tester.tap(find.text('Scan'));
        await tester.pumpAndSettle();
        final message = switch (scenario) {
          'denied' => 'CalcAI needs Bluetooth access to find your calculator.',
          'off' => 'Turn on Bluetooth, then tap Scan again.',
          'none' =>
            'No calculator found. Open Settings > BLE on it, then retry.',
          _ => 'Could not verify this calculator. Scan again.',
        };
        expect(find.text(message), findsOneWidget);
        expect(find.byType(PairDeviceScreen), findsNothing);
        expect(find.text('Device paired'), findsNothing);
        await tester.ensureVisible(find.text('Scan'));
        await tester.pumpAndSettle();
        expect(find.text('Scan').hitTestable(), findsOneWidget);
        final semantics = tester.ensureSemantics();
        try {
          final data = tester
              .getSemantics(find.widgetWithText(ElevatedButton, 'Scan'))
              .getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        } finally {
          semantics.dispose();
        }
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Scan'),
        );
        expect(
          paragraph.size.height + 0.01,
          greaterThanOrEqualTo(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width),
          ),
        );

        if (scenario == 'denied') {
          expect(find.text('Open Settings').hitTestable(), findsOneWidget);
        }
        await _capture(
          tester,
          'setup-$scenario-${scale == 1 ? 'normal' : 'large'}',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
      'pairing code and retry fit small screen with keyboard at text scale $scale',
      (tester) async {
        final auth = PairAuth();
        await auth.init();
        final ble = PairBle();
        final cloud = CloudService(
          client: MockClient(
            (_) async => http.Response('{"error":"unavailable"}', 503),
          ),
        );
        await _show(
          tester,
          const PairDeviceScreen(),
          auth,
          ble,
          cloud,
          scale: scale,
          keyboard: true,
        );
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not finish pairing'), findsOneWidget);
        await tester.ensureVisible(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Retry').hitTestable(), findsOneWidget);
        await _capture(
          tester,
          'pairing-retry-${scale == 1 ? 'normal' : 'large'}',
        );
        final pairText = tester.renderObject<RenderParagraph>(
          find.text('Retry'),
        );
        expect(
          pairText.size.height + 0.01,
          greaterThanOrEqualTo(
            pairText.getMaxIntrinsicHeight(pairText.size.width),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'approved offer retry label is complete with keyboard at text scale $scale',
      (tester) async {
        final auth = PairAuth();
        await auth.init();
        final ble = PairBle();
        final paths = <String>[];
        final cloud = CloudService(
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (r.url.path.endsWith('challenge')) {
              return http.Response(jsonEncode(offerData()), 200);
            }
            return http.Response('{"error":"unavailable"}', 503);
          }),
        );
        await _show(
          tester,
          const PairDeviceScreen(),
          auth,
          ble,
          cloud,
          scale: scale,
          keyboard: true,
        );
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pumpAndSettle();
        expect(paths, ['/ai/pair/challenge', '/ai/pair/claim']);
        expect(auth.adds, 0);
        expect(ble.pairingApprovalVersion, 2);
        expect(find.textContaining('Could not finish pairing'), findsOneWidget);
        await tester.ensureVisible(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Retry').hitTestable(), findsOneWidget);
        await _capture(
          tester,
          'pairing-claim-retry-${scale == 1 ? 'normal' : 'large'}',
        );
        final text = tester.renderObject<RenderParagraph>(find.text('Retry'));
        expect(
          text.size.height + 0.01,
          greaterThanOrEqualTo(text.getMaxIntrinsicHeight(text.size.width)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
