import 'dart:async';

import 'package:calcai_app/screens/history_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/utils/answer_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

const _selectedQuestion = 'SELECTED QUESTION';
const _selectedAnswer = 'SELECTED ANSWER';
const _otherQuestion = 'UNRELATED PRIVATE QUESTION';
const _otherAnswer = 'UNRELATED PRIVATE ANSWER';

class _ReportCloud extends FakeCloudService {
  final List<Map<String, dynamic>> entries = [
    {
      'type': 'render',
      'question': _selectedQuestion,
      'response': _selectedAnswer,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'imageUrl': 'https://ai.calcai.cc/private/photo?key=private-photo-key',
      'id': 'private-entry-id',
      'email': 'private-account@example.com',
      'mac': 'ca1ca1000001',
      'token': 'test-token',
    },
    {
      'type': 'render',
      'question': _otherQuestion,
      'response': _otherAnswer,
      'ts': DateTime.now().millisecondsSinceEpoch,
    },
  ];

  @override
  List<Map<String, dynamic>> get history => entries;

  @override
  Future<List<Map<String, dynamic>>> getHistory(
    String token,
    String mac, {
    int limit = 50,
  }) async => entries;
}

Future<FakeAuthService> _openReport(
  WidgetTester tester,
  Future<bool> Function(Uri) launcher,
) async {
  final auth = FakeAuthService();
  await auth.init();
  final cloud = _ReportCloud();
  addTearDown(auth.dispose);
  addTearDown(cloud.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        home: Scaffold(body: HistoryScreen(reportEmailLauncher: launcher)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(_selectedQuestion));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Report this answer'));
  await tester.pumpAndSettle();
  return auth;
}

String _preview(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('answer-report-preview')))
    .data!;

