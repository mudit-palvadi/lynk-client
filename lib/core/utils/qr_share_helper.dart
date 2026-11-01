import 'dart:io';
import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class QrShareHelper {
  static const _cacheFilePrefix = 'lynk_qr_';

  /// Captures a RepaintBoundary widget as PNG bytes and invokes OS native share dialog.
  static Future<void> captureAndShareQr({
    required GlobalKey qrKey,
    required String transferId,
  }) async {
    try {
      final boundary =
          qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File(_cachePath(tempDir.path, transferId));
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Scan this QR code in Lynk to receive files!',
        ),
      );
    } catch (e) {
      debugPrint('Error sharing QR code: $e');
    } finally {
      // The PNG embeds the transfer key and access token, so it must not
      // outlive the share sheet - including when it was dismissed or failed.
      await deleteCachedQr(transferId);
    }
  }

  /// Deletes the cached QR PNG for [transferId] if it exists.
  ///
  /// Cleanup is best effort: a missing file (or an unavailable temp directory)
  /// must never surface as an error.
  static Future<void> deleteCachedQr(String transferId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(_cachePath(tempDir.path, transferId));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting cached QR code: $e');
    }
  }

  static String _cachePath(String tempPath, String transferId) =>
      '$tempPath/$_cacheFilePrefix$transferId.png';
}
