import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../ui/save_browser_panel.dart';
import 'harmony_chord_sheet.dart';
import 'songwriter_block_tile.dart';

int _nextFreeBar(SongLane lane, int lengthBars) {
  // first bar not covered by an existing block, capped at lengthBars-1
  var bar = 0;
  final occupied = <int>{};
  for (final b in lane.blocks) {
    for (var i = b.startBar; i < b.endBar; i++) {
      occupied.add(i);
    }
  }
  while (bar < lengthBars && occupied.contains(bar)) {
    bar++;
  }
  return bar >= lengthBars ? 0 : bar;
}

class SongwriterLaneRow extends ConsumerWidget {
  const SongwriterLaneRow({
    super.key,
    required this.sectionId,
    required this.laneId,
  });
  final String sectionId;
  final String laneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      songwriterProvider.select((p) {
        final s = p.sections.firstWhere(
          (s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
        );
        final l = s.lanes.firstWhere(
          (l) => l.id == laneId,
          orElse: () =>
              const SongLane(id: '', kind: SongLaneKind.save, order: 0),
        );
        return (lengthBars: s.lengthBars, lane: l);
      }),
    );
    final lane = data.lane;
    final lengthBars = data.lengthBars < 1 ? 1 : data.lengthBars;
    if (lane.id.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              lane.label ??
                  (lane.kind == SongLaneKind.harmony ? 'Harmony' : 'Lane'),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 44,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth / lengthBars;
                  return Stack(
                    children: [
                      for (final block in lane.blocks)
                        Positioned(
                          left: block.startBar * barWidth,
                          width: block.spanBars * barWidth,
                          top: 0,
                          bottom: 0,
                          child: SongwriterBlockTile(
                            sectionId: sectionId,
                            laneId: laneId,
                            blockId: block.id,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          IconButton(
            key: Key('addBlock_$laneId'),
            icon: const Icon(Icons.add),
            onPressed: () async {
              if (lane.kind == SongLaneKind.harmony) {
                final config = ref.read(songwriterProvider).config;
                final block = await showHarmonyChordSheet(
                  context,
                  startBar: _nextFreeBar(lane, lengthBars),
                  spanBars: 2,
                  keyRoot: config.keyRoot,
                  keyScaleName: config.keyScaleName,
                );
                if (block != null) {
                  ref
                      .read(songwriterProvider.notifier)
                      .addHarmonyBlock(
                        sectionId: sectionId,
                        laneId: laneId,
                        block: block,
                      );
                }
              } else if (lane.kind == SongLaneKind.save) {
                final startBar = _nextFreeBar(lane, lengthBars);
                final picked = await showModalBottomSheet<SaveEntry>(
                  context: context,
                  isScrollControlled: true,
                  builder: (sheetCtx) => SaveBrowserPanel(
                    instrumentFilter: 'fretboard',
                    onPick: (entry) => Navigator.pop(sheetCtx, entry),
                  ),
                );
                if (picked != null) {
                  ref
                      .read(songwriterProvider.notifier)
                      .addSaveBlock(
                        sectionId: sectionId,
                        laneId: laneId,
                        saveId: picked.id,
                        startBar: startBar,
                        spanBars: 2,
                      );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
