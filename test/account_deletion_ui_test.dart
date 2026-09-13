import 'package:calcai_app/app.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';
import 'support/setup_test_app.dart';

class _DeletingAuth extends FakeAuthService {
  @override
  Future<String?> deleteAccount() async {
    await signOut();
    // Let the app dispose Settings before the request reports completion.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return null;
  }
}

void main() {
  testWidgets(
    'account deletion closes its progress route after Settings is disposed',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>(create: (_) => _DeletingAuth()),
            ChangeNotifierProvider<CloudService>(
              create: (_) => FakeCloudService(),
            ),
            ChangeNotifierProvider<BleService>(
              create: (_) => SetupTestAppBle(paired: true),
            ),
          ],
          child: const CalcAIApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete Account'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
