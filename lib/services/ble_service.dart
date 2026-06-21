import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

import '../models/calcai_device.dart';
import '../models/wifi_network.dart';

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
  });

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
  Future<void> connectToDevice(CalcAiDevice device) async {
    _clearError();
    _setConnectionState(DeviceConnectionState.connecting);
    _connectedDevice = device;
    notifyListeners();

    try {
      // Stop scanning to save power
      await stopScan();

      // Listen for connection state changes
      _connectionSub?.cancel();
      _connectionSub = device.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Connect with a timeout
      await device.device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // Request larger MTU for WiFi scan results (ESP32 sends ~500 bytes)
      if (Platform.isAndroid) {
        await device.device.requestMtu(517);
      }
      // iOS negotiates MTU automatically but we still request it
      try { await device.device.requestMtu(517); } catch (_) {}

      _setConnectionState(DeviceConnectionState.connected);

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

      _setConnectionState(DeviceConnectionState.ready);

      // Subscribe to status notifications if available
      await _subscribeToStatus();

      // Auto-fetch saved networks from the ESP32
      await requestSavedNetworks();
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
    _configChar = null;
    _statusChar = null;
    _wifiNetworks.clear();
    _provisioningState = ProvisioningState.idle;
    _deviceMac = null;
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
      debugPrint('CalcAI BLE: Could not subscribe to status: $e');
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
        // Normalize MAC: "AA:BB:CC:DD:EE:FF" → "aabbccddeeff"
        final rawMac = data['mac'] as String?;
        if (rawMac != null && rawMac.isNotEmpty) {
          _deviceMac = rawMac.replaceAll(':', '').toLowerCase();
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
        debugPrint('CalcAI BLE: scan read attempt ${i + 1}, got ${response.length} bytes');
        if (response.length > 10) break;
        await Future.delayed(const Duration(seconds: 2));
      }

      if (response.isNotEmpty && response.length > 4) {
        _parseWifiScanResults(response);
        debugPrint('CalcAI BLE: parsed ${_wifiNetworks.length} networks');
      } else {
        debugPrint('CalcAI BLE: no scan results received (${response.length} bytes)');
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
      debugPrint('CalcAI BLE: Error parsing WiFi scan results: $e');
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
  Future<void> requestSavedNetworks() async {
    if (_scanChar == null) return;

    try {
      await _scanChar!.write(
        utf8.encode(jsonEncode({'cmd': 'list'})),
        withoutResponse: _scanChar!.properties.writeWithoutResponse,
      );

      // Wait for ESP32 to process and set the value
      await Future.delayed(const Duration(milliseconds: 500));

      final response = await _scanChar!.read();
      if (response.isNotEmpty && response.length > 2) {
        final json = utf8.decode(response);
        final parsed = jsonDecode(json);
        _savedNetworks.clear();
        if (parsed is List) {
          for (final item in parsed) {
            if (item is Map<String, dynamic>) {
              final ssid = item['ssid'] as String? ?? '';
              if (ssid.isNotEmpty) _savedNetworks.add(ssid);
            }
          }
        }
        debugPrint('CalcAI BLE: got ${_savedNetworks.length} saved networks');

        // Persist locally for offline display
        await _persistSavedNetworks();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CalcAI BLE: Error fetching saved networks: $e');
    }
  }

  /// Loads previously saved networks from local storage.
  /// Call this on app startup so the WiFi screen can show networks
  /// even when BLE is not connected.
  Future<void> loadPersistedNetworks(String? deviceMac) async {
    if (deviceMac == null || deviceMac.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('saved_networks_$deviceMac');
      if (json != null) {
        final list = jsonDecode(json) as List;
        _savedNetworks.clear();
        _savedNetworks.addAll(list.cast<String>());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CalcAI BLE: Error loading persisted networks: $e');
    }
  }

  Future<void> _persistSavedNetworks() async {
    final mac = _connectedDevice?.device.remoteId.str;
    if (mac == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'saved_networks_$mac',
        jsonEncode(_savedNetworks),
      );
    } catch (e) {
      debugPrint('CalcAI BLE: Error persisting networks: $e');
    }
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
