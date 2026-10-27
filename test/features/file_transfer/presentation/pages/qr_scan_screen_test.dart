import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/file_transfer/presentation/pages/qr_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  for (final attachId in <String?>[null, 'transfer-1']) {
    testWidgets('scanner $attachId keeps only the bottom gallery action', (
      tester,
    ) async {
      final previous = MobileScannerPlatform.instance;
      MobileScannerPlatform.instance = _Camera();
      addTearDown(() => MobileScannerPlatform.instance = previous);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: QrScanScreen(attachTransferId: attachId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      final bottomAction = find.widgetWithText(
        OutlinedButton,
        'Pick QR from Gallery',
      );
      expect(bottomAction, findsOneWidget);
      expect(tester.widget<OutlinedButton>(bottomAction).onPressed, isNotNull);
      expect(find.byIcon(Icons.photo_library), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

class _Camera extends MobileScannerPlatform {
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async =>
      const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(640, 480),
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
