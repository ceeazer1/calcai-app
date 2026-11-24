import 'dart:async';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/services/local_bench_profile.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// Test the already locked Darwin implementation without changing dependencies.
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_darwin/flutter_blue_plus_darwin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

// All native operations are intercepted. These messages exercise the pinned
// Darwin transport, FBP mapping/aggregation and actual BleService scan path.
const _channel = MethodChannel('flutter_blue_plus/methods');
const _codec = StandardMethodCodec();
const _uuid = '021a9004-0382-4aea-bff4-6b3f1c5adfb4';
const _otherUuid = '021a9004-0382-4aea-bff4-6b3f1c5adfb5';
const _id = '00000000-0000-0000-0000-00000000C62E';
const _otherId = '00000000-0000-0000-0000-00000000C386';
final _calls = <MethodCall>[];
void Function(MethodCall)? _onNativeCall;
int? _failStartNumber;
Completer<void>? _startReplyGate;

Map<String, Object> _advertisement({
  String id = _id,
  String? name,
  String? platformName,
  List<String> services = const [_uuid],
  int rssi = -40,
}) => {
  'remote_id': id,
  if (name != null) 'adv_name': name,
  if (platformName != null) 'platform_name': platformName,
  'service_uuids': services,
  'connectable': 1,
  'rssi': rssi,
};

Future<void> _emit(List<Map<String, Object>> advertisements) async {
  final delivered = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        _codec.encodeMethodCall(
          MethodCall('OnScanResponse', {'advertisements': advertisements}),
        ),
        (_) => delivered.complete(),
      );
  await delivered.future;
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

int get _starts => _calls.where((call) => call.method == 'startScan').length;

Future<void> _waitForStart(int previous) async {
  for (var i = 0; i < 1000; i++) {
    if (_starts > previous) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('The intercepted native scan did not start');
}

Future<({BleService ble, Future<void> done})> _scan({
  BleService? service,
  Duration timeout = const Duration(milliseconds: 300),
}) async {
  final ble = service ?? BleService();
  final previous = _starts;
  final done = ble.startScan(timeout: timeout);
  addTearDown(() async {
    await ble.stopScan();
    await done;
    ble.dispose();
    await Future<void>.delayed(Duration.zero);
  });
  await _waitForStart(previous);
  return (ble: ble, done: done);
}

// Keep real discovery and the WifiScreen listener. Permission/remembered-device
// prerequisites are fixed, and connection is held at Connecting so late
// callbacks can challenge its guard without an actual connection or proof.
class _ConnectionProbeBle extends BleService {
  int connects = 0, nonceRequests = 0;
  DeviceConnectionState state = DeviceConnectionState.disconnected;
  CalcAiDevice? selected;
  bool alive = true;

  @override
  DeviceConnectionState get connectionState => state;
  @override
  CalcAiDevice? get connectedDevice => selected;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<bool> reconnectKnownDevice() async => false;
  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    connects++;
    selected = device;
    state = DeviceConnectionState.connecting;
    notifyListeners();
  }

  @override
  Future<({String mac, String nonce})?> requestAuthNonce() async {
    nonceRequests++;
    return null;
  }

  @override
  Future<void> endWifiUiMode() async {}
  @override
  Future<void> disconnect() async {
    state = DeviceConnectionState.disconnected;
    selected = null;
    if (alive) notifyListeners();
  }

  @override
  void dispose() {
    alive = false;
    super.dispose();
  }
}

