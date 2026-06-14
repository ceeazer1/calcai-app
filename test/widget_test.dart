import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:calcai_app/app.dart';
import 'package:calcai_app/services/ble_service.dart';

void main() {
  testWidgets('CalcAI app renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => BleService(),
        child: const CalcAIApp(),
      ),
    );

    // Verify the CalcAI splash screen appears
    expect(find.text('CalcAI'), findsOneWidget);
  });
}
