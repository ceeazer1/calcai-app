// Test-only iPhone discovery harness. Never imported by lib/main.dart.
// Explicit entrypoint: -t tool/bench_ble_discovery.dart
// Enable manually with --dart-define=CALCAI_BENCH_BLE=true.
// This file only observes advertisements. It has no connection or account flow.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _enabled = bool.fromEnvironment('CALCAI_BENCH_BLE');
const _targetName = 'CALCAI-C62E';
const _scanWindow = Duration(seconds: 10);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _DiscoveryScreen(),
    ),
  );
}

class _Advertisement {
  const _Advertisement(this.name, this.id, this.rssi);
  final String name;
  final String id;
  final int rssi;
  bool get isTarget => name == _targetName;
}

class _DiscoveryScreen extends StatefulWidget {
  const _DiscoveryScreen();

  @override
  State<_DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<_DiscoveryScreen>
    with WidgetsBindingObserver {
  final Map<String, _Advertisement> _advertisements = {};
  StreamSubscription<List<ScanResult>>? _results;
  StreamSubscription<BluetoothAdapterState>? _adapter;
  StreamSubscription<bool>? _scanning;
  Completer<void>? _finished;
  Timer? _deadline;
  bool _busy = false;
  bool _stopRequested = false;
  bool _nativeTouched = false;
  String _status = 'Ready. Tap Scan for a 10-second discovery window.';

  bool get _allowed =>
      _enabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _busy) {
      unawaited(
        _requestStop('Scan stopped because the app left the foreground.'),
      );
    }
  }

  bool get _current => mounted && _busy && !_stopRequested;

  String _adapterMessage(BluetoothAdapterState state) => switch (state) {
    BluetoothAdapterState.unauthorized =>
      'Bluetooth access denied. Enable CalcAI in iPhone Settings > Privacy & Security > Bluetooth, then retry.',
    BluetoothAdapterState.unavailable =>
      'Bluetooth is unavailable on this device.',
    BluetoothAdapterState.off || BluetoothAdapterState.turningOff =>
      'Bluetooth is off. Turn it on in iPhone Settings, then retry.',
    _ => 'Bluetooth is not ready. Wait a moment, then retry.',
  };

  Future<void> _stopNative() async {
    if (!_nativeTouched) return;
    // No connection exists in this harness; only the discovery scan is stopped.
    await FlutterBluePlus.stopScan();
  }

  Future<void> _requestStop(String reason) async {
    if (!_busy) return;
    _stopRequested = true;
    if (mounted) setState(() => _status = reason);
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
    try {
      await _stopNative();
    } catch (error) {
      if (mounted) {
        setState(() => _status = '$reason Could not stop discovery: $error');
      }
    }
  }

  Future<void> _scan() async {
    if (!_allowed || _busy) return;
    setState(() {
      _busy = true;
      _stopRequested = false;
      _advertisements.clear();
      _status = 'Checking iPhone Bluetooth access…';
    });
    _finished = Completer<void>();
    // Also request a stop if native startup or an adapter query stalls. Keep
    // Scan disabled until the pending native operation and cleanup finish.
    _deadline = Timer(
      const Duration(seconds: 25),
      () => unawaited(
        _requestStop('Discovery timed out. Retry when Bluetooth is ready.'),
      ),
    );
    try {
      _nativeTouched = true;
      final supported = await FlutterBluePlus.isSupported.timeout(
        const Duration(seconds: 5),
      );
      if (!_current) return;
      if (!supported) {
        setState(() => _status = 'Bluetooth is not supported on this device.');
        return;
      }
      final state = await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 8));
      if (!_current) return;
      if (state != BluetoothAdapterState.on) {
        setState(() => _status = _adapterMessage(state));
        return;
      }

      _results = FlutterBluePlus.onScanResults.listen(
        (results) {
          if (!_current) return;
          setState(() {
            for (final result in results) {
              // Use the exact advertisement local name, never a cached device
              // name. Keep unnamed advertisements visible as unnamed.
              final id = result.device.remoteId.str;
              _advertisements[id] = _Advertisement(
                result.advertisementData.advName,
                id,
                result.rssi,
              );
            }
          });
        },
        onError: (Object error) {
          unawaited(_requestStop('Discovery error: $error'));
        },
      );
      _adapter = FlutterBluePlus.adapterState.listen(
        (state) {
          if (_current && state != BluetoothAdapterState.on) {
            unawaited(_requestStop(_adapterMessage(state)));
          }
        },
        onError: (Object error) {
          unawaited(_requestStop('Bluetooth state error: $error'));
        },
      );
      if (!_current) return;
      setState(() => _status = 'Scanning advertisements for 10 seconds…');
      await FlutterBluePlus.startScan(timeout: _scanWindow);
      if (!_current) return;
      _scanning = FlutterBluePlus.isScanning.listen(
        (scanning) {
          final finished = _finished;
          if (!scanning && finished != null && !finished.isCompleted) {
            finished.complete();
          }
        },
        onError: (Object error) {
          unawaited(_requestStop('Discovery state error: $error'));
        },
      );
      await _finished!.future.timeout(const Duration(seconds: 12));
      if (_current) {
        final matches = _advertisements.values
            .where((row) => row.isTarget)
            .length;
        setState(() {
          _status = matches == 0
              ? 'Scan complete. Exact advertisement $_targetName was not observed.'
              : 'Scan complete. Exact advertisement $_targetName observed from $matches peripheral(s).';
        });
      }
    } on TimeoutException {
      if (mounted && !_stopRequested) {
        setState(
          () => _status =
              'Discovery timed out. Check Bluetooth access and retry.',
        );
      }
    } catch (error) {
      if (mounted && !_stopRequested) {
        setState(() => _status = 'Discovery failed: $error');
      }
    } finally {
      _stopRequested = true;
      _deadline?.cancel();
      _deadline = null;
      await _results?.cancel();
      await _adapter?.cancel();
      await _scanning?.cancel();
      _results = null;
      _adapter = null;
      _scanning = null;
      try {
        await _stopNative();
      } catch (error) {
        if (mounted) {
          setState(
            () => _status = 'Could not confirm discovery stopped: $error',
          );
        }
      }
      _finished = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRequested = true;
    _deadline?.cancel();
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
    unawaited(_results?.cancel());
    unawaited(_adapter?.cancel());
    unawaited(_scanning?.cancel());
    unawaited(_stopNative().catchError((Object _) {}));
    // _scan also stops after any in-flight startup returns, including disposal
    // while the native start call was pending.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _advertisements.values.toList()
      ..sort((a, b) {
        if (a.isTarget != b.isTarget) return a.isTarget ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Bench BLE discovery only')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Target: $_targetName\nAdvertisements only. No connection, pairing, sign-in, or ownership changes. Rows have no selection action.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  !_enabled
                      ? 'Disabled. Build this entrypoint with CALCAI_BENCH_BLE=true to enable discovery.'
                      : !_allowed
                      ? 'Disabled. This harness is for the physical iPhone only.'
                      : _status,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                children: [
                  ElevatedButton(
                    onPressed: _allowed && !_busy ? _scan : null,
                    child: const Text('Scan for 10 seconds'),
                  ),
                  OutlinedButton(
                    onPressed: _busy && !_stopRequested
                        ? () =>
                              unawaited(_requestStop('Scan stopped manually.'))
                        : null,
                    child: const Text('Stop scan'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Card(
                    color: row.isTarget ? Colors.green.shade900 : null,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        '${row.isTarget ? 'EXACT TARGET MATCH\n' : ''}'
                        'Advertisement local name: ${row.name.isEmpty ? '(absent)' : row.name}\n'
                        'iPhone peripheral UUID: ${row.id}\n'
                        'RSSI: ${row.rssi} dBm',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
