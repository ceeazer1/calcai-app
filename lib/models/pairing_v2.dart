/// Signed values are relayed unchanged. Only the backend and calculator can
/// authenticate them; the phone validates shape and matching identifiers.
class PairingV2Exception implements Exception {
  const PairingV2Exception(this.message, {this.restartRequired = false});
  final String message;
  final bool restartRequired;
  @override
  String toString() => message;
}

bool pairingHex(Object? value, int length) =>
    value is String && RegExp('^[0-9a-f]{$length}\$').hasMatch(value);

Never invalidPairingReply() => throw const PairingV2Exception(
  'The pairing response could not be verified. Leave setup and reconnect.',
  restartRequired: true,
);

class PairingOffer {
  PairingOffer.fromJson(Map<String, dynamic> data, String expectedMac)
    : fields = Map.unmodifiable({
        for (final key in [
          'protocol',
          'mac',
          'challengeId',
          'accountBinding',
          'nonce',
          'expiresAt',
          'offerSignature',
        ])
          key: data[key],
      }) {
    if (data['ok'] != true ||
        fields['protocol'] != 2 ||
        fields['mac'] != expectedMac ||
        !pairingHex(fields['mac'], 12) ||
        !pairingHex(fields['challengeId'], 32) ||
        !pairingHex(fields['accountBinding'], 64) ||
        !pairingHex(fields['nonce'], 64) ||
        !pairingHex(fields['offerSignature'], 64) ||
        fields['expiresAt'] is! int ||
        expiresAt <= 0 ||
        expiresAt > 9007199254740991) {
      invalidPairingReply();
    }
  }
  final Map<String, dynamic> fields;
  String get mac => fields['mac'] as String;
  String get challengeId => fields['challengeId'] as String;
  int get expiresAt => fields['expiresAt'] as int;
}

class PairingApproval {
  PairingApproval.fromJson(Map<String, dynamic> data, PairingOffer offer)
    : nonce = data['approvalNonce'] is String
          ? data['approvalNonce'] as String
          : '',
      response = data['approvalResponse'] is String
          ? data['approvalResponse'] as String
          : '' {
    if (data['ok'] != true ||
        data['cmd'] != 'pairapprove' ||
        data['protocol'] != 2 ||
        data['mac'] != offer.mac ||
        data['challengeId'] != offer.challengeId ||
        !pairingHex(nonce, 32) ||
        !pairingHex(response, 64)) {
      invalidPairingReply();
    }
  }
  final String nonce;
  final String response;
  Map<String, dynamic> claimBody(PairingOffer offer) => {
    'protocol': 2,
    'mac': offer.mac,
    'challengeId': offer.challengeId,
    'approvalNonce': nonce,
    'approvalResponse': response,
  };
}

class PairingCompletion {
  PairingCompletion.fromJson(Map<String, dynamic> data, PairingOffer offer)
    : fields = Map.unmodifiable(
        data['completion'] is Map<String, dynamic>
            ? data['completion'] as Map<String, dynamic>
            : <String, dynamic>{},
      ) {
    if (data['ok'] != true ||
        data['protocol'] != 2 ||
        data['mac'] != offer.mac ||
        fields['ownershipId'] is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(fields['ownershipId'] as String) ||
        fields['pairedAt'] is! int ||
        (fields['pairedAt'] as int) <= 0 ||
        (fields['pairedAt'] as int) > 9007199254740991 ||
        !pairingHex(fields['signature'], 64)) {
      invalidPairingReply();
    }
  }
  final Map<String, dynamic> fields;
}
