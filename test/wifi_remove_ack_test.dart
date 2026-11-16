import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/screens/wifi_screen.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Exact firmware contract: evidence/IOS-REMOVAL-CONTRACT.txt. All transports
// below are in-memory. Real BleService connection discovery/removal/cache code
// runs; no CoreBluetooth, phone, account, NVS or firmware execution is claimed.
const _mac = '112233aabbcc';
const _serviceUuid = '021a9004-0382-4aea-bff4-6b3f1c5adfb4';
const _scanUuid = '021a9006-0382-4aea-bff4-6b3f1c5adfb4';
const _configUuid = '021a9007-0382-4aea-bff4-6b3f1c5adfb4';
const _statusUuid = '021a9008-0382-4aea-bff4-6b3f1c5adfb4';
final _boundary = GlobalKey();

List<int> _bytes(Object? value) => utf8.encode(jsonEncode(value));
const _removed = {'status': 'removed', 'ssid': 'Home'};
const _storageFailed = {
  'status': 'failed',
  'ssid': 'Home',
  'error': 'storage_failed',
};

class _Characteristic implements BluetoothCharacteristic {
  _Characteristic(this.id, {this.notify = false});
  final String id;
  bool notify;
  bool notifying = false;
  final events = StreamController<List<int>>.broadcast(sync: true);
  List<int> cached = const [];
  final writes = <Map<String, dynamic>>[];
  final reliableWrites = <bool>[];
  int reads = 0;
  int freshSubscriptions = 0;
  FutureOr<void> Function(Map<String, dynamic>)? onWrite;
  FutureOr<void> Function()? onSubscribe;
  FutureOr<List<int>> Function()? onRead;
  bool failSubscribe = false;

  void emit(Object? value) => events.add(_bytes(value));
  void emitRaw(List<int> value) => events.add(value);

  @override
  Guid get uuid => Guid(id);
  @override
  CharacteristicProperties get properties =>
      CharacteristicProperties(read: true, write: true, notify: notify);
  @override
  List<int> get lastValue => cached;
  @override
  Stream<List<int>> get lastValueStream async* {
    yield cached; // Mirrors the plugin's cached-value replay.
    yield* events.stream;
  }

  @override
  Stream<List<int>> get onValueReceived {
    freshSubscriptions++;
    return events.stream; // Deliberately does not replay cached reads.
  }

  @override
  bool get isNotifying => notifying;
  @override
  Future<bool> setNotifyValue(
    bool enabled, {
    int timeout = 15,
    bool forceIndications = false,
  }) async {
    if (failSubscribe) throw StateError('fixture notify setup failed');
    notifying = enabled;
    await onSubscribe?.call();
    return true;
  }

