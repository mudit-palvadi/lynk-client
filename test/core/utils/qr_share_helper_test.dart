import 'dart:io';

import 'package:client/core/utils/qr_share_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  final previousPaths = PathProviderPlatform.instance;
  late Directory sandbox;
  late List<String> sharedPaths;
  late bool existedDuringShare;
  late int shareCalls;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('lynk-qr-cache-');
    PathProviderPlatform.instance = _FakePaths(sandbox.path);
    sharedPaths = [];
    existedDuringShare = false;
    shareCalls = 0;
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  /// Mocks the native side of share_plus and records which files it received.
  void mockShare({String result = 'ok', Object? error}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shareCalls++;
          sharedPaths = ((call.arguments as Map)['paths'] as List)
              .cast<String>();
          existedDuringShare = File(sharedPaths.single).existsSync();
          if (error != null) throw error;
          return result;
        });
  }

  Future<GlobalKey> pumpQr(WidgetTester tester) async {
    final qrKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: qrKey,
            child: Container(width: 120, height: 120, color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return qrKey;
  }

  group('deleteCachedQr', () {
    test('deletes the cached PNG for the transfer', () async {
      final cached = File('${sandbox.path}/lynk_qr_transfer-1.png');
      await cached.writeAsBytes([1, 2, 3]);

      await QrShareHelper.deleteCachedQr('transfer-1');

      expect(cached.existsSync(), isFalse);
    });

    test('ignores a cached PNG that does not exist', () async {
      final missing = File('${sandbox.path}/lynk_qr_never-written.png');

      await QrShareHelper.deleteCachedQr('never-written');

      expect(missing.existsSync(), isFalse);
    });

    test('only deletes the cache entry for the given transfer', () async {
      final cached = File('${sandbox.path}/lynk_qr_transfer-1.png');
      final other = File('${sandbox.path}/lynk_qr_transfer-2.png');
      await cached.writeAsBytes([1]);
      await other.writeAsBytes([2]);

      await QrShareHelper.deleteCachedQr('transfer-1');

      expect(cached.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });

  group('captureAndShareQr', () {
    testWidgets('deletes the PNG after the share sheet consumed it', (
      tester,
    ) async {
      final qrKey = await pumpQr(tester);
      mockShare();

      await tester.runAsync(
        () => QrShareHelper.captureAndShareQr(
          qrKey: qrKey,
          transferId: 'transfer-1',
        ),
      );

      final cached = File('${sandbox.path}/lynk_qr_transfer-1.png');
      expect(shareCalls, 1);
      expect(sharedPaths, [cached.path]);
      expect(
        existedDuringShare,
        isTrue,
        reason: 'the image must exist while the share sheet reads it',
      );
      expect(cached.existsSync(), isFalse);
    });

    testWidgets('deletes the PNG when the share is dismissed', (tester) async {
      final qrKey = await pumpQr(tester);
      mockShare(result: '');

      await tester.runAsync(
        () => QrShareHelper.captureAndShareQr(
          qrKey: qrKey,
          transferId: 'transfer-1',
        ),
      );

      final cached = File('${sandbox.path}/lynk_qr_transfer-1.png');
      expect(shareCalls, 1);
      expect(cached.existsSync(), isFalse);
    });

    testWidgets('deletes the PNG when sharing fails', (tester) async {
      final qrKey = await pumpQr(tester);
      mockShare(error: PlatformException(code: 'share_failed'));

      await tester.runAsync(
        () => QrShareHelper.captureAndShareQr(
          qrKey: qrKey,
          transferId: 'transfer-1',
        ),
      );

      final cached = File('${sandbox.path}/lynk_qr_transfer-1.png');
      expect(shareCalls, 1);
      expect(cached.existsSync(), isFalse);
    });
  });
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
