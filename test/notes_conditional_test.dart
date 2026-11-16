import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'notes_recovery_test.dart'
    show envelope, bodies, readReply, showNotes, addNote, noteButton;
import 'support/fake_auth_service.dart';

class _NotesScopeAuth extends FakeAuthService {
  String? currentToken = 'test-token';
  String? currentMac = 'ca1ca1000001';
  @override
  String? get token => currentToken;
  @override
  String? get primaryMac => currentMac;

  void changeScope(String? token, String? mac) {
    currentToken = token;
    currentMac = mac;
    notifyListeners();
  }
}

http.Response accepted(int revision) => http.Response(
  jsonEncode({'ok': true, 'rev': revision, 'etag': '"fixture-$revision"'}),
  200,
);

void main() {
  for (final change in ['sign out', 'account switch', 'calculator switch']) {
    testWidgets('open unsaved Notes review hides private draft on $change', (
      tester,
    ) async {
      final auth = _NotesScopeAuth();
      var writes = 0;
      await showNotes(tester, (request) async {
        if (request.method == 'GET') {
          return readReply(envelope('ORIGINAL'));
        }
        writes++;
        return http.Response('{"error":"revision_conflict"}', 412);
      }, authOverride: auth);
      await addNote(tester, 'PRIVATE ACCOUNT A DRAFT');
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, 'Review unsaved changes'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('PRIVATE ACCOUNT A DRAFT'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      auth.changeScope(
        change == 'sign out'
            ? null
            : change == 'account switch'
            ? 'account-b'
            : 'test-token',
        change == 'sign out'
            ? null
            : change == 'calculator switch'
            ? 'ca1ca1000002'
            : 'ca1ca1000001',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('PRIVATE ACCOUNT A DRAFT'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Notes unavailable'), findsOneWidget);
      expect(writes, 1);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      // A retained callback cannot reopen/copy the previous scope's draft.
      await tester.tap(
        find.widgetWithText(TextButton, 'Review unsaved changes'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(writes, 1);
    });
  }

  test(
    'two clients cannot replace a newer server record with an old edit base',
    () async {
      var text = 'original';
      var revision = 0;
      var writes = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') return readReply(text, revision: revision);
        final body = jsonDecode(request.body) as Map;
        if (request.headers['If-Match'] != '"fixture-$revision"' ||
            body['expectedRev'] != revision) {
          return http.Response('{"error":"revision_conflict"}', 412);
        }
        writes++;
        text = body['text'] as String;
        return accepted(++revision);
      });
      final first = CloudService(client: client);
      final second = CloudService(client: client);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final a = (await first.readNotesSnapshot('fixture', 'ca1ca1000001'))!;
      final b = (await second.readNotesSnapshot('fixture', 'ca1ca1000001'))!;
      expect(
        await second.writeNotesSnapshot(
          'fixture',
          'ca1ca1000001',
          'second client',
          base: b,
        ),
        isNotNull,
      );
      expect(
        await first.writeNotesSnapshot(
          'fixture',
          'ca1ca1000001',
          'stale first client',
          base: a,
        ),
        isNull,
      );
      expect(text, 'second client');
      expect(writes, 1);
      expect(first.notesConflict, isTrue);
      expect(first.notesRequiresRefresh, isTrue);
    },
  );

  testWidgets(
    'editor uses its captured base after another refresh advances shared cache',
    (tester) async {
      var revision = 1;
      var server = envelope('ORIGINAL');
      var writes = 0;
      int? postedRevision;
      String? postedEtag;
      final cloud = await showNotes(tester, (request) async {
        if (request.method == 'GET') {
          return readReply(server, revision: revision);
        }
        writes++;
        final body = jsonDecode(request.body) as Map;
        postedRevision = body['expectedRev'] as int;
        postedEtag = request.headers['If-Match'];
        return http.Response('{"error":"revision_conflict"}', 412);
      });
      await tester.tap(noteButton('Add note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'LOCAL DRAFT');
      server = envelope('OTHER CLIENT');
      revision = 2;
      await cloud.readNotesSnapshot('test-token', 'ca1ca1000001');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(postedRevision, 1);
      expect(postedEtag, '"fixture-1"');
      expect(writes, 1);
      expect(bodies(server), ['OTHER CLIENT']);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Reload and compare'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('OTHER CLIENT'), findsWidgets);
      await tester.tap(
        find.widgetWithText(TextButton, 'Review unsaved changes'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('LOCAL DRAFT'), findsOneWidget);
    },
  );

  final invalid = <String, Map<String, dynamic>>{
    'missing revision': {'etag': '"fixture-1"'},
    'negative revision': {'rev': -1, 'etag': '"fixture-1"'},
    'fractional revision': {'rev': 1.5, 'etag': '"fixture-1"'},
    'missing ETag': {'rev': 1},
    'weak ETag': {'rev': 1, 'etag': 'W/"fixture-1"'},
    'unquoted ETag': {'rev': 1, 'etag': 'fixture-1'},
    'header injection': {'rev': 1, 'etag': '"unsafe\r\nheader"'},
  };
  for (final value in invalid.entries) {
    test('${value.key} cannot establish a writable snapshot', () async {
      final cloud = CloudService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'text': '', ...value.value}),
            200,
          ),
        ),
      );
      addTearDown(cloud.dispose);
      expect(await cloud.readNotesSnapshot('fixture', 'ca1ca1000001'), isNull);
      expect(cloud.notes, isNull);
      expect(cloud.notesError, isNotNull);
    });
  }

  testWidgets('missing edit validators leave Add disabled', (tester) async {
    var writes = 0;
    await showNotes(tester, (request) async {
      if (request.method != 'GET') writes++;
      return http.Response('{"ok":true,"text":"","rev":0}', 200);
    });
    expect(tester.widget<IconButton>(noteButton('Add note')).onPressed, isNull);
    expect(writes, 0);
  });

  test(
    'legacy setNotes without an explicit base never sends a mutation',
    () async {
      var calls = 0;
      final cloud = CloudService(
        client: MockClient((_) async {
          calls++;
          return accepted(1);
        }),
      );
      addTearDown(cloud.dispose);
      expect(
        await cloud.setNotes('fixture', 'ca1ca1000001', 'replacement'),
        isFalse,
      );
      expect(calls, 0);
    },
  );

  for (final status in [409, 412, 403]) {
    testWidgets(
      '$status save retains copyable draft and never offers blind Retry',
      (tester) async {
        var writes = 0;
        await showNotes(tester, (request) async {
          if (request.method == 'GET') return readReply(envelope('ORIGINAL'));
          writes++;
          return http.Response(
            jsonEncode({
              'error': status == 403 ? 'device_not_owned' : 'revision_conflict',
            }),
            status,
          );
        });
        await addNote(tester, 'UNSAVED');
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
        expect(
          find.widgetWithText(TextButton, 'Reload and compare'),
          findsOneWidget,
        );
        expect(find.textContaining('lost if you leave'), findsOneWidget);
        await tester.tap(
          find.widgetWithText(TextButton, 'Review unsaved changes'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('UNSAVED'), findsOneWidget);
      },
    );
  }

  test(
    'lost reply cannot apply the same old conditional write twice',
    () async {
      var server = 'original';
      var revision = 0;
      var commits = 0;
      final cloud = CloudService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return readReply(server, revision: revision);
          }
          final body = jsonDecode(request.body) as Map;
          if (body['expectedRev'] != revision ||
              request.headers['If-Match'] != '"fixture-$revision"') {
            return http.Response('{"error":"revision_conflict"}', 412);
          }
          commits++;
          revision++;
          server = body['text'] as String;
          throw TimeoutException('fixture reply lost after commit');
        }),
      );
      addTearDown(cloud.dispose);
      final base = (await cloud.readNotesSnapshot('fixture', 'ca1ca1000001'))!;
      expect(
        await cloud.writeNotesSnapshot(
          'fixture',
          'ca1ca1000001',
          'desired',
          base: base,
        ),
        isNull,
      );
      expect(
        await cloud.writeNotesSnapshot(
          'fixture',
          'ca1ca1000001',
          'desired',
          base: base,
        ),
        isNull,
      );
      final current = (await cloud.readNotesSnapshot(
        'fixture',
        'ca1ca1000001',
      ))!;
      expect(current.text, 'desired');
      expect(current.revision, 1);
      expect(commits, 1);
    },
  );
}
