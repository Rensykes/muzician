import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('loaded nonpositive repeats still protect authored melody blocks', () {
    for (final repeat in [0, -2]) {
      final lane = SongLane.fromJson({
        'id': 'lane',
        'kind': 'melody',
        'order': 0,
        'repeat': repeat,
        'blocks': [
          const SongBlock(id: 'a', startBar: 0, spanBars: 2).toJson(),
          const SongBlock(id: 'b', startBar: 3, spanBars: 1).toJson(),
        ],
      });
      final section = SongSection(
        id: 'section',
        lengthBars: 6,
        order: 0,
        lanes: [lane],
      );
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: const SongBlock(id: 'new', startBar: 1, spanBars: 1),
        ),
        isFalse,
        reason: 'repeat $repeat',
      );
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: lane.blocks.last.copyWith(startBar: 1),
        ),
        isFalse,
        reason: 'repeat $repeat',
      );
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: const SongBlock(id: 'new', startBar: 2, spanBars: 1),
        ),
        isTrue,
        reason: 'repeat $repeat',
      );
      expect(
        isValidMelodyPlacement(
          section: section,
          lane: lane,
          candidate: lane.blocks.first,
        ),
        isTrue,
        reason: 'repeat $repeat',
      );
    }
  });
  test('melody occurrences clip repeats and protect their origins', () {
    const source = SongBlock(id: 'source', startBar: 0, spanBars: 2);
    const lane = SongLane(
      id: 'lane',
      kind: SongLaneKind.melody,
      order: 0,
      repeat: 3,
      blocks: [source],
    );
    const section = SongSection(
      id: 'section',
      lengthBars: 6,
      order: 0,
      lanes: [lane],
    );
    final occurrences = melodyOccurrences(lane: lane, sectionLengthBars: 6);
    expect(
      occurrences.map(
        (o) => (o.source.id, o.startBar, o.endBar, o.repeatIndex),
      ),
      [('source', 0, 2, 0), ('source', 2, 4, 1), ('source', 4, 6, 2)],
    );
    expect(
      isValidMelodyPlacement(section: section, lane: lane, candidate: source),
      isTrue,
    );
    expect(
      isValidMelodyPlacement(
        section: section,
        lane: lane,
        candidate: source.copyWith(spanBars: 3),
      ),
      isFalse,
    );
    expect(
      isValidMelodyPlacement(
        section: section,
        lane: lane,
        candidate: const SongBlock(id: 'new', startBar: 4, spanBars: 1),
      ),
      isFalse,
    );
    final clipped = melodyOccurrences(lane: lane, sectionLengthBars: 5);
    expect(
      (clipped.last.startBar, clipped.last.endBar, clipped.last.repeatIndex),
      (4, 5, 2),
    );
    final gapLane = lane.copyWith(
      repeat: 2,
      blocks: [const SongBlock(id: 'gap', startBar: 1, spanBars: 1)],
    );
    expect(
      isValidMelodyPlacement(
        section: section,
        lane: gapLane,
        candidate: const SongBlock(id: 'new', startBar: 4, spanBars: 1),
      ),
      isFalse,
    );
    final single = lane.copyWith(repeat: 1);
    expect(
      isValidMelodyPlacement(
        section: section,
        lane: single,
        candidate: const SongBlock(id: 'new', startBar: 2, spanBars: 1),
      ),
      isTrue,
    );
  });
  test('non-overlapping blocks with a gap are valid', () {
    final blocks = [
      const SongBlock(id: 'a', startBar: 0, spanBars: 2),
      const SongBlock(id: 'b', startBar: 4, spanBars: 2), // gap at 2-4 ok
    ];
    expect(
      blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 2, spanBars: 2)),
      isFalse,
    );
  });

  test('overlapping placement is rejected', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(
      blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 2, spanBars: 2)),
      isTrue,
    );
  });

  test('touching edges do not overlap', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(
      blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 4, spanBars: 2)),
      isFalse,
    );
  });

  test('a block does not overlap itself (same id ignored)', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(
      blocksOverlap(blocks, const SongBlock(id: 'a', startBar: 0, spanBars: 4)),
      isFalse,
    );
  });

  test('makeSection produces a valid id and defaults', () {
    final s = makeSection(label: 'Verse', lengthBars: 8, order: 0);
    expect(s.id, isNotEmpty);
    expect(s.lengthBars, 8);
    expect(s.repeat, 1);
    expect(s.lanes, hasLength(1));
    expect(s.lanes.single.kind, SongLaneKind.harmony);
  });
}
