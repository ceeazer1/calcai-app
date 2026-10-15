import 'package:http/http.dart' as http;

/// Keeps empty GET/HEAD requests bodyless at the native transport boundary.
/// CupertinoClient assigns an empty NSData body and Content-Length: 0 to an
/// ordinary Request. Some servers reject that representation of a GET request.
/// An empty BaseRequest stream with unknown length avoids both assignments.
class BodylessReadClient extends http.BaseClient {
  BodylessReadClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request ||
        (request.method != 'GET' && request.method != 'HEAD') ||
        request.bodyBytes.isNotEmpty) {
      return _inner.send(request);
    }

    final response = await _inner.send(_BodylessRead(request));
    return http.StreamedResponse(
      response.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

class _BodylessRead extends http.BaseRequest with http.Abortable {
  _BodylessRead(this._original)
    : abortTrigger = _original is http.Abortable
          ? (_original as http.Abortable).abortTrigger
          : null,
      super(_original.method, _original.url) {
    headers.addAll(_original.headers);
    headers.remove('content-length');
    followRedirects = _original.followRedirects;
    maxRedirects = _original.maxRedirects;
    persistentConnection = _original.persistentConnection;
  }

  final http.Request _original;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return _original.finalize();
  }
}
