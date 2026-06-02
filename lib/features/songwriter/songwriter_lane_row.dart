import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import 'songwriter_block_tile.dart';

class SongwriterLaneRow extends ConsumerWidget {
  const SongwriterLaneRow(
      {super.key, required this.sectionId, required this.laneId});
  final String sectionId;
  final String laneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(songwriterProvider.select((p) {
      final s = p.sections.firstWhere((s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0));
      final l = s.lanes.firstWhere((l) => l.id == laneId,
          orElse: () => const SongLane(id: '', kind: SongLaneKind.save, order: 0));
      return (lengthBars: s.lengthBars, lane: l);
    }));
    final lane = data.lane;
    final lengthBars = data.lengthBars < 1 ? 1 : data.lengthBars;
    if (lane.id.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(lane.label ??
                (lane.kind == SongLaneKind.harmony ? 'Harmony' : 'Lane')),
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
        ],
      ),
    );
  }
}
