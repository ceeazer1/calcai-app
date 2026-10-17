// Opt-in, read-only integration check. Never included in the ordinary test suite.
// CALCAI_TEST_SESSION_FILE points to an existing task-scoped JSON {token, mac}.
// The file and its contents must remain outside source control.
import 'dart:convert';
import 'dart:io';

import 'package:calcai_app/models/ai_funding.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/services/resilient_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _NativeIo extends HttpOverrides {}

class _ReadOnlyClient extends http.BaseClient {
  final http.Client inner = createResilientClient();
  final replies = <String, Map<String, dynamic>>{};
  final cacheControls = <String, String>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    const paths = {'/ai/model/get', '/ai/apikey/list'};
    if (request.method != 'GET' ||
        request.url.scheme != 'https' ||
        request.url.host != 'ai.calcai.cc' ||
        !paths.contains(request.url.path)) {
      throw StateError('Only the two approved read endpoints are allowed.');
    }
    final response = await http.Response.fromStream(await inner.send(request));
    expect(response.statusCode, 200, reason: 'Authenticated GET must succeed.');
    expect(response.headers['cache-control'], contains('no-store'));
    expect(response.headers['cache-control'], contains('private'));
    replies[request.url.path] =
        jsonDecode(response.body) as Map<String, dynamic>;
    cacheControls[request.url.path] = response.headers['cache-control']!;
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'live funding response parses safely without changing account or model',
    () async {
      final path = Platform.environment['CALCAI_TEST_SESSION_FILE'];
      if (path == null || path.isEmpty) {
        fail(
          'An existing task-scoped session file is required; no session is created.',
        );
      }
      final session = jsonDecode(await File(path).readAsString()) as Map;
      final token = session['token'];
      final mac = session['mac'];
      if (token is! String ||
          token.isEmpty ||
          mac is! String ||
          !RegExp(r'^[a-fA-F0-9]{12}$').hasMatch(mac)) {
        fail('Session file must contain a token and calculator identifier.');
      }
      HttpOverrides.global = _NativeIo();
      final client = _ReadOnlyClient();
      final cloud = CloudService(client: client);
      addTearDown(cloud.dispose);
      await cloud.refreshAiSettings(token, mac);
      expect(client.replies.keys.toSet(), {'/ai/model/get', '/ai/apikey/list'});
      expect(cloud.modelError, null);
      expect(cloud.apiKeysError, null);
      final raw = client.replies['/ai/model/get']!;
      final capability = FastModeCapability.parse(raw['fastModeCapability']);
      expect(capability, isNotNull);
      expect(cloud.fastMode, raw['fastMode']);
      expect(cloud.fastModeFunding, AiFunding.parse(raw['fastModeFunding']));
      expect(cloud.fastModeCapability?.available, capability!.available);
      expect(cloud.currentModelFunding, capability.funding);
      final provider = cloud.modelProvider(cloud.currentModel!);
      expect(provider, isNotNull);
      expect(cloud.providerFunding(provider!), capability.funding);
      // Emit only the contract and non-sensitive UI results, never auth or keys.
      stdout.writeln(
        jsonEncode({
          'model': cloud.currentModel,
          'fastMode': cloud.fastMode,
          'fastModeFunding': cloud.fastModeFunding?.apiValue,
          'capability': raw['fastModeCapability'],
          'cacheControl': client.cacheControls,
          'currentPayer': cloud.currentModelFunding?.apiValue,
          'providerPayers': {
            for (final provider in ['openai', 'google', 'anthropic'])
              provider: cloud.providerFunding(provider)?.apiValue,
          },
          'requestCount': client.replies.length,
          'mutations': 0,
        }),
      );
    },
  );
}
