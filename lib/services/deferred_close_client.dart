import 'dart:async';

import 'package:http/http.dart' as http;

import 'bounded_response.dart';

/// Closes a native transport only after its complete responses settle.
/// CupertinoClient throws when close runs while a URLSession task is active.
/// App consumers already need complete JSON/photo bodies; buffer once here so
/// response subscriptions cannot delay releasing the native task after close.
class DeferredCloseClient extends http.BaseClient {
  DeferredCloseClient(
    this._inner, {
    this.requestDeadline = const Duration(seconds: 30),
    this.maxResponseBytes,
  });

  final http.Client _inner;
  final Duration requestDeadline;
  final int? maxResponseBytes;
  int _active = 0;
  bool _closing = false;
  bool _innerClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closing) throw http.ClientException('Client closed', request.url);
    _active++;
    final deadline = Completer<void>();
    void abortRequest() {
      if (!deadline.isCompleted) {
        deadline.complete();
      }
    }

    final timer = Timer(requestDeadline, abortRequest);
    final callerAbort = request is http.Abortable ? request.abortTrigger : null;
    final abort = callerAbort == null
        ? deadline.future
        : Future.any([deadline.future, callerAbort]);
    try {
      final response = await _inner.send(_DeadlineRequest(request, abort));
      final bytes = await readBoundedResponse(
        response,
        maxResponseBytes: maxResponseBytes,
        abortTrigger: abort,
        onLimitExceeded: abortRequest,
      );
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } finally {
      timer.cancel();
      _active--;
      _closeIfSettled();
    }
  }

  void _closeIfSettled() {
    if (_closing && _active == 0 && !_innerClosed) {
      _innerClosed = true;
      _inner.close();
    }
  }

  @override
  void close() {
    _closing = true;
    _closeIfSettled();
  }
}

class _DeadlineRequest extends http.BaseRequest with http.Abortable {
  _DeadlineRequest(this._original, this.abortTrigger)
    : super(_original.method, _original.url) {
    headers.addAll(_original.headers);
    contentLength = _original.contentLength;
    followRedirects = _original.followRedirects;
    maxRedirects = _original.maxRedirects;
    persistentConnection = _original.persistentConnection;
  }

  final http.BaseRequest _original;
  @override
  final Future<void> abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return _original.finalize();
  }
}
