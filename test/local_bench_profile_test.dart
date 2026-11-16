import 'package:calcai_app/services/local_bench_profile.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/models/calcai_device.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bench blocks remembered and unobserved device before native connect', () async {
    final ble = BleService();
    expect(await ble.reconnectKnownDevice(), isFalse);
    await ble.connectToDevice(CalcAiDevice(
      device: BluetoothDevice.fromId('unobserved-target'),
      rssi: -40,
      advertisementName: 'CALCAI-C62E',
    ));
    expect(ble.connectionState, DeviceConnectionState.error);
    expect(ble.connectedDevice, isNull);
    expect(ble.error, contains('Connection blocked'));
    ble.dispose();
  }, skip: !LocalBenchProfile.enabled);
  test(
    'scoped preferences never read, overwrite or clear personal keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'email': 'personal@example.com',
        'session_valid': true,
        'saved_networks_personal': '["personal"]',
      });
      final raw = await SharedPreferences.getInstance();
      final bench = AppPreferences(raw, prefix: '__bench__');
      expect(bench.getString('email'), isNull);
      expect(bench.getBool('session_valid'), isNull);
      await bench.setString('email', 'fixture@example.com');
      await bench.setBool('session_valid', true);
      expect(bench.getKeys(), {'email', 'session_valid'});
      for (final key in bench.getKeys()) {
        await bench.remove(key);
      }
      expect(raw.getString('email'), 'personal@example.com');
      expect(raw.getBool('session_valid'), isTrue);
      expect(raw.getString('saved_networks_personal'), '["personal"]');
      final production = AppPreferences(raw, prefix: '');
      expect(production.getString('email'), 'personal@example.com');
    },
  );

  test(
    'bench init/login/relaunch/sign-out preserve personal session',
    () async {
      const prefix = LocalBenchProfile.storagePrefix;
      final secure = {'auth_token': 'personal-token'};
      secure['${prefix}auth_token'] = 'stale-bench-token';
      SharedPreferences.setMockInitialValues({
        'email': 'personal@example.com',
        'session_valid': true,
        'device_macs': '["aabbccddeeff"]',
        'primary_mac': 'aabbccddeeff',
        'last_ble_device_id': 'personal-peripheral',
        'saved_networks_aabbccddeeff': '["private"]',
        'iphone_hotspots_aabbccddeeff': '["private"]',
      });
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map;
            final key = args['key'] as String;
            switch (call.method) {
              case 'read':
                return secure[key];
              case 'write':
                secure[key] = args['value'] as String;
                return null;
              case 'delete':
                secure.remove(key);
                return null;
              default:
                throw StateError('Unexpected storage method');
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      AuthService create() => AuthService(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return http.Response(
              '{"ok":true,"token":"bench-token","email":"fixture@example.com"}',
              200,
            );
          }
          return http.Response('{"ok":true,"devices":[]}', 200);
        }),
      );
      final auth = create();
      await auth.init();
      expect(auth.isAuthenticated, isFalse);
      expect(secure['auth_token'], 'personal-token');
      expect(
        await auth.signInWithEmail('fixture@example.com', 'test-only'),
        EmailAuthOutcome.success,
      );
      auth.dispose();
      final restored = create();
      await restored.init();
      expect(restored.isAuthenticated, isTrue);
      expect(restored.email, 'fixture@example.com');
      await restored.signOut();
      restored.dispose();
      final raw = await SharedPreferences.getInstance();
      expect(secure['auth_token'], 'personal-token');
      expect(secure['${prefix}auth_token'], isNull);
      expect(raw.getString('email'), 'personal@example.com');
      expect(raw.getBool('session_valid'), isTrue);
      expect(raw.getString('primary_mac'), 'aabbccddeeff');
      expect(raw.getString('last_ble_device_id'), 'personal-peripheral');
      expect(raw.getString('saved_networks_aabbccddeeff'), '["private"]');
      expect(raw.getString('iphone_hotspots_aabbccddeeff'), '["private"]');
    },
    skip: !LocalBenchProfile.enabled,
  );
}
