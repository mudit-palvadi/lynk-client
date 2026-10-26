import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/file_receive/presentation/pages/enter_code_screen.dart';
import '../../features/file_receive/presentation/pages/receive_qr_screen.dart';
import '../../features/file_transfer/presentation/pages/download_progress_screen.dart';
import '../../features/file_transfer/presentation/pages/file_upload_screen.dart';
import '../../features/file_transfer/presentation/pages/qr_scan_screen.dart';
import '../../features/file_transfer/presentation/pages/send_qr_screen.dart';
import '../../features/home/presentation/pages/home_screen.dart';
import '../../features/home/presentation/pages/home_settings_screen.dart';
import '../../features/onboarding/presentation/pages/onboarding_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../widgets/not_found_screen.dart';
import 'pending_deep_link.dart';
import 'send_link_capability.dart';
import 'transfer_route_args.dart';

part 'app_router.g.dart';

/// Parsed target of a sender-QR deep link (`/send/{transferId}#{aesKey}`).
///
/// The AES key lives exclusively in the URL `#fragment` (client-side only,
/// Memory.md Rule 4); a legacy `?aesKey=` query param is honored as fallback.
class DeepLinkTarget {
  final String transferId;
  final String aesKey;

  /// Capability for metadata and download. Lives in the fragment, never the path.
  final String accessToken;

  const DeepLinkTarget({
    required this.transferId,
    required this.aesKey,
    this.accessToken = '',
  });
}

