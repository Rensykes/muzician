import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('lyrics lane kind round-trips through JSON', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.lyrics,
      order: 0,
      blocks: [
        SongBlock(id: 'b1', startBar: 0, spanBars: 4, lyrics: ['hello world']),
      ],
    );
    final restored = SongLane.fromJson(lane.toJson());
    expect(restored.kind, SongLaneKind.lyrics);
    expect(restored.blocks.single.lyrics, ['hello world']);
  });

  test('unknown lane kind still falls back to save', () {
    final restored =
        SongLane.fromJson({'id': 'x', 'kind': 'bogus', 'order': 0});
    expect(restored.kind, SongLaneKind.save);
  });
}
