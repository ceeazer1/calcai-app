import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

import '../models/calcai_device.dart';
import '../models/wifi_network.dart';
import '../utils/log.dart';

/// A device's answer to an identity challenge.
///
/// [response] is HMAC(PAIR_MASTER_SECRET, "mac|nonce") computed by the
/// firmware. Only the backend holds the secret, so only the backend can judge
/// it — this class just carries the three values there.
class DeviceChallenge {
  const DeviceChallenge({
    required this.mac,
    required this.nonce,
    required this.response,
  });

  final String mac;
  final String nonce;
  final String response;
}

/// A MAC as the backend keys them: 12 hex characters, no separators.
bool isValidMacHex(String? mac) =>
    mac != null && RegExp(r'^[0-9a-f]{12}$').hasMatch(mac);

/// Comprehensive BLE service for CalcAI ESP32 WiFi provisioning.
///
/// Uses [ChangeNotifier] so the UI can reactively rebuild via [Provider].
/// Handles scanning, connecting, service discovery, WiFi scanning,
/// credential provisioning, and status monitoring.
class BleService extends ChangeNotifier {
  // ── BLE UUIDs (Espressif provisioning defaults, configurable) ──────

  /// The primary provisioning service UUID.
  String serviceUuid;

  /// Characteristic to trigger / receive WiFi scan results.
  String wifiScanCharUuid;

  /// Characteristic to write WiFi credentials (SSID + password).
  String wifiConfigCharUuid;

  /// Characteristic to read / be notified of provisioning status.
  String wifiStatusCharUuid;

  BleService({
    this.serviceUuid = '021a9004-0382-4aea-bff4-6b3f1c5adfb4',
    this.wifiScanCharUuid = '021a9006-0382-4aea-bff4-6b3f1c5adfb4',
    this.wifiConfigCharUuid = '021a9007-0382-4aea-bff4-6b3f1c5adfb4',
    this.wifiStatusCharUuid = '021a9008-0382-4aea-bff4-6b3f1c5adfb4',
  }) {
    // Let iOS raise its own "Turn On Bluetooth" alert, which carries a Settings
    // button. There is no API to switch the radio on (turnOn() is Android only)
    // and the URL scheme for the Bluetooth pane is private, so the system alert
    // is the only route that both works and passes review.
    if (!kIsWeb) {
      FlutterBluePlus.setOptions(showPowerAlert: true).catchError((e) {
        logDebug('CalcAI BLE: could not enable the power alert — $e');
      });
    }
  }

  // ── State ──────────────────────────────────────────────────────────

  /// Discovered CalcAI devices during BLE scan.
  final List<CalcAiDevice> _devices = [];
  List<CalcAiDevice> get devices => List.unmodifiable(_devices);

  /// Whether a BLE scan is in progress.
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// The currently connected device (null when disconnected).
  CalcAiDevice? _connectedDevice;
  CalcAiDevice? get connectedDevice => _connectedDevice;

  /// Connection state of the current device.
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  DeviceConnectionState get connectionState => _connectionState;

  /// WiFi networks from a scan (available nearby networks).
  final List<WifiNetwork> _wifiNetworks = [];
  List<WifiNetwork> get wifiNetworks => List.unmodifiable(_wifiNetworks);

  /// Saved/configured networks on the ESP32 device.
  final List<String> _savedNetworks = [];
  List<String> get savedNetworks => List.unmodifiable(_savedNetworks);

  /// True while fetching the saved-network list from the device over BLE, so
  /// the UI can show a "loading networks…" state instead of a premature empty.
  bool _savedNetworksLoading = false;
  bool get savedNetworksLoading => _savedNetworksLoading;

  /// Stable key used to persist saved networks (the user's primary device MAC),
  /// so they survive restarts and match what the home page loads. Set via
  /// [setPersistMac] / [loadPersistedNetworks].
  String? _persistMac;

  static String? _normMac(String? mac) {
    final n = mac?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    return (n == null || n.isEmpty) ? null : n;
  }

  /// Sets the persistence key (normally the user's primary device MAC) and
  /// re-persists the current list under it, so networks saved before the device
  /// was claimed still land under the key the home page loads from.
  Future<void> setPersistMac(String? mac) async {
    final norm = _normMac(mac);
    if (norm == null) return;
    _persistMac = norm;
    if (_savedNetworks.isNotEmpty) await _persistSavedNetworks();
  }

  /// Current WiFi provisioning state.
  ProvisioningState _provisioningState = ProvisioningState.idle;
  ProvisioningState get provisioningState => _provisioningState;

