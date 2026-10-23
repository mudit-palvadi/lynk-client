import 'package:client/features/file_receive/data/models/code_session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiverCodeJoinModel', () {
    test('reads the join response', () {
      final model = ReceiverCodeJoinModel.fromJson({
        'session_id': 'session-1',
        'status': 'joined',
        'expires_in': 590,
      });

      expect(model.sessionId, 'session-1');
      expect(model.status, 'joined');
      expect(model.expiresIn, 590);
    });
  });

  group('ReceiverCodeKeyModel', () {
    test('reads the key response', () {
      final model = ReceiverCodeKeyModel.fromJson({
        'transfer_id': 'transfer-1',
        'wrapped_key': 'wrapped',
        'expires_in': 120,
      });

      expect(model.transferId, 'transfer-1');
      expect(model.wrappedKey, 'wrapped');
      expect(model.expiresIn, 120);
    });
  });
}
