library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../schema/rules/save_system_rules.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
import 'core/muzician_dialog.dart';
import '../utils/note_utils.dart';
import 'project_config_sheet.dart';

/// Bottom-sheet project picker.
///
/// Sections:
///   - PROJECTS (with "+ New project" inline)
///   - SPARE (Dump tile, or "Use Dump" if missing) — hidden when allowDump=false
///   - EDIT CONFIG row when a project is currently active
class ProjectPickerSheet extends ConsumerWidget {
  final bool allowDump;
  const ProjectPickerSheet({super.key, this.allowDump = true});

  static Future<void> show(BuildContext context, {bool allowDump = true}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectPickerSheet(allowDump: allowDump),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsListProvider);
    final dump = ref.watch(dumpFolderProvider);
    final selectedId = ref.watch(
      saveSystemProvider.select((s) => s.selectedProjectId),
    );
    final activeProjectFolder = selectedId == null
        ? null
        : ref
            .read(saveSystemProvider)
            .folders
            .where((f) => f.id == selectedId && f.kind == SaveFolderKind.project)
            .firstOrNull;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141826),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0x33FFFFFF), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DragHandle(),
              const SizedBox(height: 8),
              _SectionHeader(label: 'PROJECTS'),
              const SizedBox(height: 8),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No projects yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              for (final p in projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ProjectTile(
                    folder: p,
                    isActive: p.id == selectedId,
                    onTap: () {
                      ref
                          .read(saveSystemProvider.notifier)
                          .selectProject(p.id);
                      Navigator.of(context).pop();
                    },
                    onDelete: () => _confirmDeleteProject(context, ref, p),
                  ),
                ),
              const SizedBox(height: 4),
              _PrimaryAction(
                icon: Icons.add,
                label: 'New project',
                accent: MuzicianTheme.sky,
                onTap: () async {
                  final name = await _promptName(
                    context,
                    title: 'New project',
                  );
                  if (name == null || name.isEmpty) return;
                  final id = ref
                      .read(saveSystemProvider.notifier)
                      .createProject(name, const ProjectConfig());
                  if (id != null) {
                    ref
                        .read(saveSystemProvider.notifier)
                        .selectProject(id);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              if (activeProjectFolder != null) ...[
                const SizedBox(height: 6),
                _PrimaryAction(
                  icon: Icons.tune,
                  label: 'Edit project config',
                  accent: MuzicianTheme.violet,
                  onTap: () {
                    Navigator.of(context).pop();
                    ProjectConfigSheet.show(context, activeProjectFolder.id);
                  },
                ),
              ],
              if (allowDump) ...[
                const SizedBox(height: 14),
                _SectionHeader(label: 'SPARE'),
                const SizedBox(height: 8),
                if (dump != null)
                  _ProjectTile(
                    folder: dump,
                    isActive: dump.id == selectedId,
                    onTap: () {
                      ref
                          .read(saveSystemProvider.notifier)
                          .selectProject(dump.id);
                      Navigator.of(context).pop();
                    },
                  )
                else
                  _PrimaryAction(
                    icon: Icons.archive_outlined,
                    label: 'Use Dump',
                    accent: MuzicianTheme.textSecondary,
                    onTap: () {
                      final id = ref
                          .read(saveSystemProvider.notifier)
                          .ensureDumpFolder();
                      ref
                          .read(saveSystemProvider.notifier)
                          .selectProject(id);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: MuzicianTheme.textDim,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: MuzicianTheme.textDim,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final SaveFolder folder;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const _ProjectTile({
    required this.folder,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  String? _subtitle() {
    final cfg = folder.projectConfig;
    if (cfg == null) return null;
    final parts = <String>[];
    if (cfg.keyRootPc != null) {
      parts.add(
        '${chromaticNotes[cfg.keyRootPc!]} ${cfg.keyScaleName ?? ""}'.trim(),
      );
    }
    parts.add('${cfg.tempo} bpm');
    parts.add('${cfg.beatsPerBar}/${cfg.beatUnit}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final isDump = folder.kind == SaveFolderKind.dump;
    final accent = isDump ? MuzicianTheme.textSecondary : MuzicianTheme.emerald;
    final subtitle = _subtitle();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: isActive
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
              width: 0.6,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isDump ? Icons.archive_outlined : Icons.music_note,
                  color: accent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MuzicianTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'active',
                    style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              if (!isDump && onDelete != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Delete project',
                  icon: Icon(
                    Icons.delete_outline,
                    color: MuzicianTheme.red.withValues(alpha: 0.85),
                  ),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteProject(
  BuildContext context,
  WidgetRef ref,
  SaveFolder project,
) async {
  final state = ref.read(saveSystemProvider);
  final saves = getSavesInSubtree(state.folders, state.saves, project.id);
  final folderIds = getSubtreeFolderIds(state.folders, project.id);
  final folderCount = folderIds.length - 1;
  final body = saves.isEmpty
      ? 'Delete "${project.name}"? It has no saves.'
      : 'Delete "${project.name}"?\n\n'
          'This will permanently remove '
          '${saves.length} save${saves.length == 1 ? '' : 's'}'
          '${folderCount > 0 ? ' and $folderCount subfolder${folderCount == 1 ? '' : 's'}' : ''}.\n\n'
          'This cannot be undone.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => MuzicianDialog(
      title: 'Delete project?',
      content: Text(body),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        MuzicianDialogButton(
          'Delete',
          emphasis: MuzicianDialogEmphasis.destructive,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  ref.read(saveSystemProvider.notifier).deleteProject(project.id);
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            border: Border.all(
              color: accent.withValues(alpha: 0.40),
              width: 0.6,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptName(
  BuildContext context, {
  required String title,
}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => MuzicianDialog(
      title: title,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Project name…',
          hintStyle: TextStyle(color: MuzicianTheme.textMuted),
        ),
        onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.pop(ctx),
        ),
        MuzicianDialogButton(
          'OK',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
        ),
      ],
    ),
  );
}
