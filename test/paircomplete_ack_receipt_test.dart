// Offline synthetic GATT/verifier/storage fixtures. No device or real account.
import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/pairing_v2.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/local_bench_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Fault injection into the existing preference plugin, without a new dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'pairing_v2_test.dart' as pairing;

const _key = 'paircomplete_ack_receipt_v1';
const _owner = 'synthetic-owner@example.com';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Map<String, dynamic> _ack() => {
  'ok': true,
  'cmd': 'paircomplete',
  'protocol': 2,
  'mac': pairing.mac,
  'challengeId': 'a' * 32,
  'ownershipId': pairing.ownership,
};

class _ReceiptBle extends BleService {
  bool connected = true;
  int epoch = 7;
  bool identityAccepted = true;
  int identityReads = 0;
  bool rejectApproval = false;
  DateTime now = DateTime.fromMillisecondsSinceEpoch(1791850000000);
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? completeReply;

  _ReceiptBle() {
    deviceVerifier = (_) async => identityAccepted;
  }

  @override
  DeviceConnectionState get connectionState => connected
      ? DeviceConnectionState.ready
      : DeviceConnectionState.disconnected;

  @override
  int get connectionGeneration => epoch;

  @override
  DateTime get ackReceiptNow => now;

  @override
  Future<DeviceChallenge?> requestIdentityChallenge() async {
    identityReads++;
    return DeviceChallenge(
      mac: pairing.mac,
      nonce: '1' * 32,
      response: '2' * 64,
    );
  }

  @override
  Future<Map<String, dynamic>?> sendPairingCommand(
    Map<String, dynamic> command,
  ) async => switch (command['cmd']) {
    'capabilities' => {'cmd': 'capabilities', 'pairingApprovalVersion': 2},
    'pairapprove' =>
      rejectApproval
          ? {'ok': false, 'cmd': 'pairapprove', 'error': 'bad_code'}
          : pairing.approvalData(),
    'paircomplete' =>
      completeReply == null ? _ack() : await completeReply!(command),
    _ => throw StateError('Unexpected synthetic command'),
  };

  @override
  Future<void> disconnect() async {
    connected = false;
    epoch++;
    await super.disconnect();
  }

  // Dynamic access also lets the two regression cases run against the unchanged
  // c3d24a0 baseline, where neither a return value nor a receipt exists.
  Future<void> settleReceiptStorage() async {
    try {
      await (this as dynamic).ackReceiptPersistenceSettled;
    } on NoSuchMethodError {
      // The baseline has no receipt producer.
    }
  }

  dynamic readReceipt() {
    try {
      return (this as dynamic).pairingAckReceipt;
    } on NoSuchMethodError {
      return null;
    }
  }
}

class _ReceiptWriteFailure extends InMemorySharedPreferencesStore {
  _ReceiptWriteFailure() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      key.endsWith(_key) ? false : super.setValue(valueType, key, value);
}

Future<_ReceiptBle> _ready({bool verify = true}) async {
  final ble = _ReceiptBle();
  addTearDown(() async {
    ble.dispose();
    await ble.settleReceiptStorage();
  });
  expect(await ble.negotiatePairing(), 2);
  if (verify) expect(await ble.ensureDeviceVerified(), isTrue);
  await ble.settleReceiptStorage();
  return ble;
}

Future<dynamic> _complete(_ReceiptBle ble) async {
  final offer = PairingOffer.fromJson(pairing.offerData(), pairing.mac);
  final approval = PairingApproval.fromJson(pairing.approvalData(), offer);
  final completion = PairingCompletion.fromJson(
    pairing.completionData(),
    offer,
  );
  return await (ble as dynamic).completePairing(
    offer,
    approval,
    completion,
    _owner,
  );
}

