import '../../domain/entities/recent_transfer_record.dart';

class RecentTransferRecordModel extends RecentTransferRecord {
  const RecentTransferRecordModel({
    required super.id,
    required super.type,
    required super.fileNames,
    required super.totalSize,
    required super.timestamp,
    required super.status,
    super.filePaths,
  });

  factory RecentTransferRecordModel.fromJson(Map<String, dynamic> json) {
    return RecentTransferRecordModel(
      id: json['id'] as String? ?? '',
      type: json['type'] == 'received'
          ? RecentTransferType.received
          : RecentTransferType.sent,
      fileNames:
          (json['file_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      totalSize: json['total_size'] as int? ?? 0,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      status: json['status'] as String? ?? 'completed',
      filePaths: (json['file_paths'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type == RecentTransferType.received ? 'received' : 'sent',
      'file_names': fileNames,
      'total_size': totalSize,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      if (filePaths != null) 'file_paths': filePaths,
    };
  }

  factory RecentTransferRecordModel.fromEntity(RecentTransferRecord entity) {
    return RecentTransferRecordModel(
      id: entity.id,
      type: entity.type,
      fileNames: entity.fileNames,
      totalSize: entity.totalSize,
      timestamp: entity.timestamp,
      status: entity.status,
      filePaths: entity.filePaths,
    );
  }
}
