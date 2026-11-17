import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'local_bench_profile.dart';
import 'bench_target_policy.dart';
import 'dart:io' show Platform;

import '../models/calcai_device.dart';
import '../models/wifi_network.dart';
import '../models/pairing_v2.dart';
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
    mac != null &&
    RegExp(r'^[0-9a-f]{12}$').hasMatch(mac) &&
    mac != '000000000000' &&
    mac != 'ffffffffffff';

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
  final _benchTarget = BenchTargetPolicy(
    targetName: LocalBenchProfile.targetName,
  );
  int _benchScanGeneration = 0;
  bool _benchScanInFlight = false;
  bool _disposed = false;

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

  /// Saved networks for which the ESP32 should keep an iPhone Personal Hotspot
  /// active. This is per SSID; ordinary routers remain untouched.
  final Set<String> _iphoneHotspotNetworks = <String>{};
  Set<String> get iphoneHotspotNetworks =>
      Set.unmodifiable(_iphoneHotspotNetworks);
  bool isIphoneHotspotNetwork(String ssid) =>
      _iphoneHotspotNetworks.contains(ssid);

  /// True while fetching the saved-network list from the device over BLE, so
  /// the UI can show a "loading networks…" state instead of a premature empty.
  bool _savedNetworksLoading = false;
  bool get savedNetworksLoading => _savedNetworksLoading;
  String? _savedNetworksError;
  String? get savedNetworksError => _savedNetworksError;

  Completer<bool>? _networkRemoval;
  int? _uncertainRemovalGeneration;
  bool _forceSaveInProgress = false;
  bool get networkRemovalNeedsReconnect =>
      _uncertainRemovalGeneration == connectionGeneration;

  void _cancelNetworkRemoval() {
    final pending = _networkRemoval;
    if (pending != null && !pending.isCompleted) pending.complete(false);
  }

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

  @protected
  BluetoothCharacteristic? get commandCharacteristic => _scanChar;

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
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => BluetoothAdapterState.off,
            );

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
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (LocalBenchProfile.enabled) return _startBenchScan(timeout);
    if (_isScanning) return;

    _clearError();
    _devices.clear();
    _isScanning = true;
    notifyListeners();

    try {
      // Cancel any existing scan
      await FlutterBluePlus.stopScan();

      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName;
          final existing = _devices.indexWhere(
            (d) => d.id == r.device.remoteId.str,
          );

          if (existing == -1) {
            // A name or the configured service UUID only identifies a
            // candidate. Connection, service and ownership proof stay required.
            final hasService = r.advertisementData.serviceUuids.any(
              (uuid) => uuid.str.toLowerCase() == serviceUuid.toLowerCase(),
            );
            if (!name.toLowerCase().contains('calcai') && !hasService) continue;
            _devices.add(
              CalcAiDevice(
                device: r.device,
                rssi: r.rssi,
                advertisementName: name.isEmpty ? null : name,
              ),
            );
          } else {
            final candidate = _devices[existing];
            candidate.rssi = r.rssi;
            if (name.isNotEmpty) candidate.advertisementName = name;
          }
        }
        notifyListeners();
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      // startScan completes when scanning STARTS, not when its timer expires.
      // Keep the result subscription until native scanning ends (or connection
      // stops it early). isScanning replays its current state to new listeners.
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    } catch (e) {
      _setError('Scan failed: ${_friendlyError(e)}');
    } finally {
      _isScanning = false;
      _scanSub?.cancel();
      _scanSub = null;
      notifyListeners();
    }
  }

  Future<void> _startBenchScan(Duration timeout) async {
    if (_disposed || _isScanning || _benchScanInFlight) return;
    final generation = ++_benchScanGeneration;
    _benchScanInFlight = true;
    _benchTarget.beginScan();
    _clearError();
    _devices.clear();
    _isScanning = true;
    notifyListeners();
    final candidates = <String, CalcAiDevice>{};
    StreamSubscription<List<ScanResult>>? subscription;
    var completed = false;
    try {
      await FlutterBluePlus.stopScan();
      if (_disposed || generation != _benchScanGeneration) return;
      subscription = FlutterBluePlus.onScanResults.listen((results) {
        if (generation != _benchScanGeneration) return;
        for (final result in results) {
          final name = result.advertisementData.advName;
          final id = result.device.remoteId.str;
          _benchTarget.observe(name, id);
          if (_benchTarget.matchesName(name)) {
            candidates[id] = CalcAiDevice(
              device: result.device,
              rssi: result.rssi,
              advertisementName: name,
            );
          }
        }
        // Do not expose the first result: finish the window and reject
        // duplicate exact-name peripherals before UI auto-connect listeners run.
      });
      _scanSub = subscription;
      await FlutterBluePlus.startScan(timeout: timeout);
      if (_disposed || generation != _benchScanGeneration) {
        await FlutterBluePlus.stopScan();
        return;
      }
      await FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .first
          .timeout(timeout + const Duration(seconds: 5));
      completed = true;
    } catch (error) {
      if (generation == _benchScanGeneration) {
        _error = 'Bench discovery failed: ${_friendlyError(error)}';
      }
    } finally {
      await subscription?.cancel();
      _benchScanInFlight = false;
      if (!_disposed && generation == _benchScanGeneration) {
        _scanSub = null;
        _isScanning = false;
        if (completed) {
          _benchTarget.completeScan();
          final id = _benchTarget.allowedId;
          if (id != null && candidates.containsKey(id)) {
            _devices.add(candidates[id]!);
          } else {
            _error = _benchTarget.ambiguous
                ? 'Multiple CALCAI-C62E peripherals found. Do not connect until the wired target is confirmed.'
                : 'CALCAI-C62E was not found. Reopen the wired calculator Bluetooth portal and scan again.';
          }
        } else {
          _benchTarget.invalidate();
          await FlutterBluePlus.stopScan();
        }
        notifyListeners();
      }
    }
  }

  /// Stops an ongoing BLE scan.
  Future<void> stopScan() async {
    if (LocalBenchProfile.enabled) {
      ++_benchScanGeneration;
      _benchTarget.invalidate();
      _devices.clear();
    }
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    _isScanning = false;
    if (!_disposed) notifyListeners();
  }

  // ── Connection ─────────────────────────────────────────────────────

  /// Connects to the given [device] and discovers provisioning services.
  static const String _kLastDeviceIdKey = 'last_ble_device_id';

  Future<void> _saveLastDeviceId(String id, int generation) async {
    try {
      final prefs = await AppPreferences.getInstance();
      if (_disposed || generation != connectionGeneration) return;
      await prefs.setString(_kLastDeviceIdKey, id);
    } catch (_) {}
  }

  /// Fast path: reconnect straight to the last paired peripheral by its id,
  /// skipping the scan entirely. iOS remembers the peripheral, so this is
  /// near-instant vs. waiting for a scan to rediscover it. Uses a short
  /// timeout so a "device not here" case falls back to scanning quickly.
  /// Returns true if it connected.
  Future<bool> reconnectKnownDevice() async {
    // Every new bench link must pass fresh exact-target discovery. Never read
    // even a namespaced remembered UUID as a substitute for that observation.
    if (LocalBenchProfile.enabled) return false;
    if (connectionState.isConnected) return true;
    try {
      final prefs = await AppPreferences.getInstance();
      final id = prefs.getString(_kLastDeviceIdKey);
      if (id == null || id.isEmpty) return false;
      final dev = CalcAiDevice(
        device: BluetoothDevice.fromId(id),
        rssi: 0,
        advertisementName: 'CalcAI',
      );
      // Single short attempt: if the known device isn't right there, fail fast
      // (~4s) so the caller falls back to scanning instead of retrying for 15s.
      await connectToDevice(
        dev,
        timeout: const Duration(seconds: 4),
        attempts: 1,
      );
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
    if (LocalBenchProfile.enabled &&
        !_benchTarget.allows(device.advertisementName ?? '', device.id)) {
      _setError(
        'Connection blocked: freshly discover the exact CALCAI-C62E wired bench first.',
      );
      _setConnectionState(DeviceConnectionState.error);
      return;
    }
    if (_disposed) return;
    _cancelNetworkRemoval();
    final generation = ++_connectionGeneration;
    bool current() =>
        !_disposed &&
        generation == connectionGeneration &&
        identical(_connectedDevice, device);
    Future<void> abandonStale() async {
      // Do not tear down a newer attempt to the same peripheral.
      if (_connectedDevice?.id != device.id) {
        try {
          await device.device.disconnect();
        } catch (_) {}
      }
    }

    _pairingApprovalVersion = null;
    _clearError();
    _connectedDevice = device;
    _setConnectionState(DeviceConnectionState.connecting);
    if (!current()) return;
    notifyListeners();

    try {
      // Stop scanning to save power
      await stopScan();
      if (!current()) return;

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
        if (!current()) return;
        try {
          await device.device.connect(timeout: perAttempt, autoConnect: false);
          if (!current()) {
            await abandonStale();
            return;
          }
          didConnect = true;
          break;
        } catch (e) {
          if (!current()) {
            await abandonStale();
            return;
          }
          lastError = e;
          logDebug('connect attempt $attempt/$maxAttempts failed: $e');
          // Make sure we're fully torn down before retrying, then settle.
          try {
            await device.device.disconnect();
          } catch (_) {}
          if (!current()) return;
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
        if (current() && state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Larger MTU for WiFi scan results (~500 bytes). Android only —
      // iOS negotiates automatically and requestMtu just errors/stalls there.
      if (Platform.isAndroid) {
        await device.device.requestMtu(517);
      }
      if (!current()) return;

      _setConnectionState(DeviceConnectionState.connected);
      if (!current()) return;
      // Remember this peripheral for fast direct reconnects next time.
      await _saveLastDeviceId(device.device.remoteId.str, generation);
      if (!current()) return;

      // Discover services
      _setConnectionState(DeviceConnectionState.discovering);
      if (!current()) return;
      final services = await device.device.discoverServices();
      if (!current()) {
        await abandonStale();
        return;
      }

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
      if (!current()) return;

      // Do not request saved networks here. The firmware handles `list`
      // asynchronously, while pairing commands answer immediately on the same
      // characteristic. A slow list response can therefore arrive after
      // `pairinfo` and overwrite it. Once ownership has been established we
      // request the list safely from [proveOwnership]; newly claimed devices
      // refresh it after provisioning.
      _setConnectionState(DeviceConnectionState.ready);
    } catch (e) {
      if (!current()) return;
      _setError('Connection failed: ${_friendlyError(e)}');
      _setConnectionState(DeviceConnectionState.error);
    }
  }

  /// Disconnects from the current device.
  Future<void> disconnect() async {
    _cancelNetworkRemoval();
    final generation = ++_connectionGeneration;
    final device = _connectedDevice;
    _pairingApprovalVersion = null;
    try {
      _statusNotifySub?.cancel();
      _statusNotifySub = null;
      _connectionSub?.cancel();
      _connectionSub = null;

      await device?.device.disconnect();
    } catch (_) {
      // Best-effort disconnect
    } finally {
      if (generation == connectionGeneration &&
          identical(device, _connectedDevice)) {
        _handleDisconnection();
      }
    }
  }

  void _handleDisconnection() {
    _cancelNetworkRemoval();
    _connectionGeneration++;
    _wifiScanGeneration++;
    _savedNetworksLoading = false;
    _pairingApprovalVersion = null;
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
    final characteristic = _statusChar;
    final generation = connectionGeneration;
    if (characteristic == null || !characteristic.properties.notify) return;

    try {
      await characteristic.setNotifyValue(true);
      if (_disposed ||
          generation != connectionGeneration ||
          !identical(characteristic, _statusChar)) {
        return;
      }
      _statusNotifySub = characteristic.lastValueStream.listen((value) {
        if (_disposed || generation != connectionGeneration) return;
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
      // Removal has its own fresh, SSID-bound notification waiter. Its failure
      // must not be interpreted as a failed Wi-Fi connection attempt.
      if (_networkRemoval != null &&
          (status == 'removed' || status == 'failed' || status == 'error')) {
        return;
      }
      if (status == 'connected') {
        _connectedSsid = data['ssid'] as String? ?? _connectedSsid;
        // Normalize MAC: "AA:BB:CC:DD:EE:FF" → "aabbccddeeff".
        // Strip every separator, not just colons, and only accept the result if
        // it is a real MAC — this value reaches API query strings, and it comes
        // from whatever peripheral we are talking to.
        final rawMac = data['mac'] as String?;
        if (rawMac != null && rawMac.isNotEmpty) {
          final norm = rawMac
              .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
              .toLowerCase();
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
  int _wifiScanGeneration = 0;

  Future<void> requestWifiScan() {
    final generation = connectionGeneration;
    final scanGeneration = ++_wifiScanGeneration;
    return _serialize(() async {
      if (generation != connectionGeneration ||
          scanGeneration != _wifiScanGeneration) {
        return;
      }
      await _requestWifiScanLocked(generation, scanGeneration);
    });
  }

  Future<void> _requestWifiScanLocked(
    int generation,
    int scanGeneration,
  ) async {
    final characteristic = commandCharacteristic;
    if (characteristic == null) {
      _setError('WiFi scan characteristic not available.');
      _provisioningState = ProvisioningState.failed;
      notifyListeners();
      return;
    }

    _clearError();
    _wifiNetworks.clear();
    _provisioningState = ProvisioningState.scanning;
    notifyListeners();

    try {
      // Write a scan trigger command
      await characteristic.write(
        utf8.encode(jsonEncode({'cmd': 'scan'})),
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );

      // Both queued work and a completed empty scan are encoded as [] by
      // legacy firmware. Time passing cannot make that an authoritative reply.
      // Poll for scan-shaped rows; never consume saved-list rows as a scan.
      for (var attempt = 0; attempt < 88; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (generation != connectionGeneration ||
            scanGeneration != _wifiScanGeneration) {
          return;
        }
        final response = await characteristic.read();
        if (generation != connectionGeneration ||
            scanGeneration != _wifiScanGeneration) {
          return;
        }
        final failure = _wifiCommandError(response, 'scan');
        if (failure != null) {
          _setError(failure);
          _provisioningState = ProvisioningState.failed;
          return;
        }
        if (_parseWifiScanResults(response)) {
          _provisioningState = ProvisioningState.idle;
          return;
        }
      }
      _setError('Could not confirm Wi-Fi scan results. Try scanning again.');
      _provisioningState = ProvisioningState.failed;
    } catch (e) {
      if (generation != connectionGeneration ||
          scanGeneration != _wifiScanGeneration) {
        return;
      }
      _setError('WiFi scan failed: ${_friendlyError(e)}');
      _provisioningState = ProvisioningState.failed;
    } finally {
      if (generation == connectionGeneration) {
        if (scanGeneration != _wifiScanGeneration &&
            _provisioningState == ProvisioningState.scanning) {
          _provisioningState = ProvisioningState.idle;
        }
        notifyListeners();
      }
    }
  }

  bool _parseWifiScanResults(List<int> data) {
    try {
      final json = utf8.decode(data);
      final parsed = jsonDecode(json);

      if (parsed is! List ||
          parsed.isEmpty ||
          !parsed.every(
            (item) =>
                item is Map<String, dynamic> &&
                item['ssid'] is String &&
                item['rssi'] is int &&
                item['secured'] is bool,
          )) {
        return false;
      }
      final networks = parsed
          .map((item) => WifiNetwork.fromJson(item as Map<String, dynamic>))
          .toList();
      _wifiNetworks
        ..clear()
        ..addAll(networks);
      _normalizeWifiNetworks();
      return true;
    } catch (_) {
      // Keep compatibility with complete legacy CSV replies, not partial JSON.
      return _parseFallbackScanResults(data);
    }
  }

  bool _parseFallbackScanResults(List<int> data) {
    try {
      final text = utf8.decode(data);
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
      final networks = <WifiNetwork>[];
      for (final line in lines) {
        // Expected: "SSID,RSSI,SECURED"
        final parts = line.split(',');
        if ((parts.length != 2 && parts.length != 3) ||
            parts[0].trim().isEmpty ||
            int.tryParse(parts[1].trim()) == null ||
            (parts.length == 3 && !['0', '1'].contains(parts[2].trim()))) {
          return false;
        }
        networks.add(
          WifiNetwork(
            ssid: parts[0].trim(),
            rssi: int.parse(parts[1].trim()),
            isSecured: parts.length == 2 || parts[2].trim() == '1',
          ),
        );
      }
      if (networks.isEmpty) return false;
      _wifiNetworks
        ..clear()
        ..addAll(networks);
      _normalizeWifiNetworks();
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _wifiCommandError(List<int> raw, String command) {
    try {
      final data = jsonDecode(utf8.decode(raw));
      if (data is! Map ||
          (data['cmd'] != null && data['cmd'] != command) ||
          (data['error'] == null && data['ok'] != false)) {
        return null;
      }
      return switch (data['error']) {
        'unauthorized' => 'Reconnect to your calculator and try again.',
        'busy' => 'Your calculator is busy. Try again in a moment.',
        'storage_failed' =>
          'The calculator could not read its saved networks. Try again.',
        'network_list_too_large' =>
          'The calculator could not send its saved networks. Try again.',
        _ => 'The calculator could not complete the Wi-Fi request. Try again.',
      };
    } catch (_) {
      return null;
    }
  }

  // ── Saved Networks ────────────────────────────────────────────────

  void _normalizeWifiNetworks() {
    final networks = WifiNetwork.uniqueBySsid(_wifiNetworks);
    _wifiNetworks
      ..clear()
      ..addAll(networks);
  }

  /// Requests saved/configured networks from the ESP32 via BLE.
  /// Sends `{"cmd":"list"}` to the scan characteristic and reads the response.
  Future<void> requestSavedNetworks() {
    final generation = connectionGeneration;
    return _serialize(() async {
      if (generation != connectionGeneration) return;
      await _requestSavedNetworksLocked();
    });
  }

  Future<bool> _requestSavedNetworksLocked() async {
    final generation = connectionGeneration;
    final characteristic = commandCharacteristic;
    if (characteristic == null) {
      _savedNetworksError =
          'Reconnect to your calculator to refresh saved networks.';
      notifyListeners();
      return false;
    }

    _savedNetworksError = null;
    _savedNetworksLoading = true;
    notifyListeners();
    try {
      await characteristic.write(
        utf8.encode(jsonEncode({'cmd': 'list'})),
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );

      // Listing NVS networks runs in the firmware loop rather than inline in
      // the BLE write callback. Poll for the actual list instead of assuming it
      // always finishes within 500 ms. Legacy [] is also the queued-work
      // sentinel, so it can never confirm deletion or an empty saved list.
      for (var attempt = 0; attempt < 8; attempt++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (generation != connectionGeneration) return false;
        final response = await characteristic.read();
        if (generation != connectionGeneration) return false;
        if (response.isEmpty) continue;
        final failure = _wifiCommandError(response, 'list');
        if (failure != null) {
          _savedNetworksError = failure;
          return false;
        }
        try {
          final parsed = jsonDecode(utf8.decode(response));
          if (parsed is List &&
              parsed.isNotEmpty &&
              parsed.every(
                (item) =>
                    item is Map<String, dynamic> &&
                    item['ssid'] is String &&
                    (item['ssid'] as String).isNotEmpty &&
                    item['slot'] is int &&
                    item['slot'] >= 1 &&
                    item['slot'] <= 3 &&
                    (item['iphoneHotspot'] == null ||
                        item['iphoneHotspot'] is bool),
              )) {
            // Validate the whole response before replacing either cache.
            _savedNetworks
              ..clear()
              ..addAll(parsed.map((item) => item['ssid'] as String).toSet());
            _iphoneHotspotNetworks
              ..clear()
              ..addAll(
                parsed
                    .where((item) => item['iphoneHotspot'] == true)
                    .map((item) => item['ssid'] as String),
              );
            logDebug('CalcAI BLE: got ${_savedNetworks.length} saved networks');
            await _persistSavedNetworks();
            return true;
          }
        } catch (_) {
          // Non-JSON / partial read — keep the existing list.
        }
      }
      _savedNetworksError =
          'Could not confirm saved networks. Try refreshing again.';
    } catch (e) {
      if (generation != connectionGeneration) return false;
      _savedNetworksError =
          'Could not refresh saved networks. Reconnect and try again.';
      logDebug('CalcAI BLE: Error fetching saved networks: $e');
    } finally {
      if (generation == connectionGeneration) {
        _savedNetworksLoading = false;
        notifyListeners();
      }
    }
    return false;
  }

  /// Loads previously saved networks from local storage.
  /// Call this on app startup so the WiFi screen can show networks
  /// even when BLE is not connected.
  Future<void> loadPersistedNetworks(String? deviceMac) async {
    final norm = _normMac(deviceMac);
    if (norm == null) return;
    _persistMac = norm; // keep persist + load keyed identically
    try {
      final prefs = await AppPreferences.getInstance();
      final json = prefs.getString('saved_networks_$norm');
      if (json != null) {
        final list = jsonDecode(json) as List;
        _savedNetworks
          ..clear()
          ..addAll(list.cast<String>());
      }
      final hotspotJson = prefs.getString('iphone_hotspots_$norm');
      _iphoneHotspotNetworks.clear();
      if (hotspotJson != null) {
        final list = jsonDecode(hotspotJson) as List;
        _iphoneHotspotNetworks.addAll(
          list.cast<String>().where(_savedNetworks.contains),
        );
      }
      notifyListeners();
    } catch (e) {
      logDebug('CalcAI BLE: Error loading persisted networks: $e');
    }
  }

  Future<void> _persistSavedNetworks() async {
    // Prefer the app's primary MAC (matches what the home page loads); fall
    // back to the device's reported WiFi MAC, then the BLE remote id.
    final mac =
        _persistMac ??
        _normMac(_deviceMac) ??
        _normMac(_connectedDevice?.device.remoteId.str);
    if (mac == null) return;
    try {
      final prefs = await AppPreferences.getInstance();
      await prefs.setString('saved_networks_$mac', jsonEncode(_savedNetworks));
      await prefs.setString(
        'iphone_hotspots_$mac',
        jsonEncode(_iphoneHotspotNetworks.toList()..sort()),
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

  Future<Map<String, dynamic>?> _command(Map<String, dynamic> cmd) {
    final generation = connectionGeneration;
    return _serialize(() async {
      if (generation != connectionGeneration) return null;
      return _commandLocked(cmd);
    });
  }

  Future<Map<String, dynamic>?> _commandLocked(Map<String, dynamic> cmd) async {
    final generation = connectionGeneration;
    final characteristic = commandCharacteristic;
    _lastCommandError = null;
    final benchProbe =
        LocalBenchProfile.enabled &&
        (cmd['cmd'] == 'capabilities' || cmd['cmd'] == 'pairinfo');
    var stage = 'write';
    if (characteristic == null) {
      _lastCommandError = 'no command characteristic';
      return null;
    }
    try {
      final signedPairing =
          cmd['cmd'] == 'pairapprove' || cmd['cmd'] == 'paircomplete';
      final bytes = utf8.encode(jsonEncode(cmd));
      // Signed offers are larger than one ATT packet. Reliable long writes
      // deliver one complete JSON command, never partial unauthenticated data.
      if (signedPairing && bytes.length > 512) {
        throw const PairingV2Exception(
          'Pairing message is too large.',
          restartRequired: true,
        );
      }
      await characteristic.write(
        bytes,
        withoutResponse:
            !signedPairing && characteristic.properties.writeWithoutResponse,
        allowLongWrite: signedPairing,
      );
      for (var attempt = 0; attempt < 4; attempt++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (generation != connectionGeneration) return null;
        stage = 'read';
        final raw = await characteristic.read();
        if (generation != connectionGeneration) return null;
        if (raw.isEmpty) {
          if (benchProbe) _lastCommandError = 'empty characteristic read';
          continue;
        }
        try {
          final data = jsonDecode(utf8.decode(raw));
          if (data is! Map<String, dynamic>) {
            if (benchProbe) {
              _lastCommandError = 'characteristic returned a non-object reply';
            }
            continue;
          }
          // Firmware that echoes the command lets us prove the reply is ours
          // rather than a leftover from another exchange. Older firmware sends
          // no echo, so absence is accepted rather than treated as a mismatch.
          final echo = data['cmd'];
          if (echo is String && echo != cmd['cmd']) {
            if (benchProbe) _lastCommandError = 'reply was for another command';
            continue;
          }
          _lastCommandError = null;
          return data;
        } catch (_) {
          // Could still be a stale scan/list payload — try again.
          if (benchProbe) {
            _lastCommandError = 'characteristic returned invalid JSON';
          }
        }
      }
    } on PairingV2Exception {
      rethrow;
    } catch (e) {
      logDebug('CalcAI BLE: command ${cmd['cmd']} failed: $e');
      _lastCommandError = benchProbe
          ? '$stage: ${_friendlyError(e)}'
          : e.toString();
    }
    return null;
  }

  int _connectionGeneration = 0;
  int get connectionGeneration => _connectionGeneration;
  int? _pairingApprovalVersion;
  int? get pairingApprovalVersion => _pairingApprovalVersion;

  @protected
  Future<Map<String, dynamic>?> sendPairingCommand(
    Map<String, dynamic> command,
  ) => _command(command);

  /// Pin negotiation to this connection. Never interpret a timeout as legacy.
  Future<int> negotiatePairing() async {
    if (_pairingApprovalVersion != null) return _pairingApprovalVersion!;
    final generation = connectionGeneration;
    final reply = await sendPairingCommand({'cmd': 'capabilities'});
    if (generation != connectionGeneration || reply == null) {
      if (LocalBenchProfile.enabled && generation == connectionGeneration) {
        final capabilitiesFailure = _lastCommandError ?? 'no matching reply';
        final info = await sendPairingCommand({'cmd': 'pairinfo'});
        final infoResult = info == null
            ? (_lastCommandError ?? 'no matching reply')
            : 'reply received (version ${info['pairingApprovalVersion'] ?? 'unspecified'})';
        throw PairingV2Exception(
          'Pairing support read failed. Capabilities: $capabilitiesFailure. '
          'Pair info: $infoResult.',
          restartRequired: true,
        );
      }
      throw const PairingV2Exception(
        'Could not read pairing support. Reconnect and try again.',
        restartRequired: true,
      );
    }
    final version = reply['pairingApprovalVersion'];
    if (version != null &&
        (version is! int || (version != 1 && version != 2))) {
      invalidPairingReply();
    }
    if (reply['cmd'] != 'capabilities' &&
        reply['error'] != 'unknown_command' &&
        reply['error'] != 'unknown_cmd') {
      invalidPairingReply();
    }
    return _pairingApprovalVersion = version == 2 ? 2 : 1;
  }

  void _requirePairingV2(int generation) {
    if (pairingApprovalVersion != 2 ||
        generation != connectionGeneration ||
        !connectionState.isConnected) {
      throw const PairingV2Exception(
        'The pairing connection changed. Leave setup and reconnect.',
        restartRequired: true,
      );
    }
  }

  Future<PairingApproval> approvePairing(
    PairingOffer offer,
    String code,
  ) async {
    final generation = connectionGeneration;
    _requirePairingV2(generation);
    final reply = await sendPairingCommand({
      'cmd': 'pairapprove',
      ...offer.fields,
      'code': code,
    });
    _requirePairingV2(generation);
    if (reply == null) {
      throw const PairingV2Exception(
        'No response. Keep the calculator connected and tap Retry.',
      );
    }
    if (reply['ok'] != true) {
      final error = reply['error'];
      if (error == 'bad_code') {
        throw const PairingV2Exception(
          'Wrong code. Check the calculator and try again.',
        );
      }
      throw const PairingV2Exception(
        'The calculator rejected this pairing attempt. Leave setup and reconnect.',
        restartRequired: true,
      );
    }
    return PairingApproval.fromJson(reply, offer);
  }

  Future<void> completePairing(
    PairingOffer offer,
    PairingApproval approval,
    PairingCompletion completion,
    String owner,
  ) async {
    final generation = connectionGeneration;
    _requirePairingV2(generation);
    final reply = await sendPairingCommand({
      'cmd': 'paircomplete',
      'protocol': 2,
      'mac': offer.mac,
      'challengeId': offer.challengeId,
      'approvalNonce': approval.nonce,
      'completion': completion.fields,
    });
    _requirePairingV2(generation);
    if (reply == null) {
      throw const PairingV2Exception(
        'Could not confirm pairing on the calculator. Keep it connected and tap Retry.',
      );
    }
    if (reply['ok'] != true ||
        reply['cmd'] != 'paircomplete' ||
        reply['protocol'] != 2 ||
        reply['mac'] != offer.mac ||
        reply['challengeId'] != offer.challengeId ||
        reply['ownershipId'] != completion.fields['ownershipId']) {
      invalidPairingReply();
    }
    _pairedOwner = owner;
    notifyListeners();
  }

  /// Whether this calculator has already been claimed by an account.
  ///
  /// Null means the firmware did not answer — either it predates pairing or the
  /// peripheral is not a CalcAI at all.
  Future<bool?> isDevicePaired() async {
    final r = await _command({'cmd': 'pairinfo'});
    final v = r?['paired'];
    final mac = r?['mac'];
    if (mac is String && isValidMacHex(mac)) _deviceMac = mac;
    return v is bool ? v : null;
  }

  /// Changes only the short status shown on the calculator's BLE page.
  /// Pairing, authorization, Wi-Fi state, and advertising are untouched.
  Future<bool> setWifiUiMode(
    bool enabled, {
    bool finishOnConnect = false,
  }) async {
    final r = await _command({
      'cmd': 'uimode',
      'mode': enabled ? 'wifi' : 'normal',
      // Setup ends on a successful join; the Wi-Fi editor stays open until
      // the user leaves it. Older firmware safely ignores this field.
      'finishOnConnect': enabled && finishOnConnect,
    });
    return r?['ok'] == true && r?['mode'] == (enabled ? 'wifi' : 'normal');
  }

  /// Leave the calculator's Wi-Fi page without relying on widget disposal.
  /// A transient missed acknowledgement gets a retry. If both fail, closing
  /// the link clears the volatile firmware flag without changing saved data.
  Future<void> endWifiUiMode() async {
    final generation = connectionGeneration;
    // Release a pending scan's queue slot when leaving setup. A late scan
    // reply must not update a closed page or delay the normal-mode command.
    _wifiScanGeneration++;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (generation != connectionGeneration || !connectionState.isConnected) {
        return;
      }
      if (await setWifiUiMode(false)) return;
    }
    if (generation == connectionGeneration) await disconnect();
  }

  /// Ask the authenticated calculator to stop advertising as well as drop
  /// this link. Only the exact same-connection closed acceptance is success.
  /// This is not a measurement of radio shutdown or the TI's physical screen.
  /// Firmware 1.4.8 preserves accepted shutdown across this disconnect; earlier
  /// versions can lose it. No local sleep can certify that physical outcome.
  Future<bool> closeBlePortal() async {
    final generation = connectionGeneration;
    final reply = await _command({'cmd': 'uimode', 'mode': 'closed'});
    if (generation != connectionGeneration) return false;
    if (reply?['cmd'] != 'uimode' ||
        reply?['ok'] != true ||
        reply?['mode'] != 'closed') {
      return false;
    }
    await disconnect();
    return true;
  }

  /// Claims an unpaired calculator with the six digits shown on its screen.
  ///
  /// Returns null on success, or a short reason to show the user. The firmware
  /// allows five wrong guesses per connection and then burns the code.
  Future<String?> submitPairingCode(String code, String owner) async {
    if (pairingApprovalVersion == 2) {
      return 'This calculator requires secure pairing. Leave setup and reconnect.';
    }
    final r = await _command({'cmd': 'paircode', 'code': code, 'owner': owner});
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

  /// Asks the calculator for a nonce to have an ownership proof signed against.
  ///
  /// Returns null when the firmware predates the signed handshake.
  Future<({String mac, String nonce})?> requestAuthNonce() async {
    final r = await _command({'cmd': 'authnonce'});
    final mac = (r?['mac'] ?? '').toString().toLowerCase();
    final nonce = (r?['nonce'] ?? '').toString().toLowerCase();
    if (!isValidMacHex(mac)) return null;
    if (!RegExp(r'^[0-9a-f]{16,64}$').hasMatch(nonce)) return null;
    return (mac: mac, nonce: nonce);
  }

  /// Identifies this account to an already-paired calculator. Until this
  /// succeeds the firmware refuses every provisioning command, so it runs
  /// before any Wi-Fi work.
  ///
  /// The proof is a signature from the backend, not a name: the calculator
  /// cannot tell one account from another by itself, and the string it used to
  /// compare was the display name -- guessable by anyone in radio range.
  Future<bool> proveOwnership(
    String nonce,
    String response,
    String owner,
  ) async {
    final generation = connectionGeneration;
    final r = await _command({
      'cmd': 'hello',
      'nonce': nonce,
      'response': response,
    });
    if (generation != connectionGeneration) return false;
    final ok = r?['ok'] == true;
    if (ok) {
      _pairedOwner = owner;
      // Saved networks are intentionally deferred until after this handshake.
      // The firmware processes `list` asynchronously on the same characteristic
      // used by pairing, so fetching earlier can overwrite a pairing reply.
      await requestSavedNetworks();
      if (generation != connectionGeneration) return false;
    }
    return ok;
  }

  /// Asks the calculator for a nonce to have a release signed against.
  ///
  /// Returns null when the firmware predates the release command.
  Future<({String mac, String nonce})?> requestReleaseNonce() async {
    final r = await _command({'cmd': 'relnonce'});
    final mac = (r?['mac'] ?? '').toString().toLowerCase();
    final nonce = (r?['nonce'] ?? '').toString().toLowerCase();
    if (!isValidMacHex(mac)) return null;
    if (!RegExp(r'^[0-9a-f]{16,64}$').hasMatch(nonce)) return null;
    return (mac: mac, nonce: nonce);
  }

  /// Hands the calculator a signed instruction to forget its owner.
  ///
  /// The signature is what authorises this, not the connection — the firmware
  /// checks it against a secret only the backend holds, so a phone cannot reset
  /// someone else's calculator by asking.
  Future<bool> releaseOwnership(String nonce, String response) async {
    final r = await _command({
      'cmd': 'release',
      'nonce': nonce,
      'response': response,
    });
    final ok = r?['ok'] == true;
    if (ok) {
      _pairedOwner = null;
    } else {
      _lastCommandError = r?['error']?.toString() ?? _lastCommandError;
    }
    return ok;
  }

  /// The account this connection has identified as, once [proveOwnership] or
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
  /// Also used by the V2 code screen before requesting a signed offer.
  Future<bool> ensureDeviceVerified() async {
    final generation = connectionGeneration;
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

    if (generation != connectionGeneration) return false;
    _verifiedChallenge = challenge;
    if (isValidMacHex(challenge.mac)) _deviceMac = challenge.mac;
    return true;
  }

  // ── WiFi Provisioning ──────────────────────────────────────────────

  Future<bool> _supportsIphoneHotspotKeepAlive() =>
      _serialize(_supportsIphoneHotspotKeepAliveLocked);

  Future<bool> _supportsIphoneHotspotKeepAliveLocked() async {
    final result = await _commandLocked({'cmd': 'capabilities'});
    return result?['iphoneHotspot'] == true;
  }

  /// Sends WiFi credentials to the ESP32 and monitors connection status.
  ///
  /// [ssid] — the network SSID to connect to.
  /// [password] — the network password (empty for open networks).
  Future<bool> sendWifiCredentials({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    if (_networkRemoval != null || _forceSaveInProgress) {
      _setError('Wait for the current Wi-Fi request before changing settings.');
      return false;
    }
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
    if (iphoneHotspot && !await _supportsIphoneHotspotKeepAlive()) {
      _setError('Update the calculator firmware to use iPhone hotspot mode.');
      _provisioningState = ProvisioningState.failed;
      notifyListeners();
      return false;
    }

    if (_networkRemoval != null || _forceSaveInProgress) {
      _setError('Wait for the current Wi-Fi request before changing settings.');
      return false;
    }
    _connectedSsid = ssid;
    _provisioningState = ProvisioningState.sendingCredentials;
    notifyListeners();

    try {
      final payload = jsonEncode({
        'ssid': ssid,
        'password': password,
        'iphoneHotspot': iphoneHotspot,
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
    bool iphoneHotspot = false,
  }) async {
    if (_networkRemoval != null || _forceSaveInProgress) {
      _setError('Wait for the current Wi-Fi request before saving a network.');
      return false;
    }
    _forceSaveInProgress = true;
    try {
      return await _forceSaveNetwork(
        ssid: ssid,
        password: password,
        iphoneHotspot: iphoneHotspot,
      );
    } finally {
      _forceSaveInProgress = false;
    }
  }

  Future<bool> _forceSaveNetwork({
    required String ssid,
    String password = '',
    bool iphoneHotspot = false,
  }) async {
    if (_networkRemoval != null) {
      _setError('Wait for the current Wi-Fi request before changing settings.');
      return false;
    }
    if (_configChar == null) {
      _setError('WiFi config characteristic not available.');
      return false;
    }

    // "Save anyway" still sends the password, so it gets the same check.
    if (!await ensureDeviceVerified()) return false;
    if (iphoneHotspot && !await _supportsIphoneHotspotKeepAlive()) {
      _setError('Update the calculator firmware to use iPhone hotspot mode.');
      return false;
    }

    try {
      if (_networkRemoval != null) {
        _setError('Wait for the current Wi-Fi request before changing settings.');
        return false;
      }
      final payload = jsonEncode({
        'action': 'force_save',
        'ssid': ssid,
        'password': password,
        'iphoneHotspot': iphoneHotspot,
      });

      await _configChar!.write(utf8.encode(payload), withoutResponse: false);

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

  Future<bool> _waitForProvisioningResult({required Duration timeout}) async {
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

  /// Enables or disables keep-alive for one already-saved network.
  Future<bool> setIphoneHotspotKeepAlive(String ssid, bool enabled) =>
      _serialize(() => _setIphoneHotspotKeepAliveLocked(ssid, enabled));

  Future<bool> _setIphoneHotspotKeepAliveLocked(
    String ssid,
    bool enabled,
  ) async {
    if (_configChar == null) {
      _setError('WiFi config characteristic not available.');
      return false;
    }

    _clearError();
    try {
      if (!await _supportsIphoneHotspotKeepAliveLocked()) {
        _setError('Update the calculator firmware to use iPhone hotspot mode.');
        return false;
      }
      final payload = jsonEncode({
        'action': 'set_hotspot',
        'ssid': ssid,
        'iphoneHotspot': enabled,
      });
      await _configChar!.write(utf8.encode(payload), withoutResponse: false);
      final refreshed = await _requestSavedNetworksLocked();

      final updated =
          refreshed &&
          _savedNetworks.contains(ssid) &&
          isIphoneHotspotNetwork(ssid) == enabled;
      if (!updated) {
        _setError(
          'The calculator could not update this setting. Make sure its '
          'firmware is current.',
        );
      }
      return updated;
    } catch (e) {
      _setError('Failed to update hotspot keep-alive: ${_friendlyError(e)}');
      return false;
    }
  }

  /// A GATT write only queues removal. Keep the cache until the calculator
  /// confirms persistent removal with a fresh status notification.
  Future<bool> removeWifiNetwork(String ssid) {
    final generation = connectionGeneration;
    return _serialize(() async {
      if (_disposed || generation != connectionGeneration) return false;
      return _removeWifiNetworkLocked(ssid, generation);
    });
  }

  Future<bool> _removeWifiNetworkLocked(String ssid, int generation) async {
    final config = _configChar;
    final status = _statusChar;
    if (config == null ||
        status == null ||
        connectionState != DeviceConnectionState.ready ||
        pairedOwner == null) {
      _setError('Reconnect to your calculator to remove this network.');
      return false;
    }
    if (!status.properties.notify) {
      _setError(
        'The calculator cannot confirm removal over Bluetooth. '
        'Update its firmware and reconnect before trying again.',
      );
      return false;
    }
    if (_uncertainRemovalGeneration == generation) {
      _setError(
        'Removal was not confirmed. Reconnect to your calculator before '
        'trying again, or refresh its saved networks. It may already be removed.',
      );
      return false;
    }
    if (_forceSaveInProgress ||
        _provisioningState == ProvisioningState.sendingCredentials ||
        _provisioningState == ProvisioningState.waitingForConnection) {
      _setError(
        'Wait for the Wi-Fi connection attempt before removing a network.',
      );
      return false;
    }

    bool current() =>
        !_disposed &&
        generation == connectionGeneration &&
        identical(config, _configChar) &&
        identical(status, _statusChar);
    final completion = Completer<bool>();
    _networkRemoval = completion;
    _clearError();
    var dispatched = false;
    StreamSubscription<List<int>>? subscription;
    Timer? deadline;

    void fail(String message, {bool uncertain = false}) {
      if (completion.isCompleted) return;
      if (current()) {
        if (uncertain && dispatched) _uncertainRemovalGeneration = generation;
        _setError(message);
      }
      if (!completion.isCompleted) completion.complete(false);
    }

    try {
      deadline = Timer(const Duration(seconds: 10), () {
        fail(
          'Network removal timed out. It may already be removed. '
          'Reconnect before trying again, or refresh saved networks.',
          uncertain: true,
        );
      });
      // Unlike lastValueStream this never replays cached status. Do not read
      // or poll this characteristic: a stale matching read is not an ACK.
      subscription = status.onValueReceived.listen(
        (bytes) {
          if (!dispatched || !current() || completion.isCompleted) return;
          try {
            final reply = jsonDecode(utf8.decode(bytes));
            if (reply is! Map<String, dynamic>) return;
            final sameSsid = reply['ssid'] == ssid;
            if (reply['status'] == 'removed' && sameSsid) {
              completion.complete(true);
            } else if (reply['status'] == 'failed' &&
                (sameSsid ||
                    (reply['ssid'] == null &&
                        reply['error'] == 'bad_request'))) {
              fail(
                'The calculator could not confirm removal. It may already be '
                'removed. Refresh saved networks or try again.',
              );
            } else if (reply['status'] == 'error' &&
                reply['error'] == 'no remove handler' &&
                (sameSsid || reply['ssid'] == null)) {
              fail('Update the calculator firmware before removing networks.');
            }
          } catch (_) {
            // Partial, unrelated and wrong-SSID replies cannot confirm removal.
          }
        },
        onError: (Object error) => fail(
          'Could not confirm removal. Reconnect before trying again. '
          'The network may already be removed.',
          uncertain: true,
        ),
        onDone: () => fail(
          'Bluetooth disconnected before removal was confirmed. '
          'Reconnect and refresh saved networks.',
          uncertain: true,
        ),
      );

      // Arm before writing so an immediate firmware notification is not lost.
      // No request fields or pairing/ownership gates are changed.
      unawaited(() async {
        try {
          await status
              .setNotifyValue(true, timeout: 5)
              .timeout(const Duration(seconds: 5));
          if (!current() || completion.isCompleted) return;
          dispatched = true;
          await config
              .write(
                utf8.encode(jsonEncode({'action': 'remove', 'ssid': ssid})),
                withoutResponse: false,
                timeout: 5,
              )
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          fail(
            'Could not confirm removal. Reconnect before trying again. '
            'The network may already be removed.',
            uncertain: dispatched,
          );
        }
      }());

      final confirmed = await completion.future;
      if (!confirmed || !current()) return false;
      _wifiNetworks.removeWhere((n) => n.ssid == ssid);
      _savedNetworks.remove(ssid);
      _iphoneHotspotNetworks.remove(ssid);
      await _persistSavedNetworks();
      if (current()) notifyListeners();
      return current();
    } catch (_) {
      fail('Could not confirm network removal. Reconnect and try again.');
      return false;
    } finally {
      deadline?.cancel();
      await subscription?.cancel();
      if (identical(_networkRemoval, completion)) _networkRemoval = null;
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
  Future<void> clearUserState() async {
    await disconnect();
    _savedNetworks.clear();
    _iphoneHotspotNetworks.clear();
    _savedNetworksLoading = false;
    _savedNetworksError = null;
    _connectedSsid = null;
    _deviceMac = null;
    _persistMac = null;
    _pairedOwner = null;
    _devices.clear();
    _wifiNetworks.clear();
    _error = null;
    notifyListeners();
  }

  /// Resets discovery/provisioning state without forgetting saved networks.
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
    _cancelNetworkRemoval();
    _disposed = true;
    ++_connectionGeneration;
    ++_benchScanGeneration;
    _benchTarget.invalidate();
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _statusNotifySub?.cancel();
    if (!kIsWeb &&
        (Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isLinux)) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }
}
