import 'package:equatable/equatable.dart';
import 'file_item.dart';

enum TransferStatus { uploading, ready, expired, cancelled }

class Transfer extends Equatable {
  final String id;
  final TransferStatus status;
  final int totalFiles;
  final int totalSize;
  final int? expiresMultiplier;
  final DateTime? createdAt;
  final List<FileItem> files;

  /// Returned once, at create. Stays in memory. Never goes in the share link.
  final String? senderSecret;

  /// Returned once, at create. Travels in the link fragment for receivers.
  final String? accessToken;

  const Transfer({
    required this.id,
    required this.status,
    required this.totalFiles,
    required this.totalSize,
    this.expiresMultiplier,
    this.createdAt,
    required this.files,
    this.senderSecret,
    this.accessToken,
  });

  Transfer copyWith({
    String? id,
    TransferStatus? status,
    int? totalFiles,
    int? totalSize,
    int? expiresMultiplier,
    DateTime? createdAt,
    List<FileItem>? files,
    String? senderSecret,
    String? accessToken,
  }) {
    return Transfer(
      id: id ?? this.id,
      status: status ?? this.status,
      totalFiles: totalFiles ?? this.totalFiles,
      totalSize: totalSize ?? this.totalSize,
      expiresMultiplier: expiresMultiplier ?? this.expiresMultiplier,
      createdAt: createdAt ?? this.createdAt,
      files: files ?? this.files,
      senderSecret: senderSecret ?? this.senderSecret,
      accessToken: accessToken ?? this.accessToken,
    );
  }

  @override
  List<Object?> get props => [
    id,
    status,
    totalFiles,
    totalSize,
    expiresMultiplier,
    createdAt,
    files,
    senderSecret,
    accessToken,
  ];
}
