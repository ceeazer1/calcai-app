import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/link_device_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/ble_service.dart';
import 'services/cloud_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/calcai_mark.dart';

/// Root widget for the CalcAI application.
///
/// Applies the dark theme and delegates the initial route decision to
/// [_AppGate], which watches [AuthService] to show the appropriate screen.
class CalcAIApp extends StatelessWidget {
  const CalcAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalcAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _AppGate(),
    );
  }
}

/// Gate widget that resolves which top-level screen to display based on
/// the current [AuthService] state.
///
/// - **Loading** → minimal splash / loading indicator
/// - **Not authenticated** → [AuthScreen]
/// - **Authenticated, no devices** → [LinkDeviceScreen] (one-time WiFi setup)
/// - **Authenticated with devices** → [MainShell]
///
/// Because this widget watches [AuthService] via [Provider], it will
/// automatically rebuild whenever the auth state changes (e.g. after
/// sign-in, sign-out, or device pairing).
class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _initialized = false;
  bool _handlingDeviceRevocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAuth());
  }

  Future<void> _initAuth() async {
    final auth = context.read<AuthService>();
    final ble = context.read<BleService>();
    final cloud = context.read<CloudService>();

    // Let BleService ask the backend whether a peripheral is a genuine CalcAI
    // before it sends the user's Wi-Fi password to it. Wired here because this
    // is the first point where all three services exist; BleService fails
    // closed if it is missing, so a broken wiring blocks setup rather than
    // quietly disabling the check.
    ble.deviceVerifier = (challenge) async {
      final token = auth.token;
      if (token == null) return false;
      return cloud.verifyDevice(
        token,
        challenge.mac,
        challenge.nonce,
        challenge.response,
      );
    };

    await auth.init();

    // Load persisted WiFi networks so they display offline
    if (auth.isAuthenticated && auth.primaryMac != null) {
      await ble.loadPersistedNetworks(auth.primaryMac);
    }

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _handleDeviceRevocation(
    AuthService auth,
    CloudService cloud,
  ) async {
    if (_handlingDeviceRevocation) return;
    _handlingDeviceRevocation = true;
    cloud.clearDeviceRevoked();

    final token = auth.token;
    final mac = auth.primaryMac;
    final stillOwned = token != null && mac != null
        ? await cloud.confirmDeviceOwnership(token, mac)
        : false;

    if (!mounted) return;
    if (stillOwned == false) {
      cloud.reset();
      await auth.forgetDevice();
    }
    // A failed confirmation is normally a temporary network/auth problem.
    // Preserve the pairing until Cloudflare can answer authoritatively.
    _handlingDeviceRevocation = false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final cloud = context.watch<CloudService>();

    // The backend has stopped recognising this account as the owner — an admin
    // unpaired the calculator, or it was claimed elsewhere. Drop the stored MAC
    // so routing sends the user back to setup instead of leaving them on a
    // dashboard whose every control silently fails.
    if (cloud.deviceRevoked) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleDeviceRevocation(auth, cloud),
      );
    }

    // ── Still loading persisted session (initial app boot only) ────────
    if (!_initialized) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CalcAiMark(size: 64),
              const SizedBox(height: 20),
              Text(
                'CalcAI',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.electricBlue,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Not authenticated → sign-in screen ──────────────────────────
    if (!auth.isAuthenticated) {
      return const AuthScreen();
    }

    // ── Authenticated, no device linked → first-time setup ────────────
    // Walk the user through the one-time Bluetooth WiFi-provisioning flow
    // before they reach the main shell.
    if ((auth.primaryMac == null || auth.primaryMac!.isEmpty) &&
        !auth.setupSkipped) {
      return const LinkDeviceScreen();
    }

    // ── Authenticated + device linked → main navigation shell ─────────
    return const MainShell();
  }
}
