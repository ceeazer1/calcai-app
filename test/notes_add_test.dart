import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:calcai_app/screens/notes_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';

void main() {
  testWidgets('saving a new note shows it in the list', (tester) async {
    final auth = PreviewAuthService();
    await auth.init();
    final cloud = PreviewCloudService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
        ],
        child: const MaterialApp(home: Scaffold(body: NotesScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Starts empty.
    expect(find.text('No notes yet'), findsOneWidget);

    // Open the editor.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Type a body (second TextField; first is the optional title).
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(1), 'QUADRATIC FORMULA');
    await tester.pumpAndSettle();

    // Save. The sheet scrolls (body field + calculator preview), so make sure
    // the button is actually on screen before tapping it.
    final saveBtn = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // The note should now be listed.
    expect(find.text('No notes yet'), findsNothing);
    expect(find.text('QUADRATIC FORMULA'), findsWidgets);
  });
}
