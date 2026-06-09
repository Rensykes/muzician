import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../ui/project_chip.dart';
import '../../ui/project_gate_modal.dart';
import 'songwriter_header.dart';
import 'songwriter_save_panel.dart';
import 'songwriter_section_card.dart';
import 'songwriter_structure_editor.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key});

  void _openSaveLoad(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SizedBox(height: 480, child: SongwriterSavePanel()),
    );
  }

  void _openStructure(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SongwriterStructureEditor(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ProjectGateModal.show(context, allowDump: false, allowCancel: false);
      });
    }

    final notifier = ref.watch(songwriterProvider.notifier);
    final project = ref.watch(songwriterProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SongwriterHeader(
              onOpenSaveLoad: () => _openSaveLoad(context),
              onOpenStructure: () => _openStructure(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: ProjectChip(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (project.sections.isEmpty)
                    const Padding(
                      key: Key('songwriterEmptyHint'),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Build a song: add a section, add lanes '
                        '(harmony + saves), then drop chord and voicing blocks.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  for (final section in project.sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SongwriterSectionCard(sectionId: section.id),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('songwriterAddSection'),
                      onPressed: () =>
                          notifier.addSection(label: null, lengthBars: 8),
                      icon: const Icon(Icons.add),
                      label: const Text('Add section'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
