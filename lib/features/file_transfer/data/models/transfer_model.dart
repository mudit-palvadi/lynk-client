import '../../domain/entities/transfer.dart';
import 'file_item_model.dart';

class TransferModel extends Transfer {
  const TransferModel({
    required super.id,
    required super.status,
    required super.totalFiles,
    required super.totalSize,
    super.expiresMultiplier,
    super.createdAt,
    required super.files,
    super.senderSecret,
    super.accessToken,
  });

  factory TransferModel.fromJson(Map<String, dynamic> json) {
    TransferStatus parseStatus(String? statusStr) {
      switch (statusStr) {
        case 'ready':
          return TransferStatus.ready;
        case 'expired':
          return TransferStatus.expired;
        case 'cancelled':
          return TransferStatus.cancelled;
        case 'uploading':
        default:
          return TransferStatus.uploading;
      }
    }

    final filesList = json['files'] as List<dynamic>? ?? [];
    final parsedFiles = filesList
        .map((f) => FileItemModel.fromJson(f as Map<String, dynamic>))
        .toList();

    final int computedTotalSize = parsedFiles.fold(0, (sum, f) => sum + f.size);
    final rawSize = json['total_size'] as int? ?? json['totalSize'] as int?;

    DateTime? parsedCreatedAt;
    if (json['created_at'] != null && json['created_at'] is String) {
      parsedCreatedAt = DateTime.tryParse(json['created_at'] as String);
    }

    return TransferModel(
      id: json['transfer_id'] as String? ?? '',
      status: parseStatus(json['status'] as String?),
      totalFiles: json['total_files'] as int? ?? parsedFiles.length,
      totalSize: (rawSize != null && rawSize > 0) ? rawSize : computedTotalSize,
      expiresMultiplier:
          json['expires_in'] as int? ?? json['expires_at_seconds'] as int?,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      files: parsedFiles,
      senderSecret: json['sender_secret'] as String?,
      accessToken: json['access_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    String statusString(TransferStatus s) {
      switch (s) {
        case TransferStatus.ready:
          return 'ready';
        case TransferStatus.expired:
          return 'expired';
        case TransferStatus.cancelled:
          return 'cancelled';
        case TransferStatus.uploading:
          return 'uploading';
      }
    }

    return {
      'transfer_id': id,
      'status': statusString(status),
      'total_files': totalFiles,
      'total_size': totalSize,
      if (expiresMultiplier != null) 'expires_in': expiresMultiplier,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'files': files.map((f) => FileItemModel.fromEntity(f).toJson()).toList(),
    };
  }

  factory TransferModel.fromEntity(Transfer entity) {
    return TransferModel(
      id: entity.id,
      status: entity.status,
      totalFiles: entity.totalFiles,
      totalSize: entity.totalSize,
      expiresMultiplier: entity.expiresMultiplier,
      createdAt: entity.createdAt,
      files: entity.files,
      senderSecret: entity.senderSecret,
      accessToken: entity.accessToken,
    );
  }
}
