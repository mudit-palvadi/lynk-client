import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Role and next action stay visible above either kind of transfer QR.
class TransferRoleHeading extends StatelessWidget {
  const TransferRoleHeading({
    super.key,
    required this.role,
    required this.title,
    required this.instruction,
    required this.icon,
  });

  final String role;
  final String title;
  final String instruction;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            Text(role, textAlign: TextAlign.center),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        instruction,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textSecondary),
      ),
    ],
  );
}
