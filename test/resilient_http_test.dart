import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/services/resilient_http_client.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  test(
    'API transport reuses connections and reads responses before socket closes',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = previous);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = createResilientClient();
      final ports = <int>[];
      server.listen((request) async {
        ports.add(request.connectionInfo!.remotePort);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      try {
        final url = Uri.parse('http://127.0.0.1:${server.port}/test');
        expect(
          (await client.get(url).timeout(const Duration(seconds: 3))).body,
          '{"ok":true}',
        );
        expect(
          (await client.get(url).timeout(const Duration(seconds: 3)))
              .statusCode,
          200,
        );
        expect(ports.length, 2);
        expect(ports.toSet().length, 1);
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );
}
