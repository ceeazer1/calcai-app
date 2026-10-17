import 'package:calcai_app/screens/main_shell.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

class _CountingCloud extends FakeCloudService {
  int historyLoads = 0;
  int notesLoads = 0;

  @override
  Future<List<Map<String, dynamic>>> getHistory(
    String token,
    String mac, {
    int limit = 50,
  }) async {
    historyLoads++;
    return [];
  }

  @override
  Future<String> getNotes(String token, String mac) async {
    notesLoads++;
    return '';
  }
}

void main() {
  testWidgets('hidden tabs defer requests and retain state after first visit', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.init();
    final cloud = _CountingCloud();
    final ble = SetupTestAppBle();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          ChangeNotifierProvider<BleService>.value(value: ble),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const MainShell()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(cloud.historyLoads, 0);
    expect(cloud.notesLoads, 0);

    await tester.tap(find.text('History').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cloud.historyLoads, 1);
    await tester.enterText(find.byType(TextField), 'retained filter');
    expect(cloud.notesLoads, 0);
    await tester.tap(find.text('Notes').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cloud.notesLoads, 1);
    await tester.tap(find.text('Home').last);
    await tester.pump();
    await tester.tap(find.text('History').last);
    await tester.pump();
    expect(cloud.historyLoads, 3);
    expect(find.text('retained filter'), findsOneWidget);
    // Only the active page reloads on resume; retained hidden tabs do not.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cloud.historyLoads, 4);
    await tester.tap(find.text('Home').last);
    await tester.pump();
    expect(cloud.historyLoads, 5);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cloud.historyLoads, 6);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    cloud.dispose();
    ble.dispose();
  });
}
