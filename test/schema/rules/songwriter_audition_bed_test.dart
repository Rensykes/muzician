import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  // 4/4, ticksPerBeat=4 → measureTicks=16.
  const config = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);

  SongSection sectionWith(List<SongLane> lanes, {int lengthBars = 1}) =>
      makeSection(order: 0, lengthBars: lengthBars).copyWith(lanes: lanes);

  test('harmony stabs land on bar boundaries; drum hits appear in drumByTick',
      () {
    final harmony = makeLane(kind: SongLaneKind.harmony, order: 0).copyWith(
      blocks: [
        makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'C',
          chordRootPc: 0,
          chordQuality: 'maj',
          chordNotes: const ['C', 'E', 'G'],
        ),
      ],
    );
    final drumPattern = const DrumPattern(
      id: 'dp1',
      name: 'k',
      lengthTicks: 16,
      lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8])],
    );
    final drumLane = makeLane(kind: SongLaneKind.drum, order: 1).copyWith(
      blocks: [makeDrumBlock(patternId: 'dp1', startBar: 0, spanBars: 1)],
    );
    final section = sectionWith([harmony, drumLane]);

    final bed = sectionAuditionBed(section, config, const [],
        drumPatterns: [drumPattern]);

    expect(bed.loopTicks, 16);
    expect(bed.notesByTick[0], containsAll(<int>[60, 64, 67]));
    expect(bed.drumByTick[0], contains(DrumLaneId.kick));
    expect(bed.drumByTick[8], contains(DrumLaneId.kick));
  });

  test('drum pattern tiles across a multi-bar section', () {
    // 2-bar section → measureTicks 16, loopTicks 32. An 8-tick pattern with a
    // single kick at tick 0 tiles at origins 0, 8, 16, 24 across [0, 32).
    final drumPattern = const DrumPattern(
      id: 'dp1',
      name: 'k',
      lengthTicks: 8,
      lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
    );
    final drumLane = makeLane(kind: SongLaneKind.drum, order: 0).copyWith(
      blocks: [makeDrumBlock(patternId: 'dp1', startBar: 0, spanBars: 2)],
    );
    final section = sectionWith([drumLane], lengthBars: 2);

    final bed = sectionAuditionBed(section, config, const [],
        drumPatterns: [drumPattern]);

    expect(bed.loopTicks, 32);
    expect(bed.drumByTick.keys.toSet(), {0, 8, 16, 24});
    for (final tick in const [0, 8, 16, 24]) {
      expect(bed.drumByTick[tick], contains(DrumLaneId.kick));
    }
  });

  test('empty section yields empty maps', () {
    final bed = sectionAuditionBed(sectionWith(const []), config, const []);
    expect(bed.notesByTick, isEmpty);
    expect(bed.drumByTick, isEmpty);
    expect(bed.loopTicks, 16);
  });
}
