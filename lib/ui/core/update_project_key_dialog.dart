/// Confirmation dialog shown when the user changes the scale in an instrument
/// picker while a project key is set. Accepting promotes the change to the
/// project config (every save under the project inherits the new key);
/// dismissing leaves the project untouched.
library;

import 'package:flutter/material.dart';
import 'muzician_dialog.dart';

class UpdateProjectKeyDialog extends StatelessWidget {
  final String currentLabel;
  final String newLabel;
  final int affectedSaves;

  const UpdateProjectKeyDialog({
    super.key,
    required this.currentLabel,
    required this.newLabel,
    required this.affectedSaves,
  });

  static Future<bool> ask(
    BuildContext context, {
    required String currentLabel,
    required String newLabel,
    required int affectedSaves,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => UpdateProjectKeyDialog(
        currentLabel: currentLabel,
        newLabel: newLabel,
        affectedSaves: affectedSaves,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final detail = affectedSaves == 0
        ? 'No saves under this project yet — the new key applies going forward.'
        : '$affectedSaves save${affectedSaves == 1 ? '' : 's'} under this '
            'project will inherit the new key. Notes outside the new scale '
            'will be flagged with a warning.';
    return MuzicianDialog(
      title: 'Update project key?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change project key from $currentLabel to $newLabel?'),
          const SizedBox(height: 10),
          Text(detail, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        MuzicianDialogButton(
          'Update',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
