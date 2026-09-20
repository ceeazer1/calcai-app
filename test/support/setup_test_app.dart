// In-memory fixtures for setup and Wi-Fi regression tests only.
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/wifi_network.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'fake_auth_service.dart';
import 'fake_cloud_service.dart';

class SetupTestAppAuth extends FakeAuthService {
  SetupTestAppAuth({bool paired = false}) : _claimed = paired;
  @override
  String get username => 'Chris';

  bool _claimed;
  bool _skipped = false;

  @override
  String? get primaryMac => _claimed ? 'ca1ca1000001' : null;
  @override
  List<String> get deviceMacs => _claimed ? ['ca1ca1000001'] : [];
  @override
  bool get setupSkipped => _skipped;
  @override
  Future<void> addDevice(String mac, {bool announce = true}) async {
    _claimed = true;
    if (announce) notifyListeners();
  }

  @override
  void skipSetup() {
    _skipped = true;
    notifyListeners();
  }
}

class SetupTestAppCloud extends FakeCloudService {
  SetupTestAppCloud({super.client});
  @override
  Future<String?> requestOwnershipProof(
    String token,
    String mac,
    String nonce,
  ) async => 'test-proof';
}

/// All setup operations are simulated in memory, including credentials.
class SetupTestAppBle extends BleService {
  final Duration delay;
  SetupTestAppBle({
    this.delay = const Duration(milliseconds: 1100),
    bool paired = false,
  }) {
    if (paired) {
      _paired = true;
      _saved.addAll(['Home Wi-Fi', 'My iPhone']);
      _hotspots.add('My iPhone');
      _ssid = 'Home Wi-Fi';
    }
  }

  final _testDevice = CalcAiDevice(
    device: BluetoothDevice.fromId('ca1ca1000001'),
    rssi: -42,
    advertisementName: 'CalcAI · TI-84 Plus',
  );
  bool _alive = true;
  bool _found = false;
  bool _paired = false;
  bool _scanning = false;
  DeviceConnectionState _connection = DeviceConnectionState.disconnected;
  ProvisioningState _provisioning = ProvisioningState.idle;
  List<WifiNetwork> _networks = [];
  String? _ssid;
  final Set<String> _hotspots = {};
  final List<String> _saved = [];
  String? _owner;
  @override
  String? get pairedOwner => _owner;

  Future<bool> _pause() async {
    await Future<void>.delayed(delay);
    return _alive;
  }

