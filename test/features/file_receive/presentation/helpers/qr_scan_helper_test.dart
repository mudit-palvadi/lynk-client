import 'package:client/features/file_transfer/presentation/helpers/qr_scan_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'QrScanHelper processBarcodeDetection extracts transferId from deep link URL',
    () {
      const rawUrl = 'https://lynkshare.app/send/test_transfer_123#myAesKey';
      final result = QrScanHelper.extractTransferIdAndKey(rawUrl);
      expect(result['transferId'], equals('test_transfer_123'));
      expect(result['aesKey'], equals('myAesKey'));
    },
  );

  test(
    'QrScanHelper processBarcodeDetection extracts transferId from custom scheme URL',
    () {
      const rawUrl = 'lynk://send/test_transfer_456#anotherKey';
      final result = QrScanHelper.extractTransferIdAndKey(rawUrl);
      expect(result['transferId'], equals('test_transfer_456'));
      expect(result['aesKey'], equals('anotherKey'));
    },
  );

  test(
    'extractReceiveSessionIdAndPublicKey parses https receive URL with pk fragment',
    () {
      const rawUrl =
          'https://lynkshare.app/receive/sess_abc123#pk=AbCdEf123456';
      final result = QrScanHelper.extractReceiveSessionIdAndPublicKey(rawUrl);
      expect(result['sessionId'], equals('sess_abc123'));
      expect(result['receiverPk'], equals('AbCdEf123456'));
    },
  );

  test(
    'extractReceiveSessionIdAndPublicKey parses custom scheme receive URL',
    () {
      const rawUrl = 'lynk://receive/sess_xyz789#pk=XyZ987';
      final result = QrScanHelper.extractReceiveSessionIdAndPublicKey(rawUrl);
      expect(result['sessionId'], equals('sess_xyz789'));
      expect(result['receiverPk'], equals('XyZ987'));
    },
  );

  test(
    'extractReceiveSessionIdAndPublicKey returns null pk when no fragment present (legacy)',
    () {
      const rawUrl = 'https://lynkshare.app/receive/sess_legacy';
      final result = QrScanHelper.extractReceiveSessionIdAndPublicKey(rawUrl);
      expect(result['sessionId'], equals('sess_legacy'));
      expect(result['receiverPk'], isNull);
    },
  );
}
