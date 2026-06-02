import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/songwriter_store.dart';

/// "Modifica struttura della canzone" — bulk reorder/remove of sections.
/// Reuses the same store mutations as the inline section cards.
class SongwriterStructureEditor extends ConsumerWidget {
  const SongwriterStructureEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(songwriterProvider.select((p) => p.sections));
    final notifier = ref.read(songwriterProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit structure'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: sections.isEmpty
          ? const Center(child: Text('No sections yet.'))
          : ReorderableListView(
              padding: const EdgeInsets.all(12),
              onReorder: notifier.reorderSections,
              children: [
                for (final s in sections)
                  ListTile(
                    key: ValueKey(s.id),
                    title: Text(
                      s.label == null || s.label!.isEmpty
                          ? 'Section'
                          : s.label!,
                    ),
                    subtitle: Text(
                      '${s.lengthBars} bars · ${s.repeat}× · ${s.lanes.length} lanes',
                    ),
                    trailing: IconButton(
                      key: Key('structureRemove_${s.id}'),
                      icon: const Icon(Icons.close),
                      onPressed: () => notifier.removeSection(s.id),
                    ),
                  ),
              ],
            ),
    );
  }
}
