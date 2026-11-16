/// Initial public release provider policy. This applies to both the catalog
/// and custom/saved model IDs; a server response cannot re-enable a provider.
abstract final class InitialReleaseAi {
  static const providers = {'openai', 'anthropic'};
  static const defaultModel = 'gpt-5.6-luna';
  static const unavailableMessage =
      'This AI model is unavailable in this release. Choose an OpenAI or Anthropic model to continue.';

  static bool allowsProvider(String provider) =>
      providers.contains(provider.toLowerCase());

  static String? providerForModel(String model) {
    // Keep arbitrary values, aliases and malformed IDs out of custom requests.
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,119}$').hasMatch(model)) return null;
    if (model.startsWith('gpt-') ||
        model.startsWith('gpt5-') ||
        RegExp(r'^o\d').hasMatch(model)) {
      return 'openai';
    }
    if (model.startsWith('claude-')) return 'anthropic';
    return null;
  }

  static bool allowsModel(String model) => providerForModel(model) != null;

  /// Existing gpt5 aliases can be normalized by the server. The UI must show
  /// its actual accepted ID. Other selections require an exact acknowledgement.
  static bool acknowledges(String requested, String accepted) =>
      allowsModel(requested) &&
      allowsModel(accepted) &&
      (requested == accepted ||
          requested.startsWith('gpt5-') &&
              providerForModel(accepted) == 'openai');
}
