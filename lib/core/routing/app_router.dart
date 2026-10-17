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

/// Parsed target of a sender-QR deep link (`/send/{transferId}#{aesKey}`).
///
/// The AES key lives exclusively in the URL `#fragment` (client-side only,
/// Memory.md Rule 4); a legacy `?aesKey=` query param is honored as fallback.
class DeepLinkTarget {
  final String transferId;
  final String aesKey;

  const DeepLinkTarget({required this.transferId, required this.aesKey});
}

/// Extracts [DeepLinkTarget] from a deep-link URI.
///
/// Fragment wins over query parameter when both are present; missing values
/// degrade to empty strings instead of throwing. Any `?query` riding inside
/// the fragment (e.g. appended tracking params) is stripped from the key.
DeepLinkTarget parseSendDeepLink(Uri uri) {
  final transferId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  final rawFragment = uri.fragment.split('?').first;
  final aesKey = rawFragment.isNotEmpty
      ? rawFragment
      : (uri.queryParameters['aesKey'] ?? '');
  return DeepLinkTarget(transferId: transferId, aesKey: aesKey);
}

/// Parsed target of a receiver-QR deep link (`/receive/{sessionId}#pk={key}`).
///
/// The receiver's ephemeral public key lives exclusively in the URL `#fragment`
/// (client-side only, Memory.md Rule 4); it wraps the AES key for pairing.
class ReceiveDeepLinkTarget {
  final String sessionId;
  final String receiverPk;

  const ReceiveDeepLinkTarget({
    required this.sessionId,
    required this.receiverPk,
  });
}

/// Extracts [ReceiveDeepLinkTarget] from a deep-link URI.
///
/// Mirrors `QrScanHelper.extractReceiveSessionIdAndPublicKey`: the fragment
/// must start with `pk=` for a public key to be extracted; missing values
/// degrade to empty strings instead of throwing.
ReceiveDeepLinkTarget parseReceiveDeepLink(Uri uri) {
  final sessionId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  final fragment = uri.fragment;
  final receiverPk = fragment.startsWith('pk=') ? fragment.substring(3) : '';
  return ReceiveDeepLinkTarget(sessionId: sessionId, receiverPk: receiverPk);
}

/// Builds the upload location that pairs the sender with a receiver session.
///
/// Mirrors `QrScanHelper.handleReceiveSession` for camera-scanned receiver
/// QRs: the upload screen receives the session id and the receiver public key,
/// then attaches the transfer and wraps the AES key client-side.
String receiveUploadLocation(ReceiveDeepLinkTarget target) {
  final pkParam = target.receiverPk.isNotEmpty
      ? '&pk=${Uri.encodeComponent(target.receiverPk)}'
      : '';
  return '/upload?attachToSessionId=${target.sessionId}$pkParam';
}

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
      GoRoute(
        path: '/send/:transferId',
        builder: (context, state) {
          final target = parseSendDeepLink(state.uri);
          return DownloadProgressScreen(
            transferId: target.transferId,
            aesKey: target.aesKey,
          );
        },
      ),
      GoRoute(
        path: '/receive/:sessionId',
        redirect: (context, state) {
          final target = parseReceiveDeepLink(state.uri);
          if (target.sessionId.isEmpty) {
            return '/home';
          }
          return receiveUploadLocation(target);
        },
      ),
    ],
  );
}
