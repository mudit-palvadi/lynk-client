import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/providers/receiver_providers.dart';
import '../../../../core/routing/send_link_capability.dart';
import '../../../../core/services/key_wrap_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/upload_notifier.dart';

class QrScanHelper {
  /// Extracts transferId and aesKey from raw URL string.
  static Map<String, String?> extractTransferIdAndKey(String rawValue) {
    final uri = Uri.tryParse(rawValue);
    if (uri == null) return {'transferId': null, 'aesKey': null};

    String? transferId;
    if (uri.scheme == 'lynk') {
      if (uri.host == 'send' && uri.pathSegments.isNotEmpty) {
        transferId = uri.pathSegments.first;
      } else if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'send') {
        transferId = uri.pathSegments[1];
      }
    } else if (uri.scheme == 'https' || uri.scheme == 'http') {
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'send') {
        transferId = segments[1];
      }
    }
    if (transferId == null) return {'transferId': null, 'aesKey': null};

    final capability = splitFragmentCapability(uri.fragment.split('?').first);
    return {
      'transferId': transferId,
      'aesKey': capability.aesKey,
      'accessToken': capability.accessToken,
    };
  }

  /// Extracts receiver session id and ephemeral public key from a receiver
  /// QR URL: https://lynkshare.app/receive/{sessionId}#pk={base64url}
  static Map<String, String?> extractReceiveSessionIdAndPublicKey(
    String rawValue,
  ) {
    final uri = Uri.tryParse(rawValue);
    if (uri == null) return {'sessionId': null, 'receiverPk': null};

    final bool isReceiveUrl;
    if (uri.scheme == 'lynk') {
      isReceiveUrl =
          uri.pathSegments.isNotEmpty &&
          (uri.pathSegments.first == 'receive' || uri.host == 'receive');
    } else if (uri.scheme == 'https' || uri.scheme == 'http') {
      isReceiveUrl =
          uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'receive';
    } else {
      isReceiveUrl = false;
    }

    if (!isReceiveUrl) return {'sessionId': null, 'receiverPk': null};

    String? sessionId;
    if (uri.pathSegments.length >= 2) {
      sessionId = uri.pathSegments[1];
    } else {
      sessionId = uri.host == 'receive' ? uri.pathSegments.first : null;
    }

    final fragment = uri.fragment;
    final receiverPk = fragment.startsWith('pk=')
        ? fragment.substring(3)
        : null;

    return {'sessionId': sessionId, 'receiverPk': receiverPk};
  }

  /// Pick an image from gallery and scan for QR codes.
  static Future<bool> pickAndScanFromGallery({
    required BuildContext context,
    required WidgetRef ref,
    required MobileScannerController scannerController,
    required String? attachTransferId,
  }) async {
    try {
      final pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (pickerResult == null || pickerResult.files.single.path == null) {
        return false;
      }

      final imagePath = pickerResult.files.single.path!;
      final capture = await scannerController.analyzeImage(imagePath);

      if (capture != null && capture.barcodes.isNotEmpty && context.mounted) {
        return await processBarcodeDetection(
          context: context,
          ref: ref,
          capture: capture,
          attachTransferId: attachTransferId,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid Lynk QR code found in selected photo.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to read image from gallery.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return false;
    }
  }

  /// Processes a barcode detection event and handles routing / session attachment.
  static Future<bool> processBarcodeDetection({
    required BuildContext context,
    required WidgetRef ref,
    required BarcodeCapture capture,
    required String? attachTransferId,
  }) async {
    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue == null) return false;

    final extracted = extractTransferIdAndKey(rawValue);
    if (extracted['transferId'] != null) {
      final id = extracted['transferId']!;
      final aesKey = extracted['aesKey'] ?? '';
      final accessToken = extracted['accessToken'] ?? '';
      final tokenQuery = accessToken.isEmpty
          ? ''
          : '&a=${Uri.encodeQueryComponent(accessToken)}';
      context.go(
        '/download-progress/$id?aesKey=${Uri.encodeQueryComponent(aesKey)}$tokenQuery',
      );
      return true;
    }

    final uri = Uri.tryParse(rawValue);
    if (uri != null &&
        (uri.scheme == 'https' ||
            uri.scheme == 'http' ||
            uri.scheme == 'lynk')) {
      final extractedReceive = extractReceiveSessionIdAndPublicKey(rawValue);
      final id = extractedReceive['sessionId'];
      if (id != null) {
        return await handleReceiveSession(
          context: context,
          ref: ref,
          sessionId: id,
          attachTransferId: attachTransferId,
          receiverPk: extractedReceive['receiverPk'],
        );
      }
    }

    try {
      final json = jsonDecode(rawValue);
      if (json is Map<String, dynamic>) {
        if (json.containsKey('transfer_id') && json['transfer_id'] is String) {
          final transferId = json['transfer_id'] as String;
          context.go('/download-progress/$transferId');
          return true;
        } else if (json.containsKey('session_id') &&
            json['session_id'] is String) {
          final sessionId = json['session_id'] as String;
          return await handleReceiveSession(
            context: context,
            ref: ref,
            sessionId: sessionId,
            attachTransferId: attachTransferId,
          );
        }
      }
    } catch (_) {}

    return false;
  }

  static Future<bool> handleReceiveSession({
    required BuildContext context,
    required WidgetRef ref,
    required String sessionId,
    required String? attachTransferId,
    String? receiverPk,
  }) async {
    if (attachTransferId != null && attachTransferId.isNotEmpty) {
      final repo = ref.read(receiverRepositoryProvider);
      final currentAesKey = ref.read(uploadProvider).aesKey;

      String? wrappedKey;
      if (receiverPk != null &&
          receiverPk.isNotEmpty &&
          currentAesKey != null &&
          currentAesKey.isNotEmpty) {
        wrappedKey = await KeyWrapService().wrapKey(
          aesKey: currentAesKey,
          accessToken: ref.read(uploadProvider).transfer?.accessToken,
          receiverPublicKeyB64: receiverPk,
          sessionId: sessionId,
        );
      }

      final result = await repo.attachTransfer(
        sessionId: sessionId,
        transferId: attachTransferId,
        wrappedKey: wrappedKey,
      );

      if (context.mounted) {
        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Files successfully sent to receiver!'),
              backgroundColor: AppTheme.secondary,
            ),
          );
          context.pop();
          return true;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to pair: ${result.failure?.message}'),
              backgroundColor: AppTheme.error,
            ),
          );
          return false;
        }
      }
      return false;
    } else {
      final pkParam = receiverPk != null && receiverPk.isNotEmpty
          ? '&pk=${Uri.encodeComponent(receiverPk)}'
          : '';
      context.go('/upload?attachToSessionId=$sessionId$pkParam');
      return true;
    }
  }
}
