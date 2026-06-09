library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/save_system.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
import '../utils/note_utils.dart';
import 'project_picker_sheet.dart';

class ProjectChip extends ConsumerWidget {
  final bool allowDump;
  const ProjectChip({super.key, this.allowDump = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    final Color color;
    final String label;
    if (selected == null) {
      color = MuzicianTheme.orange;
      label = 'No project';
    } else if (selected.kind == SaveFolderKind.dump) {
      color = MuzicianTheme.textSecondary;
      label = '📦 Dump';
    } else {
      color = MuzicianTheme.emerald;
      final cfg = selected.projectConfig;
      final key = (cfg?.keyRootPc == null) ? '' : ' · ${chromaticNotes[cfg!.keyRootPc!]} ${cfg.keyScaleName ?? ''}';
      label = '🎵 ${selected.name}$key · ${cfg?.tempo ?? 120}';
    }
    return GestureDetector(
      onTap: () => ProjectPickerSheet.show(context, allowDump: allowDump),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
