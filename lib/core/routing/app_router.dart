import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/file_receive/presentation/pages/receive_qr_screen.dart';
import '../../features/file_transfer/domain/entities/transfer.dart';
import '../../features/file_transfer/presentation/pages/download_progress_screen.dart';
import '../../features/file_transfer/presentation/pages/file_upload_screen.dart';
import '../../features/file_transfer/presentation/pages/qr_scan_screen.dart';
import '../../features/file_transfer/presentation/pages/send_qr_screen.dart';
import '../../features/home/presentation/pages/home_screen.dart';
import '../../features/onboarding/presentation/pages/onboarding_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../widgets/not_found_screen.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final hasOnboarded = ref.watch(onboardingProvider);

  return GoRouter(
    initialLocation: hasOnboarded ? '/home' : '/onboarding',
    errorBuilder: (context, state) =>
        NotFoundScreen(path: state.uri.toString()),
    redirect: (context, state) {
      final isOnboardingRoute = state.matchedLocation == '/onboarding';

      if (!hasOnboarded && !isOnboardingRoute) {
        return '/onboarding';
      }
      if (hasOnboarded && isOnboardingRoute) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/upload',
        builder: (context, state) {
          final attachToSessionId =
              state.uri.queryParameters['attachToSessionId'];
          final receiverPk = state.uri.queryParameters['pk'];
          return FileUploadScreen(
            attachToSessionId: attachToSessionId,
            receiverPk: receiverPk,
          );
        },
      ),
      GoRoute(
        path: '/send-qr',
        builder: (context, state) {
          final transfer = state.extra as Transfer;
          final aesKey = state.uri.queryParameters['aesKey'] ?? '';
          return SendQrScreen(transfer: transfer, aesKey: aesKey);
        },
      ),
      GoRoute(
        path: '/scan-qr',
        builder: (context, state) {
          final attachTransferId =
              state.uri.queryParameters['attachTransferId'];
          return QrScanScreen(attachTransferId: attachTransferId);
        },
      ),
      GoRoute(
        path: '/receive-qr',
        builder: (context, state) => const ReceiveQrScreen(),
      ),
      GoRoute(
        path: '/download-progress/:transferId',
        builder: (context, state) {
          final transferId = state.pathParameters['transferId'] ?? '';
          final aesKey = state.uri.queryParameters['aesKey'] ?? '';
          return DownloadProgressScreen(transferId: transferId, aesKey: aesKey);
        },
      ),
      // Deep Link handler for Sender QR codes (e.g. https://lynk.app/send/:transferId#aesKey)
      GoRoute(
        path: '/send/:transferId',
        builder: (context, state) {
          final transferId = state.pathParameters['transferId'] ?? '';
          final aesKey = state.uri.fragment.isNotEmpty
              ? state.uri.fragment
              : (state.uri.queryParameters['aesKey'] ?? '');
          return DownloadProgressScreen(transferId: transferId, aesKey: aesKey);
        },
      ),
    ],
  );
}
