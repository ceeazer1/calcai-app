import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/calcai_device.dart';
import '../models/wifi_network.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/wifi_network_tile.dart';
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

    // Start WiFi scan immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleService>().requestWifiScan();
    });
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  Future<void> _onNetworkTapped(WifiNetwork network) async {
    if (network.isSecured) {
      final password = await _showPasswordDialog(network.ssid);
      if (password == null) return; // User cancelled
      _provisionWifi(network.ssid, password);
    } else {
      _provisionWifi(network.ssid, '');
    }
  }

  Future<String?> _showPasswordDialog(String ssid) async {
    final controller = TextEditingController();
    bool obscure = true;

    return showDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(
                  color: AppColors.glassBorder,
                  width: 0.5,
                ),
              ),
              title: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.electricBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.wifi_lock_rounded,
                      color: AppColors.electricBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ssid,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter the WiFi password to connect your CalcAI device.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                        onPressed: () {
                          setDialogState(() => obscure = !obscure);
                        },
                      ),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) Navigator.pop(ctx, value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(color: AppColors.textTertiary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (controller.text.isNotEmpty) {
                      Navigator.pop(ctx, controller.text);
                    }
                  },
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _provisionWifi(String ssid, String password) async {
    setState(() => _connectingSsid = ssid);

    final ble = context.read<BleService>();
    final success = await ble.sendWifiCredentials(
      ssid: ssid,
      password: password,
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
        pageBuilder: (_, __, ___) => SuccessScreen(ssid: ssid),
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
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
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
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
                final isScanning =
                    ble.provisioningState == ProvisioningState.scanning;
                final isSending = ble.provisioningState ==
                        ProvisioningState.sendingCredentials ||
                    ble.provisioningState ==
                        ProvisioningState.waitingForConnection;

                return Column(
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
                              duration: const Duration(milliseconds: 300),
                              child: isScanning
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          AppColors.electricBlue,
                                        ),
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

                    // ── Provisioning progress ────────────────────
                    if (isSending) ...[
                      const SizedBox(height: 8),
                      _ProvisioningProgress(state: ble.provisioningState),
                    ],

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
                                  connectingSsid: _connectingSsid,
                                  onTap: _onNetworkTapped,
                                  isSending: isSending,
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

class _ProvisioningProgress extends StatelessWidget {
  const _ProvisioningProgress({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.electricBlue),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Please wait while your device connects…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
          Icon(
            Icons.wifi_off_rounded,
            color: AppColors.textTertiary,
            size: 48,
          ),
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
    required this.connectingSsid,
    required this.onTap,
    required this.isSending,
  });

  final List<WifiNetwork> networks;
  final String? connectingSsid;
  final Function(WifiNetwork) onTap;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Text(
                'Available Networks',
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
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: networks.length,
            itemBuilder: (context, index) {
              final network = networks[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + (index * 80)),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: WifiNetworkTile(
                  network: network,
                  isConnecting: connectingSsid == network.ssid,
                  onTap: isSending ? () {} : () => onTap(network),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
