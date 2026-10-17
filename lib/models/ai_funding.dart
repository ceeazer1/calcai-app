/// Who pays for an AI request. CalcAI's own provider/payment route is private
/// to the server and does not change the customer's allowance label.
enum AiFunding {
  allowance('allowance'),
  personalKey('personal_key');

  const AiFunding(this.apiValue);
  final String apiValue;

  static AiFunding? parse(Object? value) => switch (value) {
    'allowance' => allowance,
    'personal_key' => personalKey,
    _ => null,
  };
}

class FastModeCapability {
  const FastModeCapability({
    required this.supported,
    required this.available,
    required this.funding,
    this.reason,
  });

  final bool supported, available;
  final AiFunding? funding;
  final String? reason;

  /// Malformed/missing capabilities never grant paid Fast access.
  static FastModeCapability? parse(Object? value) {
    if (value is! Map ||
        value['supported'] is! bool ||
        value['available'] is! bool ||
        !value.containsKey('funding') ||
        (value['reason'] != null && value['reason'] is! String)) {
      return null;
    }
    final funding = AiFunding.parse(value['funding']);
    if ((value['funding'] != null && funding == null) ||
        (value['available'] == true &&
            (value['supported'] != true || funding == null))) {
      return null;
    }
    return FastModeCapability(
      supported: value['supported'],
      available: value['available'],
      funding: funding,
      reason: value['reason'],
    );
  }
}

String aiProviderLabel(String provider) => switch (provider.toLowerCase()) {
  'openai' => 'OpenAI',
  'google' => 'Google',
  'anthropic' => 'Anthropic',
  _ => 'provider',
};
