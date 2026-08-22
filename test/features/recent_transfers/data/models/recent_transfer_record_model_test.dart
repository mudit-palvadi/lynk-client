import 'package:client/features/recent_transfers/data/models/recent_transfer_record_model.dart';
import 'package:client/features/recent_transfers/domain/entities/recent_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testTimestamp = DateTime.parse('2026-07-27T00:00:00.000Z');

  final testRecord = RecentTransferRecordModel(
    id: 'tx_123',
    type: RecentTransferType.sent,
    fileNames: ['file1.png', 'file2.pdf'],
    totalSize: 1048576,
    timestamp: testTimestamp,
    status: 'completed',
    filePaths: ['/path/to/file1.png', '/path/to/file2.pdf'],
  );

  final testJson = {
    'id': 'tx_123',
    'type': 'sent',
    'file_names': ['file1.png', 'file2.pdf'],
    'total_size': 1048576,
    'timestamp': testTimestamp.toIso8601String(),
    'status': 'completed',
    'file_paths': ['/path/to/file1.png', '/path/to/file2.pdf'],
  };

  group('RecentTransferRecordModel', () {
    test('fromJson parses JSON correctly into RecentTransferRecordModel', () {
      final model = RecentTransferRecordModel.fromJson(testJson);
      expect(model.id, equals('tx_123'));
      expect(model.type, equals(RecentTransferType.sent));
      expect(model.fileNames, equals(['file1.png', 'file2.pdf']));
      expect(model.totalSize, equals(1048576));
      expect(model.timestamp, equals(testTimestamp));
      expect(model.status, equals('completed'));
      expect(
        model.filePaths,
        equals(['/path/to/file1.png', '/path/to/file2.pdf']),
      );
    });

    test('toJson serializes RecentTransferRecordModel correctly', () {
      final json = testRecord.toJson();
      expect(json, equals(testJson));
    });

    test('toJson never serializes an aes_key field', () {
      final json = testRecord.toJson();
      expect(json.containsKey('aes_key'), isFalse);
    });

    test('legacy persisted aes_key field is ignored on parse', () {
      final legacyJson = Map<String, dynamic>.from(testJson)
        ..['aes_key'] = 'plaintext_key_from_old_version';

      final model = RecentTransferRecordModel.fromJson(legacyJson);
      final json = model.toJson();

      expect(json.containsKey('aes_key'), isFalse);
    });
  });
}
