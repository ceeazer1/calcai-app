import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Contract: evidence/APP-PORTAL-CLOSE-CONTRACT.txt. The real BleService
// connection, command queue, GATT request/read parsing, generation guard and
// local disconnect run. Firmware authorization and GATT I/O are synthetic;
// acceptance here proves neither radio shutdown nor a TI physical screen.
const _serviceUuid = '021a9004-0382-4aea-bff4-6b3f1c5adfb4';
const _commandUuid = '021a9006-0382-4aea-bff4-6b3f1c5adfb4';
const _request = {'cmd': 'uimode', 'mode': 'closed'};
const _accepted = {'cmd': 'uimode', 'ok': true, 'mode': 'closed'};

List<int> _bytes(Object? value) => utf8.encode(jsonEncode(value));

class _CommandCharacteristic implements BluetoothCharacteristic {
  final requests = <Map<String, dynamic>>[];
  final rawRequests = <List<int>>[];
  List<int> reply = const [];
  List<int> cachedValue = const [];
  int reads = 0;
  FutureOr<void> Function(Map<String, dynamic>)? onWrite;
  FutureOr<List<int>> Function()? onRead;

  @override
  Guid get uuid => Guid(_commandUuid);
  @override
  CharacteristicProperties get properties =>
      CharacteristicProperties(read: true, write: true);
  @override
  List<int> get lastValue => cachedValue;
  @override
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    rawRequests.add(List<int>.of(value));
    final request = Map<String, dynamic>.from(jsonDecode(utf8.decode(value)));
    requests.add(request);
    await onWrite?.call(request);
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    reads++;
    return onRead == null ? reply : await onRead!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Peripheral implements BluetoothDevice {
  _Peripheral(this.label, this.command);
  final String label;
  final _CommandCharacteristic command;
  final connections = StreamController<BluetoothConnectionState>.broadcast(
    sync: true,
  );
  int localDisconnects = 0;

  @override
  DeviceIdentifier get remoteId => DeviceIdentifier('portal-fixture-$label');
  @override
  String get platformName => 'Offline CalcAI portal fixture';
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #connect) return Future<void>.value();
    if (invocation.memberName == #disconnect) {
      localDisconnects++;
      return Future<void>.value();
    }
    if (invocation.memberName == #connectionState) return connections.stream;
    if (invocation.memberName == #discoverServices) {
      return Future.value([
        _Service([command]),
      ]);
    }
    return super.noSuchMethod(invocation);
  }
}

class _Service implements BluetoothService {
  _Service(this.characteristics);
  @override
  final List<BluetoothCharacteristic> characteristics;
  @override
  Guid get uuid => Guid(_serviceUuid);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ble extends BleService {
  // Discovery is synthetic. No close, command, auth, generation or disconnect
  // method is overridden, so tests cannot manufacture a successful close.
  @override
  Future<void> stopScan() async {}
}

class _Fixture {
  final ble = _Ble();
  _CommandCharacteristic command = _CommandCharacteristic();
  final peripherals = <_Peripheral>[];
  _Peripheral get peripheral => peripherals.last;

  Future<void> connect() async {
    final device = _Peripheral(peripherals.length.toString(), command);
    peripherals.add(device);
    await ble.connectToDevice(
      CalcAiDevice(device: device, rssi: -45, advertisementName: 'Offline'),
      attempts: 1,
    );
    expect(ble.connectionState, DeviceConnectionState.ready);
  }

  Future<void> replacement() async {
    command = _CommandCharacteristic();
    await connect();
  }

