// Local, simulated setup demo. Production still starts at lib/main.dart.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  SetupPreviewCloud({this.homePreview = false})
    : super(
        client: homePreview
            ? MockClient((request) async {
                final now = DateTime.now().toUtc();
                return http.Response(
                  jsonEncode({
                    'ok': true,
                    'usageVersion': 2,
                    'scope': 'account',
                    'plan': 'pro',
                    'serverTime': now.toIso8601String(),
                    'period': {
                      'resetsAt': DateTime.utc(
                        now.year,
                        now.month,
                        now.day + 1,
                      ).toIso8601String(),
                    },
                    'status': 'ready',
                    'allowance': {
                      'remainingPercent': 80,
                      'unlimited': false,
                      'exhausted': false,
                    },
                    'models': [],
                  }),
                  200,
                );
              })
            : null,
      );
  final bool homePreview;
  @override
  String? get currentModel => homePreview ? 'gpt-5.6-luna' : super.currentModel;
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

void main() => runApp(
  SetupPreview(homePreview: Uri.base.queryParameters['screen'] == 'home'),
);

class SetupPreview extends StatefulWidget {
  const SetupPreview({super.key, this.homePreview = false});
  final bool homePreview;
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
        create: (_) => SetupTestAppAuth(paired: widget.homePreview)..init(),
      ),
      ChangeNotifierProvider<BleService>(
        create: (_) => SetupTestAppBle(paired: widget.homePreview),
      ),
      ChangeNotifierProvider<CloudService>(
        create: (_) => SetupPreviewCloud(homePreview: widget.homePreview),
      ),
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
                          Expanded(
                            child: Text(
                              widget.homePreview
                                  ? 'DEMO · Sample usage'
                                  : 'DEMO · Pairing code 123456',
                              style: const TextStyle(
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
        builder: (_, auth, _) => widget.homePreview || auth.setupSkipped
            ? const MainShell()
            : const LinkDeviceScreen(),
      ),
    ),
  );
}
