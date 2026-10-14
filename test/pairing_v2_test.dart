import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:calcai_app/models/calcai_device.dart';
import 'package:calcai_app/models/pairing_v2.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/screens/pair_device_screen.dart';
import 'package:calcai_app/screens/success_screen.dart';
import 'support/fake_auth_service.dart';

const mac = '112233aabbcc';
const ownership = '12345678-1234-1234-1234-123456789abc';
Map<String, dynamic> offerData() => {
  'ok': true,
  'protocol': 2,
  'mac': mac,
  'challengeId': 'a' * 32,
  'accountBinding': 'b' * 64,
  'nonce': 'c' * 64,
  'expiresAt': DateTime.now().millisecondsSinceEpoch + 120000,
  'offerSignature': 'd' * 64,
};
Map<String, dynamic> approvalData() => {
  'ok': true,
  'cmd': 'pairapprove',
  'protocol': 2,
  'mac': mac,
  'challengeId': 'a' * 32,
  'approvalNonce': 'e' * 32,
  'approvalResponse': 'f' * 64,
};
Map<String, dynamic> completionData() => {
  'ok': true,
  'protocol': 2,
  'mac': mac,
  'completion': {
    'ownershipId': ownership,
    'pairedAt': 1791850000000,
    'signature': '1' * 64,
  },
};

class PairBle extends BleService {
  Map<String, dynamic>? capabilities = {
    'cmd': 'capabilities',
    'pairingApprovalVersion': 2,
  };
  final commands = <Map<String, dynamic>>[];
  bool connected = true;
  int failedCompletions = 0;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? intercept;
  @override
  DeviceConnectionState get connectionState => connected
      ? DeviceConnectionState.ready
      : DeviceConnectionState.disconnected;
  @override
  String get deviceMac => mac;
  @override
  Future<bool> ensureDeviceVerified() async => true;
  @override
  Future<void> setPersistMac(String? mac) async {}
  @override
  Future<void> disconnect() async {
    connected = false;
    await super.disconnect();
  }

  @override
  Future<Map<String, dynamic>?> sendPairingCommand(
    Map<String, dynamic> command,
  ) async {
    commands.add(command);
    if (intercept != null) return intercept!(command);
    switch (command['cmd']) {
      case 'capabilities':
        return capabilities;
      case 'pairapprove':
        return approvalData();
      case 'paircomplete':
        if (failedCompletions-- > 0) return null;
        return {
          'ok': true,
          'cmd': 'paircomplete',
          'protocol': 2,
          'mac': mac,
          'challengeId': 'a' * 32,
          'ownershipId': ownership,
        };
    }
    throw StateError('Unexpected command ${command['cmd']}');
  }
}

class PairAuth extends FakeAuthService {
  int adds = 0;
  @override
  Future<void> addDevice(String mac, {bool announce = true}) async {
    adds++;
  }
}