  Future<void> dispose() async {
    ble.dispose();
    for (final device in peripherals) {
      await device.connections.close();
    }
  }
}

class _Pending {
  _Pending(Future<bool> operation) {
    observed = operation.then((value) {
      done = true;
      result = value;
      return value;
    });
  }
  bool done = false;
  bool? result;
  late final Future<bool> observed;
}

Future<_Fixture> _fixture() async {
  SharedPreferences.setMockInitialValues({});
  final fixture = _Fixture();
  addTearDown(fixture.dispose);
  await fixture.connect();
  return fixture;
}

// Drain real-zone mock transport/persistence completions between fake-clock
// steps. These are bounded fixture scheduling operations, not device sleeps.
Future<void> _drainTransport(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

Future<void> _finish(WidgetTester tester, _Pending pending) async {
  for (var step = 0; step < 80 && !pending.done; step++) {
    await tester.pump(const Duration(milliseconds: 100));
    await _drainTransport(tester);
  }
  expect(
    pending.done,
    isTrue,
    reason: 'Portal operation must settle boundedly',
  );
  await pending.observed;
}

void _exactRequest(_CommandCharacteristic command) {
  expect(command.requests, [_request]);
  expect(
    utf8.decode(command.rawRequests.single),
    '{"cmd":"uimode","mode":"closed"}',
  );
}

void main() {
  for (final reply in [
    '{"cmd":"uimode","ok":true,"mode":"closed"}',
    '{"mode":"closed","ok":true,"cmd":"uimode"}',
  ]) {
    testWidgets('exact closed acceptance allows local disconnect: $reply', (
      tester,
    ) async {
      final fixture = await _fixture();
      final generation = fixture.ble.connectionGeneration;
      expect(
        fixture.ble.pairedOwner,
        isNull,
      ); // Unclaimed cancellation remains.
      fixture.command.reply = utf8.encode(reply);
      final pending = _Pending(fixture.ble.closeBlePortal());
      await _finish(tester, pending);
      _exactRequest(fixture.command);
      expect(pending.result, isTrue);
      expect(fixture.command.reads, 1);
      expect(fixture.peripheral.localDisconnects, 1);
      expect(fixture.ble.connectionState, DeviceConnectionState.disconnected);
      expect(fixture.ble.connectionGeneration, greaterThan(generation));
    });
  }

  testWidgets('exact acceptance works after synthetic owner authentication', (
    tester,
  ) async {
    final fixture = await _fixture();
    fixture.command.onRead = () =>
        _bytes(switch (fixture.command.requests.last['cmd']) {
          'hello' => {'cmd': 'hello', 'ok': true},
          'list' => [
            {'ssid': 'Guest', 'slot': 1},
          ],
          _ => throw StateError('Unexpected synthetic auth request'),
        });
    final authentication = _Pending(
      fixture.ble.proveOwnership(
        'fixture-nonce',
        'fixture-proof',
        'fixture-owner',
      ),
    );
    await _finish(tester, authentication);
    expect(authentication.result, isTrue);
    expect(fixture.ble.pairedOwner, 'fixture-owner');
    fixture.command.requests.clear();
    fixture.command.rawRequests.clear();
    fixture.command.reads = 0;
    fixture.command.onRead = null;
    fixture.command.reply = _bytes(_accepted);
    final pending = _Pending(fixture.ble.closeBlePortal());
    await _finish(tester, pending);
    _exactRequest(fixture.command);
    expect(pending.result, isTrue);
    expect(fixture.peripheral.localDisconnects, 1);
    expect(fixture.ble.connectionState, DeviceConnectionState.disconnected);
  });

  final rejected = <String, Object?>{
    'missing cmd': {'ok': true, 'mode': 'closed'},
    'numeric cmd': {'cmd': 7, 'ok': true, 'mode': 'closed'},
    'null cmd': {'cmd': null, 'ok': true, 'mode': 'closed'},
    'another command': {'cmd': 'pairinfo', 'ok': true, 'mode': 'closed'},
    'normal mode': {'cmd': 'uimode', 'ok': true, 'mode': 'normal'},
    'explicit rejection': {'cmd': 'uimode', 'ok': false, 'mode': 'closed'},
    'string ok': {'cmd': 'uimode', 'ok': 'true', 'mode': 'closed'},
    'empty object': <String, Object?>{},
  };
  for (final entry in rejected.entries) {
    testWidgets('does not disconnect for ${entry.key}', (tester) async {
      final fixture = await _fixture();
      final generation = fixture.ble.connectionGeneration;
      fixture.command.reply = _bytes(entry.value);
      final pending = _Pending(fixture.ble.closeBlePortal());
      await _finish(tester, pending);
      _exactRequest(fixture.command);
      expect(pending.result, isFalse);
      expect(fixture.peripheral.localDisconnects, 0);
      expect(fixture.ble.connectionState, DeviceConnectionState.ready);
      expect(fixture.ble.connectionGeneration, generation);
    });
  }

  testWidgets(
    'write ACK and old cached acceptance cannot replace an empty read',
    (tester) async {
      final fixture = await _fixture();
      fixture.command.cachedValue = _bytes(_accepted);
      fixture.command.reply = const [];
      final pending = _Pending(fixture.ble.closeBlePortal());
      await tester.pump();
      await _drainTransport(tester);
      _exactRequest(fixture.command);
      expect(pending.done, isFalse);
      expect(fixture.command.reads, 0);
      expect(fixture.peripheral.localDisconnects, 0);
      await _finish(tester, pending);
      expect(pending.result, isFalse);
      expect(fixture.command.reads, 4);
      expect(fixture.peripheral.localDisconnects, 0);
      expect(fixture.ble.connectionState, DeviceConnectionState.ready);
    },
  );

  testWidgets('malformed response is not accepted as a portal close', (
    tester,
  ) async {
    final fixture = await _fixture();
    fixture.command.reply = utf8.encode('{');
    final pending = _Pending(fixture.ble.closeBlePortal());
    await _finish(tester, pending);
    _exactRequest(fixture.command);
    expect(pending.result, isFalse);
    expect(fixture.peripheral.localDisconnects, 0);
    expect(fixture.ble.connectionState, DeviceConnectionState.ready);
  });

  testWidgets('generation replacement during write prevents old acceptance', (
    tester,
  ) async {
    final fixture = await _fixture();
    final oldCommand = fixture.command;
    final oldPeripheral = fixture.peripheral;
    final write = Completer<void>();
    oldCommand.onWrite = (_) => write.future;
    oldCommand.reply = _bytes(_accepted);
    final pending = _Pending(fixture.ble.closeBlePortal());
    await tester.pump();
    _exactRequest(oldCommand);
    expect(pending.done, isFalse);
    await fixture.replacement();
    final replacement = fixture.peripheral;
    write.complete();
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    expect(oldPeripheral.localDisconnects, 0);
    expect(replacement.localDisconnects, 0);
    expect(fixture.ble.connectionState, DeviceConnectionState.ready);
    expect(fixture.ble.connectedDevice?.id, replacement.remoteId.str);
  });

  testWidgets(
    'late old read cannot close replacement or satisfy its next close',
    (tester) async {
      final fixture = await _fixture();
      final oldCommand = fixture.command;
      final oldPeripheral = fixture.peripheral;
      final oldReply = Completer<List<int>>();
      oldCommand.onRead = () => oldReply.future;
      final oldClose = _Pending(fixture.ble.closeBlePortal());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await _drainTransport(tester);
      _exactRequest(oldCommand);
      expect(oldCommand.reads, 1);
      expect(oldClose.done, isFalse);
      await fixture.replacement();
      final replacement = fixture.peripheral;
      final ownReply = Completer<List<int>>();
      fixture.command.onRead = () => ownReply.future;
      final replacementClose = _Pending(fixture.ble.closeBlePortal());
      await tester.pump();
      oldReply.complete(_bytes(_accepted));
      await _finish(tester, oldClose);
      expect(oldClose.result, isFalse);
      await tester.pump(const Duration(milliseconds: 250));
      await _drainTransport(tester);
      _exactRequest(fixture.command);
      expect(fixture.command.reads, 1);
      expect(replacementClose.done, isFalse);
      expect(oldPeripheral.localDisconnects, 0);
      expect(replacement.localDisconnects, 0);
      expect(fixture.ble.connectionState, DeviceConnectionState.ready);
      ownReply.complete(_bytes(_accepted));
      await _finish(tester, replacementClose);
      expect(replacementClose.result, isTrue);
      expect(oldPeripheral.localDisconnects, 0);
      expect(replacement.localDisconnects, 1);
      expect(fixture.ble.connectionState, DeviceConnectionState.disconnected);
    },
  );
}
