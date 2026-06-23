/// Shared "notes outside the key" conflict dialog used by scale pickers.
library;

import 'package:flutter/material.dart';
import 'muzician_dialog.dart';

class ScaleConflictDialog extends StatelessWidget {
  final List<String> conflictingNotes;
  const ScaleConflictDialog({super.key, required this.conflictingNotes});

  @override
  Widget build(BuildContext context) {
    final noteStr = conflictingNotes.join(', ');
    final isPlural = conflictingNotes.length > 1;
    return MuzicianDialog(
      title: 'Notes outside the key',
      content: Text(
        '${isPlural ? 'Notes' : 'Note'} $noteStr '
        '${isPlural ? 'are' : 'is'} outside this scale. '
        'Remove ${isPlural ? 'them' : 'it'} to apply the scale highlight?',
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        MuzicianDialogButton(
          'Remove & Apply',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
