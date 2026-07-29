import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:calcai_app/app.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';

void main() {
  testWidgets('app boots and shows the CalcAI loading state', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BleService()),
          ChangeNotifierProvider<AuthService>(
            create: (_) => PreviewAuthService(),
          ),
          ChangeNotifierProvider<CloudService>(
            create: (_) => PreviewCloudService(),
          ),
        ],
        child: const CalcAIApp(),
      ),
    );

    // First frame is the gate's loading screen, which shows the wordmark.
    expect(find.text('CalcAI'), findsOneWidget);
  });
}
