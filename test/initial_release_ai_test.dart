import 'dart:convert';
import 'package:calcai_app/models/ai_model.dart';
import 'package:calcai_app/models/initial_release_ai.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);

void main() {
  const mac = 'ca1ca1000001';
  const unavailable = {
    'available': false,
    'provider': 'google',
    'error': 'provider_unavailable',
    'reason': 'disabled_for_release',
    'action': 'choose_available_model',
  };

  test('first release retains13 advertised models and a supported default', () {
    expect(fallbackAiModels, hasLength(13));
    expect(
      fallbackAiModels.every((m) => InitialReleaseAi.allowsModel(m.id)),
      isTrue,
    );
    expect(fallbackAiModels.any((m) => m.provider == 'google'), isFalse);
    expect(InitialReleaseAi.defaultModel, 'gpt-5.6-luna');
  });

  test('an older mixed catalog cannot re-enable Google', () {
    final models = AiModel.parseCatalog({
      'schemaVersion': 1,
      'models': [
        {
          'id': 'gemini-future',
          'provider': 'google',
          'tier': 'free',
          'fastMode': true,
        },
        {
          'id': 'gpt-future',
          'provider': 'openai',
          'tier': 'free',
          'fastMode': false,
        },
      ],
    });
    expect(models.single.id, 'gpt-future');
  });

  test(
    'legacy non-Google custom aliases remain available and display accepted normalization',
    () async {
      final cloud = CloudService(
        client: MockClient(
          (_) async => _json({'model': 'gpt-5-nano', 'style': 'small'}),
        ),
      );
      addTearDown(cloud.dispose);
      expect(InitialReleaseAi.providerForModel('gpt5-nano'), 'openai');
      await cloud.setModel('session', mac, 'gpt5-nano', 'small');
      expect(cloud.currentModel, 'gpt-5-nano');
      expect(cloud.modelSaveRevision, 1);
      expect(cloud.modelError, isNull);
    },
  );

  test(
    'a Google-only server catalog retains the non-Gemini offline fallback',
    () async {
      final cloud = CloudService(
        client: MockClient(
          (_) async => _json({
            'schemaVersion': 1,
            'models': [
              {
                'id': 'gemini-future',
                'provider': 'google',
                'tier': 'free',
                'fastMode': true,
              },
            ],
          }),
        ),
      );
      addTearDown(cloud.dispose);
      await cloud.loadModelCatalog('session');
      expect(cloud.modelCatalog, fallbackAiModels);
      expect(cloud.modelProvider('gemini-future'), isNull);
      expect(cloud.modelFastModeProvider('gemini-future'), isNull);
    },
  );

  for (final availability in [null, unavailable]) {
    test(
      'saved Gemini stays stored but unavailable (${availability == null ? 'legacy' : 'current'} server)',
      () async {
        final requests = <http.Request>[];
        final stored = {
          'model': 'gemini-3.5-flash',
          'style': 'detailed',
          'effort': 'thorough',
          'maxTokens': 320,
          'fastMode': true,
          'fastModeCapability': {
            'supported': true,
            'available': true,
            'funding': 'personal_key',
          },
          if (availability != null) 'modelAvailability': availability,
        };
        final cloud = CloudService(
          client: MockClient((r) async {
            requests.add(r);
            return _json(stored);
          }),
        );
        addTearDown(cloud.dispose);
        expect(await cloud.getModel('session', mac), stored);
        expect(cloud.modelInfo, stored);
        expect(cloud.currentModel, isNull);
        expect(cloud.modelUnavailable, isTrue);
        expect(cloud.responseStyle, 'detailed');
        expect(cloud.thinkingEffort, 'thorough');
        expect(cloud.fastMode, isFalse);
        expect(cloud.currentModelFunding, isNull);
        expect(cloud.fastModeCapability, isNull);
        expect(cloud.modelError, contains('Choose an OpenAI or Anthropic'));
        expect(requests.single.method, 'GET');
      },
    );
  }

  test(
    'explicit Gemini, aliases and malformed custom IDs never leave the client',
    () async {
      final requests = <http.Request>[];
      final cloud = CloudService(
        client: MockClient((r) async {
          requests.add(r);
          return _json({'model': 'gpt-5.6-luna', 'style': 'small'});
        }),
      );
      addTearDown(cloud.dispose);
      await cloud.getModel('session', mac);
      final saved = Map.of(cloud.modelInfo!);
      for (final id in [
        'gemini-3.5-flash',
        'gemini-future',
        'Gemini-future',
        'google/gemini-future',
        ' google ',
        'gemini',
        'unknown-custom',
      ]) {
        await cloud.setModel('session', mac, id, 'detailed');
        expect(cloud.modelInfo, saved);
        expect(cloud.modelSaveRevision, 0);
      }
      expect(requests, hasLength(1));
    },
  );

  test(
    'only an explicit supported selection recovers a saved Gemini setting',
    () async {
      final requests = <http.Request>[];
      final cloud = CloudService(
        client: MockClient((r) async {
          requests.add(r);
          return r.method == 'GET'
              ? _json({
                  'model': 'gemini-old',
                  'style': 'detailed',
                  'effort': 'thorough',
                  'modelAvailability': unavailable,
                })
              : _json({
                  'model': 'gpt-5.6-luna',
                  'style': 'detailed',
                  'effort': 'thorough',
                  'fastMode': false,
                });
        }),
      );
      addTearDown(cloud.dispose);
      await cloud.getModel('session', mac);
      expect(requests, hasLength(1));
      await cloud.setModel('session', mac, 'gpt-5.6-luna', cloud.responseStyle);
      expect(jsonDecode(requests.last.body), {
        'mac': mac,
        'model': 'gpt-5.6-luna',
        'style': 'detailed',
      });
      expect(cloud.currentModel, 'gpt-5.6-luna');
      expect(cloud.modelUnavailable, isFalse);
      expect(cloud.thinkingEffort, 'thorough');
      expect(cloud.modelSaveRevision, 1);
    },
  );

  test(
    'provider_unavailable is actionable and never acknowledges a save',
    () async {
      final cloud = CloudService(
        client: MockClient(
          (_) async => _json({
            'ok': false,
            'error': 'provider_unavailable',
            'provider': 'google',
            'reason': 'disabled_for_release',
            'action': 'choose_available_model',
            'retryable': false,
          }, 409),
        ),
      );
      addTearDown(cloud.dispose);
      await cloud.getModel('session', mac);
      expect(cloud.modelUnavailable, isTrue);
      expect(cloud.currentModel, isNull);
      await cloud.setModel('session', mac, 'gpt-future', 'small');
      expect(cloud.modelSaveRevision, 0);
      expect(cloud.modelError, contains('Choose an OpenAI or Anthropic'));
    },
  );

  for (final actualModel in ['gemini-old', 'claude-sonnet-5-5']) {
    test(
      'preferences omit a stale model and preserve server selection ($actualModel)',
      () async {
        final posts = <Map<String, dynamic>>[];
        final cloud = CloudService(
          client: MockClient((r) async {
            if (r.method == 'POST') posts.add(jsonDecode(r.body));
            return _json({
              'model': r.method == 'GET' ? 'gemini-old' : actualModel,
              'style': posts.isEmpty ? 'small' : 'detailed',
              'effort': posts.length < 2 ? 'fast' : 'thorough',
              'maxTokens': 320,
              'fastMode': false,
              if (r.method == 'GET' || actualModel.startsWith('gemini-'))
                'modelAvailability': unavailable,
            });
          }),
        );
        addTearDown(cloud.dispose);
        await cloud.getModel('session', mac);
        await cloud.updateModelPreferences('session', mac, style: 'detailed');
        await cloud.updateModelPreferences('session', mac, effort: 'thorough');
        expect(posts, [
          {'mac': mac, 'style': 'detailed'},
          {'mac': mac, 'effort': 'thorough'},
        ]);
        expect(cloud.modelInfo?['model'], actualModel);
        expect(cloud.modelInfo?['maxTokens'], 320);
        expect(cloud.responseStyle, 'detailed');
        expect(cloud.thinkingEffort, 'thorough');
        expect(cloud.modelUnavailable, actualModel.startsWith('gemini-'));
        expect(
          cloud.currentModel,
          actualModel.startsWith('gemini-') ? null : actualModel,
        );
      },
    );
  }

  test(
    'a disallowed or unconfirmed successful response cannot become the active model',
    () async {
      for (final body in [
        <String, Object?>{},
        {'model': 'gemini-future'},
        {'model': 'claude-future'},
      ]) {
        final cloud = CloudService(
          client: MockClient((_) async => _json(body)),
        );
        await cloud.setModel('session', mac, 'gpt-future', 'small');
        expect(cloud.currentModel, isNull);
        expect(cloud.modelSaveRevision, 0);
        expect(cloud.modelError, isNotNull);
        cloud.dispose();
      }
    },
  );

  test(
    'Google BYOK save/enable is blocked before any verification request',
    () async {
      var calls = 0;
      final cloud = CloudService(
        client: MockClient((_) async {
          calls++;
          return _json({'ok': true});
        }),
      );
      addTearDown(cloud.dispose);
      expect(
        await cloud.saveApiKey('session', 'Google', 'fixture-key'),
        isFalse,
      );
      expect(await cloud.toggleApiKey('session', 'Google', true), isFalse);
      expect(calls, 0);
      expect(cloud.apiKeysError, contains('unavailable'));
    },
  );

  test(
    'legacy Google metadata permits safe disable/removal without enabling use',
    () async {
      final actions = <String>[];
      final cloud = CloudService(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            actions.add(r.url.path);
            return _json({'ok': true});
          }
          return _json({
            'ok': true,
            'keys': {
              'google': {
                'active': true,
                'enabled': true,
                'storedEnabled': true,
                'available': false,
                'last4': '1234',
              },
            },
          });
        }),
      );
      addTearDown(cloud.dispose);
      await cloud.listApiKeys('session');
      expect(cloud.hasApiKey('google'), isTrue);
      expect(cloud.apiKeyEnabled('google'), isFalse);
      expect(cloud.providerFunding('google'), isNull);
      expect(await cloud.toggleApiKey('session', 'google', false), isTrue);
      expect(await cloud.deleteApiKey('session', 'google'), isTrue);
      expect(actions, ['/ai/apikey/toggle', '/ai/apikey/delete']);
    },
  );
}
