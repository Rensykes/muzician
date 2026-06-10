library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/save_system.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
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
      accent = MuzicianTheme.orange;
      icon = Icons.folder_off_outlined;
      title = 'No project';
    } else if (selected.kind == SaveFolderKind.dump) {
      accent = MuzicianTheme.textSecondary;
      icon = Icons.archive_outlined;
      title = 'Dump';
    } else {
      accent = MuzicianTheme.emerald;
      icon = Icons.music_note;
      title = selected.name;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ProjectPickerSheet.show(context, allowDump: allowDump),
        borderRadius: BorderRadius.circular(999),
        child: Container(
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
    );
  }
}
