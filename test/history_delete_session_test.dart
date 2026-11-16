import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _macA = 'ca1ca1000001';
const _macB = 'ca1ca1000002';

http.Response _history(String question) => http.Response(
  jsonEncode({
    'ok': true,
    'items': [
      {'question': question, 'response': 'fixture answer'},
    ],
  }),
  200,
);

void main() {
  for (final switchAccount in [false, true]) {
    test(
      'late deletion cannot clear the next ${switchAccount ? 'account' : 'device'} history',
      () async {
        final deletion = Completer<http.Response>();
        final cloud = CloudService(
          client: MockClient((request) async {
            if (request.method == 'DELETE') return deletion.future;
            if (request.url.path == '/ai/logs/recent') {
              return _history(request.url.queryParameters['mac']!);
            }
            return http.Response('{"error":"unavailable"}', 503);
          }),
        );
        addTearDown(cloud.dispose);
        await cloud.getHistory('account-a', _macA);
        final pending = cloud.clearHistory('account-a', _macA);
        if (switchAccount) cloud.reset();
        await cloud.getHistory(
          switchAccount ? 'account-b' : 'account-a',
          _macB,
        );
        deletion.complete(http.Response('{"ok":true}', 200));
        expect(await pending, isFalse);
        expect(cloud.history.single['question'], _macB);
        expect(cloud.error, isNull);
      },
    );
  }

  test(
    'late deletion failure cannot set an error on the next account',
    () async {
      final deletion = Completer<http.Response>();
      final cloud = CloudService(
        client: MockClient((request) async {
          if (request.method == 'DELETE') return deletion.future;
          if (request.url.path == '/ai/logs/recent') return _history('current');
          return http.Response('{"error":"unavailable"}', 503);
        }),
      );
      addTearDown(cloud.dispose);
      await cloud.getHistory('account-a', _macA);
      final pending = cloud.clearHistory('account-a', _macA);
      cloud.reset();
      await cloud.getHistory('account-b', _macB);
      deletion.complete(http.Response('{"ok":false}', 503));
      expect(await pending, isFalse);
      expect(cloud.error, isNull);
      expect(cloud.history.single['question'], 'current');
    },
  );

  test('unconfirmed deletion preserves the known history', () async {
    var body = '{}';
    final cloud = CloudService(
      client: MockClient((request) async {
        if (request.method == 'DELETE') return http.Response(body, 200);
        if (request.url.path == '/ai/logs/recent') return _history('keep');
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.getHistory('account-a', _macA);
    for (final invalid in ['{}', '{"ok":false}', 'not JSON']) {
      body = invalid;
      expect(await cloud.clearHistory('account-a', _macA), isFalse);
      expect(cloud.history.single['question'], 'keep');
    }
  });

  test('repeated clear submits only one pending deletion', () async {
    var deletes = 0;
    final deletion = Completer<http.Response>();
    final cloud = CloudService(
      client: MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          return deletion.future;
        }
        if (request.url.path == '/ai/logs/recent') return _history('keep');
        return http.Response('{"error":"unavailable"}', 503);
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.getHistory('account-a', _macA);
    final first = cloud.clearHistory('account-a', _macA);
    final second = cloud.clearHistory('account-a', _macA);
    await Future<void>.delayed(Duration.zero);
    expect(deletes, 1);
    deletion.complete(http.Response('{"ok":true}', 200));
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(cloud.history, isEmpty);
  });
}
