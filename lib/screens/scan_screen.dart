import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/scanning_animation.dart';
import 'device_screen.dart';

/// The BLE scanning screen — shows a radar animation and lists
/// discovered CalcAI devices.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOut,
    );
    _enterController.forward();

    // Start scan after a brief delay
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    final ble = context.read<BleService>();

    final hasPermissions = await ble.requestPermissions();
    if (!hasPermissions && mounted) {
      _showPermissionDialog();
      return;
    }

    final bluetoothOn = await ble.isBluetoothOn();
    if (!bluetoothOn && mounted) {
      _showBluetoothOffDialog();
      return;
    }

    ble.startScan();
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'CalcAI needs Bluetooth and Location permissions to scan for '
          'nearby devices. Please grant the permissions and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startScan();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _showBluetoothOffDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bluetooth Off'),
        content: const Text(
          'Please enable Bluetooth on your device to scan for CalcAI devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startScan();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _onDeviceTapped(CalcAiDevice device) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => DeviceScreen(device: device),
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Consumer<BleService>(
              builder: (context, ble, _) {
                return Column(
                  children: [
                    // ── Header ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'calcai_logo',
                            child: Material(
                              color: Colors.transparent,
                              child: ShaderMask(
                                shaderCallback: (bounds) =>
                                    AppColors.accentGradient
                                        .createShader(bounds),
                                child: Text(
                                  'CalcAI',
                                  style: GoogleFonts.outfit(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          _StatusChip(isScanning: ble.isScanning),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Scanning animation ─────────────────────────
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: ScanningAnimation(
                          isScanning: ble.isScanning,
                          size: 260,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.electricBlue.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.electricBlue.withOpacity(0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.bluetooth_searching_rounded,
                              color: AppColors.electricBlue,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Error message ──────────────────────────────
                    if (ble.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ble.error!,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Devices list ───────────────────────────────
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(24, 16, 24, 12),
                            child: Row(
                              children: [
                                Text(
                                  'Nearby Devices',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.electricBlue
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${ble.devices.length}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.electricBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ble.devices.isEmpty
                                ? _EmptyState(isScanning: ble.isScanning)
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    itemCount: ble.devices.length,
                                    itemBuilder: (context, index) {
                                      final device = ble.devices[index];
                                      return _DeviceCard(
                                        device: device,
                                        index: index,
                                        onTap: () => _onDeviceTapped(device),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // ── Scan button ────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: ble.isScanning ? null : _startScan,
                          icon: ble.isScanning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      AppColors.textOnAccent,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(
                            ble.isScanning ? 'Scanning…' : 'Scan Again',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isScanning ? AppColors.electricBlue : AppColors.textTertiary)
            .withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              (isScanning ? AppColors.electricBlue : AppColors.textTertiary)
                  .withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color:
                  isScanning ? AppColors.electricBlue : AppColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isScanning ? 'Scanning' : 'Idle',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isScanning
                  ? AppColors.electricBlue
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.index,
    required this.onTap,
  });

  final CalcAiDevice device;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            // BLE icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradientSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.bluetooth_rounded,
                color: AppColors.electricBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),

            // Name + ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.id,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Signal
            Column(
              children: [
                Icon(
                  device.signalIcon,
                  color: device.signalColor,
                  size: 18,
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.rssi} dBm',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isScanning
                ? Icons.bluetooth_searching_rounded
                : Icons.bluetooth_disabled_rounded,
            color: AppColors.textTertiary,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            isScanning
                ? 'Looking for CalcAI devices…'
                : 'No devices found',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
          if (!isScanning) ...[
            const SizedBox(height: 4),
            Text(
              'Make sure your CalcAI device is powered on',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textTertiary.withOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
