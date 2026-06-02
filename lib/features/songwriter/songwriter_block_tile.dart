import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../store/save_system_store.dart';

class SongwriterBlockTile extends ConsumerWidget {
  const SongwriterBlockTile(
      {super.key,
      required this.sectionId,
      required this.laneId,
      required this.blockId});
  final String sectionId;
  final String laneId;
  final String blockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final block = ref.watch(songwriterProvider.select((p) {
      for (final s in p.sections) {
        if (s.id != sectionId) continue;
        for (final l in s.lanes) {
          if (l.id != laneId) continue;
          for (final b in l.blocks) {
            if (b.id == blockId) return b;
          }
        }
      }
      return null;
    }));
    if (block == null) return const SizedBox.shrink();

    final saves = ref.watch(saveSystemProvider).saves;
    final broken = block.embedded == null &&
        block.saveId != null &&
        !saves.any((e) => e.id == block.saveId);

    // PRIMARY label: chordSymbol first, then romanNumeral, then save label
    final primary = block.chordSymbol ??
        block.romanNumeral ??
        _saveLabel(saves, block);
    final secondary = block.chordSymbol != null ? block.romanNumeral : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: broken ? Colors.red.withValues(alpha: 0.25) : Colors.teal,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (secondary != null)
            Text(secondary,
                style: const TextStyle(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _saveLabel(List<SaveEntry> saves, SongBlock block) {
    final snap = block.embedded;
    if (snap != null) return snap.pendingChord?.symbol ?? 'Saved';
    final id = block.saveId;
    if (id == null) return 'Block';
    for (final e in saves) {
      if (e.id == id) return e.name;
    }
    return 'Missing';
  }
}
