import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_theme.dart';
import '../helpers/qr_scan_helper.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  final String? attachTransferId;
  const QrScanScreen({super.key, this.attachTransferId});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final success = await QrScanHelper.processBarcodeDetection(
      context: context,
      ref: ref,
      capture: capture,
      attachTransferId: widget.attachTransferId,
    );
    if (success && mounted) {
      setState(() => _scanned = true);
    }
  }

  void _pickFromGallery() async {
    if (_scanned) return;
    final success = await QrScanHelper.pickAndScanFromGallery(
      context: context,
      ref: ref,
      scannerController: _controller,
      attachTransferId: widget.attachTransferId,
    );
    if (success && mounted) {
      setState(() => _scanned = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.attachTransferId != null
              ? 'Scan Receiver QR Code'
              : 'Scan QR Code',
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.attachTransferId != null
                      ? 'Align receiver QR code within frame to pair'
                      : 'Align sender or receiver QR code within frame',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text(
                    'Pick QR from Gallery',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
