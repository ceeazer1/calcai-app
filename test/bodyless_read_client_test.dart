import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/services/bodyless_read_client.dart';
import 'package:calcai_app/services/session_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Transport extends http.BaseClient {
  _Transport(this.onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest) onSend;
  int sends = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    return onSend(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _response(http.BaseRequest request, {int status = 200}) {
  final body = utf8.encode('{"ok":true}');
  return http.StreamedResponse(
    Stream.value(body),
    status,
    request: request,
    contentLength: body.length,
    headers: {'content-type': 'application/json'},
    reasonPhrase: 'Test response',
    persistentConnection: false,
  );
}

void main() {
  for (final method in ['GET', 'HEAD']) {
    test(
      '$method reaches native transport without a body or length header',
      () async {
        final original =
            http.Request(
                method,
                Uri.parse('https://ai.calcai.cc/ai/user/ai-consent'),
              )
              ..headers.addAll({
                'Authorization': 'Bearer test-session',
                'Accept': 'application/json',
                'Content-Length': '0',
              })
              ..followRedirects = false
              ..maxRedirects = 2
              ..persistentConnection = false;
        final transport = _Transport((request) async {
          // CupertinoClient's Request fast path assigns NSData even when empty.
          expect(request, isNot(isA<http.Request>()));
          expect(request.contentLength, isNull);
          expect(request.headers.containsKey('content-length'), isFalse);
          expect(request.method, method);
          expect(request.url, original.url);
          expect(request.headers['authorization'], 'Bearer test-session');
          expect(request.headers['accept'], 'application/json');
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 2);
          expect(request.persistentConnection, isFalse);
          expect(await request.finalize().toBytes(), isEmpty);
          return _response(request);
        });
        final client = BodylessReadClient(transport);
        addTearDown(client.close);

        final response = await http.Response.fromStream(
          await client.send(original),
        );
        expect(original.finalized, isTrue);
        expect(response.request, same(original));
        expect(response.statusCode, 200);
        expect(response.body, '{"ok":true}');
        expect(response.headers['content-type'], 'application/json');
        expect(response.reasonPhrase, 'Test response');
        expect(response.persistentConnection, isFalse);
        expect(transport.sends, 1);
      },
    );
  }

  test('consent and usage reads use the same bodyless path', () async {
    final paths = <String>[];
    final transport = _Transport((request) async {
      paths.add(request.url.path);
      expect(request.contentLength, isNull);
      expect(request, isNot(isA<http.Request>()));
      expect(await request.finalize().toBytes(), isEmpty);
      return _response(request, status: 401);
    });
    final client = BodylessReadClient(transport);
    addTearDown(client.close);
    for (final path in ['/ai/user/ai-consent', '/ai/usage/status']) {
      final response = await client.get(
        Uri.https('ai.calcai.cc', path),
        headers: {'Authorization': 'Bearer invalid-test-session'},
      );
      expect(response.statusCode, 401);
    }
    expect(paths, ['/ai/user/ai-consent', '/ai/usage/status']);
    expect(transport.sends, 2, reason: 'Failed reads must not be replayed');
  });

  test(
    'mutations, explicit bodies and streams pass through unchanged',
    () async {
      final requests = <http.BaseRequest>[
        http.Request('POST', Uri.https('ai.calcai.cc', '/auth/apple'))
          ..body = 'single-use-test-code',
        http.Request('PUT', Uri.https('ai.calcai.cc', '/ai/user/ai-consent'))
          ..body = '{"allowed":true}',
        http.Request('POST', Uri.https('ai.calcai.cc', '/empty')),
        http.Request('GET', Uri.https('example.test', '/explicit-body'))
          ..body = 'explicit-body',
        http.StreamedRequest('GET', Uri.https('example.test', '/stream')),
      ];
      final expectedBodies = [
        'single-use-test-code',
        '{"allowed":true}',
        '',
        'explicit-body',
        '',
      ];
      final transport = _Transport((request) async {
        final index = requests.indexOf(request);
        expect(index, greaterThanOrEqualTo(0));
        expect(await request.finalize().bytesToString(), expectedBodies[index]);
        return _response(request, status: 503);
      });
      final client = BodylessReadClient(transport);
      for (final request in requests) {
        if (request is http.StreamedRequest) unawaited(request.sink.close());
        final response = await client.send(request);
        expect(response.statusCode, 503);
        await response.stream.drain<void>();
      }
      expect(transport.sends, requests.length);
      client.close();
      expect(transport.closed, isTrue);
    },
  );

  test('cancelling a bodyless read reaches the native transport', () async {
    final abort = Completer<void>();
    final started = Completer<void>();
    final original = http.AbortableRequest(
      'GET',
      Uri.https('ai.calcai.cc', '/ai/usage/status'),
      abortTrigger: abort.future,
    );
    final transport = _Transport((request) async {
      expect(request, isA<http.Abortable>());
      expect((request as http.Abortable).abortTrigger, same(abort.future));
      await request.finalize().drain<void>();
      started.complete();
      await request.abortTrigger;
      throw http.RequestAbortedException(request.url);
    });
    final client = BodylessReadClient(transport);
    addTearDown(client.close);
    final pending = expectLater(
      client.send(original),
      throwsA(isA<http.RequestAbortedException>()),
    );
    await started.future;
    abort.complete();
    await pending;
    expect(transport.sends, 1);
  });

  test(
    'session guard accepts current reads and rejects old account responses',
    () async {
      final lateResponse = Completer<http.StreamedResponse>();
      final started = Completer<http.BaseRequest>();
      var delayed = false;
      final transport = _Transport((request) async {
        await request.finalize().drain<void>();
        if (!delayed) return _response(request);
        started.complete(request);
        return lateResponse.future;
      });
      final client = SessionHttpClient(BodylessReadClient(transport));
      addTearDown(client.close);
      final url = Uri.https('ai.calcai.cc', '/ai/usage/status');
      final current = await client.get(url);
      expect(() => client.ensureCurrent(current), returnsNormally);

      delayed = true;
      final pending = expectLater(
        client.get(url),
        throwsA(isA<http.ClientException>()),
      );
      final request = await started.future;
      client.invalidate();
      expect(
        () => client.ensureCurrent(current),
        throwsA(isA<http.ClientException>()),
      );
      lateResponse.complete(_response(request));
      await pending;
      expect(transport.sends, 2);
    },
  );
}
