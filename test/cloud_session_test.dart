import 'dart:async';

import 'package:calcai_app/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const keys = '{"ok":true,"keys":{"openai":{"active":true,"last4":"1234"}}}';

  test('sign-out clears provider key metadata', () async {
    final cloud = CloudService(
      client: MockClient((_) async => http.Response(keys, 200)),
    );
    addTearDown(cloud.dispose);
    await cloud.listApiKeys('account-a');
    expect(cloud.hasApiKey('openai'), isTrue);
    cloud.reset();
    expect(cloud.apiKeys, isEmpty);
    expect(cloud.apiKeyLast4('openai'), isNull);
  });

  test('a delayed key listing cannot restore a signed-out account', () async {
    final response = Completer<http.Response>();
    final cloud = CloudService(client: MockClient((_) => response.future));
    addTearDown(cloud.dispose);
    final pending = cloud.listApiKeys('account-a');
    cloud.reset();
    response.complete(http.Response(keys, 200));
    expect(await pending, isEmpty);
    expect(cloud.apiKeys, isEmpty);
  });

  test('a delayed key save cannot enter the next account', () async {
    final response = Completer<http.Response>();
    final cloud = CloudService(client: MockClient((_) => response.future));
    addTearDown(cloud.dispose);
    final pending = cloud.saveApiKey('account-a', 'openai', 'test-key');
    cloud.reset();
    response.complete(http.Response('{"ok":true,"last4":"1234"}', 200));
    expect(await pending, isFalse);
    expect(cloud.apiKeys, isEmpty);
  });

  test(
    'a delayed history response is discarded on account switching',
    () async {
      final response = Completer<http.Response>();
      final cloud = CloudService(client: MockClient((_) => response.future));
      addTearDown(cloud.dispose);
      final pending = cloud.getHistory('account-a', 'ca1ca1000001');
      cloud.reset();
      response.complete(
        http.Response('[{"question":"Private question"}]', 200),
      );
      await pending;
      expect(cloud.history, isEmpty);
    },
  );

  test(
    'disposal while a cloud request is pending does not notify a dead provider',
    () async {
      final response = Completer<http.Response>();
      final cloud = CloudService(client: MockClient((_) => response.future));
      final pending = cloud.getHistory('account-a', 'ca1ca1000001');
      cloud.dispose();
      response.complete(http.Response('[]', 200));
      await pending;
    },
  );
}
