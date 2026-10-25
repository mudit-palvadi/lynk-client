import '../../features/file_transfer/domain/entities/transfer.dart';

/// In-process navigation only: never serialize credentials into a location or
/// restoration codec. External share links use their separate fragment parser.
class SendQrArguments {
  const SendQrArguments({required this.transfer, required this.aesKey});

  final Transfer transfer;
  final String aesKey;

  bool get isValid => transfer.id.isNotEmpty && aesKey.isNotEmpty;
}

class DownloadArguments {
  const DownloadArguments({
    required this.transferId,
    required this.aesKey,
    this.accessToken = '',
    this.viaPairing = false,
  });

  final String transferId;
  final String aesKey;
  final String accessToken;
  final bool viaPairing;

  String get location =>
      Uri(pathSegments: ['', 'download-progress', transferId]).toString();

  bool matches(String routeTransferId) =>
      transferId.isNotEmpty &&
      transferId == routeTransferId &&
      aesKey.isNotEmpty;
}
