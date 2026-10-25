import 'dart:io';

import 'package:client/core/routing/app_router.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/core/routing/transfer_route_args.dart';
import 'package:client/core/widgets/not_found_screen.dart';
import 'package:client/features/file_transfer/presentation/pages/download_progress_screen.dart';
import 'package:client/features/file_transfer/presentation/pages/file_upload_screen.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deep_link_behavior_test.dart' show pumpApp;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
    PendingDeepLink.clear();
  });

  tearDown(PendingDeepLink.clear);

  group('internal transfer route privacy', () {
    testWidgets('download query credentials cannot replace memory arguments', (
      tester,
    ) async {
      await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FileUploadScreen)),
      );
      container
          .read(appRouterProvider)
          .go(
            '/download-progress/transfer-1?aesKey=private-key&a=private-token',
          );
      await tester.pumpAndSettle();

      expect(find.byType(DownloadProgressScreen), findsNothing);
      expect(find.byType(NotFoundScreen), findsOneWidget);
      expect(find.textContaining('private-key'), findsNothing);
      expect(find.textContaining('private-token'), findsNothing);
    });

    for (final extra in <Object?>[null, 'wrong argument type']) {
      testWidgets('send QR rejects ${extra == null ? 'missing' : 'wrong'} '
          'arguments without throwing', (tester) async {
        await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FileUploadScreen)),
        );
        container
            .read(appRouterProvider)
            .go('/send-qr?aesKey=private-key', extra: extra);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(NotFoundScreen), findsOneWidget);
        expect(find.textContaining('private-key'), findsNothing);
      });
    }

    testWidgets('not-found UI does not echo query or fragment secrets', (
      tester,
    ) async {
      await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FileUploadScreen)),
      );
      container
          .read(appRouterProvider)
          .go('/missing?aesKey=private-key&a=private-token#private-fragment');
      await tester.pumpAndSettle();

      expect(find.byType(NotFoundScreen), findsOneWidget);
      for (final secret in [
        'private-key',
        'private-token',
        'private-fragment',
      ]) {
        expect(find.textContaining(secret), findsNothing);
      }
    });

    testWidgets(
      'typed download arguments keep the URI clean and retain pairing',
      (tester) async {
        await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
        final router = ProviderScope.containerOf(
          tester.element(find.byType(FileUploadScreen)),
        ).read(appRouterProvider);
        const args = DownloadArguments(
          transferId: 'transfer-1',
          aesKey: 'private-key',
          accessToken: 'private-token',
          viaPairing: true,
        );
        router.go(args.location, extra: args);
        await tester.pumpAndSettle();

        final screen = tester.widget<DownloadProgressScreen>(
          find.byType(DownloadProgressScreen),
        );
        expect(screen.transferId, args.transferId);
        expect(screen.aesKey, args.aesKey);
        expect(screen.accessToken, args.accessToken);
        expect(screen.viaPairing, isTrue);
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/download-progress/transfer-1',
        );
        expect(args.toString(), isNot(contains(args.aesKey)));
        expect(args.toString(), isNot(contains(args.accessToken)));
      },
    );

    final invalidDownloads = <String, Object?>{
      'wrong type': 'wrong',
      'mismatched transfer': const DownloadArguments(
        transferId: 'another-transfer',
        aesKey: 'private-key',
      ),
      'missing key': const DownloadArguments(
        transferId: 'transfer-1',
        aesKey: '',
      ),
    };
    for (final entry in invalidDownloads.entries) {
      testWidgets('download rejects ${entry.key}', (tester) async {
        await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
        final router = ProviderScope.containerOf(
          tester.element(find.byType(FileUploadScreen)),
        ).read(appRouterProvider);
        router.go('/download-progress/transfer-1', extra: entry.value);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(NotFoundScreen), findsOneWidget);
        expect(find.byType(DownloadProgressScreen), findsNothing);
      });
    }

    testWidgets('send QR rejects typed arguments without a key', (
      tester,
    ) async {
      await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(FileUploadScreen)),
      ).read(appRouterProvider);
      router.go(
        '/send-qr',
        extra: const SendQrArguments(
          transfer: Transfer(
            id: 'transfer-1',
            status: TransferStatus.ready,
            totalFiles: 0,
            totalSize: 0,
            files: [],
          ),
          aesKey: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NotFoundScreen), findsOneWidget);
    });

    test('download locations escape IDs without exposing credentials', () {
      const args = DownloadArguments(
        transferId: 'room/other?query#fragment',
        aesKey: 'private-key',
        accessToken: 'private-token',
      );
      final uri = Uri.parse(args.location);
      expect(uri.pathSegments, ['download-progress', args.transferId]);
      expect(uri.hasQuery, isFalse);
      expect(uri.hasFragment, isFalse);
      expect(args.location, isNot(contains(args.aesKey)));
      expect(args.location, isNot(contains(args.accessToken)));
    });

    for (final suffix in [
      '?aesKey=private-key&a=private-token',
      '#private-key',
    ]) {
      testWidgets(
        'typed arguments do not permit an internal URL suffix $suffix',
        (tester) async {
          await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
          final router = ProviderScope.containerOf(
            tester.element(find.byType(FileUploadScreen)),
          ).read(appRouterProvider);
          router.go(
            '/download-progress/transfer-1$suffix',
            extra: const DownloadArguments(
              transferId: 'transfer-1',
              aesKey: 'private-key',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NotFoundScreen), findsOneWidget);
          expect(find.textContaining('private-key'), findsNothing);
          expect(find.textContaining('private-token'), findsNothing);
        },
      );
    }

    for (final link in [
      'https://lynkshare.app/send/transfer-1#private-key&a=private-token',
      'lynk://send/transfer-1#private-key&a=private-token',
      'https://lynkshare.app/send/transfer-1?aesKey=private-key&a=private-token',
    ]) {
      testWidgets('external link credentials remain compatible: $link', (
        tester,
      ) async {
        await pumpApp(tester, initialRoute: link, hasOnboarded: true);
        final screen = tester.widget<DownloadProgressScreen>(
          find.byType(DownloadProgressScreen),
        );
        expect(screen.transferId, 'transfer-1');
        expect(screen.aesKey, 'private-key');
        expect(screen.accessToken, 'private-token');
      });
    }

    test('all internal navigation emitters keep credentials out of URLs', () {
      const emitters = [
        'lib/features/file_transfer/presentation/pages/file_upload_screen.dart',
        'lib/features/home/presentation/pages/home_screen.dart',
        'lib/features/file_receive/presentation/pages/enter_code_screen.dart',
        'lib/features/file_receive/presentation/pages/receive_qr_screen.dart',
        'lib/features/file_transfer/presentation/helpers/qr_scan_helper.dart',
      ];
      for (final path in emitters) {
        final source = File(path)
            .readAsStringSync()
            .split('static Future<bool> processBarcodeDetection')
            .last;
        expect(source.contains('?aesKey='), isFalse, reason: path);
        expect(source.contains("'aesKey':"), isFalse, reason: path);
      }
    });
  });
}
