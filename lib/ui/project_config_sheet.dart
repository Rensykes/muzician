library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../schema/rules/save_system_rules.dart';
import '../store/save_system_store.dart';

class ProjectConfigSheet extends ConsumerStatefulWidget {
  final String projectId;
  const ProjectConfigSheet({super.key, required this.projectId});

  static Future<void> show(BuildContext context, String projectId) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF141826),
        isScrollControlled: true,
        builder: (_) => ProjectConfigSheet(projectId: projectId),
      );

  @override
  ConsumerState<ProjectConfigSheet> createState() => _ProjectConfigSheetState();
}

class _ProjectConfigSheetState extends ConsumerState<ProjectConfigSheet> {
  late ProjectConfig _draft;

  @override
  void initState() {
    super.initState();
    final folder = ref.read(saveSystemProvider).folders
        .firstWhere((f) => f.id == widget.projectId);
    _draft = folder.projectConfig ?? const ProjectConfig();
  }

  Future<void> _save() async {
    final state = ref.read(saveSystemProvider);
    final folder = state.folders.firstWhere((f) => f.id == widget.projectId);
    final current = folder.projectConfig ?? const ProjectConfig();
    final changed = current.tempo != _draft.tempo ||
        current.beatsPerBar != _draft.beatsPerBar ||
        current.beatUnit != _draft.beatUnit ||
        current.keyRootPc != _draft.keyRootPc ||
        current.keyScaleName != _draft.keyScaleName;
    if (!changed) {
      Navigator.of(context).pop();
      return;
    }
    final affected = getSavesInSubtree(state.folders, state.saves, widget.projectId).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply project config?'),
        content: Text('$affected saves will be retuned / retimed. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(saveSystemProvider.notifier)
        .applyProjectConfig(widget.projectId, _draft, retrofit: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Project Config',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(labelText: 'Tempo (BPM)'),
          keyboardType: TextInputType.number,
          controller: TextEditingController(text: _draft.tempo.toString()),
          onChanged: (v) => setState(() {
            _draft = _draft.copyWith(tempo: int.tryParse(v) ?? _draft.tempo);
          }),
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _save, child: const Text('Apply')),
      ]),
    ));
  }
}
