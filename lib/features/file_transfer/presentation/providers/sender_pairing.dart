import '../../../../core/services/key_wrap_service.dart';
import '../../data/datasources/sender_session_remote_data_source.dart';

/// Wraps the transfer key for the receiver's public key.
typedef KeyWrapper =
    Future<String> Function({
      required String aesKey,
      required String receiverPublicKeyB64,
      required String sessionId,
      String? accessToken,
    });

/// Where a sender pairing stands.
enum SenderPairingStatus { idle, waiting, attached, failed }

/// Mints the six-digit code the receiver types, then waits for it to join.
///
/// The sender keeps the AES key the whole time: once a receiver publishes its
/// public key the key is wrapped for it and handed to the backend, which can
/// never open it.
class SenderPairing {
  SenderPairing({
    required this.dataSource,
    required this.transferId,
    required this.aesKey,
    this.accessToken,
    this.mode = 'cloud',
    KeyWrapper? wrapKey,
  }) : _wrap = wrapKey ?? _defaultWrap;

  static Future<String> _defaultWrap({
    required String aesKey,
    required String receiverPublicKeyB64,
    required String sessionId,
    String? accessToken,
  }) => KeyWrapService().wrapKey(
    aesKey: aesKey,
    receiverPublicKeyB64: receiverPublicKeyB64,
    sessionId: sessionId,
    accessToken: accessToken,
  );

  final SenderSessionRemoteDataSource dataSource;
  final String transferId;
  final String aesKey;

  /// Travelling inside the wrapped payload, so the receiver can download the
  /// files from storage after the code is used.
  final String? accessToken;

  /// "cloud" or "p2p", so the receiver knows what to wait for.
  final String mode;

  final KeyWrapper _wrap;

  String? sessionId;
  String? code;
  String? senderSecret;
  String? receiverPublicKey;
  String? error;
  SenderPairingStatus status = SenderPairingStatus.idle;

  bool get isAttached => status == SenderPairingStatus.attached;

  /// Creates the session and exposes the code to show on screen.
  Future<bool> start() async {
    try {
      final session = await dataSource.createSession();
      sessionId = session.sessionId;
      code = session.code;
      senderSecret = session.senderSecret;
      status = SenderPairingStatus.waiting;
      return true;
    } catch (e) {
      error = e.toString();
      status = SenderPairingStatus.failed;
      return false;
    }
  }

  /// Asks once whether a receiver has joined.
  ///
  /// Returns true while the caller should keep polling; a joined receiver
  /// wraps the key, attaches it and stops the loop.
  Future<bool> poll() async {
    final id = sessionId;
    if (id == null || isAttached) return false;

    try {
      final session = await dataSource.getSession(id);
      final receiverPk = session.receiverPk;
      if (receiverPk == null || receiverPk.isEmpty) {
        status = SenderPairingStatus.waiting;
        return true;
      }
      receiverPublicKey = receiverPk;

      final wrapped = await _wrap(
        aesKey: aesKey,
        receiverPublicKeyB64: receiverPk,
        sessionId: id,
        accessToken: accessToken,
      );
      await dataSource.attachKey(
        sessionId: id,
        transferId: transferId,
        wrappedKey: wrapped,
        mode: mode,
        senderSecret: senderSecret ?? '',
      );
      status = SenderPairingStatus.attached;
      return false;
    } catch (e) {
      error = e.toString();
      status = SenderPairingStatus.failed;
      return false;
    }
  }
}
