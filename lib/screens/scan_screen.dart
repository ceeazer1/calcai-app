import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/scanning_animation.dart';
import 'wifi_setup_screen.dart';

enum _ScanPhase { scanning, connecting, connected, failed }

/// Full-screen BLE scan screen.
/// Auto-scans, auto-connects to the first CalcAI device found, then
/// transitions to the WiFi setup screen once the connection is ready.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  _ScanPhase _phase = _ScanPhase.scanning;

  /// Advertised name of the device we connected to (e.g. "CalcAI-BD21").
  String? _connectedName;

  late final AnimationController _enterController;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _enterController, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleService>().addListener(_onBleChanged);
      _startScan();
    });
  }

  @override
  void dispose() {
    context.read<BleService>().removeListener(_onBleChanged);
    _enterController.dispose();
    super.dispose();
  }

  void _onBleChanged() {
    if (!mounted) return;
    final ble = context.read<BleService>();

    // First device found → auto-connect
    if (_phase == _ScanPhase.scanning && ble.devices.isNotEmpty) {
      setState(() => _phase = _ScanPhase.connecting);
      ble.connectToDevice(ble.devices.first);
      return;
    }

    // Connected and ready → show success + device name, wait for the user
    // to tap Continue (no auto-navigate).
    if (_phase == _ScanPhase.connecting &&
        ble.connectionState == DeviceConnectionState.ready) {
      setState(() {
        _phase = _ScanPhase.connected;
        _connectedName = ble.connectedDevice?.name;
      });
      return;
    }

    // Connection error → allow retry
    if (_phase == _ScanPhase.connecting &&
        ble.connectionState == DeviceConnectionState.error) {
      setState(() => _phase = _ScanPhase.failed);
    }

    // Scan timed out without finding anything
    if (_phase == _ScanPhase.scanning && !ble.isScanning) {
      setState(() => _phase = _ScanPhase.failed);
    }
  }

  Future<void> _startScan() async {
    if (!mounted) return;
    setState(() => _phase = _ScanPhase.scanning);

    final ble = context.read<BleService>();

    final hasPermissions = await ble.requestPermissions();
    if (!hasPermissions && mounted) {
      _showDialog(
        title: 'Permissions Required',
        body: 'CalcAI needs Bluetooth permission to scan for your device.',
      );
      setState(() => _phase = _ScanPhase.failed);
      return;
    }

    final btOn = await ble.isBluetoothOn();
    if (!btOn && mounted) {
      _showDialog(
        title: 'Bluetooth Off',
        body: 'Please enable Bluetooth and tap Scan Again.',
      );
      setState(() => _phase = _ScanPhase.failed);
      return;
    }

    ble.startScan();
  }

  void _navigateToWifi() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WifiSetupScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  void _showDialog({required String title, required String body}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _statusText {
    switch (_phase) {
      case _ScanPhase.scanning:
        return 'Searching for your CalcAI…';
      case _ScanPhase.connecting:
        return 'Device found — connecting…';
      case _ScanPhase.connected:
        return 'Connected to ${_connectedName ?? 'your CalcAI'}';
      case _ScanPhase.failed:
        return 'No device found nearby';
    }
  }

  bool get _isActive =>
      _phase == _ScanPhase.scanning || _phase == _ScanPhase.connecting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Column(
              children: [
                // ── Top bar ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_ios_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      _PhaseChip(phase: _phase),
                    ],
                  ),
                ),

                // ── Animation — fills the rest of the screen ──────────
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.elasticOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: _phase == _ScanPhase.connected
                          ? const _ConnectedIcon(key: ValueKey('connected'))
                          : ScanningAnimation(
                              key: const ValueKey('radar'),
                              isScanning: _isActive,
                              size: 300,
                              color: _phase == _ScanPhase.connecting
                                  ? AppColors.success
                                  : AppColors.electricBlue,
                              child: _CenterIcon(phase: _phase),
                            ),
                    ),
                  ),
                ),

                // ── Status text ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _statusText,
                      key: ValueKey(_phase),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _phase == _ScanPhase.connected
                            ? AppColors.success
                            : AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),

                // ── Scan Again button ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: switch (_phase) {
                        _ScanPhase.connected => _navigateToWifi,
                        _ScanPhase.failed => _startScan,
                        _ => null,
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _phase == _ScanPhase.connected
                            ? AppColors.success
                            : AppColors.electricBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.surfaceHighlight,
                        disabledForegroundColor: AppColors.textTertiary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        switch (_phase) {
                          _ScanPhase.connected => 'Continue',
                          _ScanPhase.failed => 'Scan Again',
                          _ => 'Scanning…',
                        },
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

/// The icon shown in the center of the radar while scanning/connecting.
class _CenterIcon extends StatelessWidget {
  const _CenterIcon({required this.phase});
  final _ScanPhase phase;

  @override
  Widget build(BuildContext context) {
    final isConnecting = phase == _ScanPhase.connecting;
    final color =
        isConnecting ? AppColors.success : AppColors.electricBlue;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Icon(
        isConnecting
            ? Icons.bluetooth_connected_rounded
            : Icons.bluetooth_searching_rounded,
        color: color,
        size: 30,
      ),
    );
  }
}

/// Success icon shown after connection is established.
class _ConnectedIcon extends StatelessWidget {
  const _ConnectedIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.success.withOpacity(0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withOpacity(0.2),
              blurRadius: 40,
              spreadRadius: 8,
            ),
          ],
        ),
        child: const Icon(
          Icons.check_rounded,
          color: AppColors.success,
          size: 52,
        ),
      ),
    );
  }
}

/// Small chip in the top-right showing current phase.
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase});
  final _ScanPhase phase;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      _ScanPhase.scanning => ('Scanning', AppColors.electricBlue),
      _ScanPhase.connecting => ('Connecting', AppColors.warning),
      _ScanPhase.connected => ('Connected', AppColors.success),
      _ScanPhase.failed => ('Not found', AppColors.textTertiary),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