/// Extracts [DeepLinkTarget] from a deep-link URI.
///
/// Fragment wins over query parameter when both are present; missing values
/// degrade to empty strings instead of throwing. Any `?query` riding inside
/// the fragment (e.g. appended tracking params) is stripped from the key.
DeepLinkTarget parseSendDeepLink(Uri uri) {
  final transferId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  final rawFragment = uri.fragment.split('?').first;
  final split = splitFragmentCapability(rawFragment);
  final aesKey = split.aesKey.isNotEmpty
      ? split.aesKey
      : (uri.queryParameters['aesKey'] ?? '');
  final accessToken = split.accessToken.isNotEmpty
      ? split.accessToken
      : (uri.queryParameters['a'] ?? '');
  return DeepLinkTarget(
    transferId: transferId,
    aesKey: aesKey,
    accessToken: accessToken,
  );
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

/// Whether [uri] targets a transfer deep link rather than normal app chrome.
///
/// Only these locations carry key material in their fragment, so only these
/// are worth replaying after onboarding.
bool isTransferDeepLink(Uri uri) =>
    uri.path.startsWith('/send/') || uri.path.startsWith('/receive/');

/// Strips scheme and host from a transfer link, keeping path, query and
/// fragment. The result is a location the router can replay verbatim.
String canonicalDeepLinkLocation(Uri uri) => Uri(
  path: uri.path,
  query: uri.hasQuery ? uri.query : null,
  fragment: uri.hasFragment ? uri.fragment : null,
).toString();

/// Maps the offline `lynk://` custom scheme onto the canonical app location.
///
/// Android delivers `lynk://send/{id}#{key}` with `send` as the URI *host* and
/// `{id}` as the first path segment, which no `/send/:transferId` route can
/// match — go_router would land on the not-found screen. This rewrites both
/// custom-scheme shapes to the same path the `https://` deep link uses, so a
/// single route handles both forms:
///
/// * `lynk://send/{id}#{key}`   → `/send/{id}#{key}`
/// * `lynk://receive/{id}#pk={key}` → `/receive/{id}#pk={key}`
///
/// Returns `null` for every non-`lynk` URI and for unknown hosts, leaving
/// normal in-app navigation untouched. Query and fragment are preserved
/// byte-for-byte so the key material never has to be decoded and re-encoded.
String? normalizeCustomSchemeLink(Uri uri) {
  if (uri.scheme != 'lynk') return null;

  // `lynk://send/abc` puts `send` in the host and `abc` in the path;
  // `lynk:///send/abc` leaves the host empty and keeps both in the path.
  final List<String> segments = uri.host.isEmpty
      ? uri.pathSegments
      : <String>[uri.host, ...uri.pathSegments];
  if (segments.length < 2) return null;

  final target = segments.first;
  if (target != 'send' && target != 'receive') return null;

  return Uri(
    path: '/$target/${segments[1]}',
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

/// Builds the app router.
///
/// This provider deliberately `watch`es [onboardingProvider] and therefore
/// *rebuilds the whole router* when onboarding flips. That rebuild is
/// load-bearing for deep links: `GoRouter` prefers the platform's default
/// route (the deep link) over `initialLocation`, but only while the router is
/// being constructed. A cold-start link is first redirected to `/onboarding`,
/// which overwrites the router's current location; finishing onboarding
/// recreates the router, which re-reads the platform default and lands on the
/// link. A long-lived router with `refreshListenable` would lose that link.

@riverpod
GoRouter appRouter(Ref ref) {
  final hasOnboarded = ref.watch(onboardingProvider);

  // A link that arrived while the gate was up is replayed here: this provider
  // is rebuilt the moment onboarding completes, and `initialLocation` is what
  // the fresh router starts from when the platform default is `/` (warm
  // start). Cold-start links already survive via the platform default, and
  // replaying them is a harmless no-op because the location matches.
  final pendingLink = PendingDeepLink.take();

  return GoRouter(
    // When a link is waiting, it must win over the platform default. On a warm
    // start the platform default is `/` and `initialLocation` would win
    // anyway, but if the app was *itself* launched by a link, the default is
    // that older link — and the newest one the user just scanned is the one
    // they expect to open.
    initialLocation: pendingLink ?? (hasOnboarded ? '/home' : '/onboarding'),
    overridePlatformDefaultLocation: pendingLink != null,
    errorBuilder: (context, state) => NotFoundScreen(path: state.uri.path),
    redirect: (context, state) {
      // `lynk://` links arrive as scheme://host/path, which no route can
      // match. Rewrite them to the canonical path before any gate logic so
      // offline QR scans reach the same screens as https links.
      final normalized = normalizeCustomSchemeLink(state.uri);
      if (normalized != null) {
        return normalized;
      }

      final isOnboardingRoute = state.matchedLocation == '/onboarding';

      if (!hasOnboarded && !isOnboardingRoute) {
        // Remember transfer links only: everything else is ordinary app
        // chrome that the gate is allowed to drop. Storing the canonical form
        // keeps the key in the fragment and out of any route parameter.
        if (isTransferDeepLink(state.uri)) {
          PendingDeepLink.remember(canonicalDeepLinkLocation(state.uri));
        }
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
        path: '/settings',
        builder: (context, state) => const HomeSettingsScreen(),
      ),
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
          final args = state.extra;
          if (args is! SendQrArguments ||
              !args.isValid ||
              state.uri.hasQuery ||
              state.uri.hasFragment) {
            return NotFoundScreen(path: state.uri.path);
          }
          return SendQrScreen(transfer: args.transfer, aesKey: args.aesKey);
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
        path: '/receive-code',
        builder: (context, state) => const EnterCodeScreen(),
      ),
      GoRoute(
        path: '/download-progress/:transferId',
        builder: (context, state) {
          final transferId = state.pathParameters['transferId'] ?? '';
          final args = state.extra;
          if (args is! DownloadArguments ||
              !args.matches(transferId) ||
              state.uri.hasQuery ||
              state.uri.hasFragment) {
            return NotFoundScreen(path: state.uri.path);
          }
          return DownloadProgressScreen(
            transferId: transferId,
            aesKey: args.aesKey,
            accessToken: args.accessToken,
            viaPairing: args.viaPairing,
          );
        },
      ),
      GoRoute(
        path: '/send/:transferId',
        builder: (context, state) {
          final target = parseSendDeepLink(state.uri);
          return DownloadProgressScreen(
            transferId: target.transferId,
            aesKey: target.aesKey,
            accessToken: target.accessToken,
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
