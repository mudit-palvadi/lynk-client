/// The receiver's half of a sender-owned pairing session.
///
/// The join names the session and publishes the receiver's public key; the key
/// response is the wrapped AES key and is collectable exactly once.
class ReceiverCodeJoinModel {
  final String sessionId;
  final String status;
  final int expiresIn;

  const ReceiverCodeJoinModel({
    required this.sessionId,
    required this.status,
    required this.expiresIn,
  });

  factory ReceiverCodeJoinModel.fromJson(Map<String, dynamic> json) {
    return ReceiverCodeJoinModel(
      sessionId: json['session_id'] as String,
      status: json['status'] as String? ?? 'joined',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The wrapped key the receiver collects exactly once.
class ReceiverCodeKeyModel {
  final String transferId;
  final String wrappedKey;
  final int expiresIn;

  const ReceiverCodeKeyModel({
    required this.transferId,
    required this.wrappedKey,
    required this.expiresIn,
  });

  factory ReceiverCodeKeyModel.fromJson(Map<String, dynamic> json) {
    return ReceiverCodeKeyModel(
      transferId: json['transfer_id'] as String,
      wrappedKey: json['wrapped_key'] as String,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
    );
  }
}
