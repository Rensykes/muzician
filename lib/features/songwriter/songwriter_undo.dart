import 'package:flutter/material.dart';

/// Shows a SnackBar with an Undo action. Used for section/lane/block deletes:
/// the caller deletes immediately, then calls this with a restore closure.
void showUndoSnack(BuildContext context, String message, VoidCallback onUndo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
}
