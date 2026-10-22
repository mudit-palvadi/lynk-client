import 'package:client/features/file_transfer/data/models/sender_session_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SenderSessionModel', () {
    test('reads the code the create endpoint mints', () {
      final model = SenderSessionModel.fromJson({
        'session_id': 'session-1',
        'code': '042917',
        'status': 'waiting',
        'expires_in': 600,
      });

      expect(model.sessionId, 'session-1');
      expect(model.code, '042917');
      expect(model.status, 'waiting');
      expect(model.expiresIn, 600);
      expect(model.hasReceiver, isFalse);
      expect(model.isAttached, isFalse);
    });

    test('sees the receiver once it joins', () {
      final model = SenderSessionModel.fromJson({
        'session_id': 'session-1',
        'status': 'joined',
        'receiver_pk': 'receiver-public-key',
        'expires_in': 420,
      });

      expect(model.hasReceiver, isTrue);
      expect(model.receiverPk, 'receiver-public-key');
      expect(model.isAttached, isFalse);
    });

    test('carries the transfer id once the key is attached', () {
      final model = SenderSessionModel.fromJson({
        'session_id': 'session-1',
        'status': 'attached',
        'receiver_pk': 'receiver-public-key',
        'transfer_id': 'transfer-9',
        'expires_in': 300,
      });

      expect(model.isAttached, isTrue);
      expect(model.transferId, 'transfer-9');
    });

    test('a response without the optional fields stays empty', () {
      final model = SenderSessionModel.fromJson({
        'session_id': 'session-1',
        'status': 'waiting',
        'expires_in': 0,
      });

      expect(model.code, isNull);
      expect(model.receiverPk, isNull);
      expect(model.transferId, isNull);
    });
  });

  group('SenderSessionKeyModel', () {
    test('reads the wrapped key the receiver collects', () {
      final model = SenderSessionKeyModel.fromJson({
        'transfer_id': 'transfer-9',
        'wrapped_key': 'wrapped',
        'expires_in': 240,
      });

      expect(model.transferId, 'transfer-9');
      expect(model.wrappedKey, 'wrapped');
      expect(model.expiresIn, 240);
    });
  });
}
