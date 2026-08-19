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

    // No answer. Two very different causes with the same null: firmware that
    // predates pairing, or a link that broke before the command landed. Saying
    // "update the firmware" for the second one sends people to reflash a board
    // that was already fine, so separate them.
    if (paired == null) {
      final err = ble.lastCommandError;
      setState(() {
        _phase = _Phase.idle;
        _error = err == null
            ? 'This calculator needs a firmware update before it can pair.'
            : "Lost the connection before pairing could start. If you've just "
                'updated the calculator, forget it in iPhone Settings > '
                'Bluetooth, then scan again.';
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
      // Register with the backend as soon as the code is accepted, not at the
      // end of Wi-Fi setup. Ownership is settled here; leaving the server claim
      // until later meant a calculator switched off mid-setup ended up claimed
      // on the device but unknown to the account, and the next sign-in dropped
      // the user back into setup with no way to tell why.
      if (!await _claimWithBackend()) return;
    } else if (paired == true) {
      // Identify this account. The firmware refuses every provisioning command
      // until it matches the owner it stored, so a failure here has to stop the
      // flow — otherwise the user reaches Wi-Fi setup, types their password,
      // and the calculator silently drops it with nothing on screen to explain.
      final owner = context.read<AuthService>().username;
      final isOwner = owner != null && await ble.announceOwner(owner);
      if (!mounted) return;
      if (!isOwner) {
        // Not ours — but it may have been released by an admin, in which case
        // the backend will sign an instruction telling it to forget its old
        // owner. Without this the calculator is unusable by anyone forever:
        // unpairing clears the server record and cannot reach the device.
        if (await _tryRelease()) {
          if (!mounted) return;
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const PairDeviceScreen()),
          );
          if (!mounted) return;
          if (ok != true) {
            setState(() => _phase = _Phase.idle);
            return;
          }
          if (!await _claimWithBackend()) return;
        } else {
          setState(() {
            _phase = _Phase.idle;
            _error = 'This calculator belongs to another account.';
          });
          return;
        }
      } else {
        // Already ours on the device but possibly not yet on the account —
        // exactly what an interrupted setup leaves behind, so repair it rather
        // than walking past it.
        final auth = context.read<AuthService>();
        if (auth.primaryMac == null || auth.primaryMac!.isEmpty) {
          if (!await _claimWithBackend()) return;
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WifiSetupScreen()),
    );
  }

  /// Clears a calculator whose owner an admin has released.
  ///
  /// The device picks the nonce and the backend signs it, so neither this app
  /// nor a stranger's can wipe a calculator that is still legitimately owned —
  /// the backend refuses to sign for one, and the firmware refuses an unsigned
  /// instruction.
  Future<bool> _tryRelease() async {
    final ble = context.read<BleService>();
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    final token = auth.token;
    if (token == null) return false;

    final ask = await ble.requestReleaseNonce();
    if (!mounted || ask == null) return false;

    final signature =
        await cloud.requestPairingRelease(token, ask.mac, ask.nonce);
    if (!mounted || signature == null) return false;

    final released = await ble.releaseOwnership(ask.nonce, signature);
    if (!mounted) return false;
    return released;
  }

  /// Records the calculator against this account. Returns false when it could
  /// not be done, having already shown why.
  Future<bool> _claimWithBackend() async {
    final ble = context.read<BleService>();
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();

    final challenge = ble.verifiedChallenge ?? await ble.requestIdentityChallenge();
    if (!mounted) return false;
    final mac = challenge?.mac ?? ble.deviceMac ?? ble.connectedDevice?.id;
    final token = auth.token;
    if (mac == null || token == null) {
      setState(() {
        _phase = _Phase.idle;
        _error = 'Could not read the calculator id. Try scanning again.';
      });
      return false;
    }

    await ble.setPersistMac(mac);
    final claimed = await cloud.claimDevice(
      token,
      mac,
      nonce: challenge?.nonce,
      challengeResponse: challenge?.response,
    );
    if (!mounted) return false;
    if (!claimed) {
      setState(() {
        _phase = _Phase.idle;
        _error = cloud.error ?? 'Could not add this calculator to your account.';
      });
      return false;
    }
    await auth.addDevice(mac);
    return mounted;
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
    // Ten seconds is the default scan window and startScan only returns when it
    // closes, but a device found early moves the phase on via the listener — so
    // check that we are still scanning before calling it a miss. Reporting
    // "not found" while the radio was still looking was why the first attempt
    // always failed and the second, reading the devices left from the first,
    // appeared to work.
    await ble.startScan(timeout: const Duration(seconds: 6));
    if (!mounted) return;
    if (_phase == _Phase.scanning && ble.devices.isEmpty) {
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
