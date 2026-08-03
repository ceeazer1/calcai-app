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

    // Save from the editor's app bar. The editor is a full-screen page now,
    // not a bottom sheet, so Save is a TextButton in the AppBar.
    final saveBtn = find.widgetWithText(TextButton, 'Save');
    expect(saveBtn, findsOneWidget);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // The note should now be listed.
    expect(find.text('No notes yet'), findsNothing);
    expect(find.text('QUADRATIC FORMULA'), findsWidgets);
  });

  testWidgets('the editor opens full screen with a back arrow', (tester) async {
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

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('New note'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    // An untouched note leaves without a discard prompt.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('New note'), findsNothing);
  });

  testWidgets('deleting a note asks first', (tester) async {
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

    // Create one note so there is something to delete.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'DELETE ME');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('DELETE ME'), findsWidgets);

    // Trash icon, not an X.
    final trash = find.byIcon(Icons.delete_outline_rounded);
    expect(trash, findsOneWidget);
    await tester.tap(trash);
    await tester.pumpAndSettle();

    // Confirmation appears, and cancelling keeps the note.
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('DELETE ME'), findsWidgets);

    // Confirming removes it.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('DELETE ME'), findsNothing);
  });
}