Future<String?> _stored() async => (await SharedPreferences.getInstance())
    .getString('${LocalBenchProfile.storagePrefix}$_key');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'unrelated': 'preserved'});
  });

  test('validated ACK returns only its bounded observed facts', () async {
    final ble = await _ready();
    ble.completeReply = (_) async => {
      ..._ack(),
      'signature': 'must-not-export',
      'approvalNonce': 'must-not-export',
      'token': 'must-not-export',
      'email': _owner,
      'firmware': 'unverified-extra-field',
      'identityFingerprint': 'unverified-extra-field',
    };
    final receipt = await _complete(ble);
    expect(receipt, isNotNull, reason: 'Future<void> discards the actual ACK');
    final json = receipt.toJson() as Map<String, Object>;
    expect(json, {
      'schema': 'calcai-paircomplete-ack/v1',
      'receiptId': matches(_uuid),
      ..._ack(),
      'connectionGeneration': '7',
      'appSessionId': matches(_uuid),
      'observedAt': ble.now.millisecondsSinceEpoch,
    });
    expect(jsonEncode(json).length, lessThan(1024));
    expect(jsonEncode(json), isNot(contains('must-not-export')));
    expect(jsonEncode(json), isNot(contains(_owner)));
    expect(() => json['ok'] = false, throwsUnsupportedError);
    expect(ble.readReceipt(), same(receipt));
    expect(ble.pairedOwner, _owner);
  });

  test('validated ACK persists in the existing isolated namespace', () async {
    final otherPrefix = LocalBenchProfile.enabled
        ? ''
        : '__calcai_bench_c62e_20261111__';
    SharedPreferences.setMockInitialValues({
      '${LocalBenchProfile.storagePrefix}$_key': 'old-process-receipt',
      '$otherPrefix$_key': 'other-namespace-preserved',
      'unrelated': 'preserved',
    });
    final ble = await _ready();
    expect(
      await _stored(),
      isNull,
      reason: 'Clear the previous process receipt',
    );
    final receipt = await _complete(ble);
    final stored = await _stored();
    expect(stored, isNotNull, reason: 'No producer bytes existed on c3d24a0');
    expect(jsonDecode(stored!), receipt.toJson());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('$otherPrefix$_key'), 'other-namespace-preserved');
    expect(prefs.getString('unrelated'), 'preserved');
  });

  final rejected = <String, Map<String, dynamic>>{
    'explicit failure': {..._ack(), 'ok': false},
    'missing success': {..._ack()}..remove('ok'),
    'wrong command': {..._ack(), 'cmd': 'pairapprove'},
    'missing command': {..._ack()}..remove('cmd'),
    'wrong protocol': {..._ack(), 'protocol': 1},
    'non-integer protocol': {..._ack(), 'protocol': 2.0},
    'wrong MAC': {..._ack(), 'mac': '112233aabbcd'},
    'stale challenge': {..._ack(), 'challengeId': 'b' * 32},
    'old ownership': {..._ack(), 'ownershipId': 'old-ownership'},
    'missing ownership': {..._ack()}..remove('ownershipId'),
  };
  for (final failure in rejected.entries) {
    test('${failure.key} cannot produce or retain a receipt', () async {
      final ble = await _ready();
      ble.completeReply = (_) async => failure.value;
      await expectLater(_complete(ble), throwsA(isA<PairingV2Exception>()));
      await ble.settleReceiptStorage();
      expect(ble.readReceipt(), isNull);
      expect(await _stored(), isNull);
      expect(ble.pairedOwner, isNull);
    });
  }

  for (final timeout in [false, true]) {
    test(
      '${timeout ? 'thrown' : 'missing'} ACK never produces a receipt',
      () async {
        final ble = await _ready();
        ble.completeReply = (_) async {
          if (timeout) throw TimeoutException('synthetic GATT read timeout');
          return null;
        };
        await expectLater(_complete(ble), throwsA(isA<Exception>()));
        await ble.settleReceiptStorage();
        expect(ble.readReceipt(), isNull);
        expect(await _stored(), isNull);
        expect(ble.pairedOwner, isNull);
      },
    );
  }

  test('new attempt clears a previous ACK before the pending reply', () async {
    final ble = await _ready();
    expect(await _complete(ble), isNotNull);
    final pending = Completer<Map<String, dynamic>?>();
    ble.completeReply = (_) => pending.future;
    final next = _complete(ble);
    await ble.settleReceiptStorage();
    expect(ble.readReceipt(), isNull);
    expect(await _stored(), isNull);
    pending.complete(null);
    await expectLater(next, throwsA(isA<PairingV2Exception>()));
  });

  test('changed connection rejects an otherwise matching late ACK', () async {
    final ble = await _ready();
    final pending = Completer<Map<String, dynamic>?>();
    ble.completeReply = (_) => pending.future;
    final result = _complete(ble);
    ble.epoch++;
    pending.complete(_ack());
    await expectLater(result, throwsA(isA<PairingV2Exception>()));
    await ble.settleReceiptStorage();
    expect(ble.readReceipt(), isNull);
    expect(await _stored(), isNull);
    expect(ble.pairedOwner, isNull);
  });

  test('late prior attempt cannot overwrite the newer receipt', () async {
    final ble = await _ready();
    final pending = Completer<Map<String, dynamic>?>();
    var calls = 0;
    ble.completeReply = (_) =>
        ++calls == 1 ? pending.future : Future.value(_ack());
    final old = _complete(ble);
    final current = await _complete(ble);
    expect(current, isNotNull);
    pending.complete(_ack());
    expect(await old, isNull);
    expect(ble.readReceipt(), same(current));
    expect(jsonDecode((await _stored())!), current.toJson());
  });

  test(
    'disconnect notified during owner update cannot retain the ACK',
    () async {
      final ble = await _ready();
      var disconnected = false;
      void listener() {
        if (ble.pairedOwner != null && !disconnected) {
          disconnected = true;
          unawaited(ble.disconnect());
        }
      }

      ble.addListener(listener);
      expect(await _complete(ble), isNull);
      ble.removeListener(listener);
      await ble.settleReceiptStorage();
      expect(disconnected, isTrue);
      expect(ble.readReceipt(), isNull);
      expect(await _stored(), isNull);
    },
  );

  test('matching ACK alone is not identity verification', () async {
    final ble = await _ready(verify: false);
    expect(await _complete(ble), isNull);
    expect(ble.readReceipt(), isNull);
    expect(await _stored(), isNull);
    // Receipt availability never becomes the customer ownership gate.
    expect(ble.pairedOwner, _owner);
  });

  test(
    'cached verification from another generation cannot mint a receipt',
    () async {
      final ble = await _ready();
      ble.epoch++;
      expect(await _complete(ble), isNull);
      expect(await _stored(), isNull);
      expect(await ble.ensureDeviceVerified(), isTrue);
      expect(ble.identityReads, 2);
      expect(await _complete(ble), isNotNull);
    },
  );

  test(
    'rejected approval clears the prior ACK and keeps the rejection',
    () async {
      final ble = await _ready();
      expect(await _complete(ble), isNotNull);
      ble.rejectApproval = true;
      await expectLater(
        ble.approvePairing(
          PairingOffer.fromJson(pairing.offerData(), pairing.mac),
          '000000',
        ),
        throwsA(isA<PairingV2Exception>()),
      );
      await ble.settleReceiptStorage();
      expect(ble.readReceipt(), isNull);
      expect(await _stored(), isNull);
    },
  );

  for (final action in ['disconnect', 'clearUserState']) {
    test('$action clears memory and the dedicated preference only', () async {
      final ble = await _ready();
      expect(await _complete(ble), isNotNull);
      if (action == 'disconnect') {
        await ble.disconnect();
      } else {
        await ble.clearUserState();
      }
      await ble.settleReceiptStorage();
      expect(ble.readReceipt(), isNull);
      expect(await _stored(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('unrelated'),
        'preserved',
      );
    });
  }

  for (final age in [-1, 300000]) {
    test('receipt becomes unavailable at invalid age $age ms', () async {
      final ble = await _ready();
      expect(await _complete(ble), isNotNull);
      ble.now = ble.now.add(Duration(milliseconds: age));
      expect(ble.readReceipt(), isNull);
      await ble.settleReceiptStorage();
      expect(await _stored(), isNull);
    });
  }

  test(
    'repeat legitimate ACK has a new receipt but the same app session',
    () async {
      final ble = await _ready();
      final first = await _complete(ble);
      ble.now = ble.now.add(const Duration(milliseconds: 10));
      final second = await _complete(ble);
      expect(second.receiptId, isNot(first.receiptId));
      expect(second.appSessionId, first.appSessionId);
      expect(second.ownershipId, first.ownershipId);
      expect(second.observedAt, first.observedAt + 10);
      expect(jsonDecode((await _stored())!), second.toJson());
    },
  );

  test(
    'unavailable receipt storage holds the receipt, not customer pairing',
    () async {
      SharedPreferencesStorePlatform.instance = _ReceiptWriteFailure();
      final ble = await _ready();
      expect(await _complete(ble), isNull);
      await ble.settleReceiptStorage();
      expect(ble.readReceipt(), isNull);
      expect(await _stored(), isNull);
      expect(ble.pairedOwner, _owner);
    },
  );
}
