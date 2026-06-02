import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('non-overlapping blocks with a gap are valid', () {
    final blocks = [
      const SongBlock(id: 'a', startBar: 0, spanBars: 2),
      const SongBlock(id: 'b', startBar: 4, spanBars: 2), // gap at 2-4 ok
    ];
    expect(blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 2, spanBars: 2)),
        isFalse);
  });

  test('overlapping placement is rejected', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 2, spanBars: 2)),
        isTrue);
  });

  test('touching edges do not overlap', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 4, spanBars: 2)),
        isFalse);
  });

  test('a block does not overlap itself (same id ignored)', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(blocksOverlap(blocks, const SongBlock(id: 'a', startBar: 0, spanBars: 4)),
        isFalse);
  });

  test('makeSection produces a valid id and defaults', () {
    final s = makeSection(label: 'Verse', lengthBars: 8, order: 0);
    expect(s.id, isNotEmpty);
    expect(s.lengthBars, 8);
    expect(s.repeat, 1);
    expect(s.lanes, isEmpty);
  });
}
