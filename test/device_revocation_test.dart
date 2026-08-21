import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('device revocation response', () {
    test('accepts only the explicit ownership error', () {
      expect(
        isDeviceOwnershipRevocation(
          http.Response('{"ok":false,"error":"device_not_owned"}', 403),
        ),
        isTrue,
      );
    });

    test('does not mistake another security rejection for an unpair', () {
      expect(
        isDeviceOwnershipRevocation(
          http.Response('{"ok":false,"error":"not_genuine"}', 403),
        ),
        isFalse,
      );
      expect(
        isDeviceOwnershipRevocation(http.Response('invalid proof', 403)),
        isFalse,
      );
    });

    test('does not treat non-403 responses as an unpair', () {
      expect(
        isDeviceOwnershipRevocation(
          http.Response('{"error":"device_not_owned"}', 401),
        ),
        isFalse,
      );
    });
  });
}
