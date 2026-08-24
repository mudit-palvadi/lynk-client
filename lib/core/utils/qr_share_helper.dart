import 'dart:io';
import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class QrShareHelper {
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
      final file = File('${tempDir.path}/lynk_qr_$transferId.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Scan this QR code in Lynk to receive files!',
        ),
      );
    } catch (e) {
      debugPrint('Error sharing QR code: $e');
    }
  }
}