void main() {
  test(
    'email omits the selected answer unless inclusion is explicitly chosen',
    () {
      final body = answerReportBody(
        note: 'Please check this',
        question: 'PRIVATE QUESTION',
        answer: 'PRIVATE ANSWER',
      );
      expect(body, contains('Please check this'));
      expect(body, isNot(contains('PRIVATE')));
      final uri = answerReportEmailUri(body);
      expect(uri.scheme, 'mailto');
      expect(uri.path, answerReportSupportEmail);
      expect(uri.queryParameters['body'], body);
      expect(uri.queryParameters.keys, unorderedEquals(['subject', 'body']));
    },
  );

  test(
    'selected text removes URLs, identifiers and credentials and round-trips email punctuation',
    () {
      final body = answerReportBody(
        note: 'A + B & C?\nSecond line',
        includeContent: true,
        question:
            'Solve x+1=3 https://ai.calcai.cc/private/photo?token=secret-photo-key user@example.com',
        answer:
            'x=2\nca1ca1000001 AA:BB:CC:DD:EE:FF Bearer hidden-value known-session-token',
        sensitiveValues: ['known-session-token'],
      );
      expect(body, contains('Solve x+1=3'));
      expect(body, contains('x=2'));
      for (final secret in [
        'https://',
        'secret-photo-key',
        'user@example.com',
        'ca1ca1000001',
        'AA:BB:CC:DD:EE:FF',
        'hidden-value',
        'known-session-token',
      ]) {
        expect(body, isNot(contains(secret)));
      }
      final uri = answerReportEmailUri(body);
      expect(uri.queryParameters['body'], body);
      expect(uri.query, contains('A%20%2B%20B%20%26%20C%3F%0ASecond%20line'));
    },
  );

  test(
    'large selected text is bounded without splitting emoji code points',
    () {
      final body = answerReportBody(
        note: 'N' * 900,
        includeContent: true,
        question: '😀' * 4000,
        answer: 'A' * 4000,
      );
      expect(body.runes.length, lessThan(2700));
      expect(RegExp(r'\[shortened\]').allMatches(body).length, 3);
      expect(body, isNot(contains('\uFFFD')));
    },
  );

  testWidgets(
    'History report defaults private and only opens a user-sent email draft',
    (tester) async {
      Uri? prepared;
      await _openReport(tester, (uri) async {
        prepared = uri;
        return true;
      });
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(_preview(tester), isNot(contains(_selectedQuestion)));
      expect(_preview(tester), isNot(contains(_selectedAnswer)));
      expect(find.text(answerReportSupportEmail), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Copy email'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Prepare email'));
      await tester.pumpAndSettle();
      expect(prepared!.queryParameters['body'], _preview(tester));
      expect(prepared.toString(), isNot(contains(_selectedQuestion)));
      expect(
        find.text('Email app opened. Review and send it there.'),
        findsOneWidget,
      );
      expect(find.text('Report sent'), findsNothing);
      expect(find.text('Email sent'), findsNothing);
    },
  );

  testWidgets(
    'opt-in payload contains exactly this selected exchange and reviewed note',
    (tester) async {
      Uri? prepared;
      await _openReport(tester, (uri) async {
        prepared = uri;
        return true;
      });
      await tester.enterText(
        find.byType(TextField).last,
        'The explanation is concerning.',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      final preview = _preview(tester);
      expect(preview, contains('The explanation is concerning.'));
      expect(
        preview,
        contains('Question:\n$_selectedQuestion\n\nAnswer:\n$_selectedAnswer'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Prepare email'));
      await tester.pumpAndSettle();
      final body = prepared!.queryParameters['body']!;
      expect(body, preview);
      for (final excluded in [
        _otherQuestion,
        _otherAnswer,
        'private-entry-id',
        'private-account@example.com',
        'test@example.com',
        'ca1ca1000001',
        'test-token',
        'private-photo-key',
      ]) {
        expect(body, isNot(contains(excluded)));
      }
    },
  );

  for (final throws in [false, true]) {
    testWidgets(
      'email ${throws ? 'exception' : 'unavailable'} keeps a working copy-email fallback without claiming delivery',
      (tester) async {
        String? copied;
        var launches = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await _openReport(tester, (_) async {
          launches++;
          if (throws) {
            throw StateError('fixture unavailable');
          }
          return false;
        });
        await tester.tap(find.widgetWithText(TextButton, 'Copy email'));
        await tester.pumpAndSettle();
        expect(copied, answerReportSupportEmail);
        expect(launches, 0);
        copied = null;
        await tester.tap(find.widgetWithText(FilledButton, 'Prepare email'));
        await tester.pumpAndSettle();
        expect(launches, 1);
        expect(
          find.text(
            'Could not open an email app. Copy the support email to contact us.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.widgetWithText(TextButton, 'Copy email'),
        );
        await tester.tap(find.widgetWithText(TextButton, 'Copy email'));
        await tester.pumpAndSettle();
        expect(copied, answerReportSupportEmail);
        expect(find.text('Support email copied.'), findsOneWidget);
        expect(find.text('Report sent'), findsNothing);
        expect(find.text('Email sent'), findsNothing);
      },
    );
  }

  testWidgets('Cancel leaves the answer detail without opening email', (
    tester,
  ) async {
    var launches = 0;
    await _openReport(tester, (_) async {
      launches++;
      return true;
    });
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(launches, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(_selectedAnswer), findsWidgets);
  });

  testWidgets(
    'signout removes a report draft and the underlying private detail before launch',
    (tester) async {
      var launches = 0;
      final auth = await _openReport(tester, (_) async {
        launches++;
        return true;
      });
      await tester.enterText(
        find.byType(TextField).last,
        'PRIVATE REPORT NOTE',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(_preview(tester), contains(_selectedAnswer));
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Report unavailable'), findsOneWidget);
      expect(find.byKey(const ValueKey('answer-report-preview')), findsNothing);
      expect(find.text('PRIVATE REPORT NOTE'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Prepare email'), findsNothing);
      expect(launches, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(
        find.text('Account or calculator changed. Close this answer.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('repeated prepare taps do not open duplicate pending drafts', (
    tester,
  ) async {
    final reply = Completer<bool>();
    var launches = 0;
    await _openReport(tester, (_) {
      launches++;
      return reply.future;
    });
    final prepare = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Prepare email'),
        )
        .onPressed!;
    prepare();
    prepare();
    await tester.pump();
    expect(launches, 1);
    reply.complete(false);
    await tester.pumpAndSettle();
    expect(launches, 1);
  });
}