  @override
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    final request = Map<String, dynamic>.from(jsonDecode(utf8.decode(value)));
    writes.add(request);
    reliableWrites.add(!withoutResponse);
    await onWrite?.call(request);
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    reads++;
    return onRead == null ? cached : await onRead!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Peripheral implements BluetoothDevice {
  _Peripheral(this.name, this.scan, this.config, this.status);
  @override
  final String name;
  final _Characteristic scan, config, status;
  final connections = StreamController<BluetoothConnectionState>.broadcast();
  @override
  DeviceIdentifier get remoteId => DeviceIdentifier('fixture-$name');
  @override
  String get platformName => 'Offline CalcAI fixture';
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #connect ||
        invocation.memberName == #disconnect) {
      return Future<void>.value();
    }
    if (invocation.memberName == #connectionState) return connections.stream;
    if (invocation.memberName == #discoverServices) {
      return Future.value([
        _Service([scan, config, status]),
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
  // Authentication is a fixture boundary. The actual removal implementation,
  // generation lifecycle, characteristic resolution and cache paths run.
  String? owner = 'offline-fixture-owner';
  @override
  String? get pairedOwner => owner;
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> endWifiUiMode() async {}
  @override
  Future<bool> ensureDeviceVerified() async => true;
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

class _Fixture {
  final ble = _Ble();
  _Characteristic scan = _Characteristic(_scanUuid);
  _Characteristic config = _Characteristic(_configUuid);
  _Characteristic status = _Characteristic(_statusUuid, notify: true);
  final peripherals = <_Peripheral>[];
  final retired = <_Characteristic>[];
  bool disposed = false;

  Future<void> connect() async {
    final peripheral = _Peripheral(
      peripherals.length.toString(),
      scan,
      config,
      status,
    );
    peripherals.add(peripheral);
    scan.onRead = () => _bytes(switch (scan.writes.last['cmd']) {
      'list' => [
        for (final ssid in ble.savedNetworks)
          {'ssid': ssid, 'slot': ssid == 'Home' ? 1 : 2},
      ],
      'scan' => [
        {'ssid': 'Visible', 'rssi': -45, 'secured': false},
      ],
      _ => {'cmd': scan.writes.last['cmd'], 'ok': true},
    });
    await ble.connectToDevice(
      CalcAiDevice(device: peripheral, rssi: -45, advertisementName: 'Offline'),
      attempts: 1,
    );
    expect(ble.connectionState, DeviceConnectionState.ready);
  }

  Future<void> replacement() async {
    retired.addAll([scan, config, status]);
    scan = _Characteristic(_scanUuid);
    config = _Characteristic(_configUuid);
    status = _Characteristic(_statusUuid, notify: true);
    await connect();
  }

  Future<void> close() async {
    if (!disposed) {
      disposed = true;
      ble.dispose();
    }
    for (final p in peripherals) {
      await p.connections.close();
    }
    for (final c in [scan, config, status, ...retired]) {
      await c.events.close();
    }
  }
}

Future<_Fixture> _fixture({Object? cachedStatus}) async {
  SharedPreferences.setMockInitialValues({
    'saved_networks_$_mac': jsonEncode(['Home', 'Guest']),
    'iphone_hotspots_$_mac': jsonEncode(['Home']),
  });
  final f = _Fixture();
  if (cachedStatus != null) f.status.cached = _bytes(cachedStatus);
  await f.ble.loadPersistedNetworks(_mac);
  await f.connect();
  addTearDown(f.close);
  return f;
}

Future<void> _retained(_Fixture f) async {
  expect(f.ble.savedNetworks, ['Home', 'Guest']);
  expect(f.ble.iphoneHotspotNetworks, {'Home'});
  final prefs = await SharedPreferences.getInstance();
  expect(jsonDecode(prefs.getString('saved_networks_$_mac')!), [
    'Home',
    'Guest',
  ]);
  expect(jsonDecode(prefs.getString('iphone_hotspots_$_mac')!), ['Home']);
}

// Mock transport/persistence futures can complete in the real async zone.
// Drain those completions between fake-clock steps; no hardware is involved.
Future<void> _drainTransport(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

Future<void> _finish(WidgetTester tester, _Pending pending) async {
  for (var i = 0; i < 160 && !pending.done; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await _drainTransport(tester);
  }
  expect(
    pending.done,
    isTrue,
    reason: 'Removal must settle within its deadline',
  );
  await pending.observed;
}

Future<void> _screen(
  WidgetTester tester,
  _Fixture f, {
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(
    scale == 1 ? 800 : 320,
    scale == 1 ? 1000 : 568,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider<BleService>.value(
      value: f.ble,
      child: RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const WifiScreen(isActive: false),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<Map<String, Object?>> _geometry(
  WidgetTester tester,
  Finder text,
  double scale,
) async {
  await tester.ensureVisible(text);
  await tester.pump(const Duration(milliseconds: 300));
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final intrinsic = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
  final rect = tester.getRect(text);
  final viewport = tester.getRect(
    find
        .ancestor(
          of: text,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomScrollView || widget is SingleChildScrollView,
          ),
        )
        .first,
  );
  expect(
    paragraph.size.height + 0.01,
    greaterThanOrEqualTo(intrinsic),
    reason: 'Full requested text must fit its paragraph',
  );
  expect(paragraph.textScaler.scale(14) / 14, closeTo(scale, 0.001));
  expect(
    find.ancestor(of: text, matching: find.byType(FittedBox)),
    findsNothing,
  );
  expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.1));
  expect(rect.right, lessThanOrEqualTo(viewport.right + 0.1));
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.1));
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.bottom + 0.1),
    reason: 'Full text must be reachable by scrolling',
  );
  return {
    'text': paragraph.text.toPlainText(),
    'rect': [rect.left, rect.top, rect.right, rect.bottom],
    'viewport': [viewport.left, viewport.top, viewport.right, viewport.bottom],
    'height': paragraph.size.height,
    'intrinsicHeight': intrinsic,
    'requestedScale': scale,
    'actualScale': paragraph.textScaler.scale(14) / 14,
  };
}

Future<void> _saveGeometry(
  WidgetTester tester,
  String name,
  Object data,
) async {
  final dir = Platform.environment['CALCAI_SETUP_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(
    () => File(
      '$dir/$name.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data)),
  );
}

Future<void> _confirmHome(WidgetTester tester) async {
  final remove = find.byTooltip('Remove Home');
  // Baseline lacks a tooltip; use its actual first removal icon so the baseline
  // can demonstrate the transport/result defect rather than fail on a finder.
  final target = remove.evaluate().isNotEmpty
      ? remove
      : find.byIcon(Icons.close_rounded).first;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.widgetWithText(TextButton, 'Remove'));
  await tester.pump(const Duration(milliseconds: 300));
  await _drainTransport(tester);
}

void main() {
  setUpAll(() async {
    final font = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await font.load();
  });
  testWidgets(
    'GATT write is transport only; saved entry waits for storage ACK',
    (tester) async {
      final f = await _fixture();
      final pending = _Pending(f.ble.removeWifiNetwork('Home'));
      await tester.pump();
      expect(f.config.writes, [
        {'action': 'remove', 'ssid': 'Home'},
      ]);
      expect(f.config.reliableWrites, [true]);
      expect(pending.done, isFalse);
      await _retained(f);
      f.status.emit(_removed);
      await _finish(tester, pending);
      expect(pending.result, isTrue);
      expect(f.ble.savedNetworks, ['Guest']);
      expect(f.ble.iphoneHotspotNetworks, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('saved_networks_$_mac')!), ['Guest']);
      expect(jsonDecode(prefs.getString('iphone_hotspots_$_mac')!), isEmpty);
    },
  );

  testWidgets('fresh matching success during write is not missed', (
    tester,
  ) async {
    final f = await _fixture();
    f.config.onWrite = (_) => f.status.emit(_removed);
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isTrue);
    expect(f.ble.savedNetworks, ['Guest']);
    expect(f.status.reads, 0);
  });

  testWidgets(
    'delayed storage failure keeps entry and same-link retry can succeed',
    (tester) async {
      final f = await _fixture();
      final failed = _Pending(f.ble.removeWifiNetwork('Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      f.status.emit(_storageFailed);
      await _finish(tester, failed);
      expect(failed.result, isFalse);
      expect(
        f.ble.provisioningState,
        ProvisioningState.idle,
        reason: 'A removal rejection is not a Wi-Fi connection failure',
      );
      await _retained(f);
      expect(f.ble.error, isNotEmpty);
      expect(f.ble.error!.toLowerCase(), isNot(contains('still stored')));
      final retry = _Pending(f.ble.removeWifiNetwork('Home'));
      await tester.pump();
      expect(f.config.writes.length, 2);
      await _retained(f);
      f.status.emit(_removed);
      await _finish(tester, retry);
      expect(retry.result, isTrue);
      expect(f.ble.savedNetworks, ['Guest']);
      expect(f.ble.error, isNull);
    },
  );

  for (final response in [
    {'status': 'removed', 'ssid': 'Guest'},
    {'status': 'failed', 'ssid': 'Guest', 'error': 'storage_failed'},
    {'status': 'removed'},
    {'status': 'connected', 'ssid': 'Home'},
    {'status': 'removed', 'ssid': 'home'},
    {'ok': true, 'ssid': 'Home'},
    ['removed', 'Home'],
    null,
  ]) {
    testWidgets(
      'unrelated or malformed status cannot acknowledge removal: $response',
      (tester) async {
        final f = await _fixture();
        final pending = _Pending(f.ble.removeWifiNetwork('Home'));
        await tester.pump();
        f.status.emit(response);
        await tester.pump(const Duration(milliseconds: 300));
        expect(pending.done, isFalse);
        await _retained(f);
        f.status.emit(_removed);
        await _finish(tester, pending);
        expect(pending.result, isTrue);
      },
    );
  }

  testWidgets(
    'cached matching status and setup-time replay are not a new ACK',
    (tester) async {
      final f = await _fixture(cachedStatus: _removed);
      f.status.onSubscribe = () => f.status.emit(_removed);
      final pending = _Pending(f.ble.removeWifiNetwork('Home'));
      await tester.pump();
      expect(pending.done, isFalse);
      await _retained(f);
      expect(
        f.status.reads,
        0,
        reason: 'A cached characteristic read is not storage completion',
      );
      f.status.onSubscribe = null;
      f.status.emit(_removed);
      await _finish(tester, pending);
      expect(pending.result, isTrue);
    },
  );

  for (final rejection in [
    {'status': 'failed', 'error': 'bad_request'},
    {'status': 'error', 'error': 'no remove handler'},
  ]) {
    testWidgets(
      'explicit firmware rejection is a visible failure: $rejection',
      (tester) async {
        final f = await _fixture();
        f.config.onWrite = (_) => f.status.emit(rejection);
        final pending = _Pending(f.ble.removeWifiNetwork('Home'));
        await _finish(tester, pending);
        expect(pending.result, isFalse);
        await _retained(f);
        expect(f.ble.error, isNotEmpty);
      },
    );
  }

  testWidgets('notify unsupported never falls back to a stale status read', (
    tester,
  ) async {
    final f = await _fixture(cachedStatus: _removed);
    f.status.notify = false;
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    expect(f.config.writes, isEmpty);
    expect(f.status.reads, 0);
    await _retained(f);
    expect(f.ble.error, isNotEmpty);
  });

  testWidgets('notification setup failure does not dispatch removal', (
    tester,
  ) async {
    final f = await _fixture();
    f.status.failSubscribe = true;
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    expect(f.config.writes, isEmpty);
    await _retained(f);
    expect(f.ble.error, isNotEmpty);
  });

  testWidgets(
    'timeout preserves caches and requires a new connection before retry',
    (tester) async {
      final f = await _fixture();
      final pending = _Pending(f.ble.removeWifiNetwork('Home'));
      await _finish(tester, pending);
      expect(pending.result, isFalse);
      await _retained(f);
      expect(f.ble.error, isNotEmpty);
      final retry = _Pending(f.ble.removeWifiNetwork('Home'));
      await _finish(tester, retry);
      expect(retry.result, isFalse);
      expect(
        f.config.writes.length,
        1,
        reason: 'No RID: avoid confusing a late same-SSID ACK with retry',
      );
      expect(f.ble.error!.toLowerCase(), contains('reconnect'));
      await f.ble.disconnect();
      await f.replacement();
      f.config.onWrite = (_) => f.status.emit(_removed);
      final afterReconnect = _Pending(f.ble.removeWifiNetwork('Home'));
      await _finish(tester, afterReconnect);
      expect(afterReconnect.result, isTrue);
      expect(f.ble.savedNetworks, ['Guest']);
    },
  );

  testWidgets(
    'disconnect settles pending operation; old epoch cannot change replacement cache',
    (tester) async {
      final f = await _fixture();
      final oldStatus = f.status;
      final pending = _Pending(f.ble.removeWifiNetwork('Home'));
      await tester.pump();
      await f.ble.disconnect();
      await tester.pump();
      await _drainTransport(tester);
      expect(pending.done, isTrue);
      expect(pending.result, isFalse);
      await f.replacement();
      oldStatus.emit(_removed);
      await tester.pump();
      await _retained(f);
      final fresh = _Pending(f.ble.removeWifiNetwork('Home'));
      await tester.pump();
      oldStatus.emit(_removed);
      await tester.pump();
      expect(fresh.done, isFalse);
      await _retained(f);
      f.status.emit(_removed);
      await _finish(tester, fresh);
      expect(fresh.result, isTrue);
    },
  );

  testWidgets('dispose settles waiter and ignores delayed storage success', (
    tester,
  ) async {
    final f = await _fixture();
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await tester.pump();
    f.ble.dispose();
    f.disposed = true;
    await tester.pump();
    await _drainTransport(tester);
    expect(pending.done, isTrue);
    expect(pending.result, isFalse);
    f.status.emit(_removed);
    await tester.pump();
    await _retained(f);
  });

  testWidgets('saved-list command waits until removal completion', (
    tester,
  ) async {
    final f = await _fixture();
    final removing = _Pending(f.ble.removeWifiNetwork('Home'));
    await tester.pump();
    var listed = false;
    final listing = f.ble.requestSavedNetworks().then((_) => listed = true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(f.scan.writes, isEmpty);
    expect(listed, isFalse);
    f.status.emit(_removed);
    await _finish(tester, removing);
    for (var i = 0; i < 12 && !listed; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await listing;
    expect(f.scan.writes, [
      {'cmd': 'list'},
    ]);
    expect(f.ble.savedNetworks, ['Guest']);
  });

  testWidgets(
    'two removals are serialized and each needs its own matching success',
    (tester) async {
      final f = await _fixture();
      final first = _Pending(f.ble.removeWifiNetwork('Home'));
      final second = _Pending(f.ble.removeWifiNetwork('Guest'));
      await tester.pump();
      expect(f.config.writes, [
        {'action': 'remove', 'ssid': 'Home'},
      ]);
      f.status.emit({'status': 'removed', 'ssid': 'Guest'});
      await tester.pump();
      expect(first.done, isFalse);
      expect(second.done, isFalse);
      f.status.emit(_removed);
      await _finish(tester, first);
      await tester.pump();
      expect(f.config.writes.length, 2);
      expect(second.done, isFalse);
      expect(f.ble.savedNetworks, ['Guest']);
      f.status.emit({'status': 'removed', 'ssid': 'Guest'});
      await _finish(tester, second);
      expect(second.result, isTrue);
      expect(f.ble.savedNetworks, isEmpty);
    },
  );

  testWidgets(
    'exact multibyte and surrounding-space SSID are never normalized',
    (tester) async {
      final f = await _fixture();
      const ssid = '  Café 家  ';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'saved_networks_$_mac',
        jsonEncode([ssid, 'Guest']),
      );
      await prefs.setString('iphone_hotspots_$_mac', jsonEncode([ssid]));
      await f.ble.loadPersistedNetworks(_mac);
      final pending = _Pending(f.ble.removeWifiNetwork(ssid));
      await tester.pump();
      expect(f.config.writes.single, {'action': 'remove', 'ssid': ssid});
      f.status.emit({'status': 'removed', 'ssid': ssid.trim()});
      await tester.pump();
      expect(pending.done, isFalse);
      expect(f.ble.savedNetworks, contains(ssid));
      f.status.emit({'ssid': ssid, 'status': 'removed'});
      await _finish(tester, pending);
      expect(pending.result, isTrue);
      expect(f.ble.savedNetworks, ['Guest']);
    },
  );

  testWidgets('an unowned client cannot send a removal command', (
    tester,
  ) async {
    final f = await _fixture();
    f.ble.owner = null;
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    expect(f.config.writes, isEmpty);
    await _retained(f);
  });

  testWidgets('a disconnected client cannot send a removal command', (
    tester,
  ) async {
    final f = await _fixture();
    final originalConfig = f.config;
    await f.ble.disconnect();
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    expect(originalConfig.writes, isEmpty);
    await _retained(f);
  });

  testWidgets(
    'write exception is a failure and preserves retryable local state',
    (tester) async {
      final f = await _fixture();
      f.config.onWrite = (_) => throw StateError('fixture write failed');
      final pending = _Pending(f.ble.removeWifiNetwork('Home'));
      await _finish(tester, pending);
      expect(pending.result, isFalse);
      await _retained(f);
      expect(f.ble.error, isNotEmpty);
    },
  );

  testWidgets('hung write is bounded without deleting a cached network', (
    tester,
  ) async {
    final f = await _fixture();
    final stalled = Completer<void>();
    f.config.onWrite = (_) => stalled.future;
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    await _retained(f);
    stalled.complete();
    await tester.pump();
    f.status.emit(_removed);
    await tester.pump();
    await _retained(f);
  });

  testWidgets('hung notification setup is bounded and cannot send later', (
    tester,
  ) async {
    final f = await _fixture();
    final stalled = Completer<void>();
    f.status.onSubscribe = () => stalled.future;
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, pending);
    expect(pending.result, isFalse);
    expect(f.config.writes, isEmpty);
    await _retained(f);
    stalled.complete();
    await tester.pump();
    expect(f.config.writes, isEmpty);
  });

  testWidgets('pending removal blocks password and force-save config writes', (
    tester,
  ) async {
    final f = await _fixture();
    final pending = _Pending(f.ble.removeWifiNetwork('Home'));
    await tester.pump();
    expect(f.config.writes.single, {'action': 'remove', 'ssid': 'Home'});
    final credentials = _Pending(
      f.ble.sendWifiCredentials(ssid: 'New', password: 'fixture-password'),
    );
    await _finish(tester, credentials);
    expect(credentials.result, isFalse);
    final saving = _Pending(
      f.ble.forceSaveNetwork(ssid: 'New', password: 'fixture-password'),
    );
    await _finish(tester, saving);
    expect(saving.result, isFalse);
    expect(f.config.writes, [
      {'action': 'remove', 'ssid': 'Home'},
    ]);
    await _retained(f);
    f.status.emit(_removed);
    await _finish(tester, pending);
    expect(pending.result, isTrue);
  });

  testWidgets('force-save already in flight blocks removal until it settles', (
    tester,
  ) async {
    final f = await _fixture();
    final saved = Completer<void>();
    f.config.onWrite = (_) => saved.future;
    final saving = _Pending(
      f.ble.forceSaveNetwork(ssid: 'New', password: 'fixture-password'),
    );
    await tester.pump();
    expect(f.config.writes.single['action'], 'force_save');
    final removing = _Pending(f.ble.removeWifiNetwork('Home'));
    await _finish(tester, removing);
    expect(removing.result, isFalse);
    expect(f.config.writes.length, 1);
    await _retained(f);
    saved.complete();
    await _finish(tester, saving);
    expect(saving.result, isTrue);
  });

  testWidgets(
    'disconnected removal keeps cached rows and reachable uncertainty recovery at large text',
    (tester) async {
      final f = await _fixture();
      await _screen(tester, f, scale: 2);
      await _confirmHome(tester);
      await f.ble.disconnect();
      await _drainTransport(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await _retained(f);
      expect(find.text('Bluetooth disconnected'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      final message = find.textContaining('before removal was confirmed');
      expect(message, findsOneWidget);
      final messageGeometry = await _geometry(tester, message, 2);
      await _capture(tester, 'remove-disconnected-text2-message');
      final reconnect = find.text('Reconnect');
      expect(reconnect, findsOneWidget);
      final reconnectGeometry = await _geometry(tester, reconnect, 2);
      await _capture(tester, 'remove-disconnected-text2-reconnect');
      expect(
        tester
            .widget<ElevatedButton>(
              find
                  .ancestor(
                    of: reconnect,
                    matching: find.byType(ElevatedButton),
                  )
                  .first,
            )
            .onPressed,
        isNotNull,
      );
      final cacheGeometry = await _geometry(tester, find.text('Home'), 2);
      await _capture(tester, 'remove-disconnected-text2-cache');
      await _saveGeometry(tester, 'remove-disconnected-text2', {
        'message': messageGeometry,
        'reconnect': reconnectGeometry,
        'cachedSsid': cacheGeometry,
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'screen retains failed removal, exposes retry and preserves text at scale $scale',
      (tester) async {
        final f = await _fixture();
        f.config.onWrite = (_) => f.status.emit(_storageFailed);
        await _screen(tester, f, scale: scale);
        await _confirmHome(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await _retained(f);
        expect(find.text('Home'), findsOneWidget);
        final retry = find.text('Retry removal');
        expect(retry, findsOneWidget);
        await tester.ensureVisible(retry);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final retryText = tester.widget<Text>(retry);
        expect(retryText.maxLines, isNull);
        final retryGeometry = await _geometry(tester, retry, scale);
        await _capture(tester, 'remove-failure-text$scale-retry');
        final failureText = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == f.ble.error,
        );
        expect(failureText, findsOneWidget);
        final failureGeometry = await _geometry(tester, failureText, scale);
        await _capture(tester, 'remove-failure-text$scale-message');
        await _saveGeometry(tester, 'remove-failure-text$scale', {
          'message': failureGeometry,
          'retry': retryGeometry,
        });
        await tester.ensureVisible(retry);
        await tester.pump(const Duration(milliseconds: 300));
        f.config.onWrite = (_) => f.status.emit(_removed);
        await tester.tap(retry);
        await tester.pump(const Duration(milliseconds: 300));
        await _drainTransport(tester);
        expect(find.text('Home'), findsNothing);
        expect(f.ble.savedNetworks, ['Guest']);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  testWidgets('screen shows pending entry and disables duplicate removal', (
    tester,
  ) async {
    final f = await _fixture();
    await _screen(tester, f);
    await _confirmHome(tester);
    await _retained(f);
    expect(find.text('Home'), findsOneWidget);
    final remove = find.byTooltip('Remove Home');
    expect(remove, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: remove, matching: find.byType(IconButton)).first,
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Removing'), findsOneWidget);
    final pendingGeometry = await _geometry(
      tester,
      find.textContaining('Removing'),
      1,
    );
    await _capture(tester, 'remove-pending-normal');
    await _saveGeometry(tester, 'remove-pending-normal', pendingGeometry);
    expect(f.config.writes.length, 1);
    f.status.emit(_removed);
    await tester.pump(const Duration(milliseconds: 300));
    await _drainTransport(tester);
    expect(f.ble.savedNetworks, ['Guest']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
