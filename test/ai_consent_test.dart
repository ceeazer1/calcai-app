import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:calcai_app/screens/ai_consent_screen.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/theme/app_theme.dart';
import 'package:calcai_app/utils/resilient_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_cloud_service.dart';

class _ConsentCloud extends FakeCloudService {
  bool reviewed = false;
  bool allowed = false;
  bool failSave = false;
  bool failLoad = false;
  final choices = <bool>[];

  @override
  Future<Map<String, dynamic>> readAiConsent(String token) async {
    if (failLoad) throw Exception('offline');
    return {
      'ok': true,
      'version': CloudService.aiConsentVersion,
      'reviewed': reviewed,
      'allowed': allowed,
    };
  }

  @override
  Future<void> saveAiConsent(String token, bool allowed) async {
    choices.add(allowed);
    if (failSave) throw Exception('offline');
    this.allowed = allowed;
    reviewed = true;
  }
}

Future<void> _mount(WidgetTester tester, CloudService cloud) async {
  final auth = FakeAuthService();
  await auth.init();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const AiConsentGate(child: Scaffold(body: Text('Home'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a consent server error stays blocked and identifies the server failure',
    (tester) async {
      final cloud = CloudService(
        client: MockClient(
          (_) async => http.Response('{"error":"server"}', 500),
        ),
      );
      addTearDown(cloud.dispose);
      await _mount(tester, cloud);
      expect(find.textContaining('server error 500'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('ai-consent-popup')), findsOneWidget);
    },
  );

  test('an unreviewed save response never confirms permission', () async {
    final cloud = CloudService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'version': CloudService.aiConsentVersion,
            'reviewed': false,
            'allowed': true,
          }),
          200,
        ),
      ),
    );
    addTearDown(cloud.dispose);
    await expectLater(
      cloud.saveAiConsent('a', true),
      throwsA(isA<AiConsentException>()),
    );
  });

  testWidgets('failed consent load disables choices until a valid retry', (
    tester,
  ) async {
    final cloud = _ConsentCloud()..failLoad = true;
    await _mount(tester, cloud);
    expect(
      find.text('Could not load your choice. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(cloud.choices, isEmpty);
    cloud.failLoad = false;
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(cloud.choices, isEmpty);
  });

  testWidgets('new account loads its real consent contract without an error', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final cloud = CloudService(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'ok': true,
            'version': CloudService.aiConsentVersion,
            'reviewed': request.method == 'PUT',
            'allowed': request.method == 'PUT',
          }),
          200,
        );
      }),
    );
    addTearDown(cloud.dispose);
    await _mount(tester, cloud);
    expect(find.textContaining('Could not load'), findsNothing);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/ai/user/ai-consent');
    expect(requests.single.headers['Authorization'], 'Bearer test-token');
    await tester.ensureVisible(find.text('Allow AI sharing'));
    await tester.tap(find.text('Allow AI sharing'));
    await tester.pumpAndSettle();
    expect(requests.last.method, 'PUT');
    expect(jsonDecode(requests.last.body), {
      'version': CloudService.aiConsentVersion,
      'allowed': true,
    });
    expect(find.byKey(const ValueKey('ai-consent-popup')), findsNothing);
  });

  test(
    'incomplete or unconfirmed consent cannot count as a loaded choice',
    () async {
      for (final body in [
        {
          'version': CloudService.aiConsentVersion,
          'reviewed': true,
          'allowed': true,
        },
        {
          'ok': false,
          'version': CloudService.aiConsentVersion,
          'reviewed': true,
          'allowed': true,
        },
        {
          'ok': true,
          'version': CloudService.aiConsentVersion,
          'reviewed': true,
        },
        {
          'ok': true,
          'version': 'future-version',
          'reviewed': true,
          'allowed': true,
        },
      ]) {
        final cloud = CloudService(
          client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
        );
        await expectLater(
          cloud.readAiConsent('a'),
          throwsA(isA<AiConsentException>()),
        );
        cloud.dispose();
      }
    },
  );

  test(
    'missing consent endpoint reports the server mismatch, not a false save',
    () async {
      final cloud = CloudService(
        client: MockClient((_) async => http.Response('not found', 404)),
      );
      addTearDown(cloud.dispose);
      for (final choice in [true, false]) {
        await expectLater(
          cloud.saveAiConsent('test-token', choice),
          throwsA(
            isA<AiConsentException>().having(
              (e) => e.message,
              'message',
              contains('server yet'),
            ),
          ),
        );
      }
    },
  );

  for (final allowed in [false, true]) {
    testWidgets('explicit choice $allowed is saved before Home is unlocked', (
      tester,
    ) async {
      final cloud = _ConsentCloud();
      await _mount(tester, cloud);
      expect(cloud.choices, isEmpty);
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-consent-popup')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(
                    of: find.text('Home'),
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        isTrue,
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-consent-popup')), findsOneWidget);
      expect(
        find.textContaining('OpenAI, Google (Gemini), or Anthropic'),
        findsOneWidget,
      );
      final button = find.text(
        allowed ? 'Allow AI sharing' : 'Continue with AI off',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      if (!allowed) {
        expect(cloud.choices, isEmpty);
        expect(find.text('AI features will be off'), findsOneWidget);
        await tester.tap(find.text('Keep AI off'));
        await tester.pumpAndSettle();
      }
      expect(cloud.choices, [allowed]);
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-consent-popup')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('restored refusal allows non-AI setup without asking again', (
    tester,
  ) async {
    final cloud = _ConsentCloud()..reviewed = true;
    await _mount(tester, cloud);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-consent-popup')), findsNothing);
    expect(cloud.choices, isEmpty);
    expect(cloud.allowed, false);
  });

  testWidgets(
    'failed save stays on consent and retry requires a successful save',
    (tester) async {
      final cloud = _ConsentCloud()..failSave = true;
      await _mount(tester, cloud);
      final button = find.text('Allow AI sharing');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-consent-popup')), findsOneWidget);
      expect(
        find.text('Your choice was not saved. Please try again.'),
        findsOneWidget,
      );
      cloud.failSave = false;
      final retry = find.text('Retry');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-consent-popup')), findsNothing);
    },
  );

  testWidgets('Settings can withdraw previously granted AI consent', (
    tester,
  ) async {
    final cloud = _ConsentCloud()..allowed = true;
    await _mount(tester, cloud);
    final context = tester.element(find.byType(AiConsentGate));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AiConsentScreen()));
    await tester.pumpAndSettle();
    final button = find.text('Turn off AI sharing');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep AI off'));
    await tester.pumpAndSettle();
    expect(cloud.choices, [false]);
    expect(cloud.allowed, false);
  });

  test(
    'private photo credentials stay scoped to the CalcAI image endpoint',
    () {
      expect(
        privateImageHeaders('https://ai.calcai.cc/ai/image/view/abc', 'token'),
        {'Authorization': 'Bearer token'},
      );
      for (final url in [
        'http://ai.calcai.cc/ai/image/view/abc',
        'https://ai.calcai.cc.evil.test/ai/image/view/abc',
        'https://ai.calcai.cc/ai/ask',
        'https://user@ai.calcai.cc/ai/image/view/abc',
        'https://ai.calcai.cc:8443/ai/image/view/abc',
      ]) {
        expect(privateImageHeaders(url, 'token'), isEmpty);
      }
      expect(
        privateImageHeaders('https://ai.calcai.cc/ai/image/view/abc', null),
        isEmpty,
      );
      expect(
        const ResilientNetworkImage('url', token: 'a'),
        isNot(const ResilientNetworkImage('url', token: 'b')),
      );
    },
  );
}
