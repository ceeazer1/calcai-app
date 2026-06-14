import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

/// WiFi management screen — BLE-dependent, requires nearby CalcAI device.
class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  bool _isAddingNetwork = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: SafeArea(
        child: Consumer<BleService>(
          builder: (context, ble, _) {
            final isConnected =
                ble.connectionState == DeviceConnectionState.connected;

            return Column(
              children: [
                // ── Header ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        'WiFi Networks',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      _BleStatusChip(isConnected: isConnected),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Content ─────────────────────────────────
                Expanded(
                  child: isConnected
                      ? _buildConnectedView(ble)
                      : _buildDisconnectedView(ble),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDisconnectedView(BleService ble) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceLight,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Icon(
              Icons.bluetooth_disabled_rounded,
              color: AppColors.textTertiary,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Not Connected',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Move closer to your CalcAI device\nto manage WiFi networks',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _connectToDevice(ble),
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 20),
              label: Text(
                'Connect',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceLight,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.glassBorder),
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildConnectedView(BleService ble) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        // ── Saved Networks ───────────────────────────
        Text(
          'Saved Networks',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),

        if (ble.wifiNetworks.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No networks saved yet',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          )
        else
          ...ble.wifiNetworks.asMap().entries.map((entry) {
            final network = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_rounded,
                      color: entry.key == 0
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            network.ssid,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            entry.key == 0 ? 'Connected' : 'Saved',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: entry.key == 0
                                  ? AppColors.success
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (entry.key > 0)
                      IconButton(
                        onPressed: () => _removeNetwork(network.ssid),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 16),

        // ── Add Network Button ───────────────────────
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isAddingNetwork ? null : () => _addNetwork(ble),
            icon: _isAddingNetwork
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(AppColors.textOnAccent),
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(
              _isAddingNetwork ? 'Scanning...' : 'Add Network',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _connectToDevice(BleService ble) async {
    // Start BLE scan and auto-connect to first CalcAI device
    final hasPerms = await ble.requestPermissions();
    if (!hasPerms) return;

    await ble.startScan();

    // Wait for devices to appear
    await Future.delayed(const Duration(seconds: 5));

    if (ble.devices.isNotEmpty) {
      await ble.connectToDevice(ble.devices.first);
    }
  }

  Future<void> _addNetwork(BleService ble) async {
    setState(() => _isAddingNetwork = true);
    try {
      await ble.requestWifiScan();
      if (!mounted) return;

      // Show network picker bottom sheet
      _showNetworkPicker(ble);
    } finally {
      if (mounted) setState(() => _isAddingNetwork = false);
    }
  }

  void _showNetworkPicker(BleService ble) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.6,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.glassBorder, width: 0.5),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Select WiFi Network',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: ble.wifiNetworks.isEmpty
                  ? Center(
                      child: Text(
                        'No networks found',
                        style: GoogleFonts.inter(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: ble.wifiNetworks.length,
                      itemBuilder: (context, index) {
                        final network = ble.wifiNetworks[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                _showPasswordDialog(network.ssid);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.wifi_rounded,
                                      color: AppColors.textSecondary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        network.ssid,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${network.rssi} dBm',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

  void _showPasswordDialog(String ssid) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Enter Password',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ssid,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: GoogleFonts.inter(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'WiFi password',
                hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final ble = context.read<BleService>();
              ble.sendWifiCredentials(ssid, passwordController.text);
            },
            child: Text(
              'Connect',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _removeNetwork(String ssid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Remove Network?',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Remove "$ssid" from your CalcAI device?',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Send remove command via BLE
            },
            child: Text(
              'Remove',
              style: GoogleFonts.inter(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _BleStatusChip extends StatelessWidget {
  final bool isConnected;

  const _BleStatusChip({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isConnected ? AppColors.success : AppColors.textTertiary)
            .withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isConnected ? AppColors.success : AppColors.textTertiary)
              .withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            size: 14,
            color: isConnected ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: 5),
          Text(
            isConnected ? 'Connected' : 'Not Connected',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isConnected ? AppColors.success : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
