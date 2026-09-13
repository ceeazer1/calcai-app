import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_button.dart';
import '../app.dart';

/// Success screen — shown after WiFi provisioning completes.
///
/// Features an animated link symbol and a large paired heading.
/// The Home page button opens the main app.
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pairController;
  late final AnimationController _contentController;
  late final Animation<double> _pairScale;
  late final Animation<double> _pairOpacity;

  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    // ── Link animation ─────────────────────────────────────────
    _pairController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pairScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pairController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _pairOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pairController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    // ── Content fade ────────────────────────────────────────────────
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _contentFade = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOut,
    );

    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _contentController,
            curve: Curves.easeOutCubic,
          ),
        );

    // Start animations
    _pairController.forward();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _contentController.forward();
    });
  }

  @override
  void dispose() {
    _pairController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _onDone() async {
    final ble = context.read<BleService>();
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();

    // Use the WiFi MAC sent by the ESP32 over BLE (reliable on both iOS and
    // Android). Fall back to remoteId only on Android where it is the real MAC.
    // The verified challenge is authoritative: its MAC came from a device that
    // proved itself to the backend. Fall back to the status-reported MAC only
    // if there is no challenge (it is still validated as a real MAC).
    final challenge = ble.verifiedChallenge;
    final mac = challenge?.mac ?? ble.deviceMac ?? ble.connectedDevice?.id;
    // Persist the network(s) saved during setup under this device's MAC so the
    // home page shows them (and they survive restarts).
    if (mac != null) await ble.setPersistMac(mac);
    ble.disconnect();

    // Pairing normally claims the device before Wi-Fi setup begins so turning
    // the calculator off on this page cannot orphan it. Keep the cloud claim as
    // a fallback for older entry paths, but do not submit the same claim twice.
    if (mac != null && auth.token != null) {
      final normalised = mac
          .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
          .toLowerCase();
      if (!auth.deviceMacs.contains(normalised)) {
        final claimed = await cloud.claimDevice(
          auth.token!,
          mac,
          nonce: challenge?.nonce,
          challengeResponse: challenge?.response,
        );
        // Only record the device locally if the backend actually gave it to
        // this account.
        if (!claimed) {
          if (!mounted) return;
          _showClaimFailed(cloud.error);
          return;
        }
      }
      await auth.addDevice(mac);
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AppGate(restoreSession: false),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
      (_) => false,
    );
  }

  /// Explains why setup stopped, and leaves the user where they are instead of
  /// dropping them into an app that looks paired but cannot load anything.
  void _showClaimFailed(String? detail) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          "Couldn't link this CalcAI",
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          detail ??
              'This CalcAI is already linked to another account. Sign in with '
                  'that account, or remove the device from it first.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pairController,
                          builder: (context, _) => Opacity(
                            opacity: _pairOpacity.value,
                            child: Transform.scale(
                              scale: _pairScale.value,
                              child: ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFF5F6FA),
                                        Color(0xFFA5ADBC),
                                      ],
                                    ).createShader(bounds),
                                child: const Icon(
                                  Icons.link_rounded,
                                  size: 112,
                                  color: Colors.white,
                                  semanticLabel: 'Device linked',
                                  shadows: [
                                    Shadow(
                                      color: Color(0x507F879B),
                                      blurRadius: 28,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SlideTransition(
                          position: _contentSlide,
                          child: FadeTransition(
                            opacity: _contentFade,
                            child: Text(
                              'Device paired',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 44,
                                height: 1.12,
                                letterSpacing: -1,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _contentFade,
                  child: GradientButton(
                    label: 'Home page',
                    icon: Icons.home_rounded,
                    onPressed: _onDone,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
