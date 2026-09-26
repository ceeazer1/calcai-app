import 'dart:async';

import 'package:calcai_app/services/session_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _StalledBodyClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    return http.StreamedResponse(body.stream, 200, request: request);
  }
}

void main() {
  testWidgets('stalled response body times out without replaying a mutation', (
    tester,
  ) async {
    final transport = _StalledBodyClient();
    final client = SessionHttpClient(transport);
    Object? failure;
    final pending = client
        .post(Uri.parse('https://ai.calcai.cc/ai/notes'))
        .then<void>((_) {}, onError: (Object error) => failure = error);
    await tester.pump();
    transport.body.add([123]);
    await tester.pump(const Duration(seconds: 21));
    expect(failure, isA<TimeoutException>());
    expect(transport.requests, 1);
    await transport.body.close();
    await pending;
    client.close();
  });
}
