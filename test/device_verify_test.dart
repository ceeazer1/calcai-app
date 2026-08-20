import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/services/ble_service.dart';

/// Mirrors the firmware's bleChallengeResponse() and the worker's check, so the
/// three implementations are pinned to one another by a test.
String firmwareAnswer(String secret, String mac, String nonce) =>
    Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$mac|$nonce'))
        .toString();

void main() {
  group('MAC validation', () {
    test('accepts a normalised MAC', () {
      expect(isValidMacHex('aabbccddeeff'), isTrue);
    });

    test('rejects the shapes that could reach a query string', () {
      // The old code stripped only colons, so these survived into API URLs.
      expect(isValidMacHex('aabbccddeeff&limit=999'), isFalse);
      expect(isValidMacHex('aabbcc#'), isFalse);
      expect(isValidMacHex('../../etc'), isFalse);
      expect(isValidMacHex('AABBCCDDEEFF'), isFalse,
          reason: 'must be lowercased first');
      expect(isValidMacHex('aabbccddee'), isFalse, reason: 'too short');
      expect(isValidMacHex('aabbccddeeff00'), isFalse, reason: 'too long');
      expect(isValidMacHex('zzbbccddeeff'), isFalse, reason: 'not hex');
      expect(isValidMacHex('000000000000'), isFalse,
          reason: 'WiFi reports all zeroes before its radio is initialised');
      expect(isValidMacHex('ffffffffffff'), isFalse,
          reason: 'broadcast is not a device identity');
      expect(isValidMacHex(''), isFalse);
      expect(isValidMacHex(null), isFalse);
    });
  });

  group('challenge answer', () {
    const secret = 'test-master-secret';
    const mac = 'aabbccddeeff';
    const nonce = '0123456789abcdef0123456789abcdef';

    test('matches the worker byte for byte', () {
      // Reference vector generated with Node's crypto, which is what the
      // Worker's crypto.subtle HMAC produces. If the firmware, the worker and
      // this ever drift on encoding or the separator, this test fails first.
      expect(
        firmwareAnswer(secret, mac, nonce),
        'e117c9bc40fb6e56fab3f78f75e9e45b6490cf300c572b051caa57bdc47b2068',
      );
    });

    test('is 64 hex characters', () {
      final a = firmwareAnswer(secret, mac, nonce);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    });

    test('changes with the nonce, so it cannot be replayed', () {
      final a = firmwareAnswer(secret, mac, nonce);
      final b = firmwareAnswer(secret, mac, 'ffffffffffffffffffffffffffffffff');
      expect(a, isNot(b));
    });

    test('changes with the MAC, so one device cannot answer for another', () {
      final a = firmwareAnswer(secret, mac, nonce);
      final b = firmwareAnswer(secret, '112233445566', nonce);
      expect(a, isNot(b));
    });

    test('an impostor without the secret produces a different answer', () {
      final real = firmwareAnswer(secret, mac, nonce);
      final fake = firmwareAnswer('guessed-secret', mac, nonce);
      expect(real, isNot(fake));
    });

    test('the "mac|nonce" separator is not ambiguous', () {
      // Without a separator, ("aabb","ccdd") and ("aabbcc","dd") would collide.
      expect(
        firmwareAnswer(
            secret, 'aabbccddeeff', '00112233445566778899aabbccddeeff'),
        isNot(firmwareAnswer(
            secret, 'aabbccddeeff00', '112233445566778899aabbccddeeff')),
      );
    });
  });

  group('verification gate fails closed', () {
    test('an unwired verifier refuses, rather than silently allowing',
        () async {
      final ble = BleService();
      // deviceVerifier deliberately left null — a forgotten wiring must block.
      expect(await ble.ensureDeviceVerified(), isFalse);
      expect(ble.error, isNotNull);
    });

    test('a verifier that says no refuses', () async {
      final ble = BleService()..deviceVerifier = (_) async => false;
      expect(await ble.ensureDeviceVerified(), isFalse);
    });

    test('a verifier that throws refuses', () async {
      final ble = BleService()
        ..deviceVerifier = (_) async => throw Exception('offline');
      expect(await ble.ensureDeviceVerified(), isFalse);
    });

    test('a device that cannot answer the challenge refuses', () async {
      // No scan characteristic => no answer, which is what an impostor and
      // pre-challenge firmware both look like.
      final ble = BleService()..deviceVerifier = (_) async => true;
      expect(await ble.ensureDeviceVerified(), isFalse);
      expect(ble.error, contains('security check'));
    });

    test('nothing is cached as verified after a failure', () async {
      final ble = BleService()..deviceVerifier = (_) async => false;
      await ble.ensureDeviceVerified();
      expect(ble.verifiedChallenge, isNull);
    });

    test('no challenge is cached on a fresh service', () {
      expect(BleService().verifiedChallenge, isNull);
    });
  });
}
