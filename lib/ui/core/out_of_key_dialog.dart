/// Shared "outside the key" confirmation dialog used by both fretboard and piano.
library;

import 'package:flutter/material.dart';
import '../../theme/muzician_theme.dart';

/// Carries the dialog result: whether the user confirmed and whether they want
/// to suppress future alerts.
class OutOfKeyResult {
  final bool suppress;
  const OutOfKeyResult({required this.suppress});
}

class OutOfKeyDialog extends StatefulWidget {
  const OutOfKeyDialog({super.key});

  @override
  State<OutOfKeyDialog> createState() => _OutOfKeyDialogState();
}

class _OutOfKeyDialogState extends State<OutOfKeyDialog> {
  bool _suppress = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Outside the key',
        style: TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This note is outside the highlighted scale. Adding it will clear the scale highlight.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _suppress = !_suppress),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _suppress
                        ? MuzicianTheme.sky.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: _suppress
                          ? MuzicianTheme.sky
                          : Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: _suppress
                      ? const Icon(Icons.check, size: 12, color: MuzicianTheme.sky)
                      : null,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Don't show this again",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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
          onPressed: () =>
              Navigator.of(context).pop(OutOfKeyResult(suppress: _suppress)),
          child: const Text(
            'Continue',
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
