import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mac = '112233aabbcc';
const savedReply = [
  {'ssid': 'Home', 'slot': 2, 'iphoneHotspot': true},
];
const scanReply = [
  {'ssid': 'Guest', 'rssi': -50, 'secured': false},
];

class ReplyCharacteristic implements BluetoothCharacteristic {
  final commands = <String>[];
  String command = '';
  int reads = 0;
  Future<List<int>> Function(String command, int read)? reply;

  @override
  CharacteristicProperties get properties =>
      const CharacteristicProperties(read: true, write: true);

  @override
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    command = (jsonDecode(utf8.decode(value)) as Map)['cmd'] as String;
    commands.add(command);
    reads = 0;
  }

  @override
  Future<List<int>> read({int timeout = 15}) async =>
      reply == null ? jsonBytes([]) : reply!(command, ++reads);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReplyBle extends BleService {
  final characteristic = ReplyCharacteristic();
  @override
  BluetoothCharacteristic get commandCharacteristic => characteristic;
  @override
  DeviceConnectionState get connectionState => DeviceConnectionState.ready;
}

List<int> jsonBytes(Object value) => utf8.encode(jsonEncode(value));

Future<ReplyBle> service() async {
  SharedPreferences.setMockInitialValues({
    'saved_networks_$mac': jsonEncode(['Cached']),
    'iphone_hotspots_$mac': jsonEncode(['Cached']),
  });
  final ble = ReplyBle();
  await ble.loadPersistedNetworks(mac);
  addTearDown(ble.dispose);
  return ble;
}

