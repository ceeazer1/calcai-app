import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../models/wifi_network.dart';
import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_button.dart';
import '../widgets/wifi_network_tile.dart';
import '../app.dart';
import 'success_screen.dart';

/// WiFi setup screen — lists networks discovered by the ESP32 and
/// lets the user pick one, enter a password, and provision.
class WifiSetupScreen extends StatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _fadeIn;

  String? _connectingSsid;
  WifiNetwork? _selectedNetwork;
  final _password = TextEditingController();
  final _networkScroll = ScrollController();
  String? _passwordError;
  bool _obscure = true;
  bool _iphoneHotspot = false;
  late final BleService _ble;

  @override
  void initState() {
    super.initState();
    _ble = context.read<BleService>();

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _enterController, curve: Curves.easeOut);
    _enterController.forward();

    // Tell the calculator what this authenticated connection is doing, then
    // start the scan. Both commands share BleService's serialized queue.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ble = context.read<BleService>();
      await ble.setWifiUiMode(true);
      if (mounted) await ble.requestWifiScan();
    });
  }

  @override
  void dispose() {
    // Best effort only. A disconnect also clears this volatile firmware flag,
    // so an interrupted route can never leave the device stuck in Wi-Fi mode.
    unawaited(_ble.setWifiUiMode(false));
    _enterController.dispose();
    _password.dispose();
    _networkScroll.dispose();
    super.dispose();
  }

  void _onNetworkTapped(WifiNetwork network) {
    if (_connectingSsid != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedNetwork = _selectedNetwork?.ssid == network.ssid
          ? null
          : network;
      _password.clear();
      _passwordError = null;
      _obscure = true;
      _iphoneHotspot = false;
    });
    if (_networkScroll.hasClients) {
      _networkScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _connectSelected() {
    final network = _selectedNetwork;
    if (network == null || _connectingSsid != null) return;
    if (network.isSecured && _password.text.isEmpty) {
      setState(() => _passwordError = 'Enter the network password.');
      return;
    }
    FocusScope.of(context).unfocus();
    _provisionWifi(
      network.ssid,
      network.isSecured ? _password.text : '',
      iphoneHotspot: _iphoneHotspot,
    );
  }

  Widget _networkDetails() {
    final secured = _selectedNetwork?.isSecured ?? false;
    final busy = _connectingSsid != null;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: AppColors.glassBorder),
          const SizedBox(height: 18),
          if (secured)
            TextField(
              controller: _password,
              enabled: !busy,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connectSelected(),
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Wi-Fi password',
                errorText: _passwordError,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: busy
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            Text(
              'No password needed.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _iphoneHotspot,
            activeTrackColor: AppColors.textSecondary,
            title: Text(
              'iPhone hotspot',
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            onChanged: busy
                ? null
                : (value) => setState(() => _iphoneHotspot = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: busy ? null : _connectSelected,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _provisionWifi(
    String ssid,
    String password, {
    bool iphoneHotspot = false,
  }) async {
    setState(() => _connectingSsid = ssid);

    final ble = context.read<BleService>();
    final success = await ble.sendWifiCredentials(
      ssid: ssid,
      password: password,
      iphoneHotspot: iphoneHotspot,
    );

    if (!mounted) return;

    setState(() => _connectingSsid = null);

    if (success) {
      _navigateToSuccess(ssid);
    } else {
      _showProvisioningError(ble.error ?? 'Connection failed');
    }
  }

  void _navigateToSuccess(String ssid) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SuccessScreen(),
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _showProvisioningError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: GoogleFonts.inter(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Retry',
          textColor: AppColors.electricBlue,
          onPressed: () {
            context.read<BleService>().requestWifiScan();
          },
        ),
      ),
    );
  }

  Future<void> _skipForNow() async {
    final auth = context.read<AuthService>();
    final ble = context.read<BleService>();
    final mac = auth.primaryMac;
    if (mac != null && mac.isNotEmpty) {
      // The device was already claimed before this page opened. Announce the
      // saved device now that the setup route is safely on screen.
      await auth.addDevice(mac);
    }
    await ble.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppGate(restoreSession: false)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Consumer<BleService>(
              builder: (context, ble, _) {
                final isScanning =
                    ble.provisioningState == ProvisioningState.scanning;
                final isSending =
                    ble.provisioningState ==
                        ProvisioningState.sendingCredentials ||
                    ble.provisioningState ==
                        ProvisioningState.waitingForConnection;

                return PopScope(
                  canPop: !isSending,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        excluding: isSending,
                        child: Column(
                          children: [
                            // ── App Bar ───────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(
                                      Icons.arrow_back_ios_rounded,
                                      size: 20,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'WiFi Setup',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  // Refresh button
                                  IconButton(
                                    onPressed: isScanning || isSending
                                        ? null
                                        : () => ble.requestWifiScan(),
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: isScanning
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(AppColors.electricBlue),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.refresh_rounded,
                                              size: 22,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── Content ──────────────────────────────────
                            Expanded(
                              child: isScanning && ble.wifiNetworks.isEmpty
                                  ? _ScanningState()
                                  : ble.wifiNetworks.isEmpty
                                  ? _EmptyNetworkState(
                                      onRetry: () => ble.requestWifiScan(),
                                    )
                                  : _NetworkList(
                                      networks: ble.wifiNetworks,
                                      selectedNetwork: _selectedNetwork,
                                      selectedDetails: _networkDetails(),
                                      scrollController: _networkScroll,
                                      connectingSsid: _connectingSsid,
                                      onTap: _onNetworkTapped,
                                      isSending: isSending,
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                              child: TextButton(
                                onPressed: isSending ? null : _skipForNow,
                                child: Text(
                                  'Skip for now',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSending) ...[
                        const ModalBarrier(
                          dismissible: false,
                          color: Color(0x99000000),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Semantics(
                              liveRegion: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Connecting to ${_connectingSsid ?? _selectedNetwork?.ssid ?? 'Wi-Fi'}',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 17,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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

class _ScanningState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.electricBlue.withOpacity(0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Scanning for WiFi networks…',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your CalcAI device is looking for\nnearby networks',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNetworkState extends StatelessWidget {
  const _EmptyNetworkState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: AppColors.textTertiary, size: 48),
          const SizedBox(height: 16),
          Text(
            'No networks found',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your WiFi router is\npowered on and nearby',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: 'Scan Again',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
            width: 160,
            height: 48,
          ),
        ],
      ),
    );
  }
}

class _NetworkList extends StatelessWidget {
  const _NetworkList({
    required this.networks,
    required this.selectedNetwork,
    required this.selectedDetails,
    required this.scrollController,
    required this.connectingSsid,
    required this.onTap,
    required this.isSending,
  });

  final List<WifiNetwork> networks;
  final WifiNetwork? selectedNetwork;
  final Widget selectedDetails;
  final ScrollController scrollController;
  final String? connectingSsid;
  final Function(WifiNetwork) onTap;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final orderedNetworks = [
      if (selectedNetwork != null) selectedNetwork!,
      ...networks.where((network) => network.ssid != selectedNetwork?.ssid),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'Available Networks',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.electricBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${networks.length}',
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
          child: _RisingNetworkCards(
            networks: orderedNetworks,
            selectedSsid: selectedNetwork?.ssid,
            selectedDetails: selectedDetails,
            scrollController: scrollController,
            connectingSsid: connectingSsid,
            onTap: onTap,
            isSending: isSending,
          ),
        ),
      ],
    );
  }
}

/// Preserve each card's previous position while the new order is laid out,
/// then ease it into place. Measuring actual rows also handles expanded forms.
class _RisingNetworkCards extends StatefulWidget {
  const _RisingNetworkCards({
    required this.networks,
    required this.selectedSsid,
    required this.selectedDetails,
    required this.scrollController,
    required this.connectingSsid,
    required this.onTap,
    required this.isSending,
  });
  final List<WifiNetwork> networks;
  final String? selectedSsid;
  final Widget selectedDetails;
  final ScrollController scrollController;
  final String? connectingSsid;
  final Function(WifiNetwork) onTap;
  final bool isSending;

  @override
  State<_RisingNetworkCards> createState() => _RisingNetworkCardsState();
}

class _RisingNetworkCardsState extends State<_RisingNetworkCards>
    with SingleTickerProviderStateMixin {
  final _keys = <String, GlobalKey>{};
  final _deltas = <String, double>{};
  bool _showDetails = false;
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _move.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showDetails = true);
      }
    });
  }

  double? _top(String ssid) {
    final box = _keys[ssid]?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero).dy
        : null;
  }

  @override
  void didUpdateWidget(covariant _RisingNetworkCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSsid == widget.selectedSsid) return;
    final remaining = 1 - Curves.easeInOutCubic.transform(_move.value);
    final previous = <String, double>{};
    for (final network in oldWidget.networks) {
      final top = _top(network.ssid);
      if (top != null) {
        previous[network.ssid] = top + (_deltas[network.ssid] ?? 0) * remaining;
      }
    }
    _move.stop();
    _showDetails = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _deltas.clear();
      for (final network in widget.networks) {
        final top = _top(network.ssid);
        final before = previous[network.ssid];
        if (top != null && before != null) _deltas[network.ssid] = before - top;
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        setState(() {
          _deltas.clear();
          _showDetails = true;
        });
        _move.value = 1;
      } else {
        _move.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: widget.networks.map((network) {
          final selected = widget.selectedSsid == network.ssid;
          return SizedBox(
            key: _keys.putIfAbsent(network.ssid, () => GlobalKey()),
            child: AnimatedBuilder(
              animation: _move,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  0,
                  (_deltas[network.ssid] ?? 0) *
                      (1 - Curves.easeInOutCubic.transform(_move.value)),
                ),
                child: child,
              ),
              child: WifiNetworkTile(
                network: network,
                isSelected: selected,
                expandedChild: selected && _showDetails
                    ? widget.selectedDetails
                    : null,
                isConnecting: false,
                onTap: widget.isSending ? () {} : () => widget.onTap(network),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