class _ProofProbeCloud extends FakeCloudService {
  int proofs = 0;
  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) async {
    proofs++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FlutterBluePlusDarwin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          _calls.add(call);
          _onNativeCall?.call(call);
          if (call.method == 'startScan') await _startReplyGate?.future;
          if (call.method == 'startScan' && _starts == _failStartNumber) {
            throw PlatformException(code: 'scan_unavailable');
          }
          switch (call.method) {
            case 'flutterRestart':
            case 'connectedCount':
              return 0;
            case 'getAdapterState':
              return {'adapter_state': 4};
            case 'isSupported':
            case 'setOptions':
            case 'setLogLevel':
            case 'startScan':
            case 'stopScan':
              return true;
            default:
              throw StateError('Unapproved native operation: ${call.method}');
          }
        });
    await FlutterBluePlus.setLogLevel(LogLevel.none);
  });
  setUp(() {
    _calls.clear();
    _onNativeCall = null;
    _failStartNumber = null;
    _startReplyGate = null;
    SharedPreferences.setMockInitialValues({});
  });

  if (LocalBenchProfile.enabled) {
    test(
      'bench UUID evidence cannot replace the exact-name target gate',
      () async {
        final scan = await _scan();
        await _emit([
          _advertisement(),
          _advertisement(id: _otherId, name: 'CalcAI-C386'),
        ]);
        await scan.done;
        expect(scan.ble.devices, isEmpty);
        expect(scan.ble.error, contains('CALCAI-C62E was not found'));
      },
    );

    test(
      'bench target remains hidden until a complete exact-name window',
      () async {
        final scan = await _scan();
        await _emit([_advertisement(name: 'CalcAI-C62E')]);
        expect(scan.ble.devices, isEmpty);
        await scan.done;
        expect(scan.ble.devices.single.id, _id);
      },
    );

    test('bench duplicate exact-name peripherals still fail closed', () async {
      final scan = await _scan();
      await _emit([
        _advertisement(name: 'CalcAI-C62E'),
        _advertisement(id: _otherId, name: 'CalcAI-C62E'),
      ]);
      await scan.done;
      expect(scan.ble.devices, isEmpty);
      expect(scan.ble.error, contains('Multiple CALCAI-C62E'));
    });
    return;
  }

  group('iOS native discovery', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'requests only the configured service in the native first pass',
      () async {
        final scan = await _scan(
          service: BleService(serviceUuid: _otherUuid.toUpperCase()),
        );
        final arguments =
            _calls.singleWhere((c) => c.method == 'startScan').arguments as Map;
        expect(arguments['with_services'], [_otherUuid]);
        for (final key in [
          'with_names',
          'with_keywords',
          'with_remote_ids',
          'with_msd',
          'with_service_data',
        ]) {
          expect(
            arguments[key],
            isEmpty,
            reason: '$key disables native UUID filtering',
          );
        }
        await _emit([
          _advertisement(services: [_otherUuid]),
        ]);
        await scan.ble.stopScan();
        await scan.done;
        expect(_starts, 1);
        expect(scan.ble.devices.single.id, _id);
        expect(scan.ble.pairedOwner, isNull);
        expect(scan.ble.verifiedChallenge, isNull);
      },
    );

    test(
      'falls back for name-only firmware within the original timeout',
      () async {
        final elapsed = Stopwatch()..start();
        final scan = await _scan(timeout: const Duration(milliseconds: 400));
        await _waitForStart(1);
        final arguments =
            _calls.lastWhere((c) => c.method == 'startScan').arguments as Map;
        expect(arguments['with_services'], isEmpty);
        expect(scan.ble.isScanning, isTrue);
        await _emit([_advertisement(name: 'CALcAi-Legacy', services: [])]);
        final candidate = scan.ble.devices.single;
        await _emit([
          _advertisement(name: 'CalcAI-Legacy full', services: [], rssi: -29),
        ]);
        await scan.done;
        expect(_starts, 2);
        expect(identical(scan.ble.devices.single, candidate), isTrue);
        expect(candidate.advertisementName, 'CalcAI-Legacy full');
        expect(candidate.rssi, -29);
        // Includes test/transport scheduling overhead, but rejects two full windows.
        expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 650)));
        expect(scan.ble.pairedOwner, isNull);
        expect(scan.ble.verifiedChallenge, isNull);
      },
    );

    test(
      'both empty passes finish and late results cannot add a candidate',
      () async {
        final scan = await _scan(timeout: const Duration(milliseconds: 220));
        await scan.done;
        expect(_starts, 2);
        expect(scan.ble.isScanning, isFalse);
        await _emit([_advertisement(name: 'CalcAI-late')]);
        expect(scan.ble.devices, isEmpty);
      },
    );

    test(
      'user stop during the first pass prevents fallback and late updates',
      () async {
        final scan = await _scan(timeout: const Duration(milliseconds: 220));
        await scan.ble.stopScan();
        await scan.done;
        await _emit([_advertisement(name: 'CalcAI-late')]);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(_starts, 1);
        expect(scan.ble.devices, isEmpty);
      },
    );

    test(
      'mixed modern and legacy candidates survive both scan phases',
      () async {
        final scan = await _scan(timeout: const Duration(milliseconds: 400));
        await _emit([_advertisement(name: 'CalcAI-modern')]);
        final modern = scan.ble.devices.single;
        await _waitForStart(1);
        expect(scan.ble.devices.single, same(modern));
        await _emit([
          _advertisement(id: _otherId, name: 'CalcAI-legacy', services: []),
        ]);
        await scan.done;
        expect(_starts, 2);
        expect(scan.ble.devices.map((d) => d.id), [_id, _otherId]);
        expect(scan.ble.devices.first, same(modern));
        expect(scan.ble.pairedOwner, isNull);
        expect(scan.ble.verifiedChallenge, isNull);
        expect(_calls.where((c) => c.method == 'connect'), isEmpty);
      },
    );

    test('overlapping stops cannot clear a replacement attempt', () async {
      final scan = await _scan(timeout: const Duration(milliseconds: 400));
      Future<void>? replacement;
      var replacing = false;
      scan.ble.addListener(() {
        if (!scan.ble.isScanning && !replacing) {
          replacing = true;
          replacement = scan.ble.startScan(
            timeout: const Duration(milliseconds: 400),
          );
        }
      });
      addTearDown(() async {
        await scan.ble.stopScan();
        await replacement;
      });
      final stop1 = scan.ble.stopScan();
      final stop2 = scan.ble.stopScan();
      await Future.wait([stop1, stop2]);
      await _waitForStart(1);
      await scan.done;
      expect(scan.ble.isScanning, isTrue);
      expect(FlutterBluePlus.isScanningNow, isTrue);
      await _emit([_advertisement(id: _otherId)]);
      expect(scan.ble.devices.single.id, _otherId);
    });

    test('canceled pass cannot stop the replacement native scan', () async {
      final scan = await _scan(timeout: const Duration(milliseconds: 400));
      Future<void>? replacement;
      var replacing = false;
      scan.ble.addListener(() {
        if (!scan.ble.isScanning && !replacing) {
          replacing = true;
          replacement = scan.ble.startScan(
            timeout: const Duration(milliseconds: 400),
          );
        }
      });
      addTearDown(() async {
        await scan.ble.stopScan();
        await replacement;
      });
      await scan.ble.stopScan();
      await _waitForStart(1);
      await scan.done;
      final secondStart = _calls.lastIndexWhere((c) => c.method == 'startScan');
      await _emit([_advertisement(id: _otherId)]);
      expect(scan.ble.devices.single.id, _otherId);
      expect(FlutterBluePlus.isScanningNow, isTrue);
      expect(
        _calls.skip(secondStart + 1).where((c) => c.method == 'stopScan'),
        isEmpty,
      );
    });

    test('stop at the native phase boundary cannot restart scanning', () async {
      final scan = await _scan(timeout: const Duration(milliseconds: 220));
      Future<void>? stopped;
      _onNativeCall = (call) {
        if (call.method == 'stopScan' && stopped == null) {
          stopped = scan.ble.stopScan();
        }
      };
      await scan.done;
      await stopped;
      expect(stopped, isNotNull);
      expect(_starts, 1);
      expect(scan.ble.isScanning, isFalse);
    });

    test('stop while native start is pending cannot start fallback', () async {
      final gate = Completer<void>();
      _startReplyGate = gate;
      final scan = await _scan(timeout: const Duration(milliseconds: 220));
      final stopped = scan.ble.stopScan();
      gate.complete();
      await stopped;
      await scan.done;
      expect(_starts, 1);
      expect(scan.ble.isScanning, isFalse);
    });

    test('stop during compatibility fallback ignores late results', () async {
      final scan = await _scan(timeout: const Duration(milliseconds: 400));
      await _waitForStart(1);
      await scan.ble.stopScan();
      await scan.done;
      await _emit([_advertisement(name: 'CalcAI-late', services: [])]);
      expect(_starts, 2);
      expect(scan.ble.isScanning, isFalse);
      expect(scan.ble.devices, isEmpty);
    });

    test(
      'selection stop preserves the candidate without starting fallback',
      () async {
        final scan = await _scan(timeout: const Duration(milliseconds: 220));
        Future<void>? stopped;
        scan.ble.addListener(() {
          if (scan.ble.devices.isNotEmpty && stopped == null) {
            stopped = scan.ble.stopScan();
          }
        });
        await _emit([_advertisement()]);
        await scan.done;
        await stopped;
        await _emit([_advertisement(id: _otherId, name: 'CalcAI-late')]);
        expect(_starts, 1);
        expect(scan.ble.devices.single.id, _id);
        expect(scan.ble.connectionState, DeviceConnectionState.disconnected);
      },
    );

    test(
      'dispose at the phase boundary prevents fallback and notification',
      () async {
        final ble = BleService();
        final previous = _starts;
        final done = ble.startScan(timeout: const Duration(milliseconds: 220));
        await _waitForStart(previous);
        var disposed = false;
        _onNativeCall = (call) {
          if (call.method == 'stopScan' && !disposed) {
            disposed = true;
            ble.dispose();
          }
        };
        addTearDown(() async {
          _onNativeCall = null;
          if (!disposed) ble.dispose();
          await FlutterBluePlus.stopScan();
        });
        await done;
        expect(disposed, isTrue);
        await _emit([_advertisement()]);
        expect(_starts, 1);
        expect(ble.devices, isEmpty);
      },
    );

    test(
      'native start failure is reported without an automatic second attempt',
      () async {
        _failStartNumber = 1;
        final scan = await _scan();
        await scan.done;
        expect(_starts, 1);
        expect(scan.ble.error, contains('Scan failed:'));
        expect(scan.ble.devices, isEmpty);
      },
    );
  });

  test('Android keeps one unfiltered scan and name-only discovery', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final scan = await _scan();
    expect(
      (_calls.singleWhere((c) => c.method == 'startScan').arguments
          as Map)['with_services'],
      isEmpty,
    );
    await _emit([_advertisement(name: 'CalcAI-legacy', services: [])]);
    await scan.done;
    expect(_starts, 1);
    expect(scan.ble.devices.single.id, _id);
  });

  for (final name in <String?>[null, '']) {
    test('exact UUID discovers candidate with advName=$name', () async {
      final scan = await _scan();
      await _emit([_advertisement(name: name)]);
      expect(
        FlutterBluePlus.lastScanResults.single.advertisementData.serviceUuids,
        contains(Guid(_uuid)),
      );
      expect(scan.ble.devices, hasLength(1));
      expect(scan.ble.devices.single.id, _id);
      expect(scan.ble.connectionState, DeviceConnectionState.disconnected);
      expect(scan.ble.pairedOwner, isNull);
      expect(scan.ble.verifiedChallenge, isNull);
    });
  }

  test(
    'legacy case-insensitive CalcAI name remains eligible without a UUID',
    () async {
      final scan = await _scan();
      await _emit([_advertisement(name: 'CALcAi-Legacy', services: [])]);
      expect(scan.ble.devices.single.advertisementName, 'CALcAi-Legacy');
    },
  );

  test(
    'unrelated name, absent UUID and wrong UUID cannot create candidates',
    () async {
      final scan = await _scan();
      await _emit([
        _advertisement(name: 'Other accessory', services: [_otherUuid]),
        _advertisement(id: _otherId, services: []),
      ]);
      expect(scan.ble.devices, isEmpty);
    },
  );

  test(
    'discovery matches the configured UUID with case normalization',
    () async {
      final scan = await _scan(
        service: BleService(serviceUuid: _otherUuid.toUpperCase()),
      );
      await _emit([
        _advertisement(services: [_otherUuid]),
      ]);
      expect(scan.ble.devices, hasLength(1));
      expect(scan.ble.devices.single.id, _id);
    },
  );

  test(
    'default UUID is not hardcoded when another service is configured',
    () async {
      final scan = await _scan(service: BleService(serviceUuid: _otherUuid));
      await _emit([_advertisement()]);
      expect(scan.ble.devices, isEmpty);
    },
  );

  test(
    'later full name enriches UUID candidate in place without duplicates',
    () async {
      final scan = await _scan();
      await _emit([_advertisement(id: _otherId)]);
      expect(scan.ble.devices, hasLength(1));
      final candidate = scan.ble.devices.single;
      expect(candidate.name, 'CalcAI Device');
      await _emit([
        _advertisement(
          id: _otherId,
          name: 'Classroom calculator',
          services: [],
          rssi: -31,
        ),
      ]);
      expect(scan.ble.devices, hasLength(1));
      expect(identical(scan.ble.devices.single, candidate), isTrue);
      expect(candidate.name, 'Classroom calculator');
      expect(candidate.rssi, -31);
    },
  );

  test(
    'later full name enriches an existing legacy named candidate in place',
    () async {
      final scan = await _scan();
      await _emit([_advertisement(name: 'CalcAI', services: [])]);
      final candidate = scan.ble.devices.single;
      await _emit([
        _advertisement(name: 'CalcAI-C62E', services: [], rssi: -29),
      ]);
      expect(scan.ble.devices, hasLength(1));
      expect(identical(scan.ble.devices.single, candidate), isTrue);
      expect(candidate.advertisementName, 'CalcAI-C62E');
      expect(candidate.rssi, -29);
    },
  );

  test('nameless follow-up keeps the known name and updates RSSI', () async {
    final scan = await _scan();
    await _emit([_advertisement(name: 'CalcAI-C62E')]);
    final candidate = scan.ble.devices.single;
    await _emit([_advertisement(rssi: -24)]);
    expect(identical(scan.ble.devices.single, candidate), isTrue);
    expect(candidate.advertisementName, 'CalcAI-C62E');
    expect(candidate.rssi, -24);
  });

  test(
    'duplicate UUID advertisements retain one candidate with latest RSSI',
    () async {
      final scan = await _scan();
      await _emit([_advertisement(rssi: -51), _advertisement(rssi: -33)]);
      expect(scan.ble.devices, hasLength(1));
      expect(scan.ble.devices.single.rssi, -33);
    },
  );

  test(
    'late native responses after stop cannot add or rename candidates',
    () async {
      final scan = await _scan();
      await _emit([_advertisement(name: 'CalcAI')]);
      final candidate = scan.ble.devices.single;
      await scan.ble.stopScan();
      await scan.done;
      await _emit([
        _advertisement(name: 'CalcAI-late', rssi: -10),
        _advertisement(id: _otherId, name: 'CalcAI-new'),
      ]);
      expect(scan.ble.devices, hasLength(1));
      expect(candidate.advertisementName, 'CalcAI');
      expect(candidate.rssi, -40);
    },
  );

  test(
    'new scan does not replay prior candidates or stopped-scan updates',
    () async {
      final first = await _scan();
      await _emit([_advertisement(name: 'CalcAI')]);
      await first.ble.stopScan();
      await first.done;
      await _emit([_advertisement(id: _otherId, name: 'CalcAI-late')]);
      final second = await _scan();
      expect(second.ble.devices, isEmpty);
      await _emit([
        _advertisement(name: 'Unrelated', services: [_otherUuid]),
      ]);
      expect(second.ble.devices, isEmpty);
    },
  );

  test(
    'late UUID candidate is received before scan deadline and ignored after',
    () async {
      final scan = await _scan(timeout: const Duration(milliseconds: 170));
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(scan.ble.isScanning, isTrue);
      await _emit([_advertisement()]);
      expect(scan.ble.devices, hasLength(1));
      await scan.done;
      expect(scan.ble.isScanning, isFalse);
      await _emit([_advertisement(id: _otherId, name: 'CalcAI-late')]);
      expect(scan.ble.devices, hasLength(1));
    },
  );

  testWidgets(
    'UUID candidate and enriched responses trigger one WiFi connection and no ownership success',
    (tester) async {
      final ble = _ConnectionProbeBle();
      final auth = FakeAuthService();
      final cloud = _ProofProbeCloud();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(ble.stopScan);
        ble.dispose();
        auth.dispose();
        cloud.dispose();
      });
      await auth.init();
      final previous = _starts;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BleService>.value(value: ble),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const WifiScreen(),
          ),
        ),
      );
      for (var i = 0; i < 30 && _starts == previous; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        _starts,
        previous + 1,
        reason: 'The actual WiFi entry must begin its intercepted scan.',
      );
      await tester.runAsync(() => _emit([_advertisement()]));
      await tester.pump();
      expect(ble.connects, 1);
      final selected = ble.selected;
      expect(find.text('Connecting…'), findsOneWidget);
      await tester.runAsync(
        () => _emit([
          _advertisement(name: 'CalcAI-C62E', services: [], rssi: -28),
        ]),
      );
      await tester.pump();
      expect(ble.connects, 1);
      expect(identical(ble.selected, selected), isTrue);
      expect(selected!.name, 'CalcAI-C62E');
      expect(selected.rssi, -28);
      expect(ble.pairedOwner, isNull);
      expect(ble.nonceRequests, 0);
      expect(cloud.proofs, 0);
      expect(find.text('Saved Networks'), findsNothing);
      expect(find.text('Add network manually'), findsNothing);
      expect(_calls.where((call) => call.method == 'connect'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
