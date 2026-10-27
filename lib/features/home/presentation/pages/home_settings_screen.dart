import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/config_service.dart';
import '../providers/home_navigation_provider.dart';
import '../widgets/download_folder_tile.dart';

class HomeSettingsScreen extends ConsumerWidget {
  const HomeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(homeVersionProvider).asData?.value ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Saved files',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Choose where received files are saved.'),
            const SizedBox(height: 20),
            const DownloadFolderTile(),
            const SizedBox(height: 32),
            Center(
              child: GestureDetector(
                onTap: !kDebugMode
                    ? null
                    : () {
                        if (ref
                            .read(diagnosticTapProvider.notifier)
                            .registerTap()) {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const _DiagnosticDialog(),
                          );
                        }
                      },
                child: Text(version),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticDialog extends StatefulWidget {
  const _DiagnosticDialog();

  @override
  State<_DiagnosticDialog> createState() => _DiagnosticDialogState();
}

class _DiagnosticDialogState extends State<_DiagnosticDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('System Diagnostic Key'),
    content: TextField(
      controller: _controller,
      obscureText: true,
      decoration: const InputDecoration(hintText: 'Enter config payload'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () async {
          final success = await ConfigService.applyConfigurationKey(
            _controller.text,
          );
          if (success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('System configuration updated.')),
            );
            Navigator.of(context).pop();
          }
        },
        child: const Text('Submit'),
      ),
    ],
  );
}
