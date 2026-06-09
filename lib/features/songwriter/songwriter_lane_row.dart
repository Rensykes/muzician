import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../ui/save_browser_panel.dart';
import '../_mockup_shell.dart';
import 'drum_pattern_sheet.dart';
import 'harmony_chord_sheet.dart';
import 'songwriter_block_tile.dart';
import 'songwriter_grid.dart';
import 'songwriter_save_lane_filter.dart';

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
    this.activeBar,
  });
  final String sectionId;
  final String laneId;
  final int? activeBar;

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
      key: Key('drumLaneRow_$laneId'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              lane.label ??
                  switch (lane.kind) {
                    SongLaneKind.harmony => 'Harmony',
                    SongLaneKind.save => 'Lane',
                    SongLaneKind.drum => 'Beat',
                  },
              style: TextStyle(
                color: switch (lane.kind) {
                  SongLaneKind.harmony => MuzicianTheme.violet,
                  SongLaneKind.save => MuzicianTheme.teal,
                  SongLaneKind.drum => MuzicianTheme.orange,
                },
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 52,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth / lengthBars;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BarGridPainter(
                            lengthBars: lengthBars,
                            color: MuzicianTheme.glassBorder,
                          ),
                        ),
                      ),
                      for (final block in lane.blocks)
                        if (lane.kind == SongLaneKind.drum)
                          Positioned(
                            left: block.startBar * barWidth,
                            width: block.spanBars * barWidth,
                            top: 0,
                            bottom: 0,
                            child: DrumBlockTile(
                              lane: lane,
                              block: block,
                            ),
                          )
                        else
                          Positioned(
                            left: block.startBar * barWidth,
                            width: block.spanBars * barWidth,
                            top: 0,
                            bottom: 0,
                            child: SongwriterBlockTile(
                              sectionId: sectionId,
                              laneId: laneId,
                              blockId: block.id,
                              barWidth: barWidth,
                              highlighted:
                                  activeBar != null &&
                                  activeBar! >= block.startBar &&
                                  activeBar! < block.endBar,
                            ),
                          ),
                      if (activeBar != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: PlayheadPainter(
                                bar: activeBar!.toDouble(),
                                lengthBars: lengthBars,
                                color: MuzicianTheme.sky.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          IconBtn(
            key: Key('addBlock_$laneId'),
            icon: Icons.add_rounded,
            color: switch (lane.kind) {
              SongLaneKind.harmony => MuzicianTheme.violet,
              SongLaneKind.save => MuzicianTheme.teal,
              SongLaneKind.drum => MuzicianTheme.orange,
            },
            onTap: () async {
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
                  backgroundColor: Colors.transparent,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  // Allow fretboard / piano / piano_roll enrichment saves,
                  // but exclude songwriter + song arrangement-level saves so
                  // a save lane cannot embed a whole project save.
                  builder: (sheetCtx) => Container(
                    decoration: BoxDecoration(
                      color: MuzicianTheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border.all(color: MuzicianTheme.glassBorder),
                    ),
                    child: SaveBrowserPanel(
                      allowedInstruments: songwriterSaveLaneAllowedInstruments,
                      onPick: (entry) => Navigator.pop(sheetCtx, entry),
                    ),
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

class DrumBlockTile extends ConsumerWidget {
  const DrumBlockTile({
    super.key,
    required this.lane,
    required this.block,
  });
  final SongLane lane;
  final SongBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patternId = block.patternId;
    final pattern = patternId == null
        ? null
        : ref
            .read(songwriterProvider)
            .drumPatterns
            .firstWhere(
              (p) => p.id == patternId,
              orElse: () => const DrumPattern(
                id: '',
                name: 'Missing',
                lengthTicks: 0,
                lanes: [],
              ),
            );
    return GestureDetector(
      key: Key('drumBlockTile_${patternId ?? block.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (patternId == null || pattern == null || pattern.id.isEmpty) return;
        showSongwriterDrumPatternSheet(
          context: context,
          patternId: patternId,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: MuzicianTheme.orange.withValues(alpha: 0.18),
          border: Border.all(color: MuzicianTheme.orange.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, size: 14),
            const SizedBox(width: 6),
            Text(
              pattern?.name ?? 'pattern?',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
