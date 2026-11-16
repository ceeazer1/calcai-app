import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/widgets/gradient_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'support/setup_test_app.dart';

class _JoinBle extends SetupTestAppBle {
  _JoinBle() : super(delay: Duration.zero);
  final joined = Completer<bool>();
  bool pending = false;
  @override
  ProvisioningState get provisioningState => pending
      ? ProvisioningState.waitingForConnection
      : super.provisioningState;
  @override
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    pending = true;
    notifyListeners();
    final result = await joined.future;
    pending = false;
    if (!result) {
      return false;
    }
    return super.sendWifiCredentials(
      ssid: ssid,
      password: password,
      iphoneHotspot: iphoneHotspot,
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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

Future<void> main() async {
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Wi-Fi and honest completion remain usable at 320x568 scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = SetupTestAppAuth(paired: true);
        await auth.init();
        final ble = _JoinBle();
        addTearDown(auth.dispose);
        addTearDown(ble.dispose);
        await tester.runAsync(() async {
          await ble.startScan();
          await ble.connectToDevice(ble.devices.first);
        });
        final cloud = SetupTestAppCloud();
        addTearDown(cloud.dispose);
        final key = GlobalKey();
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
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const WifiSetupScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home Wi-Fi'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'fixture-password');
        tester.testTextInput.hide();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(find.text('Connect').hitTestable(), findsOneWidget);
        await _capture(
          tester,
          key,
          'wifi-details-${scale == 1 ? 'normal' : 'large'}',
        );
        final connectText = tester.renderObject<RenderParagraph>(
          find.text('Connect'),
        );
        expect(
          connectText.size.height + 0.01,
          greaterThanOrEqualTo(
            connectText.getMaxIntrinsicHeight(connectText.size.width),
          ),
        );
        await tester.tap(find.text('Connect'));
        await tester.pump();
        expect(find.text('Device paired'), findsNothing);
        expect(find.text('Connecting to Home Wi-Fi'), findsOneWidget);
        ble.joined.complete(true);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pumpAndSettle();
        expect(find.text('Device paired'), findsOneWidget);
        await tester.ensureVisible(find.text('Home page'));
        await tester.pumpAndSettle();
        expect(find.text('Home page').hitTestable(), findsOneWidget);
        await _capture(
          tester,
          key,
          'success-${scale == 1 ? 'normal' : 'large'}',
        );
        final semantics = tester.ensureSemantics();
        try {
          final data = tester
              .getSemantics(find.text('Home page'))
              .getSemanticsData();
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(data.flagsCollection.isButton, isTrue);
        } finally {
          semantics.dispose();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final (enabled, loading) in const [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      'setup custom action exposes button role enabled=$enabled loading=$loading',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GradientButton(
                label: 'Home page',
                enabled: enabled,
                isLoading: loading,
                onPressed: () {},
              ),
            ),
          ),
        );
        final semantics = tester.ensureSemantics();
        try {
          final data = tester
              .getSemantics(find.bySemanticsLabel('Home page'))
              .getSemanticsData();
          expect(data.label, 'Home page');
          expect(data.flagsCollection.isButton, isTrue);
          expect(
            data.flagsCollection.isEnabled,
            enabled && !loading ? ui.Tristate.isTrue : ui.Tristate.isFalse,
          );
          expect(data.hasAction(ui.SemanticsAction.tap), enabled && !loading);
        } finally {
          semantics.dispose();
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
