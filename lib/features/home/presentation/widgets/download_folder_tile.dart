import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/download_folder_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Shows where downloads are saved and lets the user point them elsewhere.
///
/// The picker is Android's own folder chooser, and the grant is remembered, so
/// this only has to be answered once. Until it is, finished files stay in the
/// app's own folder, which needs no permission but is not easy to find.
class DownloadFolderTile extends StatefulWidget {
  const DownloadFolderTile({super.key});

  @override
  State<DownloadFolderTile> createState() => _DownloadFolderTileState();
}

class _DownloadFolderTileState extends State<DownloadFolderTile> {
  final DownloadFolderService _folder = DownloadFolderService();
  String? _treeUri;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uri = await _folder.treeUri();
    if (mounted) setState(() => _treeUri = uri);
  }

  Future<void> _choose() async {
    if (_busy) return;
    if (kIsWeb || !Platform.isAndroid) {
      _say('Choosing a download folder is available on Android.');
      return;
    }

    setState(() => _busy = true);
    try {
      final picked = await _folder.choose();
      if (!mounted) return;
      if (picked != null) {
        setState(() => _treeUri = picked);
        _say('Downloads will be saved to ${DownloadFolderService.displayName(picked)}.');
      }
    } on PlatformException {
      if (mounted) _say('Could not open the folder picker.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final treeUri = _treeUri;
    final label = treeUri == null
        ? 'App storage — tap to choose a folder'
        : DownloadFolderService.displayName(treeUri);

    return InkWell(
      onTap: _busy ? null : _choose,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E364F), width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.folder_outlined,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Download folder',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppTheme.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