  /// The SSID the device has successfully connected to.
  String? _connectedSsid;
  String? get connectedSsid => _connectedSsid;

  /// The WiFi MAC address received from the ESP32 over BLE.
  /// On iOS, device.remoteId is a UUID not a MAC, so we read the real
  /// MAC from the status characteristic's connected response instead.
  String? _deviceMac;
  String? get deviceMac => _deviceMac;

  /// The verified identity challenge for the current connection, once the
  /// backend has confirmed the peripheral is genuine. Also relayed on claim, so
  /// pairing proves possession with the same nonce-bound answer.
  DeviceChallenge? _verifiedChallenge;
  DeviceChallenge? get verifiedChallenge => _verifiedChallenge;

  /// Asks the backend whether a challenge answer is genuine.
  ///
  /// Injected (rather than calling CloudService directly) to keep this service
  /// free of auth/HTTP concerns and testable without a network. Wired up in
  /// `app.dart`. **Leaving it null fails closed** — the WiFi password is not
  /// sent to an unverified peripheral just because the wiring was forgotten.
  Future<bool> Function(DeviceChallenge challenge)? deviceVerifier;

  /// Human-readable error message (null when there is no error).
  String? _error;
  String? get error => _error;

  // ── Internal handles ───────────────────────────────────────────────

  BluetoothCharacteristic? _scanChar;
  BluetoothCharacteristic? _configChar;
  BluetoothCharacteristic? _statusChar;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _statusNotifySub;

  /// Requests Bluetooth permissions required for BLE.
  ///
  /// On iOS, CoreBluetooth handles permissions natively when scanning starts.
  /// On Android, flutter_blue_plus requests permissions automatically.
  /// Returns `true` if Bluetooth is ready to use.
  Future<bool> requestPermissions() async {
    try {
      // Check if Bluetooth adapter is available
      if (await FlutterBluePlus.isSupported == false) {
        _setError('Bluetooth is not supported on this device.');
        return false;
      }

      // Check adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      
      if (adapterState != BluetoothAdapterState.on) {
        // On iOS, this prompts the user to enable Bluetooth
        if (Platform.isIOS) {
          _setError('Please enable Bluetooth in Settings.');
        } else {
          // On Android, try to turn it on
          try {
            await FlutterBluePlus.turnOn();
          } catch (_) {
            _setError('Please enable Bluetooth.');
            return false;
          }
        }
        
        // Wait briefly for Bluetooth to turn on
        final state = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 10), onTimeout: () => BluetoothAdapterState.off);
        
        if (state != BluetoothAdapterState.on) {
          _setError('Bluetooth is not enabled.');
          return false;
        }
      }

