import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_settings.dart';
import '../widgets/scanning_animation.dart';
import 'pair_device_screen.dart';
import 'wifi_setup_screen.dart';

/// Shown when the user is signed in but has no paired CalcAI device.
///
/// The scan runs here rather than on a page of its own: pushing a second
/// screen to show a spinner made the user watch two layouts to do one thing.
enum _Phase { idle, scanning, connecting, connected }

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;
  /// Set when the only fix is the iOS Settings app, so the error can carry a
  /// button instead of asking the user to go find it.
  bool _needsSettings = false;

  @override
  void initState() {
    super.initState();
    context.read<BleService>().addListener(_onBleChanged);
  }

  @override
  void dispose() {
    context.read<BleService>().removeListener(_onBleChanged);
    super.dispose();
  }

  void _onBleChanged() {
    if (!mounted) return;
    final ble = context.read<BleService>();

    if (_phase == _Phase.scanning && ble.devices.isNotEmpty) {
      setState(() => _phase = _Phase.connecting);
      ble.connectToDevice(ble.devices.first);
      return;
    }

    if (_phase == _Phase.connecting &&
        ble.connectionState == DeviceConnectionState.ready) {
      setState(() => _phase = _Phase.connected);
      _afterConnect();
    }
  }

  /// A calculator nobody owns has to be claimed with the code on its screen
  /// before it will accept Wi-Fi credentials, so pairing comes first.
  Future<void> _afterConnect() async {
    final ble = context.read<BleService>();
    final paired = await ble.isDevicePaired();
    if (!mounted) return;

    // No answer at all: firmware older than the pairing feature, or the read
    // failed. Falling through would hand the Wi-Fi password to a calculator we
    // could not identify, and would silently skip the step that makes it yours.
    if (paired == null) {
      setState(() {
        _phase = _Phase.idle;
        _error = 'This calculator needs a firmware update before it can pair.';
      });
      return;
    }

    if (paired == false) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PairDeviceScreen()),
      );
      if (!mounted) return;
      if (ok != true) {
        setState(() => _phase = _Phase.idle);
        return;
      }
    } else if (paired == true) {
      // Identify this account. The firmware refuses every provisioning command
      // until it matches the owner it stored, so a failure here has to stop the
      // flow — otherwise the user reaches Wi-Fi setup, types their password,
      // and the calculator silently drops it with nothing on screen to explain.
      final owner = context.read<AuthService>().username;
      final isOwner = owner != null && await ble.announceOwner(owner);
      if (!mounted) return;
      if (!isOwner) {
        setState(() {
          _phase = _Phase.idle;
          _error = 'This calculator belongs to another account.';
        });
        return;
      }
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WifiSetupScreen()),
    );
  }

  Future<void> _scan() async {
    final ble = context.read<BleService>();
    setState(() {
      _error = null;
      _needsSettings = false;
      _phase = _Phase.scanning;
    });

    // Refused once, iOS never asks again — Settings is the only way back.
    if (!await ble.requestPermissions()) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _needsSettings = true;
        _error = 'CalcAI needs Bluetooth access to find your calculator.';
      });
      return;
    }
    // The radio being off is handled by the system power alert (it has its own
    // Settings button), so this is only a fallback if the user dismisses it.
    if (!await ble.isBluetoothOn()) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = 'Turn on Bluetooth, then tap Scan again.';
      });
      return;
    }
    await ble.startScan();
    if (!mounted) return;
    // Scanning finished with nothing in range.
    if (_phase == _Phase.scanning && context.read<BleService>().devices.isEmpty) {
      setState(() {
        _phase = _Phase.idle;
        _error = 'No calculator found. Open Settings > BLE on it, then retry.';
      });
    }
  }

  String get _status {
    switch (_phase) {
      case _Phase.scanning:
        return 'Looking for your calculator';
      case _Phase.connecting:
        return 'Connecting';
      case _Phase.connected:
        return 'Connected';
      case _Phase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase != _Phase.idle;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    // Clear cloud state too, or the next account to sign in on
                    // this phone sees the previous user's history and notes.
                    onPressed: () {
                      context.read<AuthService>().signOut();
                      context.read<CloudService>().reset();
                    },
                    icon: const Icon(Icons.logout_rounded,
                        color: AppColors.textTertiary, size: 20),
                    tooltip: 'Sign out',
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  'Pair your device',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),

                Expanded(
                  child: Center(
                    child: busy
                        ? ScanningAnimation(
                            isScanning: _phase != _Phase.connected,
                            size: 260,
                            color: _phase == _Phase.connected
                                ? AppColors.accentBlue
                                : AppColors.electricBlue,
                            child: Icon(
                              _phase == _Phase.connected
                                  ? Icons.check_rounded
                                  : Icons.bluetooth_searching_rounded,
                              size: 40,
                              color: _phase == _Phase.connected
                                  ? AppColors.accentBlue
                                  : AppColors.electricBlue,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),

                if (busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _status,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.error,
                          ),
                        ),
                        if (_needsSettings) ...[
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: openAppSettings,
                            child: Text(
                              'Open Settings',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.electricBlue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: busy ? null : _scan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.electricBlue,
                      disabledBackgroundColor: AppColors.surfaceLight,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bluetooth_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Scan',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => context.read<AuthService>().skipSetup(),
                  child: Text(
                    'Set up later',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
