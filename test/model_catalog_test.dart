import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcai_app/models/ai_model.dart';
import 'package:calcai_app/services/cloud_service.dart';

void main() {
  final catalog = {
    'schemaVersion': 1,
    'models': [
      {
        'id': 'claude-test-future',
        'provider': 'anthropic',
        'tier': 'free',
        'fastMode': true,
      },
    ],
  };
  test(
    'catalog accepts a future model without an app update and preserves server metadata',
    () async {
      var calls = 0;
      final cloud = CloudService(
        client: MockClient((r) async {
          calls++;
          expect(r.url.path, '/ai/models/catalog');
          return http.Response(jsonEncode(catalog), 200);
        }),
      );
      await cloud.loadModelCatalog('token');
      expect(cloud.modelCatalog.single.id, 'claude-test-future');
      expect(cloud.modelCatalog.single.free, true);
      expect(cloud.modelFastModeProvider('claude-test-future'), 'anthropic');
      await cloud.loadModelCatalog('token');
      expect(calls, 1);
      cloud.reset();
      expect(cloud.modelCatalog, fallbackAiModels);
      cloud.dispose();
    },
  );
  test('failed or malformed catalog retains usable fallback', () async {
    final cloud = CloudService(
      client: MockClient(
        (_) async => http.Response('{"schemaVersion":2}', 200),
      ),
    );
    await cloud.loadModelCatalog('token');
    expect(cloud.modelCatalog, fallbackAiModels);
    expect(cloud.error, isNull);
    cloud.dispose();
    expect(
      () => AiModel.parseCatalog({'schemaVersion': 1, 'models': []}),
      throwsFormatException,
    );
  });
  test('catalog completing after logout cannot repopulate state', () async {
    final pending = Completer<http.Response>();
    final cloud = CloudService(client: MockClient((_) => pending.future));
    final load = cloud.loadModelCatalog('token');
    await Future<void>.delayed(Duration.zero);
    cloud.reset();
    pending.complete(http.Response(jsonEncode(catalog), 200));
    await load;
    expect(cloud.modelCatalog, fallbackAiModels);
    cloud.dispose();
  });
}
