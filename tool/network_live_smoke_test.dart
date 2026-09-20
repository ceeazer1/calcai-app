import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/services/resilient_http_client.dart';

class NativeIo extends HttpOverrides {}

void main() {
  test('live HTTPS without credentials', () async {
    HttpOverrides.global = NativeIo();
    final client = createResilientClient();
    try {
      for (var i = 0; i < 2; i++) {
        final watch = Stopwatch()..start();
        final result = await client
            .get(Uri.parse('https://ai.calcai.cc/ai/user/ai-consent'))
            .timeout(const Duration(seconds: 20));
        expect(result.statusCode, 401);
        expect(result.body, contains('unauth'));
        stdout.writeln(
          'HTTPS request ${i + 1}: ${result.statusCode}, ${watch.elapsedMilliseconds} ms',
        );
      }
    } finally {
      client.close();
    }
  });
}