Future<void> finish(WidgetTester tester, Future<void> operation) async {
  var complete = false;
  final observed = operation.whenComplete(() => complete = true);
  for (var i = 0; i < 120 && !complete; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(
    complete,
    isTrue,
    reason: 'BLE operation must finish within its bound',
  );
  await observed;
}

Future<void> expectCacheUntouched(ReplyBle ble) async {
  expect(ble.savedNetworks, ['Cached']);
  expect(ble.iphoneHotspotNetworks, {'Cached'});
  final prefs = await SharedPreferences.getInstance();
  expect(jsonDecode(prefs.getString('saved_networks_$mac')!), ['Cached']);
  expect(jsonDecode(prefs.getString('iphone_hotspots_$mac')!), ['Cached']);
}

void main() {
  testWidgets('late hello reply cannot authenticate a replacement generation', (
    tester,
  ) async {
    final ble = _OwnershipReplyBle();
    addTearDown(ble.dispose);
    final reply = Completer<List<int>>();
    ble.characteristic.reply = (_, _) => reply.future;
    final proof = ble.proveOwnership('nonce', 'signature', 'owner');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await ble.disconnect();
    reply.complete(jsonBytes({'cmd': 'hello', 'ok': true}));
    await tester.pump();
    expect(await proof, false);
    expect(ble.pairedOwner, null);
    expect(ble.savedReads, 0);
  });

  testWidgets(
    'disconnect during post-hello list invalidates ownership result',
    (tester) async {
      final ble = _OwnershipReplyBle();
      addTearDown(ble.dispose);
      ble.characteristic.reply = (_, _) async =>
          jsonBytes({'cmd': 'hello', 'ok': true});
      final proof = ble.proveOwnership('nonce', 'signature', 'owner');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(ble.pairedOwner, 'owner');
      expect(ble.savedReads, 1);
      await ble.disconnect();
      ble.savedReply.complete();
      await tester.pump();
      expect(await proof, false);
      expect(ble.pairedOwner, null);
    },
  );
  testWidgets(
    'queued empty sentinel cannot erase saved cache before real reply',
    (tester) async {
      final ble = await service();
      ble.characteristic.reply = (_, read) async =>
          jsonBytes(read < 4 ? [] : savedReply);
      final request = ble.requestSavedNetworks();
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        await expectCacheUntouched(ble);
        expect(ble.savedNetworksLoading, isTrue);
      }
      await finish(tester, request);
      expect(ble.savedNetworks, ['Home']);
      expect(ble.iphoneHotspotNetworks, {'Home'});
      expect(ble.savedNetworksError, isNull);
      expect(ble.savedNetworksLoading, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('saved_networks_$mac')!), ['Home']);
    },
  );

  for (final response in [
    [],
    scanReply,
    [
      {'ssid': 'Bad', 'slot': '2'},
    ],
    [
      savedReply.first,
      {'ssid': null, 'slot': 3},
    ],
    {'cmd': 'uimode', 'ok': true},
  ]) {
    testWidgets(
      'ambiguous or wrong-shaped list preserves both caches: $response',
      (tester) async {
        final ble = await service();
        ble.characteristic.reply = (_, _) async => jsonBytes(response);
        await finish(tester, ble.requestSavedNetworks());
        await expectCacheUntouched(ble);
        expect(ble.savedNetworksError, contains('Could not confirm'));
        expect(ble.savedNetworksLoading, isFalse);
      },
    );
  }

  testWidgets(
    'device error and BLE read failure are visible and retry recovers',
    (tester) async {
      final ble = await service();
      ble.characteristic.reply = (_, _) async =>
          jsonBytes({'error': 'storage_failed'});
      await finish(tester, ble.requestSavedNetworks());
      await expectCacheUntouched(ble);
      expect(ble.savedNetworksError, contains('could not read'));
      expect(ble.characteristic.reads, 1);

      ble.characteristic.reply = (_, _) async => throw StateError('link lost');
      await finish(tester, ble.requestSavedNetworks());
      await expectCacheUntouched(ble);
      expect(ble.savedNetworksError, contains('Reconnect'));

      ble.characteristic.reply = (_, _) async => jsonBytes(savedReply);
      await finish(tester, ble.requestSavedNetworks());
      expect(ble.savedNetworksError, isNull);
      expect(ble.savedNetworks, ['Home']);
    },
  );

  testWidgets(
    'scan and saved-list commands cannot interleave on the characteristic',
    (tester) async {
      final ble = await service();
      final scanRead = Completer<List<int>>();
      ble.characteristic.reply = (command, _) async =>
          command == 'scan' ? scanRead.future : jsonBytes(savedReply);
      final scan = ble.requestWifiScan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final list = ble.requestSavedNetworks();
      await tester.pump();
      expect(ble.characteristic.commands, ['scan']);
      scanRead.complete(jsonBytes(scanReply));
      await finish(tester, Future.wait([scan, list]));
      expect(ble.characteristic.commands, ['scan', 'list']);
      expect(ble.wifiNetworks.single.ssid, 'Guest');
      expect(ble.savedNetworks, ['Home']);
    },
  );

  testWidgets('saved-list wait also holds scan and ordinary command writes', (
    tester,
  ) async {
    final ble = await service();
    final listRead = Completer<List<int>>();
    ble.characteristic.reply = (command, _) async => switch (command) {
      'list' => listRead.future,
      'scan' => jsonBytes(scanReply),
      _ => jsonBytes({'cmd': 'pairinfo', 'paired': true}),
    };
    final list = ble.requestSavedNetworks();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final scan = ble.requestWifiScan();
    final info = ble.isDevicePaired();
    await tester.pump();
    expect(ble.characteristic.commands, ['list']);
    listRead.complete(jsonBytes(savedReply));
    await finish(tester, Future.wait([list, scan, info]));
    expect(ble.characteristic.commands, ['list', 'scan', 'pairinfo']);
    expect(await info, isTrue);
  });

  testWidgets('scan ignores saved-list rows and queued empty replies', (
    tester,
  ) async {
    final ble = await service();
    ble.characteristic.reply = (_, read) async => jsonBytes(
      read == 1
          ? savedReply
          : read == 2
          ? []
          : scanReply,
    );
    await finish(tester, ble.requestWifiScan());
    expect(ble.wifiNetworks.single.ssid, 'Guest');
    expect(ble.provisioningState, ProvisioningState.idle);
    await expectCacheUntouched(ble);
  });

  testWidgets(
    'ambiguous empty scan times out as unconfirmed, not a successful empty scan',
    (tester) async {
      final ble = await service();
      await finish(tester, ble.requestWifiScan());
      expect(ble.provisioningState, ProvisioningState.failed);
      expect(ble.error, contains('Could not confirm'));
      await expectCacheUntouched(ble);
    },
  );

  testWidgets(
    'scan rejection is reported without parsing an error as a network',
    (tester) async {
      final ble = await service();
      ble.characteristic.reply = (_, _) async =>
          jsonBytes({'error': 'unauthorized'});
      await finish(tester, ble.requestWifiScan());
      expect(ble.provisioningState, ProvisioningState.failed);
      expect(ble.error, contains('Reconnect'));
      expect(ble.wifiNetworks, isEmpty);
      expect(ble.characteristic.reads, 1);
    },
  );

  testWidgets(
    'disconnect invalidates pending reply and commands queued on the old link',
    (tester) async {
      final ble = await service();
      final oldRead = Completer<List<int>>();
      ble.characteristic.reply = (_, _) => oldRead.future;
      final list = ble.requestSavedNetworks();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final scan = ble.requestWifiScan();
      final anotherList = ble.requestSavedNetworks();
      await ble.disconnect();
      oldRead.complete(jsonBytes(savedReply));
      await finish(tester, Future.wait([list, scan, anotherList]));
      expect(ble.characteristic.commands, ['list']);
      expect(ble.savedNetworksLoading, isFalse);
      await expectCacheUntouched(ble);
    },
  );

  testWidgets(
    'leaving Wi-Fi cancels pending scan polling and permits normal-mode command',
    (tester) async {
      final ble = await service();
      ble.characteristic.reply = (command, _) async => jsonBytes(
        command == 'scan'
            ? []
            : {'cmd': 'uimode', 'ok': true, 'mode': 'normal'},
      );
      final scan = ble.requestWifiScan();
      await tester.pump();
      final exit = ble.endWifiUiMode();
      await finish(tester, Future.wait([scan, exit]));
      expect(ble.characteristic.commands, ['scan', 'uimode']);
      expect(ble.provisioningState, ProvisioningState.idle);
      await expectCacheUntouched(ble);
    },
  );
}

class _OwnershipReplyBle extends ReplyBle {
  int savedReads = 0;
  final savedReply = Completer<void>();
  @override
  Future<void> requestSavedNetworks() {
    savedReads++;
    return savedReply.future;
  }
}
