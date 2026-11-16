import 'package:calcai_app/services/local_bench_profile.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/models/calcai_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProductionReconnectProbe extends BleService {
  CalcAiDevice? requested;
  @override
  Future<void> connectToDevice(CalcAiDevice device,
      {Duration timeout = const Duration(seconds: 15), int attempts = 3}) async {
    requested = device;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production inputs disable bench-only routing and storage', () {
    expect(LocalBenchProfile.enabled, isFalse);
    expect(LocalBenchProfile.storagePrefix, isEmpty);
  });
  test('default preferences use existing production keys without migration', () async {
    SharedPreferences.setMockInitialValues({
      'email': 'production-fixture@example.com',
      '__calcai_bench_c62e_20261111__email': 'bench-fixture@example.com',
    });
    final prefs = await AppPreferences.getInstance();
    expect(prefs.getString('email'), 'production-fixture@example.com');
    await prefs.setString('email', 'updated-fixture@example.com');
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('email'), 'updated-fixture@example.com');
    expect(raw.getString('__calcai_bench_c62e_20261111__email'),
        'bench-fixture@example.com');
  });
  test('normal remembered peripheral reaches reconnect without C62E discovery gate', () async {
    SharedPreferences.setMockInitialValues({
      'last_ble_device_id': 'production-fixture-peripheral',
      '__calcai_bench_c62e_20261111__last_ble_device_id': 'bench-fixture-peripheral',
    });
    final ble = _ProductionReconnectProbe();
    await ble.reconnectKnownDevice();
    expect(ble.requested?.id, 'production-fixture-peripheral');
    expect(ble.error, isNull);
    ble.dispose();
  });
}
