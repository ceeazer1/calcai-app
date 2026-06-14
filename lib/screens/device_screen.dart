import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import 'wifi_setup_screen.dart';

/// Device detail screen — shows connection info and status after
/// connecting to a CalcAI BLE device.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.device,
  });

  /// The device the user tapped on the scan screen.
  final CalcAiDevice device;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen>
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

    // Auto-connect
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleService>().connectToDevice(widget.device);
    });
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  void _navigateToWifiSetup() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WifiSetupScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
  }

  void _handleDisconnect() {
    context.read<BleService>().disconnect();
    Navigator.of(context).pop();
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
                final state = ble.connectionState;
                final isReady = state == DeviceConnectionState.ready;

                return Column(
                  children: [
                    // ── App Bar ───────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _handleDisconnect,
                            icon: const Icon(
                              Icons.arrow_back_ios_rounded,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Device',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          // Disconnect button
                          if (state.isConnected)
                            TextButton(
                              onPressed: _handleDisconnect,
                              child: Text(
                                'Disconnect',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 80),
                        ],
                      ),
                    ),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),

                            // ── Device icon ──────────────────────
                            _AnimatedDeviceIcon(state: state),

                            const SizedBox(height: 24),

                            // ── Device name ──────────────────────
                            Text(
                              widget.device.name,
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),

                            const SizedBox(height: 8),

                            // ── Connection status ────────────────
                            _ConnectionStatusBadge(state: state),

                            const SizedBox(height: 32),

                            // ── Info cards ───────────────────────
                            Row(
                              children: [
                                Expanded(
                                  child: _InfoCard(
                                    icon: Icons.perm_device_info_rounded,
                                    label: 'Device ID',
                                    value: widget.device.id.length > 12
                                        ? '${widget.device.id.substring(0, 12)}…'
                                        : widget.device.id,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _InfoCard(
                                    icon: widget.device.signalIcon,
                                    label: 'Signal',
                                    value: '${widget.device.rssi} dBm',
                                    valueColor: widget.device.signalColor,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: _InfoCard(
                                    icon: Icons.bluetooth_rounded,
                                    label: 'Protocol',
                                    value: 'BLE 5.0',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _InfoCard(
                                    icon: Icons.speed_rounded,
                                    label: 'Status',
                                    value: state.label,
                                    valueColor: state.color,
                                  ),
                                ),
                              ],
                            ),

                            // ── Error message ────────────────────
                            if (ble.error != null) ...[
                              const SizedBox(height: 20),
                              GlassCard(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
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
                            ],

                            const SizedBox(height: 40),

                            // ── WiFi Setup button ────────────────
                            GradientButton(
                              label: 'Set Up WiFi',
                              icon: Icons.wifi_rounded,
                              onPressed: _navigateToWifiSetup,
                              enabled: isReady,
                              width: double.infinity,
                              isLoading: state == DeviceConnectionState.connecting ||
                                  state == DeviceConnectionState.discovering,
                            ),

                            const SizedBox(height: 16),

                            if (!isReady &&
                                state != DeviceConnectionState.error)
                              Text(
                                state == DeviceConnectionState.connecting
                                    ? 'Establishing connection…'
                                    : state == DeviceConnectionState.discovering
                                        ? 'Discovering services…'
                                        : 'Waiting for device…',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textTertiary,
                                ),
                              ),

                            if (state == DeviceConnectionState.error) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () {
                                  context
                                      .read<BleService>()
                                      .connectToDevice(widget.device);
                                },
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Retry Connection'),
                              ),
                            ],
                          ],
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

class _AnimatedDeviceIcon extends StatelessWidget {
  const _AnimatedDeviceIcon({required this.state});

  final DeviceConnectionState state;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradientSoft,
          border: Border.all(
            color: state.color.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: state.color.withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: state == DeviceConnectionState.connecting ||
                  state == DeviceConnectionState.discovering
              ? SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(state.color),
                  ),
                )
              : Icon(
                  state == DeviceConnectionState.error
                      ? Icons.bluetooth_disabled_rounded
                      : Icons.bluetooth_connected_rounded,
                  color: state.color,
                  size: 40,
                  key: ValueKey(state),
                ),
        ),
      ),
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({required this.state});

  final DeviceConnectionState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: state.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: state.color.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: state.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: state.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 18),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
