import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// Shows a themed SnackBar with Undo + dismiss actions.
void showUndoSnack(BuildContext context, String message, VoidCallback onUndo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: MuzicianTheme.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: MuzicianTheme.glassBorder),
      ),
      duration: const Duration(seconds: 4),
      content: Text(
        message,
        style: const TextStyle(
          color: MuzicianTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      action: SnackBarAction(
        label: 'Undo',
        textColor: MuzicianTheme.sky,
        onPressed: onUndo,
      ),
      dismissDirection: DismissDirection.horizontal,
    ),
  );
}
