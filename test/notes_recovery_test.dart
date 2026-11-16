import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/models/calc_note.dart';
import 'package:calcai_app/screens/notes_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';

String envelope(String body) =>
    CalcNote.toEnvelope([CalcNote.create(body: body)]);

List<String> bodies(String value) =>
    CalcNote.parseStored(value).map((note) => note.body).toList();

http.Response readReply(String value, {int revision = 1}) => http.Response(
  jsonEncode({
    'ok': true,
    'text': value,
    'rev': revision,
    'etag': '"fixture-$revision"',
  }),
  200,
);

http.Response saveReply({int revision = 2}) => http.Response(
  jsonEncode({'ok': true, 'rev': revision, 'etag': '"fixture-$revision"'}),
  200,
);

Future<CloudService> showNotes(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) handler, {
  double textScale = 1,
  FakeAuthService? authOverride,
}) async {
  final auth = authOverride ?? FakeAuthService();
  await auth.init();
  final cloud = CloudService(client: MockClient(handler));
  addTearDown(auth.dispose);
  addTearDown(cloud.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: NotesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cloud;
}

Future<void> addNote(WidgetTester tester, String body) async {
  await tester.tap(noteButton('Add note'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(1), body);
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder noteButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

const EditSnapshot fixtureBase = (text: '', revision: 1, etag: '"fixture-1"');

void main() {
  testWidgets(
    'repeat Back opens one discard prompt and keeps the Notes draft',
    (tester) async {
      var writes = 0;
      await showNotes(tester, (request) async {
        if (request.method == 'GET') return readReply('');
        writes++;
        return saveReply();
      });
      await tester.tap(noteButton('Add note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(1),
        'Unsaved fixture note',
      );
      final back = find.byTooltip('Back');
      final point = tester.getCenter(back);
      await tester.tapAt(point);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'Unsaved fixture note',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('0/5'), findsOneWidget);
      expect(writes, 0);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'failed Notes read keeps retry usable on a small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showNotes(
        tester,
        (_) async => http.Response('unavailable', 503),
        textScale: 2,
      );
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed first read blocks overwrite until retry loads all notes',
    (tester) async {
      var failing = true;
      var saved = envelope('EXISTING NOTE');
      var writes = 0;
      await showNotes(tester, (request) async {
        if (request.method == 'GET') {
          return failing ? http.Response('unavailable', 503) : readReply(saved);
        }
        writes++;
        saved = (jsonDecode(request.body) as Map)['text'] as String;
        return saveReply();
      });

      expect(find.textContaining('Failed to load notes'), findsOneWidget);
      expect(
        tester.widget<IconButton>(noteButton('Add note')).onPressed,
        isNull,
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(writes, 0);
      failing = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('EXISTING NOTE'), findsWidgets);
      await addNote(tester, 'NEW NOTE');
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(bodies(saved), ['EXISTING NOTE', 'NEW NOTE']);
      expect(find.text('Saved to your account'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh failure retains notes and disables mutations until retry',
    (tester) async {
      var failing = false;
      await showNotes(
        tester,
        (_) async => failing
            ? http.Response('unavailable', 503)
            : readReply(envelope('KEEP THIS NOTE')),
      );
      failing = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('KEEP THIS NOTE'), findsWidgets);
      expect(
        tester.widget<IconButton>(noteButton('Add note')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(noteButton('Delete: KEEP THIS NOTE'))
            .onPressed,
        isNull,
      );
      failing = false;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(noteButton('Add note')).onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(noteButton('Delete: KEEP THIS NOTE'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('lost save reply is reconciled by GET without repeating POST', (
    tester,
  ) async {
    var serverText = envelope('ORIGINAL');
    var revision = 1;
    var writes = 0;
    await showNotes(tester, (request) async {
      if (request.method == 'GET') {
        return readReply(serverText, revision: revision);
      }
      writes++;
      final posted = jsonDecode(request.body) as Map;
      expect(posted['expectedRev'], 1);
      expect(request.headers['If-Match'], '"fixture-1"');
      serverText = posted['text'] as String;
      revision = 2;
      throw TimeoutException('fixture lost reply after commit');
    });
    await addNote(tester, 'UNSAVED DRAFT');
    await tester.pumpAndSettle();
    expect(find.text('ORIGINAL'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    expect(
      find.widgetWithText(TextButton, 'Review unsaved changes'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Reload and compare'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(bodies(serverText), ['ORIGINAL', 'UNSAVED DRAFT']);
    expect(find.text('UNSAVED DRAFT'), findsWidgets);
    expect(find.text('Saved to your account'), findsOneWidget);
  });

  testWidgets('pending save blocks add, delete and refresh', (tester) async {
    final reply = Completer<http.Response>();
    var reads = 0;
    var writes = 0;
    await showNotes(tester, (request) async {
      if (request.method == 'GET') {
        reads++;
        return readReply(envelope('ORIGINAL'));
      }
      writes++;
      return reply.future;
    });
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await addNote(tester, 'SECOND');
    expect(writes, 1);
    expect(tester.widget<IconButton>(noteButton('Add note')).onPressed, isNull);
    expect(
      tester.widget<IconButton>(noteButton('Delete: ORIGINAL')).onPressed,
      isNull,
    );
    await refresh.onRefresh();
    expect(reads, 1);
    reply.complete(saveReply());
    await tester.pumpAndSettle();
    expect(find.text('SECOND'), findsWidgets);
    expect(
      tester.widget<IconButton>(noteButton('Add note')).onPressed,
      isNotNull,
    );
  });

  testWidgets('discarding uncertain save reloads the authoritative notes', (
    tester,
  ) async {
    var reads = 0;
    await showNotes(tester, (request) async {
      if (request.method == 'GET') {
        reads++;
        return readReply(envelope(reads == 1 ? 'ORIGINAL' : 'SERVER COPY'));
      }
      return http.Response('unavailable', 503);
    });
    await addNote(tester, 'UNSAVED');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Discard changes and reload'),
    );
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('SERVER COPY'), findsWidgets);
    expect(find.text('ORIGINAL'), findsNothing);
    expect(find.text('UNSAVED'), findsNothing);
    expect(
      tester.widget<IconButton>(noteButton('Add note')).onPressed,
      isNotNull,
    );
  });

  test('late read cannot replace a successful write', () async {
    final oldRead = Completer<http.Response>();
    final cloud = CloudService(
      client: MockClient(
        (request) async =>
            request.method == 'GET' ? oldRead.future : saveReply(),
      ),
    );
    addTearDown(cloud.dispose);
    final pending = cloud.getNotes('fixture', 'ca1ca1000001');
    expect(
      await cloud.setNotes(
        'fixture',
        'ca1ca1000001',
        envelope('NEW'),
        base: fixtureBase,
      ),
      isTrue,
    );
    oldRead.complete(readReply(envelope('OLD')));
    expect(await pending, isNull);
    expect(bodies(cloud.notes!), ['NEW']);
    expect(cloud.notesError, isNull);
  });

  test('overlapping reads keep only the newest response', () async {
    final oldRead = Completer<http.Response>();
    var count = 0;
    final cloud = CloudService(
      client: MockClient(
        (_) async => ++count == 1 ? oldRead.future : readReply(envelope('NEW')),
      ),
    );
    addTearDown(cloud.dispose);
    final pending = cloud.getNotes('fixture', 'ca1ca1000001');
    expect(bodies((await cloud.getNotes('fixture', 'ca1ca1000001'))!), ['NEW']);
    oldRead.complete(http.Response('unavailable', 503));
    expect(await pending, isNull);
    expect(bodies(cloud.notes!), ['NEW']);
    expect(cloud.notesError, isNull);
  });

  test(
    'concurrent write and read are rejected while a save is outstanding',
    () async {
      final reply = Completer<http.Response>();
      var requests = 0;
      final cloud = CloudService(
        client: MockClient((_) async {
          requests++;
          return reply.future;
        }),
      );
      addTearDown(cloud.dispose);
      final pending = cloud.setNotes(
        'fixture',
        'ca1ca1000001',
        envelope('FIRST'),
        base: fixtureBase,
      );
      expect(
        await cloud.setNotes(
          'fixture',
          'ca1ca1000001',
          envelope('SECOND'),
          base: fixtureBase,
        ),
        isFalse,
      );
      expect(await cloud.getNotes('fixture', 'ca1ca1000001'), isNull);
      reply.complete(saveReply());
      expect(await pending, isTrue);
      expect(requests, 1);
      expect(bodies(cloud.notes!), ['FIRST']);
    },
  );

  for (final writing in [false, true]) {
    test(
      'late ${writing ? 'write' : 'read'} cannot affect reset session',
      () async {
        final reply = Completer<http.Response>();
        final cloud = CloudService(client: MockClient((_) => reply.future));
        addTearDown(cloud.dispose);
        final pending = writing
            ? cloud.setNotes(
                'old-account',
                'ca1ca1000001',
                envelope('PRIVATE'),
                base: fixtureBase,
              )
            : cloud.getNotes('old-account', 'ca1ca1000001');
        cloud.reset();
        reply.complete(writing ? saveReply() : readReply(envelope('PRIVATE')));
        expect(await pending, writing ? isFalse : isNull);
        expect(cloud.notes, isNull);
        expect(cloud.notesError, isNull);
        expect(cloud.error, isNull);
      },
    );
  }

  test(
    'malformed successful read cannot masquerade as an empty list',
    () async {
      final cloud = CloudService(client: MockClient((_) async => saveReply()));
      addTearDown(cloud.dispose);
      expect(await cloud.getNotes('fixture', 'ca1ca1000001'), isNull);
      expect(cloud.notes, isNull);
      expect(cloud.notesError, isNotNull);
    },
  );

  test('unconfirmed successful save does not claim stored notes', () async {
    final cloud = CloudService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(cloud.dispose);
    expect(
      await cloud.setNotes(
        'fixture',
        'ca1ca1000001',
        envelope('UNCONFIRMED'),
        base: fixtureBase,
      ),
      isFalse,
    );
    expect(cloud.notes, isNull);
    expect(cloud.notesError, isNotNull);
  });

  for (final status in [200, 204]) {
    test(
      'empty $status raw response is unknown rather than no notes',
      () async {
        final cloud = CloudService(
          client: MockClient((_) async => http.Response('', status)),
        );
        addTearDown(cloud.dispose);
        expect(await cloud.getNotes('fixture', 'ca1ca1000001'), isNull);
        expect(cloud.notes, isNull);
        expect(cloud.notesError, isNotNull);
      },
    );
  }

  testWidgets(
    '409 preserves reviewable draft and requires reload without retrying write',
    (tester) async {
      var reads = 0;
      var writes = 0;
      await showNotes(tester, (request) async {
        if (request.method == 'GET') {
          reads++;
          return readReply(
            envelope(reads == 1 ? 'ORIGINAL' : 'LATEST SERVER NOTE'),
          );
        }
        writes++;
        return http.Response('{"error":"notes_write_conflict"}', 409);
      });
      await addNote(tester, 'LOCAL DRAFT');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(writes, 1);
      await tester.tap(
        find.widgetWithText(TextButton, 'Review unsaved changes'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('LOCAL DRAFT'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, 'Discard changes and reload'),
      );
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(reads, 2);
      expect(find.text('LATEST SERVER NOTE'), findsWidgets);
    },
  );
}
