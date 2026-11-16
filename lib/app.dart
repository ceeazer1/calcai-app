import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/ai_consent_screen.dart';
import 'screens/link_device_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/ble_service.dart';
import 'services/cloud_service.dart';
import 'services/local_bench_profile.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/calcai_mark.dart';

/// Root widget for the CalcAI application.
///
/// Applies the dark theme and delegates the initial route decision to
/// [AppGate], which watches [AuthService] to show the appropriate screen.
class CalcAIApp extends StatelessWidget {
  const CalcAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalcAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: LocalBenchProfile.enabled
          ? (context, child) => Banner(
              message: 'BENCH C62E',
              location: BannerLocation.topEnd,
              child: child!,
            )
          : null,
      home: const AppGate(),
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
class AppGate extends StatefulWidget {
  const AppGate({super.key, this.restoreSession = true});
  final bool restoreSession;

  @override
  State<AppGate> createState() => AppGateState();
}

class AppGateState extends State<AppGate> {
  bool _initialized = false;
  String? _setupSession;
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

    if (widget.restoreSession) await auth.init();

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
    CloudService cloud, {
    required String? token,
    required String? mac,
  }) async {
    bool sameScope() =>
        mounted && auth.token == token && auth.primaryMac == mac;
    if (_handlingDeviceRevocation || !sameScope() || !cloud.deviceRevoked) {
      return;
    }
    _handlingDeviceRevocation = true;
    try {
      cloud.clearDeviceRevoked();
      if (token == null ||
          mac == null ||
          !auth.isAuthenticated ||
          !sameScope()) {
        return;
      }
      final stillOwned = await cloud.confirmDeviceOwnership(token, mac);
      if (stillOwned != false || !sameScope()) return;
      cloud.reset();
      // Reset notifies listeners synchronously; a replacement account/device
      // must not be forgotten if one of those listeners changes the scope.
      if (!sameScope()) return;
      await auth.forgetDevice();
    } catch (_) {
      // A failed check cannot establish ownership loss. Keep the pairing.
    } finally {
      _handlingDeviceRevocation = false;
      // A newer event may have arrived while this check was pending. Give it
      // its own scope check instead of losing it behind the in-flight guard.
      if (mounted && cloud.deviceRevoked) setState(() {});
    }
  }

  Widget _deviceDiscovery(AuthService auth) {
    final waiting = auth.deviceListLoading || auth.deviceListError == null;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (waiting) const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  waiting
                      ? 'Checking your calculators…'
                      : "Couldn't load your calculators",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!waiting) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      auth.deviceListError!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: auth.fetchDevices,
                    child: const Text('Retry'),
                  ),
                ],
                TextButton(
                  onPressed: auth.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      final token = auth.token;
      final mac = auth.primaryMac;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleDeviceRevocation(auth, cloud, token: token, mac: mac),
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
      _setupSession = null;
      return const AuthScreen();
    }

    // A failed account-device lookup is unknown, not a first-time account.
    // A restored session with a cached calculator can still open offline.
    final hasDevice = auth.primaryMac?.isNotEmpty == true;
    if (!auth.setupSkipped && !hasDevice && !auth.deviceListVerified) {
      final token = auth.token;
      if (!auth.deviceListLoading && auth.deviceListError == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              auth.token == token &&
              auth.isAuthenticated &&
              auth.primaryMac?.isNotEmpty != true &&
              !auth.setupSkipped &&
              !auth.deviceListVerified &&
              !auth.deviceListLoading &&
              auth.deviceListError == null) {
            auth.fetchDevices();
          }
        });
      }
      return _deviceDiscovery(auth);
    }

    // ── Authenticated, no device linked → first-time setup ────────────
    // Walk the user through the one-time Bluetooth WiFi-provisioning flow
    // before they reach the main shell.
    if (_setupSession != auth.token || auth.setupSkipped) _setupSession = null;
    if (!auth.setupSkipped &&
        ((auth.primaryMac == null || auth.primaryMac!.isEmpty) ||
            _setupSession == auth.token)) {
      // Keep this gate on setup while a claim persists its MAC. Provider
      // notifications must not replace the welcome route before it can push
      // Wi-Fi setup. Completion opens a fresh AppGate in SuccessScreen.
      _setupSession = auth.token;
      return const LinkDeviceScreen();
    }

    // ── Authenticated + device linked → main navigation shell ─────────
    return AiConsentGate(key: ValueKey(auth.token), child: const MainShell());
  }
}
