library;

import 'package:flutter/material.dart';
import '../theme/studio_theme.dart';
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
          color: StudioPalette.of(context).glassBg,
          border: Border.all(
            color: StudioPalette.of(context).glassBorder,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              color: StudioPalette.of(context).textMuted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: StudioPalette.of(context).textSecondary,
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
                  color: StudioPalette.of(context).sky.withValues(alpha: 0.14),
                  border: Border.all(
                    color: StudioPalette.of(context).sky.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Choose project',
                  style: TextStyle(
                    color: StudioPalette.of(context).sky,
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
