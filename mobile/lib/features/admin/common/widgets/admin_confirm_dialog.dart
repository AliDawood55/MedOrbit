import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// One confirmation dialog shape for every consequential administration
/// action, so approving an application, deactivating an account, revoking an
/// invitation, and moderating a post all read the same way.
///
/// `scrollable: true` plus the reduced inset padding keeps the dialog usable
/// on a 320 px screen at large text scales, where a fixed-height dialog would
/// clip its actions.
Future<bool> showAdminConfirmDialog({
  required BuildContext context,
  required AppStrings strings,
  required String title,
  required String body,
  required String confirmLabel,
  required IconData icon,
  required Color tone,
  Key? confirmKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceLg,
        vertical: AppTheme.spaceXl,
      ),
      icon: Icon(icon, color: tone, size: AppTheme.iconXl),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(body, textAlign: TextAlign.center),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton.icon(
          key: confirmKey,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: tone,
            foregroundColor: Colors.white,
          ),
          icon: Icon(icon),
          label: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
