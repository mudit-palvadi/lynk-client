import 'package:equatable/equatable.dart';

enum ReceiverSessionStatus { waiting, attached, expired }

class ReceiverSession extends Equatable {
  final String id;
  final ReceiverSessionStatus status;
  final String? transferId;

  /// Opaque ECDH-sealed ciphertext of the AES key (never plaintext).
  /// Unwrapped locally with the ephemeral private key held in memory.
  final String? wrappedKey;
  final int? expiresMultiplier;

  const ReceiverSession({
    required this.id,
    required this.status,
    this.transferId,
    this.wrappedKey,
    this.expiresMultiplier,
  });

  ReceiverSession copyWith({
    String? id,
    ReceiverSessionStatus? status,
    String? transferId,
    String? wrappedKey,
    int? expiresMultiplier,
  }) {
    return ReceiverSession(
      id: id ?? this.id,
      status: status ?? this.status,
      transferId: transferId ?? this.transferId,
      wrappedKey: wrappedKey ?? this.wrappedKey,
      expiresMultiplier: expiresMultiplier ?? this.expiresMultiplier,
    );
  }

  @override
  List<Object?> get props => [
    id,
    status,
    transferId,
    wrappedKey,
    expiresMultiplier,
  ];
}
