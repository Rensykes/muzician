import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('lane round-trips with kind and repeat', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.harmony,
      label: 'Harmony',
      order: 0,
      repeat: 2,
      blocks: [SongBlock(id: 'b1', startBar: 0, spanBars: 1, saveId: 's1')],
    );
    final back = SongLane.fromJson(lane.toJson());
    expect(back.kind, SongLaneKind.harmony);
    expect(back.repeat, 2);
    expect(back.blocks.single.id, 'b1');
  });

  test('section round-trips with optional label and repeat', () {
    const section = SongSection(
      id: 's1',
      label: null,
      lengthBars: 8,
      order: 0,
      repeat: 1,
      lanes: [],
    );
    final back = SongSection.fromJson(section.toJson());
    expect(back.label, isNull);
    expect(back.lengthBars, 8);
    expect(back.lanes, isEmpty);
  });
}
