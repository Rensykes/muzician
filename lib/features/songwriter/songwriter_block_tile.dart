import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../store/save_system_store.dart';

class SongwriterBlockTile extends ConsumerWidget {
  const SongwriterBlockTile({
    super.key,
    required this.sectionId,
    required this.laneId,
    required this.blockId,
  });
  final String sectionId;
  final String laneId;
  final String blockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final block = ref.watch(
      songwriterProvider.select((p) {
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
      }),
    );
    if (block == null) return const SizedBox.shrink();

    final saves = ref.watch(saveSystemProvider).saves;
    final broken =
        block.embedded == null &&
        block.saveId != null &&
        !saves.any((e) => e.id == block.saveId);

    // PRIMARY label: chordSymbol first, then romanNumeral, then save label
    final primary =
        block.chordSymbol ?? block.romanNumeral ?? _saveLabel(saves, block);
    final secondary = block.chordSymbol != null ? block.romanNumeral : null;

    return GestureDetector(
      key: Key('block_$blockId'),
      onLongPress: () => _openMenu(context, ref, block),
      child: Container(
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
              Text(
                secondary,
                style: const TextStyle(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  void _openMenu(BuildContext context, WidgetRef ref, SongBlock block) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('Edit placement'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _editPlacement(context, ref, block);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheetCtx);
                ref
                    .read(songwriterProvider.notifier)
                    .removeBlock(
                      sectionId: sectionId,
                      laneId: laneId,
                      blockId: blockId,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editPlacement(BuildContext context, WidgetRef ref, SongBlock block) {
    showDialog<void>(
      context: context,
      builder: (_) => _PlacementDialog(
        initialStart: block.startBar,
        initialSpan: block.spanBars,
        onApply: (start, span) => ref
            .read(songwriterProvider.notifier)
            .setBlockPlacement(
              sectionId: sectionId,
              laneId: laneId,
              blockId: blockId,
              startBar: start,
              spanBars: span,
            ),
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

class _PlacementDialog extends StatefulWidget {
  const _PlacementDialog({
    required this.initialStart,
    required this.initialSpan,
    required this.onApply,
  });
  final int initialStart;
  final int initialSpan;
  final void Function(int startBar, int spanBars) onApply;

  @override
  State<_PlacementDialog> createState() => _PlacementDialogState();
}

class _PlacementDialogState extends State<_PlacementDialog> {
  late int _start = widget.initialStart;
  late int _span = widget.initialSpan;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Block placement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(
            'Start bar',
            _start,
            0,
            (v) => setState(() => _start = v < 0 ? 0 : v),
          ),
          _row(
            'Span (bars)',
            _span,
            1,
            (v) => setState(() => _span = v < 1 ? 1 : v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onApply(_start, _span);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _row(String label, int value, int min, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Text('$value'),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}
