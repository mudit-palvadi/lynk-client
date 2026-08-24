import '../../domain/entities/receiver_session.dart';

class ReceiverSessionModel extends ReceiverSession {
  const ReceiverSessionModel({
    required super.id,
    required super.status,
    super.transferId,
    super.wrappedKey,
    super.expiresMultiplier,
  });

  factory ReceiverSessionModel.fromJson(Map<String, dynamic> json) {
    ReceiverSessionStatus parseStatus(String? statusStr) {
      switch (statusStr) {
        case 'attached':
          return ReceiverSessionStatus.attached;
        case 'expired':
          return ReceiverSessionStatus.expired;
        case 'waiting':
        default:
          return ReceiverSessionStatus.waiting;
      }
    }

    return ReceiverSessionModel(
      id: (json['session_id'] ?? json['id']) as String? ?? '',
      status: parseStatus(json['status'] as String?),
      transferId: json['transfer_id'] as String?,
      wrappedKey: json['wrapped_key'] as String?,
      expiresMultiplier:
          json['expires_in'] as int? ?? json['expires_at_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    String statusString(ReceiverSessionStatus s) {
      switch (s) {
        case ReceiverSessionStatus.attached:
          return 'attached';
        case ReceiverSessionStatus.expired:
          return 'expired';
        case ReceiverSessionStatus.waiting:
          return 'waiting';
      }
    }

    return {
      'session_id': id,
      'status': statusString(status),
      if (transferId != null) 'transfer_id': transferId,
      if (wrappedKey != null) 'wrapped_key': wrappedKey,
      if (expiresMultiplier != null) 'expires_in': expiresMultiplier,
    };
  }

  factory ReceiverSessionModel.fromEntity(ReceiverSession entity) {
    return ReceiverSessionModel(
      id: entity.id,
      status: entity.status,
      transferId: entity.transferId,
      wrappedKey: entity.wrappedKey,
      expiresMultiplier: entity.expiresMultiplier,
    );
  }
}
