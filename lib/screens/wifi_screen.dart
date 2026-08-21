import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

/// WiFi management screen — BLE-dependent, requires nearby CalcAI device.
///
/// Opened as a full page from the Home screen (no longer a bottom-nav tab).
/// Auto-connects to the device over BLE as soon as it opens.
class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key, this.isActive = true});

  /// Whether the screen is currently visible. Defaults to true because the
  /// screen is now pushed on demand, so opening it should auto-connect.
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

  /// True while this account proves ownership to a claimed calculator.
  bool _authenticating = false;

  /// True when the last attempt failed because Bluetooth is off/unavailable
  /// (vs. the device simply not being found nearby).
  bool _btOff = false;

  /// Whether a connect attempt has finished at least once. Until then we show
  /// "Searching…" instead of the failed state, so there's no initial flash.
  bool _attempted = false;

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
    final ble = context.read<BleService>();
    ble.removeListener(_onBle);
    // Cut the BLE link entirely when leaving this screen so the app isn't
    // left silently connected to the calculator after WiFi management is done.
    ble.disconnect();
    super.dispose();
  }

  /// User tapped "skip" — stop searching and show the not-found state now.
  void _skipSearch() {
    context.read<BleService>().stopScan();
    _btOff = false; // skip is only offered while Bluetooth is on
    _stopAutoConnecting();
  }

  void _stopAutoConnecting() {
    _connectTimeout?.cancel();
    _connectStarted = false;
    if (mounted) {
      setState(() {
        _autoConnecting = false;
        _attempted = true;
      });
    } else {
      _autoConnecting = false;
      _attempted = true;
    }
  }

  /// Side-effect listener: connect to the first CalcAI found during an
  /// auto-connect scan, and clear the flag once resolved.
  void _onBle() {
    if (!mounted || !_autoConnecting) return;
    final ble = context.read<BleService>();

    // A raw BLE link is not enough on a claimed calculator. Once service
    // discovery is complete, prove ownership before showing it as connected.
    if (ble.connectionState == DeviceConnectionState.ready) {
      unawaited(_authenticateConnectedDevice());
      return;
    }

    // A started connect attempt failed → stop showing the connecting state.
    if (_connectStarted && ble.connectionState == DeviceConnectionState.error) {
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
      _btOff = false;
    });

    final granted = await ble.requestPermissions();
    final on = granted && await ble.isBluetoothOn();
    if (!granted || !on) {
      _btOff = true;
      _stopAutoConnecting();
      return;
    }

    // Fast path: reconnect straight to the last paired device (no scan).
    final reconnected = await ble.reconnectKnownDevice();
    if (!mounted) return;
    if (reconnected || ble.connectionState.isConnected) {
      if (ble.connectionState == DeviceConnectionState.ready) {
        unawaited(_authenticateConnectedDevice());
      }
      return;
    }

    // Fall back to scanning for the device.
    _connectStarted = false;
    _connectTimeout?.cancel();
    // Short timeout so a missing device drops to "Bluetooth disconnected"
    // quickly instead of leaving the user on "Connecting…".
    _connectTimeout = Timer(const Duration(seconds: 12), () {
      if (mounted && _autoConnecting) {
        ble.stopScan();
        ble.disconnect();
        _stopAutoConnecting();
      }
    });

    // Fire the scan — _onBle handles connecting when a device appears.
    ble.startScan();
  }

  Future<void> _authenticateConnectedDevice() async {
    if (_authenticating || !_autoConnecting || !mounted) return;
    _authenticating = true;
    setState(() {});

    final ble = context.read<BleService>();
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    var proved = false;

    try {
      final token = auth.token;
      final owner = auth.email;
      if (token != null && owner != null && owner.isNotEmpty) {
        final ask = await ble.requestAuthNonce();
        if (ask != null) {
          final signature =
              await cloud.requestOwnershipProof(token, ask.mac, ask.nonce);
          if (signature != null) {
            proved = await ble.proveOwnership(ask.nonce, signature, owner);
          }
        }
      }
    } finally {
      _authenticating = false;
    }

    if (!mounted) return;
    if (proved) {
      // Presentation only: the TI-84 BLE page shows "WIFI MODE" while this
      // authenticated management screen owns the connection. Disconnecting on
      // dispose clears it in firmware even if this request is interrupted.
      await ble.setWifiUiMode(true);
      if (!mounted) return;
      _stopAutoConnecting();
    } else {
      await ble.disconnect();
      _stopAutoConnecting();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Consumer<BleService>(
            builder: (context, ble, _) {
              final isConnected =
                  ble.connectionState == DeviceConnectionState.ready &&
                      ble.pairedOwner != null;

              return Column(
                children: [
                  // ── Header ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'WiFi Networks',
                          style: GoogleFonts.outfit(
                            fontSize: 26,
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

                  // Connected → show the saved-network list. While the list is
                  // still being fetched (first load), show a connected phase
                  // with the device name instead of a premature empty list.
                  Expanded(
                    child: isConnected
                        ? (ble.savedNetworksLoading && ble.savedNetworks.isEmpty
                            ? _buildConnectedLoading(ble)
                            : _buildNetworkList(ble))
                        : _buildDisconnectedView(ble),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Shown until the device is connected. The screen is just the Bluetooth
  /// symbol plus "Searching…" while looking for the CalcAI, switching to
  /// "Connecting…" once one is found. If it can't be found, it drops straight
  /// to "Bluetooth disconnected" with a retry.
  Widget _buildDisconnectedView(BleService ble) {
    // A device has been found and we're establishing the link.
    final isLinking = _connectStarted ||
        _authenticating ||
        (ble.connectionState != DeviceConnectionState.disconnected &&
            ble.connectionState != DeviceConnectionState.error);
    // Show the searching UI while connecting, or before the first attempt has
    // resolved (avoids a "Calc not found" flash on open).
    final searching = _autoConnecting || !_attempted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: searching
              ? [
                  const _SearchingBleIcon(),
                  const SizedBox(height: 18),
                  Text(
                    _authenticating
                        ? 'Verifying…'
                        : isLinking
                            ? 'Connecting…'
                            : 'Searching…',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Plain "skip" link — stop waiting and jump to the not-found
                  // state instead of sitting through the timeout.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _skipSearch,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 16),
                      child: Text(
                        'skip',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ]
              : [
                  Icon(
                    _btOff
                        ? Icons.bluetooth_disabled_rounded
                        : Icons.search_off_rounded,
                    color: AppColors.textTertiary,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _btOff ? 'Bluetooth disconnected' : 'Calc not found',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _attemptAutoConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricBlue,
                        foregroundColor: AppColors.textOnAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Try again',
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
    );
  }

  /// Connected, but the saved-network list is still loading over BLE. Shows the
  /// device it linked to so the user sees the connection succeeded.
  Widget _buildConnectedLoading(BleService ble) {
    final name = ble.connectedDevice?.name ?? 'your CalcAI';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bluetooth_connected_rounded,
                color: AppColors.accentBlue,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Connected',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.accentBlue,
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading networks…',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
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

        // ── Scan for networks ────────────────────────
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
                : const Icon(Icons.wifi_find_rounded),
            label: Text(
              _isAddingNetwork ? 'Scanning…' : 'Scan network',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ),

        // ── Manual entry — plain text, no box ────────
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isAddingNetwork ? null : _showManualNetworkDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Text(
                'Add network manually',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Manual SSID + password entry, for hidden networks or when the scan can't
  /// see the network.
  void _showManualNetworkDialog() {
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    bool iphoneHotspot = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.glassBorder),
          ),
          title: Text(
            'Add Network',
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
                'Enter the network name exactly as it appears.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ssidController,
                autocorrect: false,
                autofocus: true,
                style: GoogleFonts.inter(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Network name (SSID)',
                  hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: GoogleFonts.inter(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Password (leave blank if open)',
                  hintStyle: GoogleFonts.inter(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: iphoneHotspot,
                activeColor: AppColors.lightBlue,
                title: Text(
                  'iPhone hotspot',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Keep it active while your iPhone is locked.',
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                onChanged: (value) =>
                    setDialogState(() => iphoneHotspot = value),
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
                final ssid = ssidController.text.trim();
                if (ssid.isEmpty) return;
                Navigator.pop(ctx);
                _attemptConnect(
                  ssid,
                  passwordController.text,
                  iphoneHotspot: iphoneHotspot,
                );
              },
              child: Text(
                'Connect',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
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
      final isIphoneHotspot = ble.isIphoneHotspotNetwork(ssid);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          onTap: readOnly ? null : () => _showSavedNetworkSettings(ble, ssid),
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
                      '${isCurrentlyConnected ? 'Connected' : 'Saved'}'
                      '${isIphoneHotspot ? ' • iPhone hotspot' : ''}',
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

  void _showSavedNetworkSettings(BleService ble, String ssid) {
    bool iphoneHotspot = ble.isIphoneHotspotNetwork(ssid);
    bool updating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.glassBorder),
          ),
          title: Text(
            ssid,
            style: GoogleFonts.outfit(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: iphoneHotspot,
            activeColor: AppColors.lightBlue,
            title: Text(
              'iPhone hotspot',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Keep this hotspot active while your iPhone is locked. Uses a '
              'small amount of data and battery.',
              style: GoogleFonts.inter(
                color: AppColors.textTertiary,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            onChanged: updating
                ? null
                : (value) async {
                    setDialogState(() => updating = true);
                    final success =
                        await ble.setIphoneHotspotKeepAlive(ssid, value);
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      if (success) iphoneHotspot = value;
                      updating = false;
                    });
                    if (!success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ble.error ?? 'Could not update hotspot setting.',
                          ),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
          ),
          actions: [
            TextButton(
              onPressed: updating ? null : () => Navigator.pop(ctx),
              child: Text(
                'Done',
                style: GoogleFonts.inter(color: AppColors.electricBlue),
              ),
            ),
          ],
        ),
      ),
    );
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

  void _showPasswordDialog(
    String ssid, {
    bool initialIphoneHotspot = false,
  }) {
    final passwordController = TextEditingController();
    bool iphoneHotspot = initialIphoneHotspot;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: iphoneHotspot,
                activeColor: AppColors.lightBlue,
                title: Text(
                  'iPhone hotspot',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Keep it active while your iPhone is locked.',
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                onChanged: (value) =>
                    setDialogState(() => iphoneHotspot = value),
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
                _attemptConnect(
                  ssid,
                  passwordController.text,
                  iphoneHotspot: iphoneHotspot,
                );
              },
              child: Text(
                'Connect',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attemptConnect(
    String ssid,
    String password, {
    bool iphoneHotspot = false,
  }) async {
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
              width: 24,
              height: 24,
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
      iphoneHotspot: iphoneHotspot,
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
      _showConnectionFailedDialog(
        ssid,
        password,
        iphoneHotspot: iphoneHotspot,
        error: ble.error,
      );
    }
  }

  void _showConnectionFailedDialog(
    String ssid,
    String password, {
    bool iphoneHotspot = false,
    String? error,
  }) {
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
          error ??
              'Could not connect to "$ssid". The password may be incorrect, '
                  'or the network may be out of range.',
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
              _showPasswordDialog(
                ssid,
                initialIphoneHotspot: iphoneHotspot,
              );
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
              await ble.forceSaveNetwork(
                ssid: ssid,
                password: password,
                iphoneHotspot: iphoneHotspot,
              );
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

/// Large Bluetooth symbol that pulses while we search for the CalcAI device.
class _SearchingBleIcon extends StatefulWidget {
  const _SearchingBleIcon();

  @override
  State<_SearchingBleIcon> createState() => _SearchingBleIconState();
}

class _SearchingBleIconState extends State<_SearchingBleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06 + 0.06 * t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.10 + 0.22 * t),
                blurRadius: 12 + 20 * t,
                spreadRadius: 1 + 4 * t,
              ),
            ],
          ),
          child: const Icon(
            Icons.bluetooth_searching_rounded,
            color: color,
            size: 40,
          ),
        );
      },
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
