import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  test('SongLaneKind.drum exists and round-trips by name', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.drum,
      label: 'Beat',
      order: 0,
      blocks: [
        SongBlock(id: 'b1', startBar: 0, spanBars: 4, patternId: 'p1'),
      ],
    );
    final back = SongLane.fromJson(lane.toJson());
    expect(back.kind, SongLaneKind.drum);
    expect(back.blocks.single.patternId, 'p1');
  });

  test('unknown lane kind still falls back to save', () {
    final back = SongLane.fromJson({
      'id': 'l2',
      'kind': 'mystery',
      'order': 0,
      'blocks': [],
    });
    expect(back.kind, SongLaneKind.save);
  });

  test('SongwriterProjectSnapshot round-trips drumPatterns', () {
    const pattern = DrumPattern(
      id: 'p1',
      name: 'Backbeat',
      lengthTicks: 16,
      lanes: [
        DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
        DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [4, 12]),
      ],
    );
    const snapshot = SongwriterProjectSnapshot(
      name: 'demo',
      config: SongwriterConfig(
        tempo: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      ),
      drumPatterns: [pattern],
    );
    final back = SongwriterProjectSnapshot.fromJson(snapshot.toJson());
    expect(back.drumPatterns.single.id, 'p1');
    expect(back.drumPatterns.single.lanes.first.activeTicks, [0, 8]);
  });

  test('fromJson tolerates missing drumPatterns key', () {
    final back = SongwriterProjectSnapshot.fromJson({
      'type': 'songwriter',
      'instrument': 'songwriter',
      'name': 'demo',
      'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
    });
    expect(back.drumPatterns, isEmpty);
  });

  test('SongBlock round-trips patternId', () {
    const block = SongBlock(
      id: 'b1',
      startBar: 2,
      spanBars: 4,
      patternId: 'p42',
    );
    final back = SongBlock.fromJson(block.toJson());
    expect(back.patternId, 'p42');
  });
}
