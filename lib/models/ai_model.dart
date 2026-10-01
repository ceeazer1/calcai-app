/// Public model metadata served by CalcAI, never provider credentials/prices.
class AiModel {
  const AiModel(
    this.id,
    this.provider, {
    this.free = false,
    this.fastMode = false,
  });
  final String id, provider;
  final bool free, fastMode;

  static List<AiModel> parseCatalog(dynamic data) {
    if (data is! Map || data['schemaVersion'] != 1 || data['models'] is! List) {
      throw const FormatException('Unsupported model catalog');
    }
    final result = <AiModel>[];
    final seen = <String>{};
    for (final item in data['models'] as List) {
      if (item is! Map) throw const FormatException('Invalid model');
      final id = item['id'], provider = item['provider'];
      const prefixes = {
        'openai': 'gpt-',
        'google': 'gemini-',
        'anthropic': 'claude-',
      };
      if (id is! String ||
          provider is! String ||
          !prefixes.containsKey(provider) ||
          !id.startsWith(prefixes[provider]!) ||
          !RegExp(r'^[a-z0-9][a-z0-9._-]{1,119}$').hasMatch(id) ||
          !['free', 'pro'].contains(item['tier']) ||
          item['fastMode'] is! bool ||
          !seen.add(id)) {
        throw const FormatException('Invalid model metadata');
      }
      result.add(
        AiModel(
          id,
          provider,
          free: item['tier'] == 'free',
          fastMode: item['fastMode'],
        ),
      );
    }
    if (result.isEmpty || result.length > 100) {
      throw const FormatException('Invalid model count');
    }
    return List.unmodifiable(result);
  }
}

// Offline/older-server fallback. A successful catalog response replaces it.
const fallbackAiModels = <AiModel>[
  AiModel('gpt-6-astra', 'openai', fastMode: true),
  AiModel('gpt-6.1-sol', 'openai', fastMode: true),
  AiModel('gpt-6-luna', 'openai', free: true, fastMode: true),
  AiModel('gpt-5.6-sol', 'openai', fastMode: true),
  AiModel('gpt-5.6-terra', 'openai', fastMode: true),
  AiModel('gpt-5.6-luna', 'openai', free: true, fastMode: true),
  AiModel('gemini-3.8-flash', 'google'),
  AiModel('gemini-3.7-flash', 'google'),
  AiModel('gemini-3.1-pro-preview', 'google'),
  AiModel('gemini-3.6-flash', 'google'),
  AiModel('gemini-3.5-flash', 'google', free: true),
  AiModel('gemini-3.5-flash-lite', 'google', free: true),
  AiModel('claude-opus-5-5', 'anthropic', fastMode: true),
  AiModel('claude-sonnet-5-5', 'anthropic'),
  AiModel('claude-fable-5-1', 'anthropic'),
  AiModel('claude-opus-5', 'anthropic', fastMode: true),
  AiModel('claude-sonnet-5', 'anthropic'),
  AiModel('claude-fable-5', 'anthropic'),
  AiModel('claude-haiku-4-5', 'anthropic', free: true),
];
