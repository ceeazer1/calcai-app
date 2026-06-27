import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

/// WiFi management screen — BLE-dependent, requires nearby CalcAI device.
class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key, this.isActive = false});

  /// Whether this tab is currently the visible one. The shell flips this so
  /// the screen can auto-connect over BLE when the user opens the tab.
  final bool isActive;

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  bool _isAddingNetwork = false;

  /// True while we're scanning for + connecting to the device from this tab.
  bool _autoConnecting = false;

  /// Guards against calling connectToDevice more than once per scan.
  bool _connectStarted = false;

  /// Fallback timer that gives up auto-connect if nothing connects in time.
  Timer? _connectTimeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleService>().addListener(_onBle);
      if (widget.isActive) _attemptAutoConnect();
    });
  }

  @override
  void didUpdateWidget(covariant WifiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tab just became visible → try to reconnect to the device.
    if (!oldWidget.isActive && widget.isActive) {
      _attemptAutoConnect();
    }
  }

  @override
  void dispose() {
    _connectTimeout?.cancel();
    context.read<BleService>().removeListener(_onBle);
    super.dispose();
  }

  void _stopAutoConnecting() {
    _connectTimeout?.cancel();
    _connectStarted = false;
    if (mounted) setState(() => _autoConnecting = false);
  }

  /// Side-effect listener: connect to the first CalcAI found during an
  /// auto-connect scan, and clear the flag once resolved.
  void _onBle() {
    if (!mounted || !_autoConnecting) return;
    final ble = context.read<BleService>();

    // Connected → done.
    if (ble.connectionState.isConnected) {
      _stopAutoConnecting();
      return;
    }

    // A started connect attempt failed → stop showing the connecting state.
    if (_connectStarted &&
        ble.connectionState == DeviceConnectionState.error) {
      _stopAutoConnecting();
      return;
    }

    // First device found during the scan → connect to it.
    if (!_connectStarted && ble.devices.isNotEmpty) {
      _connectStarted = true;
      ble.connectToDevice(ble.devices.first);
    }
    // Note: "nothing found" is handled by the timeout timer, not here, so we
    // don't give up before the scan has had time to discover the device.
  }

  /// Scans for a nearby CalcAI and connects to it. Safe to call repeatedly.
  Future<void> _attemptAutoConnect() async {
    final ble = context.read<BleService>();
    if (ble.connectionState.isConnected || _autoConnecting) return;

    setState(() {
      _autoConnecting = true;
      _connectStarted = false;
    });

    final granted = await ble.requestPermissions();
    final on = granted && await ble.isBluetoothOn();
    if (!granted || !on) {
      _stopAutoConnecting();
      return;
    }

    // Fast path: reconnect straight to the last paired device (no scan).
    final reconnected = await ble.reconnectKnownDevice();
    if (!mounted) return;
    if (reconnected || ble.connectionState.isConnected) {
      _stopAutoConnecting();
      return;
    }

    // Fall back to scanning for the device.
    _connectStarted = false;
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 20), () {
      if (mounted && _autoConnecting && !ble.connectionState.isConnected) {
        ble.stopScan();
        _stopAutoConnecting();
      }
    });

    // Fire the scan — _onBle handles connecting when a device appears.
    ble.startScan();
  }

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
                ble.connectionState == DeviceConnectionState.connected ||
                ble.connectionState == DeviceConnectionState.ready ||
                ble.connectionState == DeviceConnectionState.discovering;

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
                      // Glowing Bluetooth icon = device connected.
                      if (isConnected) const _GlowingBleIcon(),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Connected → network list. Otherwise a simple connect prompt.
                Expanded(
                  child: isConnected
                      ? _buildNetworkList(ble)
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
    return Column(
      children: [
        // ── Saved Networks on top, read-only, fading out at the bottom ──
        Expanded(
          flex: 3,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.5, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                _savedNetworksHeader(),
                const SizedBox(height: 10),
                Opacity(
                  opacity: 0.6,
                  child: Column(
                    children: _savedNetworkTiles(ble, readOnly: true),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Bluetooth not connected, around the middle (no box) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _autoConnecting
                    ? Icons.bluetooth_searching_rounded
                    : Icons.bluetooth_disabled_rounded,
                color: AppColors.textTertiary,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                _autoConnecting ? 'Connecting…' : 'Bluetooth not connected',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Turn on Bluetooth from CalcAI Settings to manage Wi-Fi.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Settings > Bluetooth > On',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _autoConnecting ? null : _attemptAutoConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.surfaceHighlight,
                    disabledForegroundColor: AppColors.textTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _autoConnecting ? 'Connecting…' : 'Connect',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Empty space below so the prompt sits around the middle.
        const Expanded(flex: 2, child: SizedBox()),
      ],
    );
  }

  Widget _buildNetworkList(BleService ble) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        _savedNetworksHeader(),
        const SizedBox(height: 10),
        ..._savedNetworkTiles(ble, readOnly: false),
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

  Widget _savedNetworksHeader() {
    return Text(
      'Saved Networks',
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  /// Saved-network tiles. When [readOnly] (Bluetooth disconnected) the remove
  /// button is hidden so the list is view-only.
  List<Widget> _savedNetworkTiles(BleService ble, {required bool readOnly}) {
    if (ble.savedNetworks.isEmpty) {
      return [
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
        ),
      ];
    }
    return ble.savedNetworks.map((ssid) {
      final isCurrentlyConnected = ssid == ble.connectedSsid;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.wifi_rounded,
                color: isCurrentlyConnected
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
                      ssid,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      isCurrentlyConnected ? 'Connected' : 'Saved',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isCurrentlyConnected
                            ? AppColors.success
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!readOnly)
                IconButton(
                  onPressed: () => _removeNetwork(ssid),
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
    }).toList();
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
              _attemptConnect(ssid, passwordController.text);
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

  Future<void> _attemptConnect(String ssid, String password) async {
    final ble = context.read<BleService>();

    // Show a connecting indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        content: Row(
          children: [
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.electricBlue,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Connecting to $ssid...',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );

    final success = await ble.sendWifiCredentials(
      ssid: ssid,
      password: password,
    );

    if (!mounted) return;
    Navigator.pop(context); // dismiss connecting dialog

    if (success) {
      // Show success briefly
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $ssid'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      // Show failure dialog with Save Anyway option
      _showConnectionFailedDialog(ssid, password);
    }
  }

  void _showConnectionFailedDialog(String ssid, String password) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        icon: Icon(
          Icons.wifi_off_rounded,
          color: AppColors.error,
          size: 32,
        ),
        title: Text(
          'Connection Failed',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Could not connect to "$ssid". The password may be incorrect, or the network may be out of range.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Re-open password dialog to try again
              _showPasswordDialog(ssid);
            },
            child: Text(
              'Try Again',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ble = context.read<BleService>();
              await ble.forceSaveNetwork(ssid: ssid, password: password);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$ssid saved for later'),
                    backgroundColor: AppColors.surface,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            },
            child: Text(
              'Save Anyway',
              style: GoogleFonts.inter(
                color: AppColors.electricBlue,
                fontWeight: FontWeight.w600,
              ),
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
              final ble = context.read<BleService>();
              ble.removeWifiNetwork(ssid);
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

/// A small Bluetooth icon with a softly pulsing glow — shown when the device
/// is connected over BLE.
class _GlowingBleIcon extends StatefulWidget {
  const _GlowingBleIcon();

  @override
  State<_GlowingBleIcon> createState() => _GlowingBleIconState();
}

class _GlowingBleIconState extends State<_GlowingBleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const color = AppColors.electricBlue;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.25 + 0.40 * t),
                blurRadius: 6 + 12 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: const Icon(
            Icons.bluetooth_connected_rounded,
            color: color,
            size: 16,
          ),
        );
      },
    );
  }
}
