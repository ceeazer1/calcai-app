// Real BleService command queue/parser/release with synthetic GATT and storage.
// These tests cannot establish firmware, enrollment or host/container provenance.
import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/local_bench_profile.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing plugin fault injection, no added dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _key = 'release_ack_receipt_v1';
const _mac = '112233aabbcc';
final _nonce = 'a' * 32;
final _signature = 'b' * 64;
const _owner = 'synthetic-owner@example.com';

class _Command implements BluetoothCharacteristic {
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic> nonceReply = {
    'cmd': 'relnonce',
    'mac': _mac,
    'nonce': _nonce,
  };
  FutureOr<Object?> Function()? releaseReply;

  @override
  CharacteristicProperties get properties =>
      CharacteristicProperties(read: true, write: true);
  @override
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    requests.add(Map<String, dynamic>.from(jsonDecode(utf8.decode(value))));
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    final reply = switch (requests.last['cmd']) {
      'hello' => {'cmd': 'hello', 'ok': true},
      'relnonce' => nonceReply,
      'release' =>
        releaseReply == null
            ? {'cmd': 'release', 'ok': true}
            : await releaseReply!(),
      _ => throw StateError('Unexpected offline command'),
    };
    return reply == null ? [] : utf8.encode(jsonEncode(reply));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReleaseBle extends BleService {
  _ReleaseBle() {
    deviceVerifier = (_) async => true;
  }
  final command = _Command();
  int epoch = 7;
  bool connected = true;
  DateTime now = DateTime.fromMillisecondsSinceEpoch(1791850000000);
  bool disposed = false;
  String identityMac = _mac;

  @override
  BluetoothCharacteristic get commandCharacteristic => command;
  @override
  DeviceConnectionState get connectionState => connected
      ? DeviceConnectionState.ready
      : DeviceConnectionState.disconnected;
  @override
  int get connectionGeneration => epoch;
  @override
  DateTime get ackReceiptNow => now;
  @override
  Future<DeviceChallenge?> requestIdentityChallenge() async =>
      DeviceChallenge(mac: identityMac, nonce: 'c' * 32, response: 'd' * 64);
  @override
  Future<void> requestSavedNetworks() async {}
  @override
  Future<void> disconnect() async {
    connected = false;
    epoch++;
    await super.disconnect();
  }

  Future<void> settle() async {
    try {
      await (this as dynamic).ackReceiptPersistenceSettled;
    } on NoSuchMethodError {
      // The c3d24a0 baseline has no producer/storage hook.
    }
  }

  dynamic receipt() {
    try {
      return (this as dynamic).releaseAckReceipt;
    } on NoSuchMethodError {
      return null;
    }
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    super.dispose();
  }
}

class _WriteFailure extends InMemorySharedPreferencesStore {
  _WriteFailure() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      key.endsWith(_key) ? false : super.setValue(valueType, key, value);
}

Future<_ReleaseBle> _ready({
  bool requestNonce = true,
  bool verify = true,
}) async {
  final ble = _ReleaseBle();
  addTearDown(() async {
    ble.dispose();
    await ble.settle();
  });
  expect(
    await ble.proveOwnership('fixture-auth-nonce', 'fixture-proof', _owner),
    isTrue,
  );
  expect(ble.pairedOwner, _owner);
  if (verify) expect(await ble.ensureDeviceVerified(), isTrue);
  if (requestNonce) {
    expect(await ble.requestReleaseNonce(), (mac: _mac, nonce: _nonce));
  }
  await ble.settle();
  return ble;
}

Future<bool> _release(_ReleaseBle ble) =>
    ble.releaseOwnership(_nonce, _signature);
Future<String?> _stored() async => (await SharedPreferences.getInstance())
    .getString('${LocalBenchProfile.storagePrefix}$_key');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({'unrelated': 'preserved'}),
  );

  test(
    'validated release retains actual ACK and same-link nonce MAC only',
    () async {
      final ble = await _ready();
      ble.command.releaseReply = () => {
        'cmd': 'release',
        'ok': true,
        'response': _signature,
        'nonce': _nonce,
        'token': 'must-not-export',
        'email': _owner,
        'firmware': 'unobservable',
        'identityFingerprint': 'unobservable',
      };
      expect(await _release(ble), isTrue);
      expect(ble.pairedOwner, isNull);
      final receipt = ble.receipt();
      expect(
        receipt,
        isNotNull,
        reason: 'The bool-only baseline discarded the real ACK',
      );
      final json = receipt.toJson() as Map<String, Object>;
      final uuid = matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      );
      expect(json, {
        'schema': 'calcai-release-ack/v1',
        'receiptId': uuid,
        'cmd': 'release',
        'ok': true,
        'mac': _mac,
        'connectionGeneration': '7',
        'appSessionId': uuid,
        'observedAt': ble.now.millisecondsSinceEpoch,
      });
      expect(jsonEncode(json).length, lessThan(1024));
      expect(jsonEncode(json), isNot(contains('must-not-export')));
      expect(jsonEncode(json), isNot(contains(_signature)));
      expect(jsonEncode(json), isNot(contains(_nonce)));
      expect(() => json['ok'] = false, throwsUnsupportedError);
      expect(jsonDecode((await _stored())!), json);
      expect(ble.command.requests.last, {
        'cmd': 'release',
        'nonce': _nonce,
        'response': _signature,
      });
    },
  );

  test('release uses only its dedicated existing namespace key', () async {
    final other = LocalBenchProfile.enabled
        ? ''
        : '__calcai_bench_c62e_20261111__';
    SharedPreferences.setMockInitialValues({
      '${LocalBenchProfile.storagePrefix}$_key': 'old-process',
      '$other$_key': 'other-profile-preserved',
      'unrelated': 'preserved',
    });
    final ble = await _ready();
    expect(await _stored(), isNull);
    final prefs = await SharedPreferences.getInstance();
    final pairingKey =
        '${LocalBenchProfile.storagePrefix}paircomplete_ack_receipt_v1';
    await prefs.setString(pairingKey, 'distinct-command-preserved');
    expect(await _release(ble), isTrue);
    expect(await _stored(), isNotNull);
    expect(prefs.getString('$other$_key'), 'other-profile-preserved');
    expect(prefs.getString(pairingKey), 'distinct-command-preserved');
    expect(prefs.getString('unrelated'), 'preserved');
  });

  for (final reply in <String, Map<String, Object>>{
    'rejected': {'cmd': 'release', 'ok': false, 'error': 'bad_signature'},
    'missing success': {'cmd': 'release'},
    'wrong command': {'cmd': 'hello', 'ok': true},
  }.entries) {
    test(
      '${reply.key} release cannot clear the owner or mint a receipt',
      () async {
        final ble = await _ready();
        ble.command.releaseReply = () => reply.value;
        expect(await _release(ble), isFalse);
        await ble.settle();
        expect(ble.receipt(), isNull);
        expect(await _stored(), isNull);
        expect(ble.pairedOwner, _owner);
      },
    );
  }

  for (final thrown in [false, true]) {
    test(
      '${thrown ? 'thrown' : 'missing'} release ACK remains failure',
      () async {
        final ble = await _ready();
        ble.command.releaseReply = () {
          if (thrown) throw TimeoutException('Synthetic read timeout');
          return null;
        };
        expect(await _release(ble), isFalse);
        expect(ble.receipt(), isNull);
        expect(await _stored(), isNull);
        expect(ble.pairedOwner, _owner);
      },
    );
  }

  test(
    'generation changed during real ACK read cannot mint or succeed',
    () async {
      final ble = await _ready();
      ble.command.releaseReply = () {
        ble.epoch++;
        return {'cmd': 'release', 'ok': true};
      };
      expect(await _release(ble), isFalse);
      expect(ble.receipt(), isNull);
      expect(await _stored(), isNull);
      expect(ble.pairedOwner, _owner);
    },
  );

  test('missing verified identity cannot mint a release receipt', () async {
    final ble = await _ready(verify: false);
    expect(await _release(ble), isTrue);
    expect(ble.receipt(), isNull);
    expect(await _stored(), isNull);
  });

  test(
    'a verified identity for a different MAC cannot mint the receipt',
    () async {
      final ble = await _ready(verify: false);
      ble.identityMac = '112233aabbcd';
      expect(await ble.ensureDeviceVerified(), isTrue);
      expect(await _release(ble), isTrue);
      expect(ble.receipt(), isNull);
      expect(await _stored(), isNull);
    },
  );

  test('nonce from a prior connection is not receipt provenance', () async {
    final ble = await _ready();
    ble.epoch++;
    expect(await _release(ble), isTrue);
    expect(ble.receipt(), isNull);
    expect(await _stored(), isNull);
  });

  test(
    'caller supplied nonce without an actual relnonce cannot mint',
    () async {
      final ble = await _ready(requestNonce: false);
      expect(await _release(ble), isTrue);
      expect(ble.receipt(), isNull);
      expect(await _stored(), isNull);
    },
  );

  test(
    'legacy no-cmd acceptance keeps bool compatibility without inventing cmd',
    () async {
      final ble = await _ready();
      ble.command.releaseReply = () => {'ok': true};
      expect(await _release(ble), isTrue);
      expect(ble.pairedOwner, isNull);
      expect(ble.receipt(), isNull);
      expect(await _stored(), isNull);
    },
  );

  test('conflicting optional MAC cannot become a receipt', () async {
    final ble = await _ready();
    ble.command.releaseReply = () => {
      'cmd': 'release',
      'ok': true,
      'mac': '112233aabbcd',
    };
    expect(await _release(ble), isTrue);
    expect(ble.receipt(), isNull);
    expect(await _stored(), isNull);
  });

  test(
    'new release nonce invalidates prior receipt and retry stays supported',
    () async {
      final ble = await _ready();
      expect(await _release(ble), isTrue);
      final first = ble.receipt();
      expect(first, isNotNull);
      expect(await ble.requestReleaseNonce(), isNotNull);
      await ble.settle();
      expect(ble.receipt(), isNull);
      expect(await _stored(), isNull);
      ble.now = ble.now.add(const Duration(milliseconds: 10));
      expect(await _release(ble), isTrue);
      expect(ble.receipt().receiptId, isNot(first.receiptId));
      expect(ble.receipt().appSessionId, first.appSessionId);
      expect(ble.receipt().observedAt, first.observedAt + 10);
    },
  );

  test(
    'a second attempt cannot reuse nonce context or keep an old receipt',
    () async {
      final ble = await _ready();
      expect(await _release(ble), isTrue);
      expect(ble.receipt(), isNotNull);
      expect(await _release(ble), isTrue);
      expect(ble.receipt(), isNull);
      await ble.settle();
      expect(await _stored(), isNull);
    },
  );

  for (final action in ['disconnect', 'dispose', 'expired', 'clock-reversed']) {
    test(
      '$action invalidates release receipt without deleting other preferences',
      () async {
        final ble = await _ready();
        expect(await _release(ble), isTrue);
        expect(ble.receipt(), isNotNull);
        switch (action) {
          case 'disconnect':
            await ble.disconnect();
          case 'dispose':
            ble.dispose();
          case 'expired':
            ble.now = ble.now.add(const Duration(minutes: 5));
          case 'clock-reversed':
            ble.now = ble.now.subtract(const Duration(milliseconds: 1));
        }
        expect(ble.receipt(), isNull);
        await ble.settle();
        expect(await _stored(), isNull);
        expect(
          (await SharedPreferences.getInstance()).getString('unrelated'),
          'preserved',
        );
      },
    );
  }

  test(
    'receipt storage failure cannot fail the actual signed release',
    () async {
      SharedPreferencesStorePlatform.instance = _WriteFailure();
      final ble = await _ready();
      expect(await _release(ble), isTrue);
      expect(ble.pairedOwner, isNull);
      await ble.settle();
      expect(ble.receipt(), isNull);
      expect(await _stored(), isNull);
    },
  );
}
