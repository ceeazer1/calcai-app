import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/app.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

const _storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _mac = 'ca1ca1000001';

Future<void> _show(
  WidgetTester tester,
  AuthService auth, {
  double textScale = 1,
}) async {
  final cloud = FakeCloudService();
  final ble = SetupTestAppBle();
  addTearDown(cloud.dispose);
  addTearDown(ble.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
        ChangeNotifierProvider<BleService>.value(value: ble),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AppGate(restoreSession: false),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

void main() {
  late Map<String, String> secure;
  setUp(() {
    secure = {};
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storage, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return secure[key];
            case 'write':
              secure[key] = args['value'] as String;
            case 'delete':
              secure.remove(key);
            default:
              throw UnsupportedError(call.method);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storage, null);
  });

  AuthService authFor(Future<http.Response> Function(http.Request) devices) {
    final auth = AuthService(
      httpClient: MockClient((request) async {
        if (request.url.path == '/ai/user/devices') return devices(request);
        return http.Response(
          '{"ok":true,"token":"fixture-session","email":"a@example.com"}',
          200,
        );
      }),
    );
    addTearDown(auth.dispose);
    return auth;
  }

  testWidgets(
    'a503 after login shows discovery Retry and successful empty retry permits setup',
    (tester) async {
      var healthy = false;
      var lookups = 0;
      final auth = authFor((request) async {
        lookups++;
        expect(request.headers['Authorization'], 'Bearer fixture-session');
        return healthy
            ? http.Response('{"ok":true,"devices":[]}', 200)
            : http.Response('{"ok":false,"error":"unavailable"}', 503);
      });
      await auth.signInWithEmail('a@example.com', 'fixture-password');
      await _show(tester, auth);
      expect(find.text("Couldn't load your calculators"), findsOneWidget);
      expect(find.byType(LinkDeviceScreen), findsNothing);
      expect(lookups, 1);
      healthy = true;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(lookups, 2);
      expect(find.byType(LinkDeviceScreen), findsOneWidget);
      expect(auth.deviceListVerified, isTrue);
    },
  );

  testWidgets('a verified empty lookup opens first-time setup directly', (
    tester,
  ) async {
    var lookups = 0;
    final auth = authFor((_) async {
      lookups++;
      return http.Response('{"ok":true,"devices":[]}', 200);
    });
    await auth.signInWithEmail('a@example.com', 'fixture-password');
    await _show(tester, auth);
    expect(find.byType(LinkDeviceScreen), findsOneWidget);
    expect(find.text('Checking your calculators…'), findsNothing);
    expect(lookups, 1);
  });

  testWidgets(
    'discovery Retry stays reachable with large text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = authFor((_) async => http.Response('{"ok":false}', 503));
      await auth.signInWithEmail('a@example.com', 'fixture-password');
      await _show(tester, auth, textScale: 2);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Retry'));
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restored no-MAC session performs one discovery before routing', (
    tester,
  ) async {
    secure['auth_token'] = 'fixture-session';
    SharedPreferences.setMockInitialValues({'session_valid': true});
    final pending = Completer<http.Response>();
    var lookups = 0;
    final auth = authFor((_) {
      lookups++;
      return pending.future;
    });
    await auth.init();
    await _show(tester, auth);
    expect(find.text('Checking your calculators…'), findsOneWidget);
    expect(find.byType(LinkDeviceScreen), findsNothing);
    expect(lookups, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(lookups, 1);
    pending.complete(http.Response('{"ok":true,"devices":[]}', 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(LinkDeviceScreen), findsOneWidget);
  });

  testWidgets(
    'a restored cached calculator remains available without discovery',
    (tester) async {
      secure['auth_token'] = 'fixture-session';
      SharedPreferences.setMockInitialValues({
        'session_valid': true,
        'device_macs': jsonEncode([_mac]),
        'primary_mac': _mac,
      });
      var lookups = 0;
      final auth = authFor((_) async {
        lookups++;
        return http.Response('{"ok":false}', 503);
      });
      await auth.init();
      await _show(tester, auth);
      expect(auth.primaryMac, _mac);
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(LinkDeviceScreen), findsNothing);
      expect(lookups, 0);
    },
  );

  testWidgets('explicit setup skip can bypass failed no-MAC discovery', (
    tester,
  ) async {
    final auth = authFor((_) async => http.Response('{"ok":false}', 503));
    await auth.signInWithEmail('a@example.com', 'fixture-password');
    auth.skipSetup();
    await _show(tester, auth);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text("Couldn't load your calculators"), findsNothing);
    expect(find.byType(LinkDeviceScreen), findsNothing);
  });
}
