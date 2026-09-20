import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/services/usage_tracker.dart';
import 'package:calcai_app/widgets/daily_usage_card.dart';
import 'package:calcai_app/services/auth_service.dart';
import 'support/fake_auth_service.dart';

Map<String, dynamic> usage({
  double? percent = 80,
  String plan = 'free',
  bool unlimited = false,
  String status = 'ready',
  bool exhausted = false,
  String time = '2026-09-20T12:00:00Z',
  String reset = '2026-09-21T00:00:00Z',
  List<Map<String, dynamic>> models = const [],
}) => {
  'ok': true,
  'usageVersion': 2,
  'scope': 'account',
  'plan': plan,
  'serverTime': time,
  'period': {'resetsAt': reset},
  'status': status,
  'allowance': {
    'remainingPercent': percent,
    'unlimited': unlimited,
    'exhausted': exhausted,
  },
  'models': models,
};

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('account usage needs only Bearer auth, never a paired MAC', () async {
    final requests = <http.Request>[];
    final cloud = CloudService(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/usage/status')
                ? usage(plan: 'pro', percent: 34)
                : {'keys': {}},
          ),
          200,
        );
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.getUsage('session-a');
    final request = requests.singleWhere(
      (r) => r.url.path.endsWith('/usage/status'),
    );
    expect(request.url.toString(), 'https://ai.calcai.cc/ai/usage/status');
    expect(request.headers['Authorization'], 'Bearer session-a');
    expect(cloud.usageTracker.data!.remainingPercent, 34);
    expect(cloud.usageTracker.data!.unlimited, isFalse);
  });

  test(
    'late response cannot enter a new account or restore logged-out usage',
    () async {
      final pending = Completer<http.Response>();
      final cloud = CloudService(
        client: MockClient((r) async {
          if (!r.url.path.endsWith('/usage/status')) {
            return http.Response('{"keys":{}}', 200);
          }
          if (r.headers['Authorization'] == 'Bearer a') return pending.future;
          return http.Response(jsonEncode(usage(percent: 22)), 200);
        }),
      );
      addTearDown(cloud.dispose);
      final old = cloud.getUsage('a');
      await cloud.getUsage('b');
      pending.complete(http.Response(jsonEncode(usage(percent: 99)), 200));
      await old;
      expect(cloud.usageTracker.data!.remainingPercent, 22);
      cloud.reset();
      expect(cloud.usageTracker.data, isNull);
    },
  );

  test('temporary failure preserves the last good value as stale', () async {
    var fail = false;
    final tracker = UsageTracker(
      fetch: (_) async {
        if (fail) throw http.ClientException('offline');
        return usage(percent: 63);
      },
    )..bind('a');
    addTearDown(tracker.dispose);
    await tracker.refresh();
    fail = true;
    await tracker.refresh();
    expect(tracker.data!.remainingPercent, 63);
    expect(tracker.stale, isTrue);
    expect(tracker.failure, UsageFailure.offline);
  });

  testWidgets('polls every 15 seconds only while visible and syncing', (
    tester,
  ) async {
    var requests = 0;
    final tracker = UsageTracker(
      fetch: (_) async {
        requests++;
        return usage(status: 'syncing', percent: null);
      },
    )..bind('a');
    await tracker.refresh();
    await tester.pump(const Duration(seconds: 30));
    expect(requests, 1);
    tracker.setVisible(true);
    await tester.pump(const Duration(seconds: 14));
    expect(requests, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 2);
    tracker.setVisible(false);
    await tester.pump(const Duration(seconds: 30));
    expect(requests, 2);
    tracker.dispose();
  });

  testWidgets('reset follows server time even with a different device date', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var requests = 0;
    final tracker = UsageTracker(
      elapsed: () => elapsed,
      fetch: (_) async {
        requests++;
        return requests == 1
            ? usage(time: '2032-04-03T23:59:58Z', reset: '2032-04-04T00:00:00Z')
            : usage(
                time: '2032-04-04T00:00:00Z',
                reset: '2032-04-05T00:00:00Z',
                percent: 100,
              );
      },
    )..bind('a');
    await tracker.refresh();
    tracker.setVisible(true);
    expect(tracker.resetIn, const Duration(seconds: 2));
    elapsed += const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 2));
    expect(requests, 2);
    expect(tracker.data!.remainingPercent, 100);
    tracker.dispose();
  });

  testWidgets('503 Retry-After is respected without retrying a solve', (
    tester,
  ) async {
    var calls = 0;
    var elapsed = Duration.zero;
    final tracker = UsageTracker(
      elapsed: () => elapsed,
      fetch: (_) async {
        calls++;
        if (calls == 1) {
          throw const UsageRequestException(
            503,
            'usage_syncing',
            retryAfter: Duration(seconds: 30),
          );
        }
        return usage();
      },
    )..bind('a');
    await tracker.refresh();
    tracker.setVisible(true);
    elapsed += const Duration(seconds: 15);
    await tester.pump(const Duration(seconds: 15));
    expect(calls, 1);
    await tracker.refresh();
    expect(calls, 1);
    elapsed += const Duration(seconds: 15);
    await tester.pump(const Duration(seconds: 15));
    expect(calls, 2);
    tracker.dispose();
  });

  test('newly fetched solve history triggers a fresh usage GET', () async {
    var statusCalls = 0;
    final cloud = CloudService(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/usage/status')) {
          statusCalls++;
          return http.Response(jsonEncode(usage()), 200);
        }
        if (r.url.path.endsWith('/logs/recent')) {
          return http.Response(
            '{"items":[{"id":"new-solve","question":"2+2"}]}',
            200,
          );
        }
        return http.Response('{"keys":{}}', 200);
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.getUsage('a');
    await cloud.getHistory('a', 'ca1ca1000001');
    await Future<void>.delayed(Duration.zero);
    expect(statusCalls, 2);
  });

  test(
    'solve completion refreshes after an older status request finishes',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      final tracker = UsageTracker(
        fetch: (_) async {
          calls++;
          return calls == 1 ? pending.future : usage(percent: 70);
        },
      )..bind('a');
      final initial = tracker.refresh();
      final afterSolve = tracker.refreshAfterSolve();
      pending.complete(usage(percent: 80));
      await initial;
      await afterSolve;
      expect(calls, 2);
      expect(tracker.data!.remainingPercent, 70);
      tracker.dispose();
    },
  );

  test('401 clears private usage and 403 uses an access error', () async {
    final tracker = UsageTracker(fetch: (_) async => usage())..bind('a');
    addTearDown(tracker.dispose);
    await tracker.refresh();
    tracker.handleError(const UsageRequestException(401, 'unauth'));
    expect(tracker.data, isNull);
    expect(tracker.failure, UsageFailure.session);
    tracker.handleError(const UsageRequestException(403, 'device_not_owned'));
    expect(tracker.failure, UsageFailure.forbidden);
  });

  test(
    '429 exhausts allowance without inventing a reset or resubmitting',
    () async {
      var calls = 0;
      final tracker = UsageTracker(
        fetch: (_) async {
          calls++;
          return usage();
        },
      )..bind('a');
      await tracker.refresh();
      tracker.handleError(
        const UsageRequestException(429, 'usage_limit_reached'),
      );
      expect(tracker.exhausted, isTrue);
      expect(calls, 1);
      tracker.dispose();
    },
  );

  test('personal usage covers only its reported provider', () {
    final data = AccountUsage(
      usage(
        models: [
          {'provider': 'openai', 'billingSource': 'user'},
          {'provider': 'anthropic', 'billingSource': 'platform'},
        ],
      ),
    );
    expect(data.personalProviders, {'openai'});
  });

  testWidgets('resume and returning Home refresh; ready usage never polls', (
    tester,
  ) async {
    var calls = 0;
    final auth = FakeAuthService();
    await auth.init();
    final cloud = CloudService(
      auth: auth,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/usage/status')) {
          calls++;
          return http.Response(jsonEncode(usage()), 200);
        }
        return http.Response('{"keys":{}}', 200);
      }),
    );
    Widget app(bool active) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        home: Scaffold(body: DailyUsageCard(active: active)),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump();
    final initial = calls;
    await tester.pump(const Duration(seconds: 30));
    expect(calls, initial);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, initial);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, initial + 1);
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(calls, initial + 2);
    await auth.signOut();
    expect(cloud.usageTracker.data, isNull);
    await tester.pumpWidget(const SizedBox());
    cloud.dispose();
    auth.dispose();
  });

  testWidgets('offline is explicit and last good percentage is visibly stale', (
    tester,
  ) async {
    var fail = true;
    final tracker = UsageTracker(
      fetch: (_) async {
        if (fail) throw http.ClientException('offline');
        return usage(percent: 63);
      },
    )..bind('a');
    Widget app() => MaterialApp(
      home: Scaffold(
        body: UsageCardContent(
          tracker: tracker,
          personalProviders: const {},
          onRefresh: () {},
        ),
      ),
    );
    await tracker.refresh();
    await tester.pumpWidget(app());
    expect(find.text('Usage unavailable offline'), findsOneWidget);
    expect(find.textContaining('% left'), findsNothing);
    fail = false;
    await tracker.refresh();
    fail = true;
    await tracker.refresh();
    await tester.pumpWidget(app());
    expect(find.text('63% left'), findsOneWidget);
    expect(find.text('Out of date · Showing last known usage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
  });

  for (final entry in <String, Map<String, dynamic>>{
    'finite Pro': usage(plan: 'pro', percent: 34),
    'null': usage(percent: null),
    'syncing': usage(status: 'syncing', percent: 80),
    'unlimited': usage(plan: 'pro', unlimited: true, percent: null),
    'exhausted': usage(percent: 0, exhausted: true),
  }.entries) {
    testWidgets('card renders ${entry.key} without fabricated credits', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tracker = UsageTracker(fetch: (_) async => entry.value)..bind('a');
      await tracker.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.6),
                disableAnimations: true,
              ),
              child: SingleChildScrollView(
                child: UsageCardContent(
                  tracker: tracker,
                  personalProviders: const {'openai'},
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final expected = switch (entry.key) {
        'finite Pro' => '34% left',
        'unlimited' => 'Unlimited',
        'exhausted' => 'Daily allowance used',
        _ => 'Updating usage',
      };
      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Standard'), findsNothing);
      expect(
        find.textContaining('OpenAI usage is billed separately'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Other providers still use it.'),
        findsOneWidget,
      );
      if (entry.key == 'finite Pro') {
        expect(find.text('Unlimited'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      tracker.dispose();
    });
  }
}
