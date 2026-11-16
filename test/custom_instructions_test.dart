import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/screens/custom_instructions_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

http.Response _context(String text, {int revision = 0}) => http.Response(
  jsonEncode({
    'ok': true,
    'context': text,
    'rev': revision,
    'etag': '"fixture-$revision"',
  }),
  200,
);

http.Response _accepted({int revision = 1}) => http.Response(
  jsonEncode({'ok': true, 'rev': revision, 'etag': '"fixture-$revision"'}),
  200,
);

CloudService _contextCloud(
  Future<http.Response> Function(http.Request) handle,
) => CloudService(
  client: MockClient((request) async {
    if (request.url.path.startsWith('/ai/context/')) return handle(request);
    return http.Response('{"error":"unavailable"}', 503);
  }),
);

Future<CloudService> openEditor(
  WidgetTester tester, {
  CloudService? service,
  FakeAuthService? account,
  bool settle = true,
}) async {
  final auth = account ?? FakeAuthService();
  await auth.init();
  final cloud = service ?? FakeCloudService();
  addTearDown(auth.dispose);
  addTearDown(cloud.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomInstructionsScreen(),
                ),
              ),
              child: const Text('Open instructions'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open instructions'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  return cloud;
}

void main() {
  testWidgets('a read without edit validators cannot open the editor', (
    tester,
  ) async {
    final cloud = CloudService(
      client: MockClient(
        (_) async => http.Response('{"ok":true,"context":"Existing"}', 200),
      ),
    );
    await openEditor(tester, service: cloud);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  for (final status in [409, 412]) {
    testWidgets(
      'conflict $status requires explicit comparison before saving a draft',
      (tester) async {
        var stored = 'Original';
        var revision = 0;
        var writes = 0;
        String? copied;
        final clipboardAccepted = Completer<void>();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
            await clipboardAccepted.future;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final cloud = _contextCloud((request) async {
          if (request.method == 'GET') {
            return _context(stored, revision: revision);
          }
          writes++;
          final body = jsonDecode(request.body) as Map;
          if (writes == 1) {
            expect(request.headers['If-Match'], '"fixture-0"');
            expect(body['expectedRev'], 0);
            stored = 'Saved elsewhere';
            revision = 1;
            return http.Response(
              '{"ok":false,"error":"revision_conflict"}',
              status,
            );
          }
          expect(request.headers['If-Match'], '"fixture-1"');
          expect(body['expectedRev'], 1);
          return _accepted(revision: 2);
        });
        await openEditor(tester, service: cloud);
        await tester.enterText(find.byType(TextField), 'My preserved draft');
        await tester.pump();
        await tester.tap(find.widgetWithText(TextButton, 'Save'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.text('Copy draft'));
        await tester.tap(find.text('Copy draft'));
        await tester.pump();
        expect(copied, 'My preserved draft');
        expect(find.text('Draft copied.'), findsNothing);
        clipboardAccepted.complete();
        await tester.pumpAndSettle();
        expect(find.text('Draft copied.'), findsOneWidget);
        await tester.tap(find.text('Check saved instructions'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        await tester.ensureVisible(find.text('Review changes'));
        await tester.tap(find.text('Review changes'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SelectableText, 'Saved elsewhere'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SelectableText, 'My preserved draft'),
          findsOneWidget,
        );
        await tester.tap(find.text('Keep my draft'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        await tester.tap(find.widgetWithText(TextButton, 'Save'));
        await tester.pumpAndSettle();
        expect(writes, 2);
        expect(cloud.customContext, 'My preserved draft');
        expect(find.byType(CustomInstructionsScreen), findsNothing);
      },
    );
  }

  testWidgets('background refresh cannot substitute the editor base at save', (
    tester,
  ) async {
    var reads = 0;
    var writes = 0;
    final cloud = _contextCloud((request) async {
      if (request.method == 'GET') {
        return _context('Version $reads', revision: reads++);
      }
      writes++;
      expect(request.headers['If-Match'], '"fixture-0"');
      expect((jsonDecode(request.body) as Map)['expectedRev'], 0);
      return http.Response('{"ok":false,"error":"revision_conflict"}', 412);
    });
    await openEditor(tester, service: cloud);
    await cloud.readContextSnapshot('test-token', 'ca1ca1000001');
    await tester.enterText(find.byType(TextField), 'Draft from first version');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(cloud.customContext, 'Version 1');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Draft from first version',
    );
  });

  testWidgets(
    'a lost reply can confirm the stored draft without a second write',
    (tester) async {
      var stored = 'Original';
      var revision = 0;
      var writes = 0;
      final cloud = _contextCloud((request) async {
        if (request.method == 'GET') {
          return _context(stored, revision: revision);
        }
        writes++;
        stored = (jsonDecode(request.body) as Map)['context'] as String;
        revision++;
        throw TimeoutException('Reply lost after commit');
      });
      await openEditor(tester, service: cloud);
      await tester.enterText(find.byType(TextField), 'My saved draft');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tester.ensureVisible(find.text('Check saved instructions'));
      await tester.tap(find.text('Check saved instructions'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(cloud.customContext, 'My saved draft');
      expect(find.byType(CustomInstructionsScreen), findsNothing);
    },
  );

  testWidgets('editing waits for a verified read even with a cached value', (
    tester,
  ) async {
    final read = Completer<http.Response>();
    var delayed = false;
    final cloud = CloudService(
      client: MockClient((request) async {
        if (request.url.path == '/ai/context/get') {
          return delayed ? read.future : _context('Cached');
        }
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );
    await cloud.getContext('test-token', 'ca1ca1000001');
    delayed = true;
    await openEditor(tester, service: cloud, settle: false);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    read.complete(_context('Current'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Current',
    );
  });

  testWidgets(
    'an unconfirmed save keeps the draft available for explicit retry',
    (tester) async {
      var healthy = false;
      var writes = 0;
      final cloud = CloudService(
        client: MockClient((request) async {
          if (request.url.path == '/ai/context/get') {
            return _context('Original');
          }
          if (request.url.path == '/ai/context/set') {
            writes++;
            return healthy ? _accepted() : http.Response('{"ok":false}', 200);
          }
          return http.Response('{"error":"unavailable"}', 503);
        }),
      );
      await openEditor(tester, service: cloud);
      await tester.enterText(find.byType(TextField), 'My draft');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomInstructionsScreen), findsOneWidget);
      expect(cloud.customContext, 'Original');
      expect(writes, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My draft',
      );
      healthy = true;
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Check saved instructions'));
      await tester.tap(find.text('Check saved instructions'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(cloud.customContext, 'My draft');
      expect(find.byType(CustomInstructionsScreen), findsNothing);
    },
  );

  testWidgets(
    'a pending save locks its draft and cannot be discarded mid-write',
    (tester) async {
      final save = Completer<http.Response>();
      String? sent;
      final cloud = CloudService(
        client: MockClient((request) async {
          if (request.url.path == '/ai/context/get') {
            return _context('Original');
          }
          if (request.url.path == '/ai/context/set') {
            sent = (jsonDecode(request.body) as Map)['context'] as String;
            return save.future;
          }
          return http.Response('{"error":"unavailable"}', 503);
        }),
      );
      await openEditor(tester, service: cloud);
      await tester.enterText(find.byType(TextField), 'Submitted draft');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Back',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widgetList<ActionChip>(find.byType(ActionChip))
            .every((chip) => chip.onPressed == null),
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CustomInstructionsScreen), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
      expect(sent, 'Submitted draft');
      save.complete(_accepted());
      await tester.pumpAndSettle();
      expect(cloud.customContext, 'Submitted draft');
      expect(find.byType(CustomInstructionsScreen), findsNothing);
    },
  );

  testWidgets('sign-out hides the draft and fences a pending save completion', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final save = Completer<http.Response>();
    final cloud = CloudService(
      auth: auth,
      client: MockClient((request) async {
        if (request.url.path == '/ai/context/get') {
          return _context('Private draft');
        }
        if (request.url.path == '/ai/context/set') return save.future;
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );
    await openEditor(tester, service: cloud, account: auth);
    await tester.enterText(find.byType(TextField), 'Changed private draft');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await auth.signOut();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('Your account or calculator changed.'),
      findsOneWidget,
    );
    save.complete(_accepted());
    await tester.pumpAndSettle();
    expect(cloud.customContext, isEmpty);
    expect(find.byType(CustomInstructionsScreen), findsOneWidget);
    expect(find.text('Open instructions'), findsNothing);
  });

  testWidgets(
    'failed initial load cannot expose an empty editable replacement',
    (tester) async {
      var healthy = false;
      var saves = 0;
      final cloud = CloudService(
        client: MockClient((request) async {
          if (request.url.path == '/ai/context/get') {
            return healthy
                ? _context('Keep my instructions')
                : http.Response('{"error":"unavailable"}', 503);
          }
          if (request.url.path == '/ai/context/set') saves++;
          return http.Response('{"ok":true}', 200);
        }),
      );
      await openEditor(tester, service: cloud);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(saves, 0);
      healthy = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep my instructions',
      );
    },
  );

  for (final length in [1999, 2000, 2001]) {
    testWidgets('instructions pasted at $length stay within the saved limit', (
      tester,
    ) async {
      final cloud = await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'x' * length);
      await tester.pump();
      final expected = length > 2000 ? 2000 : length;
      expect(find.text('$expected/2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(cloud.customContext, 'x' * expected);
      expect(find.byType(CustomInstructionsScreen), findsNothing);
    });
  }

  testWidgets(
    'example chips cannot exceed the limit or overwrite existing text',
    (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'x' * 1990);
      await tester.pump();
      final example = find.text('Always show the formula before the numbers.');
      await tester.ensureVisible(example);
      await tester.tap(example);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'x' * 1990,
      );
      expect(
        find.text(
          'Not enough space for this example. Limit: 2,000 characters.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Unicode respects the server limit without splitting a character',
    (tester) async {
      final cloud = await openEditor(tester);
      await tester.enterText(find.byType(TextField), '${'x' * 1998}😀z');
      await tester.pump();
      expect(find.text('2000/2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(cloud.customContext, '${'x' * 1998}😀');
    },
  );

  for (final character in ['😀', 'e\u0301']) {
    testWidgets('a partial $character at the limit is never saved', (
      tester,
    ) async {
      final cloud = await openEditor(tester);
      await tester.enterText(find.byType(TextField), '${'x' * 1999}$character');
      await tester.pump();
      expect(find.text('1999/2000'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(cloud.customContext, 'x' * 1999);
    });
  }

  testWidgets('an unfinished over-limit composition cannot be saved', (
    tester,
  ) async {
    final cloud = await openEditor(tester);
    final composing = TextEditingValue(
      text: 'x' * 2001,
      selection: const TextSelection.collapsed(offset: 2001),
      composing: const TextRange(start: 2000, end: 2001),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(cloud.customContext, isEmpty);
    tester.testTextInput.updateEditingValue(
      composing.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(cloud.customContext.length, 2000);
  });
}
