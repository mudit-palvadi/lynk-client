import 'dart:async';

import 'package:client/core/services/play_update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.ffuf.in_app_update/methods');

  void version(String build) => PackageInfo.setMockInitialValues(
    appName: 'Lynk',
    packageName: 'app.xynix.lynk',
    version: '0.1.0',
    buildNumber: build,
    buildSignature: '',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Play update native bridge', () {
    test('reads the installed version code rather than version name', () async {
      version('123');
      expect(await PlayUpdateService().installedVersion(), 123);
    });

    test('invalid installed codes cannot be used for admission', () async {
      for (final build in ['bad', '', '0', '-1']) {
        version(build);
        await expectLater(
          PlayUpdateService().installedVersion(),
          throwsStateError,
        );
      }
    });

    test('retries share a native check that has not returned yet', () async {
      var checks = 0;
      final reply = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            checks++;
            return reply.future;
          });
      final service = PlayUpdateService();
      final first = service.check();
      final second = service.check();
      await pumpEventQueue();
      expect(identical(first, second), true);
      expect(checks, 1);
      reply.complete({
        'updateAvailability': 1,
        'immediateAllowed': false,
        'flexibleAllowed': false,
        'availableVersionCode': null,
        'installStatus': 0,
        'packageName': 'app.xynix.lynk',
        'updatePriority': 0,
      });
      expect(
        (await first).updateAvailability,
        UpdateAvailability.updateNotAvailable,
      );
      await second;
      await service.check();
      expect(checks, 2);
    });

    test('a failed native request is cleared for a real Retry', () async {
      var checks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            checks++;
            throw PlatformException(code: 'CHECK_FAILED');
          });
      final service = PlayUpdateService();
      await expectLater(service.check(), throwsA(isA<PlatformException>()));
      await expectLater(service.check(), throwsA(isA<PlatformException>()));
      expect(checks, 2);
    });
  });
}