      _clearError();
      return true;
    } catch (e) {
      _setError('Bluetooth setup failed: ${_friendlyError(e)}');
      return false;
    }
  }

  /// Checks whether Bluetooth is currently on.
  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  // ── Scanning ───────────────────────────────────────────────────────

  /// Starts scanning for CalcAI BLE devices.
  ///
  /// Results are accumulated in [devices]. The scan runs for [timeout]
  /// seconds and then stops automatically.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;

    _clearError();
    _devices.clear();
    _isScanning = true;
    notifyListeners();

    try {
      // Cancel any existing scan
      await FlutterBluePlus.stopScan();

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName;
          if (name.isEmpty) continue;
          if (!name.toLowerCase().contains('calcai')) continue;

          final existing = _devices.indexWhere(
            (d) => d.id == r.device.remoteId.str,
          );

          if (existing == -1) {
            _devices.add(CalcAiDevice(
              device: r.device,
              rssi: r.rssi,
              advertisementName: name,
            ));
          } else {
            _devices[existing].rssi = r.rssi;
          }
        }
        notifyListeners();
      });

      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      _setError('Scan failed: ${_friendlyError(e)}');
    } finally {
      _isScanning = false;
      _scanSub?.cancel();
      _scanSub = null;
      notifyListeners();
    }
  }

  /// Stops an ongoing BLE scan.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    _isScanning = false;
    notifyListeners();
  }

  // ── Connection ─────────────────────────────────────────────────────

  /// Connects to the given [device] and discovers provisioning services.
  static const String _kLastDeviceIdKey = 'last_ble_device_id';

  Future<void> _saveLastDeviceId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastDeviceIdKey, id);
    } catch (_) {}
  }

  /// Fast path: reconnect straight to the last paired peripheral by its id,
  /// skipping the scan entirely. iOS remembers the peripheral, so this is
  /// near-instant vs. waiting for a scan to rediscover it. Uses a short
  /// timeout so a "device not here" case falls back to scanning quickly.
  /// Returns true if it connected.
  Future<bool> reconnectKnownDevice() async {
    if (connectionState.isConnected) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kLastDeviceIdKey);
      if (id == null || id.isEmpty) return false;
      final dev = CalcAiDevice(
        device: BluetoothDevice.fromId(id),
        rssi: 0,
        advertisementName: 'CalcAI',
      );
      // Single short attempt: if the known device isn't right there, fail fast
      // (~4s) so the caller falls back to scanning instead of retrying for 15s.
      await connectToDevice(dev,
          timeout: const Duration(seconds: 4), attempts: 1);
      return connectionState.isConnected;
    } catch (e) {
      logDebug('reconnectKnownDevice error: $e');
      return false;
    }
  }

  Future<void> connectToDevice(
    CalcAiDevice device, {
    Duration timeout = const Duration(seconds: 15),
    int attempts = 3,
  }) async {
    _clearError();
    _setConnectionState(DeviceConnectionState.connecting);
    _connectedDevice = device;
    notifyListeners();

    try {
      // Stop scanning to save power
      await stopScan();

      // Connect, with retries. On iOS the FIRST connect to a freshly-
      // discovered peripheral very often hangs to timeout while an immediate
      // retry succeeds — so instead of one long (15s) hang that forces the
      // user to tap Connect again, we try a few short attempts and self-heal.
      // The reconnect fast-path passes attempts:1 so a stale/absent device
      // fails fast and the caller can fall back to scanning.
      final maxAttempts = attempts.clamp(1, 5);
      final perAttempt = Duration(
        seconds: (timeout.inSeconds ~/ maxAttempts).clamp(4, 8),
      );
      Object? lastError;
      var didConnect = false;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await device.device.connect(
            timeout: perAttempt,
            autoConnect: false,
          );
          didConnect = true;
          break;
        } catch (e) {
          lastError = e;
          logDebug('connect attempt $attempt/$maxAttempts failed: $e');
          // Make sure we're fully torn down before retrying, then settle.
          try {
            await device.device.disconnect();
          } catch (_) {}
          if (attempt < maxAttempts) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
      if (!didConnect) {
        throw lastError ?? Exception('Could not connect to the device');
      }

      // Now that we're connected, watch for real disconnections. (Set up
      // AFTER the retry loop so a failed attempt's teardown doesn't trip it.)
      _connectionSub?.cancel();
      _connectionSub = device.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Larger MTU for WiFi scan results (~500 bytes). Android only —
      // iOS negotiates automatically and requestMtu just errors/stalls there.
      if (Platform.isAndroid) {
        await device.device.requestMtu(517);
      }

      _setConnectionState(DeviceConnectionState.connected);
      // Remember this peripheral for fast direct reconnects next time.
      _saveLastDeviceId(device.device.remoteId.str);

      // Discover services
      _setConnectionState(DeviceConnectionState.discovering);
      final services = await device.device.discoverServices();

      // Find the provisioning service
      bool serviceFound = false;
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          serviceFound = true;
          _resolveCharacteristics(service);
          break;
        }
      }

      if (!serviceFound) {
        _setError(
          'Provisioning service not found on this device. '
          'Make sure the CalcAI firmware is up to date.',
        );
        _setConnectionState(DeviceConnectionState.error);
        return;
      }

      // Subscribe to status notifications if available
      await _subscribeToStatus();

      // Auto-fetch saved networks BEFORE announcing ready. Listeners react to
      // `ready` by running the pairing handshake, and both talk on the same
      // characteristic — announcing first meant `list` overwrote the pairinfo
      // reply before it could be read.
      await requestSavedNetworks();

      _setConnectionState(DeviceConnectionState.ready);
    } catch (e) {
      _setError('Connection failed: ${_friendlyError(e)}');
      _setConnectionState(DeviceConnectionState.error);
    }
  }

  /// Disconnects from the current device.
  Future<void> disconnect() async {
    try {
      _statusNotifySub?.cancel();
      _statusNotifySub = null;
      _connectionSub?.cancel();
      _connectionSub = null;

      await _connectedDevice?.device.disconnect();
    } catch (_) {
      // Best-effort disconnect
    } finally {
      _handleDisconnection();
    }
  }

  void _handleDisconnection() {
    _connectedDevice = null;
    _scanChar = null;
    _pairedOwner = null;
    _configChar = null;
    _statusChar = null;
    _wifiNetworks.clear();
    _provisioningState = ProvisioningState.idle;
    _deviceMac = null;
    // Verification is per-connection: a new link must prove itself again.
    _verifiedChallenge = null;
    _setConnectionState(DeviceConnectionState.disconnected);
  }

  void _resolveCharacteristics(BluetoothService service) {
    for (final c in service.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (uuid == wifiScanCharUuid.toLowerCase()) {
        _scanChar = c;
      } else if (uuid == wifiConfigCharUuid.toLowerCase()) {
        _configChar = c;
      } else if (uuid == wifiStatusCharUuid.toLowerCase()) {
        _statusChar = c;
      }
    }
  }

  Future<void> _subscribeToStatus() async {
    if (_statusChar == null) return;
    if (!_statusChar!.properties.notify) return;

    try {
      await _statusChar!.setNotifyValue(true);
      _statusNotifySub = _statusChar!.lastValueStream.listen((value) {
        _handleStatusUpdate(value);
      });
    } catch (e) {
      logDebug('CalcAI BLE: Could not subscribe to status: $e');
    }
  }

  void _handleStatusUpdate(List<int> value) {
    if (value.isEmpty) return;

    try {
      final json = utf8.decode(value);
      final data = jsonDecode(json) as Map<String, dynamic>;

      final status = data['status'] as String?;
      if (status == 'connected') {
        _connectedSsid = data['ssid'] as String? ?? _connectedSsid;
        // Normalize MAC: "AA:BB:CC:DD:EE:FF" → "aabbccddeeff".
        // Strip every separator, not just colons, and only accept the result if
        // it is a real MAC — this value reaches API query strings, and it comes
        // from whatever peripheral we are talking to.
        final rawMac = data['mac'] as String?;
        if (rawMac != null && rawMac.isNotEmpty) {
          final norm =
              rawMac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
          if (isValidMacHex(norm)) _deviceMac = norm;
        }
        _provisioningState = ProvisioningState.success;
      } else if (status == 'failed') {
        _setError(data['error'] as String? ?? 'WiFi connection failed.');
        _provisioningState = ProvisioningState.failed;
      }
      notifyListeners();
    } catch (e) {
      // Handle simple byte-status protocol as fallback
      if (value.first == 0x01) {
        _provisioningState = ProvisioningState.success;
        notifyListeners();
      } else if (value.first == 0xFF) {
        _setError('WiFi connection failed.');
        _provisioningState = ProvisioningState.failed;
        notifyListeners();
      }
    }
  }

  // ── WiFi Scanning ──────────────────────────────────────────────────

  /// Requests a WiFi scan from the connected ESP32.
  ///
  /// Results are populated in [wifiNetworks] once the ESP32 responds.
  Future<void> requestWifiScan() async {
    if (_scanChar == null) {
      _setError('WiFi scan characteristic not available.');
      return;
    }

    _clearError();
    _wifiNetworks.clear();
    _provisioningState = ProvisioningState.scanning;
    notifyListeners();

    try {
      // Write a scan trigger command
      await _scanChar!.write(
        utf8.encode(jsonEncode({'cmd': 'scan'})),
        withoutResponse: _scanChar!.properties.writeWithoutResponse,
      );

      // ESP32 WiFi scan takes ~10 seconds for 40+ networks.
      // Wait 12s before first read, then retry a few times.
      await Future.delayed(const Duration(seconds: 12));

      List<int> response = [];
      for (int i = 0; i < 5; i++) {
        response = await _scanChar!.read();
        logDebug('CalcAI BLE: scan read attempt ${i + 1}, got ${response.length} bytes');
        if (response.length > 10) break;
        await Future.delayed(const Duration(seconds: 2));
      }

      if (response.isNotEmpty && response.length > 4) {
        _parseWifiScanResults(response);
        logDebug('CalcAI BLE: parsed ${_wifiNetworks.length} networks');
      } else {
        logDebug('CalcAI BLE: no scan results received (${response.length} bytes)');
      }

      _provisioningState = ProvisioningState.idle;
    } catch (e) {
      _setError('WiFi scan failed: ${_friendlyError(e)}');
      _provisioningState = ProvisioningState.failed;
    }

    notifyListeners();
  }

  void _parseWifiScanResults(List<int> data) {
    try {
      final json = utf8.decode(data);
      final parsed = jsonDecode(json);

      if (parsed is List) {
        _wifiNetworks.clear();
        for (final item in parsed) {
          if (item is Map<String, dynamic>) {
            final network = WifiNetwork.fromJson(item);
            if (network.ssid.isNotEmpty) {
              _wifiNetworks.add(network);
            }
          }
        }
        // Sort by signal strength (strongest first)
        _wifiNetworks.sort((a, b) => b.rssi.compareTo(a.rssi));
      }
    } catch (e) {
      logDebug('CalcAI BLE: Error parsing WiFi scan results: $e');
      // Try a simpler line-based format as fallback
      _parseFallbackScanResults(data);
    }
  }

  void _parseFallbackScanResults(List<int> data) {
    try {
      final text = utf8.decode(data);
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty);

      _wifiNetworks.clear();
      for (final line in lines) {
        // Expected: "SSID,RSSI,SECURED"
        final parts = line.split(',');
        if (parts.length >= 2) {
          _wifiNetworks.add(WifiNetwork(
            ssid: parts[0].trim(),
            rssi: int.tryParse(parts[1].trim()) ?? -70,
            isSecured: parts.length > 2 ? parts[2].trim() == '1' : true,
          ));
        }
      }
      _wifiNetworks.sort((a, b) => b.rssi.compareTo(a.rssi));
    } catch (_) {
      // Silently fail; user will see empty list
    }
  }

  // ── Saved Networks ────────────────────────────────────────────────

  /// Requests saved/configured networks from the ESP32 via BLE.
  /// Sends `{"cmd":"list"}` to the scan characteristic and reads the response.
  Future<void> requestSavedNetworks() =>
      _serialize(() => _requestSavedNetworksLocked());

  Future<void> _requestSavedNetworksLocked() async {
    if (_scanChar == null) return;

    _savedNetworksLoading = true;
    notifyListeners();
    try {
      await _scanChar!.write(
        utf8.encode(jsonEncode({'cmd': 'list'})),
        withoutResponse: _scanChar!.properties.writeWithoutResponse,
      );

      // Wait for ESP32 to process and set the value
      await Future.delayed(const Duration(milliseconds: 500));

      final response = await _scanChar!.read();
      if (response.isNotEmpty) {
        try {
          final parsed = jsonDecode(utf8.decode(response));
          if (parsed is List) {
            // Replace the list (handles going down to zero saved networks).
            _savedNetworks.clear();
            for (final item in parsed) {
              if (item is Map<String, dynamic>) {
                final ssid = item['ssid'] as String? ?? '';
                if (ssid.isNotEmpty) _savedNetworks.add(ssid);
              }
            }
            logDebug(
                'CalcAI BLE: got ${_savedNetworks.length} saved networks');
            await _persistSavedNetworks();
          }
        } catch (_) {
          // Non-JSON / partial read — keep the existing list.
        }
      }
    } catch (e) {
      logDebug('CalcAI BLE: Error fetching saved networks: $e');
    } finally {
      _savedNetworksLoading = false;
      notifyListeners();
    }
  }

  /// Loads previously saved networks from local storage.
  /// Call this on app startup so the WiFi screen can show networks
  /// even when BLE is not connected.
  Future<void> loadPersistedNetworks(String? deviceMac) async {
    final norm = _normMac(deviceMac);
    if (norm == null) return;
    _persistMac = norm; // keep persist + load keyed identically
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('saved_networks_$norm');
      if (json != null) {
        final list = jsonDecode(json) as List;
        _savedNetworks
          ..clear()
          ..addAll(list.cast<String>());
        notifyListeners();
      }
    } catch (e) {
      logDebug('CalcAI BLE: Error loading persisted networks: $e');
    }
  }

  Future<void> _persistSavedNetworks() async {
    // Prefer the app's primary MAC (matches what the home page loads); fall
    // back to the device's reported WiFi MAC, then the BLE remote id.
    final mac = _persistMac ??
        _normMac(_deviceMac) ??
        _normMac(_connectedDevice?.device.remoteId.str);
    if (mac == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'saved_networks_$mac',
        jsonEncode(_savedNetworks),
      );
    } catch (e) {
      logDebug('CalcAI BLE: Error persisting networks: $e');
    }
  }

  // ── Device Identity ────────────────────────────────────────────────

  static final _rng = Random.secure();

  /// A fresh 32-character hex nonce (128 bits).
  static String _newNonce() {
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[_rng.nextInt(16)]).join();
  }

  /// Asks the connected peripheral to answer an identity challenge.
  ///
  /// Serialises access to the scan characteristic.
  ///
  /// Every command writes a request and then reads the reply back off the same
  /// characteristic, so two of them in flight at once means the second one's
  /// write lands before the first one's read — and the first caller parses the
  /// wrong answer. Ordering here is cheaper than making every caller careful.
  Future<void> _cmdQueue = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() op) {
    final done = Completer<T>();
    _cmdQueue = _cmdQueue.then((_) async {
      try {
        done.complete(await op());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// One JSON command on the scan characteristic, with the reply read back.
  ///
  /// The firmware answers inline inside its write callback, so the value is
  /// ready almost immediately; the short retries cover BLE scheduling rather
  /// than any work on the device.
  /// Why the last [_command] failed, when it failed for a reason other than the
  /// calculator simply not recognising the command. Lets the UI tell "this
  /// firmware is too old" apart from "the link broke", which look identical
  /// from a null result and have completely different fixes.
  String? _lastCommandError;
  String? get lastCommandError => _lastCommandError;

  Future<Map<String, dynamic>?> _command(Map<String, dynamic> cmd) =>
      _serialize(() => _commandLocked(cmd));

  Future<Map<String, dynamic>?> _commandLocked(Map<String, dynamic> cmd) async {
    _lastCommandError = null;
    if (_scanChar == null) {
      _lastCommandError = 'no command characteristic';
      return null;
    }
    try {
      await _scanChar!.write(
        utf8.encode(jsonEncode(cmd)),
        withoutResponse: _scanChar!.properties.writeWithoutResponse,
      );
      for (var attempt = 0; attempt < 4; attempt++) {
        await Future.delayed(const Duration(milliseconds: 250));
        final raw = await _scanChar!.read();
        if (raw.isEmpty) continue;
        try {
          final data = jsonDecode(utf8.decode(raw));
          if (data is! Map<String, dynamic>) continue;
          // Firmware that echoes the command lets us prove the reply is ours
          // rather than a leftover from another exchange. Older firmware sends
          // no echo, so absence is accepted rather than treated as a mismatch.
          final echo = data['cmd'];
          if (echo is String && echo != cmd['cmd']) continue;
          return data;
        } catch (_) {
          // Could still be a stale scan/list payload — try again.
        }
      }
    } catch (e) {
      logDebug('CalcAI BLE: command ${cmd['cmd']} failed: $e');
      _lastCommandError = e.toString();
    }
    return null;
  }

  /// Whether this calculator has already been claimed by an account.
  ///
  /// Null means the firmware did not answer — either it predates pairing or the
  /// peripheral is not a CalcAI at all.
  Future<bool?> isDevicePaired() async {
    final r = await _command({'cmd': 'pairinfo'});
    final v = r?['paired'];
    return v is bool ? v : null;
  }

  /// Claims an unpaired calculator with the six digits shown on its screen.
  ///
  /// Returns null on success, or a short reason to show the user. The firmware
  /// allows five wrong guesses per connection and then burns the code.
  Future<String?> submitPairingCode(String code, String owner) async {
    final r = await _command({
      'cmd': 'paircode',
      'code': code,
      'owner': owner,
    });
    if (r == null) return 'No response. Try again.';
    if (r['ok'] == true) {
      _pairedOwner = owner;
      notifyListeners();
      return null;
    }
    final left = (r['left'] as num?)?.toInt();
    switch ((r['error'] ?? '').toString()) {
      case 'bad_code':
        return left != null && left > 0
            ? 'Wrong code — $left ${left == 1 ? 'try' : 'tries'} left.'
            : 'Wrong code. Reconnect for a new one.';
      case 'code_expired':
        return 'Code expired. Reconnect for a new one.';
      case 'too_many_tries':
        return 'Too many tries. Reconnect for a new code.';
      case 'already_paired':
        return 'Already paired to another account.';
      default:
        return 'Pairing failed. Try again.';
    }
  }

  /// Identifies this account to an already-paired calculator. Until this
  /// succeeds the firmware refuses every provisioning command, so it runs
  /// before any Wi-Fi work.
  Future<bool> announceOwner(String owner) async {
    final r = await _command({'cmd': 'hello', 'owner': owner});
    final ok = r?['ok'] == true;
    if (ok) _pairedOwner = owner;
    return ok;
  }

  /// The account this connection has identified as, once [announceOwner] or
  /// [submitPairingCode] has succeeded.
  String? _pairedOwner;
  String? get pairedOwner => _pairedOwner;

  /// Writes `{"cmd":"auth","nonce":...}` and reads the answer back from the
  /// same characteristic, the way the saved-network list already works.
  /// Returns null if the peripheral cannot answer — which is what an impostor,
  /// or a device on firmware older than the challenge, will do.
  Future<DeviceChallenge?> requestIdentityChallenge() =>
      _serialize(() => _requestIdentityChallengeLocked());

  Future<DeviceChallenge?> _requestIdentityChallengeLocked() async {
    if (_scanChar == null) return null;
    final nonce = _newNonce();

    try {
      await _scanChar!.write(
        utf8.encode(jsonEncode({'cmd': 'auth', 'nonce': nonce})),
        withoutResponse: _scanChar!.properties.writeWithoutResponse,
      );

      // The firmware answers inline in its write callback, so the value is
      // ready almost immediately; a few short retries cover BLE scheduling.
      for (var attempt = 0; attempt < 4; attempt++) {
        await Future.delayed(const Duration(milliseconds: 250));
        final raw = await _scanChar!.read();
        if (raw.isEmpty) continue;
        try {
          final data = jsonDecode(utf8.decode(raw));
          if (data is! Map) continue;

          final mac = (data['mac'] ?? '')
              .toString()
              .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
              .toLowerCase();
          final echoed = (data['nonce'] ?? '').toString().toLowerCase();
          final answer = (data['response'] ?? '').toString().toLowerCase();

          // The echoed nonce must be the one we just generated. Without this
          // check a captured answer from an earlier session could be replayed.
          if (!isValidMacHex(mac)) continue;
          if (echoed != nonce) continue;
          if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(answer)) continue;

          return DeviceChallenge(mac: mac, nonce: nonce, response: answer);
        } catch (_) {
          // Not the answer yet (could be a stale scan/list payload) — retry.
        }
      }
    } catch (e) {
      logDebug('CalcAI BLE: identity challenge failed: $e');
    }
    return null;
  }

  /// Confirms the peripheral is a genuine CalcAI device before anything
  /// sensitive is written to it.
  ///
  /// Cached per connection: the check runs once, so re-sending credentials or
  /// saving a second network costs nothing extra. Cleared on disconnect.
  ///
  /// Public only so tests can assert it fails closed; callers inside this class
  /// are the real users.
  @visibleForTesting
  Future<bool> ensureDeviceVerified() async {
    if (_verifiedChallenge != null) return true;

    final verifier = deviceVerifier;
    if (verifier == null) {
      // Fail closed: an unwired verifier must not silently disable the check.
      _setError('Cannot verify this device right now. Please try again.');
      return false;
    }

    final challenge = await requestIdentityChallenge();
    if (challenge == null) {
      _setError(
        "This device didn't pass the CalcAI security check. If it is your "
        'CalcAI, update its firmware and try again.',
      );
      return false;
    }

    bool genuine;
    try {
      genuine = await verifier(challenge);
    } catch (e) {
      logDebug('CalcAI BLE: verifier error: $e');
      genuine = false;
    }

    if (!genuine) {
      _setError(
        'Could not confirm this is a genuine CalcAI device, so your Wi-Fi '
        'password was not sent. Check your internet connection and try again.',
      );
      return false;
    }

    _verifiedChallenge = challenge;
    if (isValidMacHex(challenge.mac)) _deviceMac = challenge.mac;
    return true;
  }

  // ── WiFi Provisioning ──────────────────────────────────────────────

  /// Sends WiFi credentials to the ESP32 and monitors connection status.
  ///
  /// [ssid] — the network SSID to connect to.
  /// [password] — the network password (empty for open networks).
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
  }) async {
    if (_configChar == null) {
      _setError('WiFi config characteristic not available.');
      return false;
    }

    _clearError();

    // Never hand the user's Wi-Fi password to a peripheral we haven't proven
    // is a real CalcAI. Anyone can advertise the name.
    if (!await ensureDeviceVerified()) {
      _provisioningState = ProvisioningState.failed;
      notifyListeners();
      return false;
    }

    _connectedSsid = ssid;
    _provisioningState = ProvisioningState.sendingCredentials;
    notifyListeners();

    try {
      final payload = jsonEncode({
        'ssid': ssid,
        'password': password,
      });

      await _configChar!.write(
        utf8.encode(payload),
        withoutResponse: _configChar!.properties.writeWithoutResponse,
      );

      _provisioningState = ProvisioningState.waitingForConnection;
      notifyListeners();

      // Poll status if notifications are not available
      if (_statusChar != null && !_statusChar!.properties.notify) {
        return await _pollProvisioningStatus();
      }

      // If notifications are enabled, wait up to 30 seconds
      final success = await _waitForProvisioningResult(
        timeout: const Duration(seconds: 30),
      );

      // Refresh saved networks after successful provisioning
      if (success) {
        await requestSavedNetworks();
      }

      return success;
    } catch (e) {
      _setError('Failed to send credentials: ${_friendlyError(e)}');
      _provisioningState = ProvisioningState.failed;
      notifyListeners();
      return false;
    }
  }

  /// Force-saves a network to the ESP32 without verifying connection.
  /// Used when the user chooses "Save Anyway" after a failed connection.
  Future<bool> forceSaveNetwork({
    required String ssid,
    String password = '',
  }) async {
    if (_configChar == null) {
      _setError('WiFi config characteristic not available.');
      return false;
    }

    // "Save anyway" still sends the password, so it gets the same check.
    if (!await ensureDeviceVerified()) return false;

    try {
      final payload = jsonEncode({
        'action': 'force_save',
        'ssid': ssid,
        'password': password,
      });

      await _configChar!.write(
        utf8.encode(payload),
        withoutResponse: false,
      );

      // Wait for ESP32 confirmation
      await Future.delayed(const Duration(milliseconds: 300));

      // Refresh saved networks list
      await requestSavedNetworks();

      return true;
    } catch (e) {
      _setError('Failed to save network: ${_friendlyError(e)}');
      return false;
    }
  }

  Future<bool> _pollProvisioningStatus() async {
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));

      try {
        final value = await _statusChar!.read();
        _handleStatusUpdate(value);

        if (_provisioningState == ProvisioningState.success) return true;
        if (_provisioningState == ProvisioningState.failed) return false;
      } catch (_) {
        // Continue polling
      }
    }

    _setError('WiFi connection timed out.');
    _provisioningState = ProvisioningState.failed;
    notifyListeners();
    return false;
  }

  Future<bool> _waitForProvisioningResult({
    required Duration timeout,
  }) async {
    final completer = Completer<bool>();

    // Set a timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _setError('WiFi connection timed out.');
        _provisioningState = ProvisioningState.failed;
        notifyListeners();
        completer.complete(false);
      }
    });

    // Listen for state changes
    void checkState() {
      if (completer.isCompleted) return;
      if (_provisioningState == ProvisioningState.success) {
        timer.cancel();
        completer.complete(true);
      } else if (_provisioningState == ProvisioningState.failed) {
        timer.cancel();
        completer.complete(false);
      }
    }

    addListener(checkState);

    final result = await completer.future;
    removeListener(checkState);

    return result;
  }

  /// Sends a remove-network command to the ESP32 via BLE.
  ///
  /// The ESP32 firmware accepts `{"action":"remove","ssid":"..."}` on the
  /// Config characteristic and clears the matching NVS slot.
  Future<bool> removeWifiNetwork(String ssid) async {
    if (_configChar == null) {
      _setError('WiFi config characteristic not available.');
      return false;
    }

    _clearError();

    try {
      final payload = jsonEncode({
        'action': 'remove',
        'ssid': ssid,
      });

      await _configChar!.write(
        utf8.encode(payload),
        withoutResponse: false,
      );

      // Remove from local lists and persist
      _wifiNetworks.removeWhere((n) => n.ssid == ssid);
      _savedNetworks.remove(ssid);
      await _persistSavedNetworks();
      notifyListeners();

      return true;
    } catch (e) {
      _setError('Failed to remove network: $e');
      return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  void _setConnectionState(DeviceConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  /// Converts exceptions to user-friendly strings.
  String _friendlyError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('timeout')) {
      return 'Connection timed out. Make sure the device is nearby.';
    }
    if (msg.contains('not found')) {
      return 'Device not found. Try scanning again.';
    }
    if (msg.contains('denied')) {
      return 'Permission denied. Please grant Bluetooth permissions.';
    }
    return msg.replaceAll('Exception: ', '');
  }

  /// Resets all state. Useful when returning to the scan screen.
  void reset() {
    disconnect();
    _devices.clear();
    _wifiNetworks.clear();
    _error = null;
    _provisioningState = ProvisioningState.idle;
    _connectionState = DeviceConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _statusNotifySub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}

/// BLE test double.
///
/// A browser has no Bluetooth radio, so the real service can never populate the
/// saved-network list. Constructed only by tests — nothing in lib/
/// instantiates it. It lives in this file because `_savedNetworks` and
/// `_connectedSsid` are library-private.
class PreviewBleService extends BleService {
  PreviewBleService();

  /// Never touches SharedPreferences — a test has no real store to read.
  @override
  Future<void> loadPersistedNetworks(String? deviceMac) async {}
}
