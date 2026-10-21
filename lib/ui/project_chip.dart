library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/save_system.dart';
import '../store/save_system_store.dart';
import '../theme/studio_theme.dart';
import 'project_picker_sheet.dart';

/// Compact glass chip showing the active project (or Dump, or none).
///
/// Tap → bottom-sheet picker. Layout: icon + project name on top line,
/// optional key / tempo / time-signature subtitle below, in the accent color
/// that matches the chip's role (emerald = project, slate = dump, orange =
/// no selection).
class ProjectChip extends ConsumerWidget {
  final bool allowDump;
  const ProjectChip({super.key, this.allowDump = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);

    final Color accent;
    final IconData icon;
    final String title;

    if (selected == null) {
      accent = StudioPalette.of(context).orange;
      icon = Icons.folder_off_outlined;
      title = 'No project';
    } else if (selected.kind == SaveFolderKind.dump) {
      accent = StudioPalette.of(context).textSecondary;
      icon = Icons.archive_outlined;
      title = 'Dump';
    } else {
      accent = StudioPalette.of(context).emerald;
      icon = Icons.music_note;
      title = selected.name;
    }

    if (StudioPalette.of(context).isStudio) {
      final p = StudioPalette.of(context);
      return Tooltip(
        message: title,
        child: Semantics(
          label: 'Project: $title',
          button: true,
          child: InkWell(
            onTap: () => ProjectPickerSheet.show(context, allowDump: allowDump),
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, maxWidth: 240),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: p.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: title,
      child: Semantics(
        label: 'Project: $title',
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => ProjectPickerSheet.show(context, allowDump: allowDump),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: BoxConstraints(
                minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 0.6,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: accent, size: 12),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 86),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
