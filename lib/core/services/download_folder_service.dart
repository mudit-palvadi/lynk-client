import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The folder finished downloads are written to, chosen by the user.
///
/// Android's scoped storage does not allow writing into a public folder by
/// path, so the folder is picked once through the storage access framework and
/// its tree URI is kept. Every finished file is then copied into it by the
/// native side, which holds the grant.
class DownloadFolderService {
  DownloadFolderService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'lynk/storage';
  static const String _treeKey = 'lynk_download_tree_uri';

  final MethodChannel _channel;

  /// The chosen folder, or null while downloads stay in app storage.
  Future<String?> treeUri() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_treeKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Opens the system folder picker and remembers the choice.
  ///
  /// Returns the chosen tree URI, or null when the user backed out.
  Future<String?> choose() async {
    final picked = await _channel.invokeMethod<String>('pickFolder');
    if (picked == null || picked.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_treeKey, picked);
    return picked;
  }

  /// Forgets the chosen folder, so downloads go back to app storage.
  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_treeKey);
  }

  /// Copies [sourcePath] into the chosen folder.
  ///
  /// Returns the new document URI, or null when no folder has been chosen.
  Future<String?> publish({
    required String sourcePath,
    required String fileName,
  }) async {
    final tree = await treeUri();
    if (tree == null) return null;
    return _channel.invokeMethod<String>('publish', {
      'treeUri': tree,
      'sourcePath': sourcePath,
      'fileName': fileName,
      'mimeType': mimeTypeFor(fileName),
    });
  }

  /// Opens a delivered document with whatever app handles its type.
  Future<bool> open(String uri) async {
    final opened = await _channel.invokeMethod<bool>('open', {'uri': uri});
    return opened ?? false;
  }

  /// A short, human name for a tree URI.
  ///
  /// `content://com.android.externalstorage.documents/tree/primary%3ADownload%2FLynk`
  /// reads as `Download / Lynk`.
  static String displayName(String treeUri) {
    final decoded = Uri.decodeFull(treeUri);
    final marker = decoded.indexOf('/tree/');
    if (marker < 0) return 'Chosen folder';
    var id = decoded.substring(marker + '/tree/'.length);
    final document = id.indexOf('/document/');
    if (document >= 0) id = id.substring(0, document);
    final colon = id.indexOf(':');
    final path = colon >= 0 ? id.substring(colon + 1) : id;
    if (path.isEmpty) return 'Device storage';
    return path.split('/').where((part) => part.isNotEmpty).join(' / ');
  }

  /// The MIME type a document should be created with, so that the system can
  /// open it again from the folder.
  static String mimeTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }
}
