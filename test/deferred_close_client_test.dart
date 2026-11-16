import 'dart:async';

import 'package:calcai_app/services/deferred_close_client.dart';
import 'package:calcai_app/services/bounded_response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class NativeLifetimeClient extends http.BaseClient {
  NativeLifetimeClient(this.onSend);
  final Future<http.StreamedResponse> Function(http.BaseRequest) onSend;
  int active = 0;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
  @override
  void close() {
    if (active != 0) throw StateError('cannot close with running requests');
    closes++;
  }
}

void main() {
  for (final headersReady in [false, true]) {
    test(
      'close ${headersReady ? 'during body' : 'before headers'} waits for native completion',
      () async {
        final headers = Completer<http.StreamedResponse>();
        final body = StreamController<List<int>>();
        final inner = NativeLifetimeClient((request) async {
          await request.finalize().drain<void>();
          return headers.future;
        })..active = 1;
        final client = DeferredCloseClient(inner);
        final pending = client.get(Uri.https('fixture.test', '/image'));
        if (headersReady) {
          headers.complete(http.StreamedResponse(body.stream, 200));
          body.add([1, 2]);
          await Future<void>.delayed(Duration.zero);
        }
        client.close();
        client.close();
        expect(inner.closes, 0);
        await expectLater(
          client.get(Uri.https('fixture.test', '/other')),
          throwsA(isA<http.ClientException>()),
        );
        if (!headersReady) {
          headers.complete(http.StreamedResponse(body.stream, 200));
        }
        inner.active = 0;
        await body.close();
        expect((await pending).statusCode, 200);
        expect(inner.closes, 1);
        client.close();
        expect(inner.closes, 1);
      },
    );
  }

  test('send failure settles native task before deferred close', () async {
    final error = Completer<http.StreamedResponse>();
    final inner = NativeLifetimeClient((_) => error.future)..active = 1;
    final client = DeferredCloseClient(inner);
    final pending = expectLater(
      client.get(Uri.https('fixture.test', '/error')),
      throwsA(isA<http.ClientException>()),
    );
    client.close();
    inner.active = 0;
    error.completeError(http.ClientException('fixture failure'));
    await pending;
    expect(inner.closes, 1);
  });

  test(
    'partial-body failure releases the native client without hiding the error',
    () async {
      final body = StreamController<List<int>>();
      final inner = NativeLifetimeClient((request) async {
        await request.finalize().drain<void>();
        return http.StreamedResponse(body.stream, 200);
      })..active = 1;
      final client = DeferredCloseClient(inner);
      final pending = expectLater(
        client.get(Uri.https('fixture.test', '/partial')),
        throwsA(isA<http.ClientException>()),
      );
      body.add([1]);
      await Future<void>.delayed(Duration.zero);
      client.close();
      expect(inner.closes, 0);
      inner.active = 0;
      body.addError(http.ClientException('partial fixture failure'));
      await body.close();
      await pending;
      expect(inner.closes, 1);
    },
  );

  for (final callerCancels in [false, true]) {
    test(
      '${callerCancels ? 'caller abort' : 'total deadline'} cancels once and settles before close',
      () async {
        final caller = Completer<void>();
        late NativeLifetimeClient inner;
        var sends = 0;
        inner = NativeLifetimeClient((request) async {
          sends++;
          inner.active++;
          expect(request, isA<http.Abortable>());
          expect(request.headers['authorization'], 'Bearer fixture');
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 2);
          expect(request.persistentConnection, isFalse);
          expect(await request.finalize().bytesToString(), 'single-use-code');
          await (request as http.Abortable).abortTrigger;
          inner.active--;
          throw http.RequestAbortedException(request.url);
        });
        final client = DeferredCloseClient(
          inner,
          requestDeadline: const Duration(milliseconds: 20),
        );
        final request =
            http.AbortableRequest(
                'POST',
                Uri.https('fixture.test', '/auth'),
                abortTrigger: caller.future,
              )
              ..headers['authorization'] = 'Bearer fixture'
              ..body = 'single-use-code'
              ..followRedirects = false
              ..maxRedirects = 2
              ..persistentConnection = false;
        final pending = expectLater(
          client.send(request),
          throwsA(isA<http.RequestAbortedException>()),
        );
        client.close();
        if (callerCancels) caller.complete();
        await pending;
        expect(inner.closes, 1);
        expect(sends, 1, reason: 'mutations must never be replayed');
      },
    );
  }

  test('unrelated close errors are propagated', () {
    final inner = NativeLifetimeClient((_) async => throw UnimplementedError())
      ..active = 1;
    expect(DeferredCloseClient(inner).close, throwsStateError);
  });

  for (final declared in [false, true]) {
    test(
      '${declared ? 'declared' : 'chunked'} oversized response aborts once and waits for native cancellation before close',
      () async {
        final cancelled = Completer<void>();
        final settled = Completer<void>();
        late NativeLifetimeClient inner;
        var sends = 0;
        var aborts = 0;
        final body = StreamController<List<int>>(
          onCancel: () async {
            cancelled.complete();
            await settled.future;
            inner.active = 0;
          },
        );
        inner = NativeLifetimeClient((request) async {
          sends++;
          inner.active++;
          unawaited(
            (request as http.Abortable).abortTrigger!.then<void>((_) {
              aborts++;
            }),
          );
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: declared ? 5 : null,
          );
        });
        final client = DeferredCloseClient(inner, maxResponseBytes: 4);
        final pending = expectLater(
          client.get(Uri.https('fixture.test', '/photo')),
          throwsA(isA<ResponseTooLargeException>()),
        );
        if (!declared) {
          body.add([1, 2, 3]);
          body.add([4, 5]);
        }
        await cancelled.future;
        client.close();
        client.close();
        expect(inner.closes, 0);
        expect(inner.active, 1);
        settled.complete();
        await pending;
        expect(aborts, 1);
        expect(sends, 1);
        expect(inner.closes, 1);
        await body.close();
      },
    );
  }

  test(
    'deadline during a stalled partial body cancels and waits for native settlement',
    () async {
      final cancelled = Completer<void>();
      final settled = Completer<void>();
      late NativeLifetimeClient inner;
      final body = StreamController<List<int>>(
        onCancel: () async {
          cancelled.complete();
          await settled.future;
          inner.active = 0;
        },
      );
      inner = NativeLifetimeClient((_) async {
        inner.active++;
        return http.StreamedResponse(body.stream, 200);
      });
      final client = DeferredCloseClient(
        inner,
        maxResponseBytes: 4,
        requestDeadline: const Duration(milliseconds: 20),
      );
      final pending = expectLater(
        client.get(Uri.https('fixture.test', '/slow-photo')),
        throwsA(isA<http.RequestAbortedException>()),
      );
      body.add([1]);
      client.close();
      await cancelled.future;
      expect(inner.closes, 0);
      settled.complete();
      await pending;
      expect(inner.closes, 1);
      await body.close();
    },
  );
}
