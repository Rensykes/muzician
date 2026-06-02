import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
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
    const lane = SongLane(id: 'l', kind: SongLaneKind.save, order: 0, blocks: [
      SongBlock(id: 'a', startBar: 0, spanBars: 2),
      SongBlock(id: 'b', startBar: 4, spanBars: 2),
    ]);
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
    const lane = SongLane(id: 'l1', kind: SongLaneKind.save, order: 0, repeat: 3);
    expect(tileLaneBlocks(lane, sectionLengthBars: 8), isEmpty);
  });
}
