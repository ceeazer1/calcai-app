import 'dart:io';
import 'dart:async';
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
  test(
    'HTTPS starts TLS before any HTTP headers or credentials are sent',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = previous);
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final client = createResilientClient();
      final firstPacket = Completer<List<int>>();
      server.listen((socket) {
        socket.listen(
          (data) {
            if (!firstPacket.isCompleted) firstPacket.complete(data);
            socket.destroy();
          },
          onError: (_) {
            socket.destroy();
          },
        );
      });
      try {
        final request = client.post(
          Uri.parse('https://127.0.0.1:${server.port}/auth/apple'),
          headers: {'Authorization': 'Bearer test-only-token'},
          body: 'test-only-code',
        );
        final failed = expectLater(request, throwsA(anything));
        final packet = await firstPacket.future.timeout(
          const Duration(seconds: 3),
        );
        expect(
          packet.first,
          0x16,
          reason:
              'The first record must be a TLS handshake, never plaintext HTTP',
        );
        expect(
          String.fromCharCodes(packet),
          isNot(contains('test-only-token')),
        );
        expect(String.fromCharCodes(packet), isNot(contains('test-only-code')));
        await failed;
      } finally {
        client.close();
        await server.close();
      }
    },
  );
}
