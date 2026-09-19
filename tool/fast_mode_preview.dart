import 'package:calcai_app/screens/ai_consent_screen.dart';
// Development-only entry point. Not imported by the shipping app.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/screens/dashboard_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import '../test/support/fake_auth_service.dart';
import '../test/support/fake_cloud_service.dart';

class PreviewCloud extends FakeCloudService {
  @override
  Future<Map<String, dynamic>> readAiConsent(String token) async => {
    'ok': true, 'version': CloudService.aiConsentVersion,
    'reviewed': false, 'allowed': false,
  };
  String model = 'gpt-5.6-sol';
  bool fast = false;
  @override
  String get currentModel => model;
  @override
  bool get fastMode => fast;
  @override
  bool hasApiKey(String provider) => true;
  @override
  bool apiKeyEnabled(String provider) => true;
  @override
  Future<void> setModel(String token, String mac, String model, String style,
      {String? effort, bool? fastMode}) async {
    fast = fastMode ?? (this.model == model && fast);
    this.model = model;
    await super.setModel(token, mac, model, style, effort: effort, fastMode: fast);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = FakeAuthService();
  await auth.init();
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider<AuthService>.value(value: auth),
    ChangeNotifierProvider<CloudService>(create: (_) => PreviewCloud()),
    ChangeNotifierProvider<BleService>(create: (_) => BleService()),
  ], child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.darkTheme,
    home: Scaffold(body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(children: [
        const SafeArea(bottom: false, child: Padding(padding: EdgeInsets.all(12),
          child: Text('DESIGN PREVIEW · No API calls', style: TextStyle(fontSize: 11, color: Colors.grey)))),
        Expanded(child: Uri.base.queryParameters['screen'] == 'consent'
          ? const AiConsentGate(child: DashboardScreen()) : const DashboardScreen()),
        NavigationBar(selectedIndex: 0, destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ]),
      ]),
    ))))));
}
