import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/link_device_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/ble_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAuth());
  }

  Future<void> _initAuth() async {
    final auth = context.read<AuthService>();
    final ble = context.read<BleService>();
    await auth.init();

    // Load persisted WiFi networks so they display offline
    if (auth.isAuthenticated && auth.primaryMac != null) {
      await ble.loadPersistedNetworks(auth.primaryMac);
    }

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // ── Still loading persisted session (initial app boot only) ────────
    if (!_initialized) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
    if (auth.primaryMac == null || auth.primaryMac!.isEmpty) {
      return const LinkDeviceScreen();
    }

    // ── Authenticated + device linked → main navigation shell ─────────
    return const MainShell();
  }
}
