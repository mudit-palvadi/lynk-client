import 'package:flutter_test/flutter_test.dart';
import 'package:client/features/file_receive/data/models/receiver_session_model.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';

void main() {
  group('ReceiverSessionModel', () {
    test('fromJson parses waiting session correctly', () {
      final json = {
        'session_id': 'sess_abc',
        'status': 'waiting',
        'transfer_id': null,
        'wrapped_key': null,
        'expires_in': 600,
      };

      final model = ReceiverSessionModel.fromJson(json);

      expect(model.id, 'sess_abc');
      expect(model.status, ReceiverSessionStatus.waiting);
      expect(model.transferId, isNull);
      expect(model.wrappedKey, isNull);
      expect(model.expiresMultiplier, 600);
    });

    test('fromJson parses attached session with wrapped_key correctly', () {
      final json = {
        'session_id': 'sess_xyz',
        'status': 'attached',
        'transfer_id': 'tx_777',
        'wrapped_key': 'x25519-sealed-blob-base64==',
        'expires_in': 500,
      };

      final model = ReceiverSessionModel.fromJson(json);

      expect(model.id, 'sess_xyz');
      expect(model.status, ReceiverSessionStatus.attached);
      expect(model.transferId, 'tx_777');
      expect(model.wrappedKey, 'x25519-sealed-blob-base64==');
    });

    test('legacy aes_key field is never mapped into the model', () {
      final legacyJson = {
        'session_id': 'sess_old',
        'status': 'attached',
        'transfer_id': 'tx_1',
        'aes_key': 'plaintext_leaked_key',
        'expires_in': 500,
      };

      final model = ReceiverSessionModel.fromJson(legacyJson);

      expect(model.wrappedKey, isNull);
    });
  });
}
