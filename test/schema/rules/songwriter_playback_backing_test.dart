import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';

void main() {
  // measureTicks = ticksPerBeat(4) * beatsPerBar(4) = 16.
  const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);

  test('loopTicks spans the whole section; no harmony → empty map', () {
    const section = SongSection(id: 's1', lengthBars: 2, order: 0, lanes: []);
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.loopTicks, 32); // 2 bars × 16
    expect(loop.notesByTick, isEmpty);
  });

  test('harmony block fires its chord pitches at the bar tick', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 2,
      order: 0,
      lanes: [
        SongLane(
          id: 'l1',
          kind: SongLaneKind.harmony,
          order: 0,
          blocks: [
            SongBlock(
              id: 'b1',
              startBar: 0,
              spanBars: 1,
              chordNotes: ['C', 'E', 'G'],
            ),
          ],
        ),
      ],
    );
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.notesByTick[0], [60, 64, 67]); // C4 E4 G4
    expect(loop.notesByTick.keys.toSet(), {0});
  });

  test('multi-bar harmony block fires on each bar boundary', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 2,
      order: 0,
      lanes: [
        SongLane(
          id: 'l1',
          kind: SongLaneKind.harmony,
          order: 0,
          blocks: [
            SongBlock(
              id: 'b1',
              startBar: 0,
              spanBars: 2,
              chordNotes: ['C', 'E', 'G'],
            ),
          ],
        ),
      ],
    );
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.notesByTick.keys.toSet(), {0, 16});
  });

  test('drum lanes are ignored', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 1,
      order: 0,
      lanes: [
        SongLane(
          id: 'd1',
          kind: SongLaneKind.drum,
          order: 0,
          blocks: [
            SongBlock(id: 'b1', startBar: 0, spanBars: 1, patternId: 'p1'),
          ],
        ),
      ],
    );
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.notesByTick, isEmpty);
  });
}
