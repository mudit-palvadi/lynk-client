/// A sender-owned pairing session addressed by a six-digit code.
///
/// The same shape is used for every response that carries a session, so the
/// optional fields are filled in only where the endpoint provides them.
class SenderSessionModel {
  final String sessionId;
  final String? code;
  final String status;
  final int expiresIn;
  final String? receiverPk;
  final String? transferId;

  const SenderSessionModel({
    required this.sessionId,
    this.code,
    required this.status,
    required this.expiresIn,
    this.receiverPk,
    this.transferId,
  });

  /// True once the receiver published its public key.
  bool get hasReceiver => (receiverPk ?? '').isNotEmpty;

  /// True once the sender wrapped the key for the joined receiver.
  bool get isAttached => status == 'attached';

  factory SenderSessionModel.fromJson(Map<String, dynamic> json) {
    return SenderSessionModel(
      sessionId: json['session_id'] as String,
      code: json['code'] as String?,
      status: json['status'] as String? ?? 'waiting',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      receiverPk: json['receiver_pk'] as String?,
      transferId: json['transfer_id'] as String?,
    );
  }
}

/// The wrapped AES key the receiver collects exactly once.
class SenderSessionKeyModel {
  final String transferId;
  final String wrappedKey;
  final int expiresIn;

  const SenderSessionKeyModel({
    required this.transferId,
    required this.wrappedKey,
    required this.expiresIn,
  });

  factory SenderSessionKeyModel.fromJson(Map<String, dynamic> json) {
    return SenderSessionKeyModel(
      transferId: json['transfer_id'] as String,
      wrappedKey: json['wrapped_key'] as String,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
    );
  }
}
