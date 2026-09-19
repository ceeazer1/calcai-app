// Local, simulated setup demo. Production still starts at lib/main.dart.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/screens/link_device_screen.dart';
import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import '../test/support/setup_test_app.dart';

class SetupPreviewCloud extends SetupTestAppCloud {
  bool reviewed = false;
  bool allowed = false;
  @override
  Future<Map<String, dynamic>> readAiConsent(String token) async => {
    'ok': true,
    'version': CloudService.aiConsentVersion,
    'reviewed': reviewed,
    'allowed': allowed,
  };
  @override
  Future<void> saveAiConsent(String token, bool allowed) async {
    this.allowed = allowed;
    reviewed = true;
  }
}

void main() => runApp(const SetupPreview());

class SetupPreview extends StatefulWidget {
  const SetupPreview({super.key});
  @override
  State<SetupPreview> createState() => _SetupPreviewState();
}

class _SetupPreviewState extends State<SetupPreview> {
  int generation = 0;
  @override
  Widget build(BuildContext context) => MultiProvider(
    key: ValueKey(generation),
    providers: [
      ChangeNotifierProvider<AuthService>(
        create: (_) => SetupTestAppAuth()..init(),
      ),
      ChangeNotifierProvider<BleService>(create: (_) => SetupTestAppBle()),
      ChangeNotifierProvider<CloudService>(create: (_) => SetupPreviewCloud()),
    ],
    child: MaterialApp(
      title: 'CalcAI setup demo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
      builder: (context, child) => ColoredBox(
        color: const Color(0xFF09090B),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                Material(
                  color: const Color(0xFF111113),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'DEMO · Pairing code 123456',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8E8E96),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => generation++),
                            child: const Text('Restart'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            ),
          ),
        ),
      ),
      home: Consumer<AuthService>(
        builder: (_, auth, _) => auth.setupSkipped
            ? const MainShell()
            : const LinkDeviceScreen(),
      ),
    ),
  );
}
