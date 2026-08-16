import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/ble_service.dart';
import 'services/cloud_service.dart';

/// Application entry point.
///
/// Sets up system UI overlays, initialises service providers
/// ([BleService], [AuthService], [CloudService]), and launches the
/// CalcAI app.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status & navigation bars for the immersive dark UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF09090B),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    MultiProvider(
      providers: [
        // In UI-preview builds, swap in stand-ins that simulate a signed-in
        // account with a paired device so features are testable in a browser.
        // Release builds pass no dart-defines, so these never ship.
        ChangeNotifierProvider<BleService>(
          create: (_) => kUiPreview
              ? PreviewBleService(walkthrough: kUiPreviewScreen == 'setup')
              : BleService(),
        ),
        ChangeNotifierProvider<AuthService>(
          create: (_) => kUiPreview
              ? PreviewAuthService(signedOut: kUiPreviewScreen == 'setup')
              : AuthService(),
        ),
        ChangeNotifierProvider<CloudService>(
          create: (_) => kUiPreview ? PreviewCloudService(seeded: true) : CloudService(),
        ),
      ],
      child: const CalcAIApp(),
    ),
  );
}