Future<void> openPair(
  WidgetTester tester,
  PairBle ble,
  PairAuth auth,
  CloudService cloud,
) async {
  await auth.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BleService>.value(value: ble),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PairDeviceScreen(),
                ),
              ),
              child: const Text('Start'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
    'shared backend vector survives the complete app relay unchanged',
    () async {
      // Exact copy of edge-worker/test/fixtures/pairing-v2-contract.json so the
      // app's standalone CI checkout can run this contract test. Public test key
      // only: production clients never sign these messages or hold device keys.
      final vector =
          jsonDecode(
                File(
                  'test/fixtures/pairing-v2-contract.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final signedOffer = vector['offer'] as Map<String, dynamic>;
      final signedApproval = vector['approval'] as Map<String, dynamic>;
      final signedCompletion = vector['completion'] as Map<String, dynamic>;
      final messages = vector['messages'] as Map<String, dynamic>;
      final requests = <http.Request>[];
      final cloud = CloudService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('challenge')
                  ? {'ok': true, ...signedOffer}
                  : {
                      'ok': true,
                      'protocol': 2,
                      'mac': signedOffer['mac'],
                      'pairedAt': signedCompletion['pairedAt'],
                      'completion': signedCompletion,
                    },
            ),
            200,
          );
        }),
      );
      final ble = PairBle();
      addTearDown(cloud.dispose);
      addTearDown(ble.dispose);
      ble.intercept = (command) async => switch (command['cmd']) {
        'capabilities' => ble.capabilities,
        'pairapprove' => {'ok': true, 'cmd': 'pairapprove', ...signedApproval},
        'paircomplete' => {
          'ok': true,
          'cmd': 'paircomplete',
          'protocol': 2,
          'mac': signedOffer['mac'],
          'challengeId': signedOffer['challengeId'],
          'ownershipId': signedCompletion['ownershipId'],
        },
        _ => throw StateError('Unexpected pairing command'),
      };
      await ble.negotiatePairing();
      final offer = await cloud.requestPairingOffer('test-token', mac);
      final approval = await ble.approvePairing(offer, '123456');
      final completion = await cloud.claimApprovedDevice(
        'test-token',
        offer,
        approval,
      );
      await ble.completePairing(
        offer,
        approval,
        completion,
        'test@example.com',
      );

      expect(ble.commands[1], {
        'cmd': 'pairapprove',
        ...signedOffer,
        'code': '123456',
      });
      expect(jsonDecode(requests[0].body), {'mac': signedOffer['mac']});
      expect(jsonDecode(requests[1].body), signedApproval);
      expect(
        requests.map((r) => r.headers['Authorization']),
        everyElement('Bearer test-token'),
      );
      expect(ble.commands[2], {
        'cmd': 'paircomplete',
        'protocol': 2,
        'mac': signedOffer['mac'],
        'challengeId': signedOffer['challengeId'],
        'approvalNonce': signedApproval['approvalNonce'],
        'completion': signedCompletion,
      });
      for (final command in ble.commands.skip(1)) {
        expect(utf8.encode(jsonEncode(command)).length, lessThanOrEqualTo(512));
      }

      // Construct signing messages from the actual relayed values, so field
      // transformations, timestamps, ordering and delimiters cannot drift.
      final sent = ble.commands[1];
      final binding = [
        sent['mac'],
        sent['challengeId'],
        sent['accountBinding'],
        sent['nonce'],
        sent['expiresAt'],
      ].join('|');
      final approvedBinding = '$binding|${approval.nonce}';
      final actualMessages = {
        'offer': 'calcai-pair-offer-v2|$binding',
        'approval': 'calcai-pair-approved-v2|$approvedBinding',
        'completion':
            'calcai-pair-complete-v2|$approvedBinding|${completion.fields['ownershipId']}|${completion.fields['pairedAt']}',
      };
      expect(actualMessages, messages);
      final key = vector['enrolledKeyAscii'] as String;
      expect(utf8.encode(key).length, 64);
      final hmac = Hmac(sha256, utf8.encode(key));
      final signatures = {
        'offer': sent['offerSignature'],
        'approval': approval.response,
        'completion': completion.fields['signature'],
      };
      for (final entry in actualMessages.entries) {
        expect(
          hmac.convert(utf8.encode(entry.value)).toString(),
          signatures[entry.key],
        );
      }
      // Explicitly distinguish ASCII key material from decoded hex bytes.
      final decodedHexKey = [
        for (var i = 0; i < key.length; i += 2)
          int.parse(key.substring(i, i + 2), radix: 16),
      ];
      expect(
        Hmac(
          sha256,
          decodedHexKey,
        ).convert(utf8.encode(actualMessages['offer']!)).toString(),
        isNot(signatures['offer']),
      );
    },
  );
  test(
    'negotiation pins V2 and rejects transport/unknown versions without downgrade',
    () async {
      for (final payload in [
        null,
        {'cmd': 'capabilities', 'pairingApprovalVersion': 3},
        {'cmd': 'capabilities', 'pairingApprovalVersion': 2.0},
        {'cmd': 'pairinfo'},
      ]) {
        final ble = PairBle()..capabilities = payload;
        await expectLater(
          ble.negotiatePairing(),
          throwsA(isA<PairingV2Exception>()),
        );
        ble.dispose();
      }
      final ble = PairBle();
      expect(await ble.negotiatePairing(), 2);
      ble.capabilities = {'cmd': 'capabilities'};
      expect(await ble.negotiatePairing(), 2);
      expect(
        await ble.submitPairingCode('123456', 'test@example.com'),
        isNotNull,
      );
      expect(ble.commands.map((x) => x['cmd']), ['capabilities']);
      ble.dispose();
      final old = PairBle()
        ..capabilities = {'cmd': 'capabilities', 'iphoneHotspot': true};
      expect(await old.negotiatePairing(), 1);
      old.dispose();
    },
  );
  test(
    'signed BLE messages preserve offer and receipt, and reject stale echoes',
    () async {
      final ble = PairBle();
      await ble.negotiatePairing();
      final offer = PairingOffer.fromJson(offerData(), mac);
      final approval = await ble.approvePairing(offer, '123456');
      expect(ble.commands.last, {
        'cmd': 'pairapprove',
        ...offer.fields,
        'code': '123456',
      });
      final completion = PairingCompletion.fromJson(completionData(), offer);
      await ble.completePairing(
        offer,
        approval,
        completion,
        'test@example.com',
      );
      expect(ble.commands.last['completion'], completion.fields);
      expect(
        utf8.encode(jsonEncode(ble.commands.last)).length,
        lessThanOrEqualTo(512),
      );
      expect(ble.pairedOwner, 'test@example.com');
      ble.intercept = (_) async => {...approvalData(), 'challengeId': '2' * 32};
      await expectLater(
        ble.approvePairing(offer, '123456'),
        throwsA(isA<PairingV2Exception>()),
      );
      ble.dispose();
    },
  );
  test(
    'disconnect invalidates a pending approval and clears negotiation',
    () async {
      final ble = PairBle();
      await ble.negotiatePairing();
      final pending = Completer<Map<String, dynamic>?>();
      ble.intercept = (_) => pending.future;
      final call = ble.approvePairing(
        PairingOffer.fromJson(offerData(), mac),
        '123456',
      );
      final check = expectLater(call, throwsA(isA<PairingV2Exception>()));
      await ble.disconnect();
      pending.complete(approvalData());
      await check;
      expect(ble.pairingApprovalVersion, isNull);
      expect(ble.pairedOwner, isNull);
      ble.dispose();
    },
  );
  test(
    'cloud sends only V2 approval fields and rejects unsigned completion',
    () async {
      final requests = <http.Request>[];
      final cloud = CloudService(
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('challenge') ? offerData() : completionData(),
            ),
            200,
          );
        }),
      );
      final offer = await cloud.requestPairingOffer('token', mac);
      final approval = PairingApproval.fromJson(approvalData(), offer);
      await cloud.claimApprovedDevice('token', offer, approval);
      expect(
        requests.map((r) => r.headers['Authorization']),
        everyElement('Bearer token'),
      );
      expect(jsonDecode(requests.last.body), approval.claimBody(offer));
      expect(
        () => PairingCompletion.fromJson({
          'ok': true,
          'protocol': 2,
          'mac': mac,
        }, offer),
        throwsA(isA<PairingV2Exception>()),
      );
      cloud.dispose();
    },
  );
  for (final status in [400, 401, 403, 404, 409, 410, 413, 503]) {
    test(
      'V2 HTTP $status never falls back to legacy or retries automatically',
      () async {
        var calls = 0;
        final cloud = CloudService(
          client: MockClient((r) async {
            calls++;
            return http.Response(
              '{"error":"pairing_challenge_consumed"}',
              status,
            );
          }),
        );
        await expectLater(
          cloud.requestPairingOffer('token', mac),
          throwsA(isA<PairingV2Exception>()),
        );
        expect(calls, 1);
        cloud.dispose();
      },
    );
  }
  testWidgets(
    'lost claim response retries same approval; lost BLE completion retries only completion',
    (tester) async {
      final ble = PairBle()..failedCompletions = 1;
      final auth = PairAuth();
      final requests = <http.Request>[];
      final cloud = CloudService(
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('challenge')) {
            return http.Response(jsonEncode(offerData()), 200);
          }
          if (requests.where((r) => r.url.path.endsWith('claim')).length == 1) {
            throw http.ClientException('lost response');
          }
          return http.Response(jsonEncode(completionData()), 200);
        }),
      );
      await openPair(tester, ble, auth, cloud);
      await tester.pumpAndSettle();
      expect(auth.adds, 0);
      expect(find.textContaining('Could not reach CalcAI'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(auth.adds, 0);
      expect(find.textContaining('Could not confirm pairing'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(auth.adds, 1);
      expect(find.byType(PairDeviceScreen), findsNothing);
      expect(requests.where((r) => r.url.path.endsWith('challenge')).length, 1);
      final claims = requests
          .where((r) => r.url.path.endsWith('claim'))
          .toList();
      expect(claims.length, 2);
      expect(claims[0].body, claims[1].body);
      expect(ble.commands.where((r) => r['cmd'] == 'pairapprove').length, 1);
      expect(ble.commands.where((r) => r['cmd'] == 'paircomplete').length, 2);
      await tester.pumpWidget(const SizedBox());
      ble.dispose();
      auth.dispose();
      cloud.dispose();
    },
  );
  testWidgets('account change while issuing offer cannot approve or claim', (
    tester,
  ) async {
    final ble = PairBle();
    final auth = PairAuth();
    final pending = Completer<http.Response>();
    var calls = 0;
    final cloud = CloudService(
      client: MockClient((_) {
        calls++;
        return pending.future;
      }),
    );
    await openPair(tester, ble, auth, cloud);
    await auth.signOut();
    pending.complete(http.Response(jsonEncode(offerData()), 200));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(auth.adds, 0);
    expect(ble.commands.any((c) => c['cmd'] == 'pairapprove'), false);
    expect(
      find.textContaining('sign-in or Bluetooth connection changed'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
    auth.dispose();
    cloud.dispose();
  });

  for (final lostAt in ['cloud claim', 'BLE completion']) {
    testWidgets(
      '$lostAt lost: reconnect uses fresh approval; already-owned waits for acknowledgement',
      (tester) async {
        final ble = PairBle();
        final auth = PairAuth();
        final requests = <http.Request>[];
        final finalAck = Completer<Map<String, dynamic>?>();
        var attempt = 0;
        var serverOwned = false;
        Map<String, dynamic> currentOffer() => {
          ...offerData(),
          if (attempt == 2) 'challengeId': '2' * 32,
          if (attempt == 2) 'nonce': '3' * 64,
          if (attempt == 2) 'offerSignature': '4' * 64,
        };
        Map<String, dynamic> currentApproval() => {
          ...approvalData(),
          'challengeId': currentOffer()['challengeId'],
          if (attempt == 2) 'approvalNonce': '5' * 32,
          if (attempt == 2) 'approvalResponse': '6' * 64,
        };
        final recoveredCompletion = {
          ...completionData(),
          'already': true,
          'completion': {
            ...completionData()['completion'] as Map<String, dynamic>,
            'signature': '7' * 64,
          },
        };
        final cloud = CloudService(
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('challenge')) {
              attempt++;
              return http.Response(jsonEncode(currentOffer()), 200);
            }
            serverOwned = true;
            if (attempt == 1 && lostAt == 'cloud claim') {
              throw http.ClientException('Claim committed; response lost');
            }
            return http.Response(
              jsonEncode(attempt == 1 ? completionData() : recoveredCompletion),
              200,
            );
          }),
        );
        ble.intercept = (command) async => switch (command['cmd']) {
          'capabilities' => ble.capabilities,
          'pairapprove' => currentApproval(),
          // Simulate no verified local completion on the first connection.
          // The cloud owns it, so recovery must not require unpair/data deletion.
          'paircomplete' => attempt == 1 ? null : await finalAck.future,
          _ => throw StateError('Unexpected command ${command['cmd']}'),
        };
        await openPair(tester, ble, auth, cloud);
        await tester.pumpAndSettle();
        expect(serverOwned, true);
        expect(auth.adds, 0);
        expect(attempt, 1);
        final firstConnection = ble.connectionGeneration;
        await ble.disconnect();
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(requests.length, 2);
        expect(
          find.textContaining('sign-in or Bluetooth connection changed'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave setup'));
        await tester.pumpAndSettle();
        expect(find.byType(PairDeviceScreen), findsNothing);
        ble.connected = true;
        expect(ble.connectionGeneration, greaterThan(firstConnection));
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(requests.length, 2); // No automatic issuance on reconnect.
        await tester.enterText(find.byType(TextField), '654321');
        await tester.pump();

        expect(attempt, 2);
        expect(auth.adds, 0); // already:true is not device confirmation.
        expect(find.byType(PairDeviceScreen), findsOneWidget);
        final approvals = ble.commands
            .where((c) => c['cmd'] == 'pairapprove')
            .toList();
        expect(approvals.map((c) => c['code']), ['123456', '654321']);
        expect(approvals[1]['challengeId'], isNot(approvals[0]['challengeId']));
        expect(approvals[1]['nonce'], isNot(approvals[0]['nonce']));
        final claims = requests
            .where((r) => r.url.path.endsWith('claim'))
            .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
            .toList();
        expect(claims.length, 2);
        expect(claims.map((c) => c['protocol']), everyElement(2));
        expect(claims[1]['approvalNonce'], isNot(claims[0]['approvalNonce']));
        expect(
          claims[1]['approvalResponse'],
          isNot(claims[0]['approvalResponse']),
        );
        expect(requests.map((r) => r.url.path), [
          '/ai/pair/challenge',
          '/ai/pair/claim',
          '/ai/pair/challenge',
          '/ai/pair/claim',
        ]);
        expect(ble.commands.any((c) => c['cmd'] == 'paircode'), false);
        expect(
          ble.commands.last['completion'],
          recoveredCompletion['completion'],
        );
        expect(ble.commands.last['approvalNonce'], claims[1]['approvalNonce']);
        finalAck.complete({
          'ok': true,
          'cmd': 'paircomplete',
          'protocol': 2,
          'mac': mac,
          'challengeId': currentOffer()['challengeId'],
          'ownershipId': ownership,
        });
        await tester.pumpAndSettle();
        expect(auth.adds, 1);
        expect(find.byType(PairDeviceScreen), findsNothing);
        await tester.pumpWidget(const SizedBox());
        ble.dispose();
        auth.dispose();
        cloud.dispose();
      },
    );
  }

  testWidgets(
    'disconnect during cloud claim cannot complete or record ownership',
    (tester) async {
      final ble = PairBle();
      final auth = PairAuth();
      final pending = Completer<http.Response>();
      var claims = 0;
      final cloud = CloudService(
        client: MockClient((r) async {
          if (r.url.path.endsWith('challenge')) {
            return http.Response(jsonEncode(offerData()), 200);
          }
          claims++;
          return pending.future;
        }),
      );
      await openPair(tester, ble, auth, cloud);
      await tester.pump();
      expect(claims, 1);
      await ble.disconnect();
      pending.complete(http.Response(jsonEncode(completionData()), 200));
      await tester.pumpAndSettle();
      expect(auth.adds, 0);
      expect(ble.commands.any((c) => c['cmd'] == 'paircomplete'), false);
      expect(
        find.textContaining('sign-in or Bluetooth connection changed'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      ble.dispose();
      auth.dispose();
      cloud.dispose();
    },
  );

  testWidgets('wrong code keeps the offer; leaving drops the pending attempt', (
    tester,
  ) async {
    final ble = PairBle();
    final auth = PairAuth();
    ble.intercept = (cmd) async => cmd['cmd'] == 'capabilities'
        ? ble.capabilities
        : {'cmd': 'pairapprove', 'ok': false, 'error': 'bad_code'};
    var offers = 0;
    final paths = <String>[];
    final cloud = CloudService(
      client: MockClient((r) async {
        paths.add(r.url.path);
        offers++;
        return http.Response(jsonEncode(offerData()), 200);
      }),
    );
    await openPair(tester, ble, auth, cloud);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '654321');
    await tester.pumpAndSettle();
    expect(offers, 1);
    expect(paths, ['/ai/pair/challenge']);
    final approvals = ble.commands
        .where((c) => c['cmd'] == 'pairapprove')
        .toList();
    expect(approvals.map((c) => c['code']), ['123456', '654321']);
    expect(approvals[0]['challengeId'], approvals[1]['challengeId']);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave setup'));
    await tester.pumpAndSettle();
    expect(ble.connected, false);
    expect(ble.pairingApprovalVersion, isNull);
    expect(auth.adds, 0);
    expect(find.byType(PairDeviceScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
    auth.dispose();
    cloud.dispose();
  });

  testWidgets('invalid completion stops without ownership or legacy fallback', (
    tester,
  ) async {
    final ble = PairBle();
    final auth = PairAuth();
    final paths = <String>[];
    final cloud = CloudService(
      client: MockClient((r) async {
        paths.add(r.url.path);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('challenge')
                ? offerData()
                : {...completionData(), 'mac': '000000000000'},
          ),
          200,
        );
      }),
    );
    await openPair(tester, ble, auth, cloud);
    await tester.pumpAndSettle();
    expect(paths, ['/ai/pair/challenge', '/ai/pair/claim']);
    expect(auth.adds, 0);
    expect(ble.commands.any((c) => c['cmd'] == 'paircomplete'), false);
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
    auth.dispose();
    cloud.dispose();
  });

  testWidgets(
    'V2 success page never sends a legacy claim after disconnection',
    (tester) async {
      final ble = PairBle();
      final auth = PairAuth();
      await auth.init();
      await ble.disconnect();
      var requests = 0;
      final cloud = CloudService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BleService>.value(value: ble),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
          ],
          child: const MaterialApp(home: SuccessScreen(securePairing: true)),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home page'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(auth.adds, 0);
      expect(
        find.textContaining('Secure pairing was not completed'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      ble.dispose();
      auth.dispose();
      cloud.dispose();
    },
  );
}
