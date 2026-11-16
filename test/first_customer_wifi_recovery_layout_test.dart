import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_setup_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/setup_test_app.dart';

class _EmptyScanBle extends SetupTestAppBle {
  _EmptyScanBle(this.scanFailed) : super(delay: Duration.zero);
  final bool scanFailed;
  int scans = 0;
  @override
  ProvisioningState get provisioningState => scans == 1 && scanFailed
      ? ProvisioningState.failed
      : super.provisioningState;
  @override
  String? get error => scans == 1 && scanFailed
      ? 'Could not confirm Wi-Fi scan results. Try scanning again.'
      : null;
  @override
  Future<void> requestWifiScan() async {
    scans++;
    if (scans == 1) {
      notifyListeners();
      return;
    }
    await super.requestWifiScan();
  }
}

class _FailedJoinBle extends SetupTestAppBle {
  _FailedJoinBle() : super(delay: Duration.zero);
  int joins = 0;
  @override
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    joins++;
    if (joins == 1) return false;
    return super.sendWifiCredentials(
      ssid: ssid,
      password: password,
      iphoneHotspot: iphoneHotspot,
    );
  }
}

final _boundary = GlobalKey();

Future<void> _show(
  WidgetTester tester,
  SetupTestAppBle ble,
  double scale,
) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final auth = SetupTestAppAuth(paired: true);
  await auth.init();
  final cloud = SetupTestAppCloud();
  addTearDown(auth.dispose);
  addTearDown(ble.dispose);
  addTearDown(cloud.dispose);
  await tester.runAsync(() async {
    await ble.startScan();
    await ble.connectToDevice(ble.devices.first);
  });
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
}

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

void _expectUnclipped(WidgetTester tester, Finder finder) {
  final text = tester.renderObject<RenderParagraph>(finder);
  expect(
    text.size.height + 0.01,
    greaterThanOrEqualTo(text.getMaxIntrinsicHeight(text.size.width)),
  );
}

Future<void> main() async {
  final font = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await font.load();
  for (final scale in [1.0, 2.0]) {
    for (final scanFailed in [false, true]) {
      testWidgets(
        'empty Wi-Fi scan failure=$scanFailed can retry at 320x568 scale $scale',
        (tester) async {
          final ble = _EmptyScanBle(scanFailed);
          await _show(tester, ble, scale);
          expect(
            find.text(
              scanFailed ? 'Could not load networks' : 'No networks found',
            ),
            findsOneWidget,
          );
          expect(find.text('Device paired'), findsNothing);
          await tester.ensureVisible(find.text('Scan Again'));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            'wifi-empty-$scanFailed-${scale == 1 ? 'normal' : 'large'}',
          );
          expect(find.text('Scan Again').hitTestable(), findsOneWidget);
          _expectUnclipped(tester, find.text('Scan Again'));
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Scan Again'));
          await tester.pumpAndSettle();
          expect(ble.scans, 2);
          expect(find.text('Home Wi-Fi'), findsOneWidget);
          expect(find.text('Device paired'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'Wi-Fi keyboard, failed join and retry stay honest at 320x568 scale $scale',
      (tester) async {
        final ble = _FailedJoinBle();
        await _show(tester, ble, scale);
        await tester.tap(find.text('Home Wi-Fi'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 216);
        await tester.enterText(find.byType(TextField), 'fixture-password');
        await tester.showKeyboard(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.ensureVisible(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(find.text('Connect').hitTestable(), findsOneWidget);
        await _capture(
          tester,
          'wifi-keyboard-${scale == 1 ? 'normal' : 'large'}',
        );
        _expectUnclipped(tester, find.text('Connect'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(ble.joins, 1);
        expect(find.text('Connection failed'), findsOneWidget);
        expect(find.text('Device paired'), findsNothing);
        await _capture(
          tester,
          'wifi-join-failed-${scale == 1 ? 'normal' : 'large'}',
        );
        _expectUnclipped(tester, find.text('Connection failed'));
        expect(find.text('Retry').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        tester.testTextInput.hide();
        FocusManager.instance.primaryFocus?.unfocus();
        ScaffoldMessenger.of(
          tester.element(find.byType(WifiSetupScreen)),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Connect'));
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pumpAndSettle();
        expect(ble.joins, 2);
        expect(find.text('Device paired'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
