library;

import 'package:flutter/material.dart';
import '../theme/muzician_theme.dart';
import 'project_picker_sheet.dart';

/// Empty-state shown by Song / Songwriter save panels when no project is
/// selected (or Dump is selected, which is disallowed for arrangement saves).
/// Renders a compact glass card with the message and a button that opens the
/// project picker — no forced modal, no full-screen takeover.
class ProjectRequiredPlaceholder extends StatelessWidget {
  final String message;
  final bool allowDump;

  const ProjectRequiredPlaceholder({
    super.key,
    required this.message,
    this.allowDump = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: MuzicianTheme.glassBg,
          border: Border.all(color: MuzicianTheme.glassBorder, width: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_open_outlined,
              color: MuzicianTheme.textMuted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () =>
                  ProjectPickerSheet.show(context, allowDump: allowDump),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: MuzicianTheme.sky.withValues(alpha: 0.14),
                  border: Border.all(
                    color: MuzicianTheme.sky.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Choose project',
                  style: TextStyle(
                    color: MuzicianTheme.sky,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
