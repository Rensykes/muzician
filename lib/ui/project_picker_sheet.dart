library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
import '../utils/note_utils.dart';
import 'project_config_sheet.dart';

class ProjectPickerSheet extends ConsumerWidget {
  final bool allowDump;
  const ProjectPickerSheet({super.key, this.allowDump = true});

  static Future<void> show(BuildContext context, {bool allowDump = true}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141826),
      isScrollControlled: true,
      builder: (_) => ProjectPickerSheet(allowDump: allowDump),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsListProvider);
    final dump = ref.watch(dumpFolderProvider);
    final selectedId = ref.watch(saveSystemProvider.select((s) => s.selectedProjectId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PROJECTS',
                style: TextStyle(
                    color: MuzicianTheme.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final p in projects) _ProjectTile(
              folder: p,
              isActive: p.id == selectedId,
              onTap: () {
                ref.read(saveSystemProvider.notifier).selectProject(p.id);
                Navigator.of(context).pop();
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New project'),
              onPressed: () async {
                final name = await _promptName(context, title: 'New project');
                if (name == null || name.isEmpty) return;
                final id = ref.read(saveSystemProvider.notifier)
                    .createProject(name, const ProjectConfig());
                if (id != null) {
                  ref.read(saveSystemProvider.notifier).selectProject(id);
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            if (selectedId != null &&
                ref.read(saveSystemProvider).folders
                    .where((f) => f.id == selectedId).firstOrNull?.kind ==
                    SaveFolderKind.project) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Edit project config'),
                onPressed: () {
                  Navigator.of(context).pop();
                  ProjectConfigSheet.show(context, selectedId);
                },
              ),
            ],
            if (allowDump && (dump != null)) ...[
              const Divider(),
              const Text('SPARE',
                  style: TextStyle(
                      color: MuzicianTheme.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              _ProjectTile(
                folder: dump,
                isActive: dump.id == selectedId,
                onTap: () {
                  ref.read(saveSystemProvider.notifier).selectProject(dump.id);
                  Navigator.of(context).pop();
                },
              ),
            ] else if (allowDump && dump == null) ...[
              const Divider(),
              TextButton.icon(
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Use Dump'),
                onPressed: () {
                  final id = ref.read(saveSystemProvider.notifier).ensureDumpFolder();
                  ref.read(saveSystemProvider.notifier).selectProject(id);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final SaveFolder folder;
  final bool isActive;
  final VoidCallback onTap;
  const _ProjectTile({required this.folder, required this.isActive, required this.onTap});

  String _subtitle() {
    final cfg = folder.projectConfig;
    if (cfg == null) return '';
    final key = cfg.keyRootPc == null
        ? '—'
        : '${chromaticNotes[cfg.keyRootPc!]} ${cfg.keyScaleName ?? ''}'.trim();
    return '$key · ${cfg.tempo} · ${cfg.beatsPerBar}/${cfg.beatUnit}';
  }

  @override
  Widget build(BuildContext context) {
    final icon = folder.kind == SaveFolderKind.dump ? '📦' : '🎵';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Text(icon),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(folder.name,
                    style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (_subtitle().isNotEmpty)
                  Text(_subtitle(),
                      style: const TextStyle(
                          color: MuzicianTheme.textDim, fontSize: 11)),
              ],
            ),
          ),
          if (isActive)
            const Text('☆', style: TextStyle(color: MuzicianTheme.emerald)),
        ]),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context, {required String title}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}
