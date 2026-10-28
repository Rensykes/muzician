import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  group('melody placement limits', () {
    const measureTicks = 16;
    const pattern = NotePattern(
      id: 'lead',
      name: 'Lead',
      lengthTicks: 48,
      notes: [
        NotePatternNote(
          id: 'last',
          midiNote: 72,
          startTick: 46,
          durationTicks: 2,
        ),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 1,
      highlightedNotes: [],
    );
    const lane = SongLane(id: 'melody', kind: SongLaneKind.melody, order: 0);
    const section = SongSection(
      id: 'section',
      lengthBars: 8,
      order: 0,
      lanes: [lane],
    );

    test('a three-bar melody rejects a four-bar placement', () {
      final melodyBars = melodyBarCount(pattern, measureTicks);
      expect(melodyBars, 3);
      for (final span in [1, 2, 3]) {
        expect(
          isValidMelodyPlacement(
            section: section,
            lane: lane,
            candidate: SongBlock(id: 'new', startBar: 0, spanBars: span),
            melodyBars: melodyBars,
          ),
          isTrue,
          reason: '$span bars',
        );
      }
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: const SongBlock(id: 'new', startBar: 0, spanBars: 4),
          melodyBars: melodyBars,
        ),
        isFalse,
      );
    });

    test('a legacy over-long placement may move unchanged but must resize '
        'within the melody', () {
      const legacy = SongBlock(
        id: 'legacy',
        startBar: 0,
        spanBars: 4,
        patternId: 'lead',
      );
      final overLongLane = lane.copyWith(blocks: [legacy]);
      final overLongSection = section.copyWith(lanes: [overLongLane]);
      bool valid(SongBlock candidate) => isValidMelodyPlacement(
        section: overLongSection,
        lane: overLongLane,
        candidate: candidate,
        melodyBars: 3,
      );

      expect(valid(legacy.copyWith(startBar: 1)), isTrue);
      expect(valid(legacy.copyWith(startBar: 1, spanBars: 2)), isTrue);
      expect(valid(legacy.copyWith(startBar: 1, spanBars: 3)), isTrue);
      expect(valid(legacy.copyWith(startBar: 1, spanBars: 5)), isFalse);
      expect(
        valid(const SongBlock(id: 'new', startBar: 0, spanBars: 4)),
        isFalse,
      );
    });

    test('non-bar-aligned legacy lengths round up for placement limits', () {
      const legacy = NotePattern(
        id: 'legacy',
        name: 'Legacy',
        lengthTicks: 25,
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        snapTicks: 1,
        highlightedNotes: [],
      );
      final limit = melodyPlacementBarLimit(legacy, measureTicks);
      expect(limit, 2);
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: const SongBlock(id: 'new', startBar: 0, spanBars: 2),
          melodyBars: limit,
        ),
        isTrue,
      );
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: const SongBlock(id: 'new', startBar: 0, spanBars: 3),
          melodyBars: limit,
        ),
        isFalse,
      );
    });
  });

  test('total flattened bars expands section repeats', () {
    const sections = [
      SongSection(id: 's1', lengthBars: 4, order: 0, repeat: 2), // 8
      SongSection(id: 's2', lengthBars: 8, order: 1, repeat: 1), // 8
    ];
    expect(flattenedBarCount(sections), 16);
  });

  test('laneNaturalLength is max block end, 0 when empty', () {
    const empty = SongLane(id: 'l', kind: SongLaneKind.save, order: 0);
    expect(laneNaturalLength(empty), 0);
    const lane = SongLane(
      id: 'l',
      kind: SongLaneKind.save,
      order: 0,
      blocks: [
        SongBlock(id: 'a', startBar: 0, spanBars: 2),
        SongBlock(id: 'b', startBar: 4, spanBars: 2),
      ],
    );
    expect(laneNaturalLength(lane), 6);
  });

  test('lane tiling expands a 2-bar pattern to fill via repeat', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.save,
      order: 0,
      repeat: 2,
      blocks: [SongBlock(id: 'b', startBar: 0, spanBars: 2, saveId: 's')],
    );
    final placed = tileLaneBlocks(lane, sectionLengthBars: 8);
    expect(placed.map((p) => p.startBar).toList(), [0, 2]);
  });

  test('tiled content is clipped to the section length', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.save,
      order: 0,
      repeat: 5, // would run to bar 10
      blocks: [SongBlock(id: 'b', startBar: 0, spanBars: 2, saveId: 's')],
    );
    final placed = tileLaneBlocks(lane, sectionLengthBars: 4);
    expect(placed.map((p) => p.startBar).toList(), [0, 2]);
  });

  test('empty lane tiles to nothing', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.save,
      order: 0,
      repeat: 3,
    );
    expect(tileLaneBlocks(lane, sectionLengthBars: 8), isEmpty);
  });
}
