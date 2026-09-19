import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcai_app/services/cloud_service.dart';

void main() {
  test('only an explicit ownership conflict returns null', () async {
    for (final status in [401, 403, 404, 409, 500, 503]) {
      final cloud = CloudService(
        client: MockClient(
          (_) async => http.Response('{"error":"unexpected"}', status),
        ),
      );
      addTearDown(cloud.dispose);
      await expectLater(
        cloud.requestPairingRelease(
          'token',
          '112233aabbcc',
          '1234567890abcdef',
        ),
        throwsA(isA<PairingReleaseException>()),
      );
    }
    final cloud = CloudService(
      client: MockClient(
        (_) async => http.Response('{"error":"still_owned"}', 409),
      ),
    );
    addTearDown(cloud.dispose);
    expect(
      await cloud.requestPairingRelease(
        'token',
        '112233aabbcc',
        '1234567890abcdef',
      ),
      isNull,
    );
  });
  test(
    'valid signed recovery succeeds; malformed success is an error',
    () async {
      final sig = 'a' * 64;
      final cloud = CloudService(
        client: MockClient(
          (_) async => http.Response('{"ok":true,"response":"$sig"}', 200),
        ),
      );
      addTearDown(cloud.dispose);
      expect(
        await cloud.requestPairingRelease(
          'token',
          '112233aabbcc',
          '1234567890abcdef',
        ),
        sig,
      );
      final invalid = CloudService(
        client: MockClient((_) async => http.Response('{"ok":true}', 200)),
      );
      addTearDown(invalid.dispose);
      await expectLater(
        invalid.requestPairingRelease(
          'token',
          '112233aabbcc',
          '1234567890abcdef',
        ),
        throwsA(isA<PairingReleaseException>()),
      );
    },
  );
}
