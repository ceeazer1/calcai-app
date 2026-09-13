import 'package:http/http.dart' as http;

/// Discards responses that finish after sign-out or account/device switching.
/// CloudService consumes complete JSON responses, so guard the complete body,
/// not just the response headers, before allowing it to enter a new session.
class SessionHttpClient extends http.BaseClient {
  SessionHttpClient(this._inner);
  final http.Client _inner;
  int _generation = 0;
  bool _closed = false;
  final _requests = Expando<int>();

  void invalidate() => _generation++;

  /// Recheck at the cache write boundary, after BaseClient consumes the stream.
  void ensureCurrent(http.Response response) {
    final request = response.request;
    if (_closed || request == null || _requests[request] != _generation) {
      throw http.ClientException('Session changed', request?.url);
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed', request.url);
    final generation = _generation;
    _requests[request] = generation;
    final response = await http.Response.fromStream(await _inner.send(request));
    if (_closed || generation != _generation) {
      throw http.ClientException('Session changed', request.url);
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      contentLength: response.bodyBytes.length,
      request: request,
      reasonPhrase: response.reasonPhrase,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
    );
  }

  @override
  void close() {
    _closed = true;
    invalidate();
    _inner.close();
  }
}
