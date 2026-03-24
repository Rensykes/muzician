/// Shared "notes outside the key" conflict dialog used by scale pickers.
library;

import 'package:flutter/material.dart';
import '../../theme/muzician_theme.dart';

class ScaleConflictDialog extends StatelessWidget {
  final List<String> conflictingNotes;
  const ScaleConflictDialog({super.key, required this.conflictingNotes});

  @override
  Widget build(BuildContext context) {
    final noteStr = conflictingNotes.join(', ');
    final isPlural = conflictingNotes.length > 1;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Notes outside the key',
        style: TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        '${isPlural ? 'Notes' : 'Note'} $noteStr '
        '${isPlural ? 'are' : 'is'} outside this scale. '
        'Remove ${isPlural ? 'them' : 'it'} to apply the scale highlight?',
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Remove & Apply',
            style: TextStyle(
              color: MuzicianTheme.sky,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
