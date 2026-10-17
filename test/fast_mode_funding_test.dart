import 'dart:async';
import 'dart:convert';

import 'package:calcai_app/models/ai_funding.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const model = 'gpt-6.1-sol';
const mac = 'ca1ca1000001';

Map<String, Object?> configuration({
  String selected = model,
  String payer = 'allowance',
  bool enabled = false,
  String? storedFunding,
  bool available = true,
}) => {
  'model': selected,
  'style': 'small',
  'effort': 'fast',
  'fastMode': enabled,
  'fastModeRequested': storedFunding != null,
  'fastModeFunding': storedFunding,
  'fastModeCapability': {
    'supported': true,
    'available': available,
    'funding': payer,
    'reason': available ? null : 'platform_fast_unavailable',
  },
};

http.Response jsonResponse(Object value, [int code = 200]) =>
    http.Response(jsonEncode(value), code);

void main() {
  test('allowance Fast sends explicit scope without a personal key', () async {
    final requests = <http.Request>[];
    final cloud = CloudService(
      client: MockClient((r) async {
        requests.add(r);
        expect(r.headers['Authorization'], 'Bearer session');
        return jsonResponse(
          configuration(
            enabled: r.method == 'POST',
            storedFunding: r.method == 'POST' ? 'allowance' : null,
          ),
        );
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.getModel('session', mac);
    expect(cloud.hasApiKey('openai'), false);
    expect(cloud.fastModeCapability?.funding, AiFunding.allowance);
    await cloud.setModel(
      'session',
      mac,
      model,
      'small',
      fastMode: true,
      fastModeFunding: 'allowance',
    );
    expect(jsonDecode(requests.last.body)['fastModeFunding'], 'allowance');
    expect(cloud.fastMode, true);
    expect(cloud.error, null);
  });

  test(
    'missing or malformed capability never grants allowance access',
    () async {
      for (final cap in [
        null,
        {'supported': true, 'available': true, 'funding': null},
        {'supported': true, 'available': 'true', 'funding': 'allowance'},
        {'supported': false, 'available': true, 'funding': 'allowance'},
        {'supported': true, 'available': true, 'funding': 'unknown'},
      ]) {
        var posts = 0;
        final data = configuration();
        if (cap == null) {
          data.remove('fastModeCapability');
        } else {
          data['fastModeCapability'] = cap;
        }
        final cloud = CloudService(
          client: MockClient((r) async {
            if (r.method == 'POST') posts++;
            return jsonResponse(data);
          }),
        );
        await cloud.getModel('session', mac);
        await cloud.setModel(
          'session',
          mac,
          model,
          'small',
          fastMode: true,
          fastModeFunding: 'allowance',
        );
        expect(cloud.fastModeCapability, null);
        expect(posts, 0);
        expect(cloud.fastMode, false);
        cloud.dispose();
      }
    },
  );

  test(
    'unsupported/unavailable capabilities retain payer but cannot enable',
    () async {
      for (final supported in [true, false]) {
        final data = configuration(available: false);
        (data['fastModeCapability'] as Map)['supported'] = supported;
        var posts = 0;
        final cloud = CloudService(
          client: MockClient((r) async {
            if (r.method == 'POST') posts++;
            return jsonResponse(data);
          }),
        );
        await cloud.getModel('session', mac);
        expect(cloud.currentModelFunding, AiFunding.allowance);
        await cloud.setModel(
          'session',
          mac,
          model,
          'small',
          fastMode: true,
          fastModeFunding: 'allowance',
        );
        expect(posts, 0);
        cloud.dispose();
      }
    },
  );

  test(
    'legacy server cannot acknowledge allowance funding by ignoring scope',
    () async {
      final cloud = CloudService(
        client: MockClient(
          (r) async => jsonResponse(
            r.method == 'GET'
                ? configuration()
                : {'model': model, 'fastMode': true},
          ),
        ),
      );
      addTearDown(cloud.dispose);
      await cloud.getModel('session', mac);
      await cloud.setModel(
        'session',
        mac,
        model,
        'small',
        fastMode: true,
        fastModeFunding: 'allowance',
      );
      expect(cloud.fastMode, false);
      expect(cloud.fastModeCapability, null);
      expect(cloud.error, contains('could not confirm'));
    },
  );

  test('legacy personal-key Fast is still opt-in and scoped', () async {
    Map<String, dynamic>? sent;
    final cloud = CloudService(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/list')) {
          return jsonResponse({
            'ok': true,
            'keys': {
              'openai': {'active': true, 'enabled': true, 'last4': '1234'},
            },
          });
        }
        if (r.method == 'POST') sent = jsonDecode(r.body);
        return jsonResponse({'model': model, 'fastMode': r.method == 'POST'});
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.listApiKeys('session');
    await cloud.getModel('session', mac);
    expect(cloud.fastModeCapability?.funding, AiFunding.personalKey);
    await cloud.setModel(
      'session',
      mac,
      model,
      'small',
      fastMode: true,
      fastModeFunding: 'personal_key',
    );
    expect(sent?['fastModeFunding'], 'personal_key');
    expect(cloud.fastMode, true);
  });

  test('model/style changes never submit a new paid-mode consent', () async {
    final sent = <Map<String, dynamic>>[];
    final cloud = CloudService(
      client: MockClient((r) async {
        if (r.method == 'GET') return jsonResponse(configuration());
        sent.add(jsonDecode(r.body));
        // Missing fresh capability must not inherit the old model's access.
        return jsonResponse({'model': 'gemini-3.5-flash', 'fastMode': false});
      }),
    );
    addTearDown(cloud.dispose);
    await cloud.getModel('session', mac);
    await cloud.setModel('session', mac, 'gemini-3.5-flash', 'small');
    expect(sent.single.containsKey('fastModeFunding'), false);
    expect(sent.single.containsKey('fastMode'), false);
    expect(cloud.fastModeCapability, null);
    expect(cloud.fastMode, false);
  });

  test('late model read cannot overwrite a completed model change', () async {
    final pending = Completer<http.Response>();
    final cloud = CloudService(
      client: MockClient(
        (r) async => r.method == 'GET'
            ? pending.future
            : jsonResponse(configuration(selected: 'claude-opus-5')),
      ),
    );
    addTearDown(cloud.dispose);
    final read = cloud.getModel('session', mac);
    await cloud.setModel('session', mac, 'claude-opus-5', 'small');
    pending.complete(jsonResponse(configuration()));
    await read;
    expect(cloud.currentModel, 'claude-opus-5');
  });

  test(
    'payer change rejects Fast and requires fresh explicit consent',
    () async {
      var payer = 'personal_key';
      final sent = <Map<String, dynamic>>[];
      final cloud = CloudService(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/toggle')) {
            payer = 'allowance';
            return jsonResponse({'ok': true, 'enabled': false});
          }
          if (r.url.path.endsWith('/list')) {
            return jsonResponse({
              'ok': true,
              'keys': {
                'openai': {
                  'active': true,
                  'enabled': payer == 'personal_key',
                  'last4': '1234',
                },
              },
            });
          }
          if (r.method == 'POST') sent.add(jsonDecode(r.body));
          return jsonResponse(
            configuration(
              payer: payer,
              enabled: payer == 'personal_key',
              storedFunding: 'personal_key',
            ),
          );
        }),
      );
      addTearDown(cloud.dispose);
      await cloud.listApiKeys('session');
      await cloud.getModel('session', mac);
      expect(cloud.fastMode, true);
      await cloud.toggleApiKey('session', 'openai', false);
      expect(cloud.fastMode, false);
      expect(cloud.fastModeFunding, AiFunding.personalKey);
      expect(cloud.fastModeCapability?.funding, AiFunding.allowance);
      expect(cloud.providerFunding('openai'), AiFunding.allowance);
      expect(sent, isEmpty); // No auto-enable POST after the payer changes.
    },
  );

  test(
    'funding conflict does not silently retry with a different payer',
    () async {
      var posts = 0;
      final cloud = CloudService(
        client: MockClient((r) async {
          if (r.method == 'GET') return jsonResponse(configuration());
          posts++;
          return jsonResponse({'error': 'fast_mode_funding_changed'}, 409);
        }),
      );
      addTearDown(cloud.dispose);
      await cloud.getModel('session', mac);
      await cloud.setModel(
        'session',
        mac,
        model,
        'small',
        fastMode: true,
        fastModeFunding: 'allowance',
      );
      expect(posts, 1);
      expect(cloud.fastMode, false);
      expect(cloud.fastModeCapability, null);
      expect(cloud.error, contains('Billing changed'));
    },
  );

  test(
    'billing labels distinguish enabled, disabled and missing provider keys',
    () async {
      final cloud = CloudService(
        client: MockClient(
          (_) async => jsonResponse({
            'ok': true,
            'keys': {
              'openai': {'active': true, 'enabled': true, 'last4': '1234'},
              'google': {'active': true, 'enabled': false, 'last4': '5678'},
            },
          }),
        ),
      );
      addTearDown(cloud.dispose);
      expect(cloud.providerFunding('openai'), null);
      await cloud.listApiKeys('session');
      expect(
        cloud.providerFundingLabel('OpenAI'),
        'Using your OpenAI key ••••1234',
      );
      expect(
        cloud.providerFundingDetail('OpenAI'),
        contains('does not use your CalcAI allowance'),
      );
      expect(cloud.providerFundingLabel('Google'), 'Using CalcAI allowance');
      expect(cloud.providerFundingLabel('Anthropic'), 'Using CalcAI allowance');
      expect(cloud.providerFundingDetail('Google'), null);
    },
  );

  test('key metadata errors never fabricate allowance or leak a key', () async {
    var fail = false;
    final cloud = CloudService(
      client: MockClient(
        (_) async => fail
            ? jsonResponse({
                'ok': false,
                'error': 'provider_key_unavailable',
              }, 503)
            : jsonResponse({
                'ok': true,
                'keys': {
                  'openai': {
                    'active': true,
                    'enabled': true,
                    'last4': 'full-secret-must-not-be-rendered',
                    'key': 'another-secret',
                  },
                },
              }),
      ),
    );
    addTearDown(cloud.dispose);
    await cloud.listApiKeys('session');
    expect(cloud.apiKeyLast4('openai'), null);
    expect(cloud.apiKeys.toString(), isNot(contains('secret')));
    fail = true;
    await cloud.listApiKeys('session');
    expect(cloud.providerFunding('openai'), null);
    expect(cloud.providerFundingLabel('google'), 'Could not confirm billing');
  });

  test('failed key toggle does not optimistically show allowance', () async {
    final pending = Completer<http.Response>();
    final cloud = CloudService(
      client: MockClient(
        (r) async => r.method == 'POST'
            ? pending.future
            : jsonResponse({
                'ok': true,
                'keys': {
                  'openai': {'active': true, 'enabled': true, 'last4': '1234'},
                },
              }),
      ),
    );
    addTearDown(cloud.dispose);
    await cloud.listApiKeys('session');
    final change = cloud.toggleApiKey('session', 'openai', false);
    expect(cloud.providerFunding('openai'), null);
    expect(cloud.apiKeyEnabled('openai'), true);
    pending.complete(jsonResponse({'error': 'server'}, 503));
    expect(await change, false);
    expect(cloud.providerFunding('openai'), null);
    expect(cloud.apiKeyEnabled('openai'), true);
  });

  test('sign-out fences chained billing refresh requests', () async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final cloud = CloudService(
      client: MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
    addTearDown(cloud.dispose);
    final refresh = cloud.refreshAiSettings('old-session', mac);
    cloud.reset();
    pending.complete(jsonResponse({'ok': true, 'keys': {}}));
    await refresh;
    expect(requests, 1);
    expect(cloud.currentModelFunding, null);
    expect(cloud.fastModeCapability, null);
  });
}
