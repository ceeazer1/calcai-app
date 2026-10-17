import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:calcai_app/screens/dashboard_screen.dart';
import 'package:calcai_app/screens/history_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/setup_test_app.dart';

const _mac = 'ca1ca1000001';

http.Response _answer(String question) => http.Response(
  jsonEncode({
    'ok': true,
    'items': [
      {
        'type': 'render',
        'question': question,
        'response': 'x=4',
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
    ],
  }),
  200,
);

CloudService _cloud(Future<http.Response> Function(http.Request) history) =>
    CloudService(
      client: MockClient((request) async {
        if (request.url.path == '/ai/logs/recent' ||
            request.method == 'DELETE') {
          return history(request);
        }
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );

Future<void> _show(
  WidgetTester tester,
  CloudService cloud, {
  Widget screen = const HistoryScreen(),
}) async {
  final auth = FakeAuthService();
  await auth.init();
  final ble = SetupTestAppBle();
  addTearDown(auth.dispose);
  addTearDown(ble.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
        ChangeNotifierProvider<BleService>.value(value: ble),
      ],
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty history can pull to refresh and displays render answers', (
    tester,
  ) async {
    var calls = 0;
    final cloud = _cloud((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.queryParameters['mac'], _mac);
      expect(request.url.queryParameters['limit'], '200');
      return ++calls == 1
          ? http.Response('{"items":[]}', 200)
          : _answer('SOLVE2X+3=11');
    });
    addTearDown(cloud.dispose);
    await _show(tester, cloud);
    expect(find.text('No prompts yet'), findsOneWidget);
    final refresh = tester
        .getSemantics(find.byTooltip('Refresh history'))
        .getSemanticsData();
    expect(refresh.tooltip, 'Refresh history');
    expect(refresh.flagsCollection.isButton, isTrue);
    expect(refresh.hasAction(SemanticsAction.tap), isTrue);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('SOLVE2X+3=11'), findsOneWidget);
    expect(find.text('No prompts yet'), findsNothing);
  });

  testWidgets('a failed read shows Retry instead of an empty history', (
    tester,
  ) async {
    var healthy = false;
    final cloud = _cloud(
      (_) async => healthy
          ? _answer('RECOVERED')
          : http.Response('{"error":"unavailable"}', 503),
    );
    addTearDown(cloud.dispose);
    await _show(tester, cloud);
    expect(find.text("Couldn't load history"), findsOneWidget);
    expect(find.text('No prompts yet'), findsNothing);
    healthy = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('RECOVERED'), findsOneWidget);
    expect(cloud.historyError, isNull);
  });

  testWidgets('failed refresh keeps saved answers and exposes recovery', (
    tester,
  ) async {
    var healthy = true;
    final cloud = _cloud(
      (_) async => healthy
          ? _answer('SAVED ANSWER')
          : http.Response('{"error":"unavailable"}', 503),
    );
    addTearDown(cloud.dispose);
    await _show(tester, cloud);
    healthy = false;
    await tester.tap(find.byTooltip('Refresh history'));
    await tester.pumpAndSettle();
    expect(find.text('SAVED ANSWER'), findsOneWidget);
    expect(find.textContaining('Showing saved activity.'), findsOneWidget);
    healthy = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
    'Home surfaces failed activity reads and Retry fetches the answer',
    (tester) async {
      var healthy = false;
      final cloud = _cloud(
        (_) async => healthy
            ? _answer('HOME ANSWER')
            : http.Response('{"error":"unavailable"}', 503),
      );
      addTearDown(cloud.dispose);
      await _show(tester, cloud, screen: const DashboardScreen());
      await tester.scrollUntilVisible(
        find.textContaining('History is unavailable'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No prompt yet'), findsNothing);
      final notice = find
          .ancestor(
            of: find.textContaining('History is unavailable'),
            matching: find.byType(Row),
          )
          .first;
      healthy = true;
      await tester.tap(
        find.descendant(of: notice, matching: find.text('Retry')),
      );
      await tester.pumpAndSettle();
      expect(find.text('HOME ANSWER'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'malformed success responses preserve cache and surface an error',
    () async {
      var response = _answer('ORIGINAL');
      final cloud = _cloud((_) async => response);
      addTearDown(cloud.dispose);
      await cloud.getHistory('test-token', _mac);
      for (final body in [
        '{}',
        '{"ok":false,"items":[]}',
        '{"items":[null]}',
        'not json',
      ]) {
        response = http.Response(body, 200);
        await cloud.getHistory('test-token', _mac);
        expect(cloud.history.single['question'], 'ORIGINAL');
        expect(cloud.historyError, contains('unexpected history response'));
        expect(cloud.isHistoryLoading, isFalse);
      }
      response = http.Response('{"ok":true,"items":[]}', 200);
      await cloud.getHistory('test-token', _mac);
      expect(cloud.history, isEmpty);
      expect(cloud.historyError, isNull);
    },
  );

  test('Home refresh retains the larger History request size', () async {
    final limits = <String?>[];
    final cloud = _cloud((request) async {
      limits.add(request.url.queryParameters['limit']);
      return http.Response('{"items":[]}', 200);
    });
    addTearDown(cloud.dispose);
    await cloud.getHistory('test-token', _mac, limit: 200);
    await cloud.getHistory('test-token', _mac, limit: 10);
    await cloud.getHistory('test-token', 'ca1ca1000002', limit: 10);
    expect(limits, ['200', '200', '10']);
  });

  test(
    'an older response cannot replace a newer answer or error state',
    () async {
      final old = Completer<http.Response>();
      var calls = 0;
      final cloud = _cloud(
        (_) => ++calls == 1 ? old.future : Future.value(_answer('NEWER')),
      );
      addTearDown(cloud.dispose);
      final pending = cloud.getHistory('test-token', _mac);
      await cloud.getHistory('test-token', _mac);
      old.complete(http.Response('{"error":"unavailable"}', 503));
      await pending;
      expect(cloud.history.single['question'], 'NEWER');
      expect(cloud.historyError, isNull);
      expect(cloud.isHistoryLoading, isFalse);
    },
  );

  test('cleared history cannot reappear from an older pending read', () async {
    final old = Completer<http.Response>();
    final cloud = _cloud(
      (request) => request.method == 'DELETE'
          ? Future.value(http.Response('{"ok":true}', 200))
          : old.future,
    );
    addTearDown(cloud.dispose);
    final pending = cloud.getHistory('test-token', _mac);
    expect(await cloud.clearHistory('test-token', _mac), isTrue);
    old.complete(_answer('DELETED'));
    await pending;
    expect(cloud.history, isEmpty);
    expect(cloud.historyError, isNull);
  });
}
