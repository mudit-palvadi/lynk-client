import 'package:equatable/equatable.dart';

enum RecentTransferType { sent, received }

class RecentTransferRecord extends Equatable {
  final String id;
  final RecentTransferType type;
  final List<String> fileNames;
  final int totalSize;
  final DateTime timestamp;
  final String status;
  final List<String>? filePaths;

  const RecentTransferRecord({
    required this.id,
    required this.type,
    required this.fileNames,
    required this.totalSize,
    required this.timestamp,
    required this.status,
    this.filePaths,
  });

  @override
  List<Object?> get props => [
    id,
    type,
    fileNames,
    totalSize,
    timestamp,
    status,
    filePaths,
  ];
}