  @override
  List<CalcAiDevice> get devices => _found ? [_testDevice] : [];
  @override
  bool get isScanning => _scanning;
  @override
  CalcAiDevice? get connectedDevice =>
      _connection.isConnected ? _testDevice : null;
  @override
  DeviceConnectionState get connectionState => _connection;
  @override
  ProvisioningState get provisioningState => _provisioning;
  @override
  List<WifiNetwork> get wifiNetworks => _networks;
  @override
  List<String> get savedNetworks => List.unmodifiable(_saved);
  @override
  String? get connectedSsid => _ssid;
  @override
  String? get deviceMac => 'ca1ca1000001';
  @override
  Set<String> get iphoneHotspotNetworks => Set.unmodifiable(_hotspots);
  @override
  bool isIphoneHotspotNetwork(String ssid) => _hotspots.contains(ssid);
  @override
  DeviceChallenge get verifiedChallenge => const DeviceChallenge(
    mac: 'ca1ca1000001',
    nonce: 'test',
    response: 'test',
  );
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _found = false;
    _scanning = true;
    notifyListeners();
    if (!await _pause()) return;
    _found = true;
    _scanning = false;
    notifyListeners();
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    _connection = DeviceConnectionState.connecting;
    notifyListeners();
    if (!await _pause()) return;
    _connection = DeviceConnectionState.ready;
    notifyListeners();
  }

  @override
  Future<bool?> isDevicePaired() async => _paired;
  @override
  Future<String?> submitPairingCode(String code, String owner) async {
    if (!await _pause()) return 'Test disposed.';
    if (code != '123456') return 'Incorrect pairing code.';
    _paired = true;
    return null;
  }

  @override
  Future<bool> setWifiUiMode(bool enabled) async => true;
  @override
  Future<void> setPersistMac(String? mac) async {}
  @override
  Future<void> loadPersistedNetworks(String? deviceMac) async {}
  @override
  Future<void> requestSavedNetworks() async {}
  @override
  Future<bool> reconnectKnownDevice() async {
    if (!_paired) return false;
    await connectToDevice(_testDevice);
    return _alive && _connection == DeviceConnectionState.ready;
  }

  @override
  Future<({String mac, String nonce})?> requestAuthNonce() async =>
      (mac: 'ca1ca1000001', nonce: 'demo-nonce');
  @override
  Future<bool> proveOwnership(
    String nonce,
    String response,
    String owner,
  ) async {
    if (!await _pause()) return false;
    _owner = owner;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> setIphoneHotspotKeepAlive(String ssid, bool enabled) async {
    if (!await _pause() || !_saved.contains(ssid)) return false;
    if (enabled) {
      _hotspots.add(ssid);
    } else {
      _hotspots.remove(ssid);
    }
    notifyListeners();
    return true;
  }

  @override
  Future<bool> removeWifiNetwork(String ssid) async {
    if (!await _pause()) return false;
    _saved.remove(ssid);
    _hotspots.remove(ssid);
    if (_ssid == ssid) _ssid = null;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> forceSaveNetwork({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    if (!await _pause()) return false;
    _saveNetwork(ssid, iphoneHotspot);
    notifyListeners();
    return true;
  }

  void _saveNetwork(String ssid, bool hotspot) {
    if (!_saved.contains(ssid)) _saved.add(ssid);
    if (hotspot) {
      _hotspots.add(ssid);
    } else {
      _hotspots.remove(ssid);
    }
  }

  @override
  Future<void> requestWifiScan() async {
    _provisioning = ProvisioningState.scanning;
    notifyListeners();
    if (!await _pause()) return;
    _networks = const [
      WifiNetwork(ssid: 'Home Wi-Fi', rssi: -42, isSecured: true),
      WifiNetwork(ssid: 'My iPhone', rssi: -54, isSecured: true),
      WifiNetwork(ssid: 'Guest network', rssi: -68, isSecured: false),
    ];
    _provisioning = ProvisioningState.idle;
    notifyListeners();
  }

  @override
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    _provisioning = ProvisioningState.sendingCredentials;
    notifyListeners();
    if (!await _pause()) return false;
    _provisioning = ProvisioningState.waitingForConnection;
    notifyListeners();
    if (!await _pause()) return false;
    _ssid = ssid;
    _saveNetwork(ssid, iphoneHotspot);
    _provisioning = ProvisioningState.success;
    notifyListeners();
    return true;
  }

  @override
  Future<void> disconnect() async {
    _owner = null;
    _connection = DeviceConnectionState.disconnected;
    if (_alive) notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

class SetupTestApp extends StatefulWidget {
  const SetupTestApp({super.key, this.startAtHome = false});
  final bool startAtHome;
  @override
  State<SetupTestApp> createState() => _SetupTestAppState();
}

class _SetupTestAppState extends State<SetupTestApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(
          create: (_) => SetupTestAppAuth(paired: widget.startAtHome)..init(),
        ),
        ChangeNotifierProvider<BleService>(
          create: (_) => SetupTestAppBle(paired: widget.startAtHome),
        ),
        ChangeNotifierProvider<CloudService>(
          create: (_) => SetupTestAppCloud(),
        ),
      ],
      child: MaterialApp(
        title: 'CalcAI test harness',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
        home: Consumer<AuthService>(
          builder: (_, auth, __) => widget.startAtHome || auth.setupSkipped
              ? const MainShell()
              : const LinkDeviceScreen(),
        ),
      ),
    );
  }
}
