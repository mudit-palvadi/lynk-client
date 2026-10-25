import 'package:client/core/errors/failures.dart';
import 'package:client/core/errors/result.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/services/unlock_credits.dart';
import 'package:client/features/file_transfer/data/models/transfer_model.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/domain/repositories/transfer_repository.dart';
import 'package:client/features/file_transfer/presentation/helpers/send_qr_helper.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUploadNotifier extends UploadNotifier {
  @override
  UploadState build() => const UploadState();
}

class _RecordingTransferRepository implements TransferRepository {
  String? extendedId;
  String? extendedSecret;
  Result<void>? extendResult;

  @override
  Future<Result<void>> extendTransfer(
    String transferId, {
    String? senderSecret,
  }) async {
    extendedId = transferId;
    extendedSecret = senderSecret;
    return extendResult ?? Result.success(null);
  }

  @override
  Future<Result<Transfer>> createTransfer(List<FileItem> files) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  }) async => throw UnimplementedError();

  @override
  Future<Result<Transfer>> getTransferMetadata(
    String transferId, {
    String? accessToken,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<FileItem>>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> cancelTransfer(
    String transferId, {
    String? senderSecret,
  }) async => throw UnimplementedError();
}

void main() {
  group('SendQrHelper & TransferModel fixes tests', () {
    test(
      'calculateRemainingSeconds calculates exact countdown from createdAt timestamp',
      () {
        final now = DateTime.now();
        final createdAt = now.subtract(const Duration(minutes: 3, seconds: 15));
        final remaining = SendQrHelper.calculateRemainingSeconds(createdAt);

        expect(remaining, equals(405)); // 600 - 195 = 405s
      },
    );

    test(
      'TransferModel.fromJson correctly falls back to sum of file sizes when total_size is missing/null',
      () {
        final json = {
          'transfer_id': 'tx_test_size',
          'status': 'ready',
          'total_files': 2,
          'total_size': null,
          'files': [
            {
              'file_id': 'f1',
              'file_name': 'doc.pdf',
              'file_size': 1048576,
              'content_type': 'application/pdf',
              'status': 'pending',
            },
            {
              'file_id': 'f2',
              'file_name': 'img.png',
              'file_size': 2097152,
              'content_type': 'image/png',
              'status': 'pending',
            },
          ],
        };

        final model = TransferModel.fromJson(json);

        expect(model.totalSize, equals(3145728)); // 1MB + 2MB = 3MB
      },
    );
  });

  group('extendSessionTimeWithAd', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget harness({
      required _RecordingTransferRepository repository,
      required ValueNotifier<int> seconds,
    }) {
      return ProviderScope(
        overrides: [
          transferRepositoryProvider.overrideWithValue(repository),
          uploadProvider.overrideWith(_FakeUploadNotifier.new),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => SendQrHelper.extendSessionTimeWithAd(
                  context: context,
                  ref: ref,
                  transferId: 't1',
                  secondsNotifier: seconds,
                  unlockCredits: UnlockCredits(
                    showRewardedAd: ({required onRewardGranted}) async {
                      onRewardGranted();
                      return true;
                    },
                  ),
                ),
                child: const Text('extend'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('calls the backend before moving the timer', (tester) async {
      final repository = _RecordingTransferRepository();
      final seconds = ValueNotifier<int>(600);
      addTearDown(seconds.dispose);

      await tester.pumpWidget(
        harness(repository: repository, seconds: seconds),
      );
      await tester.tap(find.text('extend'));
      await tester.pumpAndSettle();

      expect(repository.extendedId, 't1');
      expect(seconds.value, 1800);
      expect(find.text('Session extended to 30 minutes!'), findsOneWidget);
    });

    testWidgets('leaves the timer alone when the backend refuses', (
      tester,
    ) async {
      final repository = _RecordingTransferRepository()
        ..extendResult = Result.failure(
          ServerFailure('Session is already gone'),
        );
      final seconds = ValueNotifier<int>(600);
      addTearDown(seconds.dispose);

      await tester.pumpWidget(
        harness(repository: repository, seconds: seconds),
      );
      await tester.tap(find.text('extend'));
      await tester.pumpAndSettle();

      expect(seconds.value, 600);
      expect(find.text('Session is already gone'), findsOneWidget);
    });
  });
}
