import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  const pattern = DrumPattern(
    id: 'd1',
    name: 'My Beat',
    lengthTicks: 16,
    lanes: [
      DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
      DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [4, 12]),
    ],
  );

  test('DrumLoopSnapshot exposes the abstract contract', () {
    const snap = DrumLoopSnapshot(pattern: pattern);
    expect(snap.instrument, 'drum_loop');
    expect(snap.selectedNotes, isEmpty);
    expect(snap.pendingChord, isNull);
    expect(snap.pendingScale, isNull);
  });

  test('toJson carries the drum_loop type + pattern', () {
    const snap = DrumLoopSnapshot(pattern: pattern);
    final json = snap.toJson();
    expect(json['type'], 'drum_loop');
    expect(json['instrument'], 'drum_loop');
    expect(json['pattern'], isA<Map<String, dynamic>>());
  });

  test('InstrumentSnapshot.fromJson dispatches drum_loop', () {
    final back = InstrumentSnapshot.fromJson(
      const DrumLoopSnapshot(pattern: pattern).toJson(),
    );
    expect(back, isA<DrumLoopSnapshot>());
    final loop = back as DrumLoopSnapshot;
    expect(loop.pattern.name, 'My Beat');
    expect(loop.pattern.lengthTicks, 16);
    expect(loop.pattern.lanes.first.laneId, DrumLaneId.kick);
    expect(loop.pattern.lanes.first.activeTicks, [0, 8]);
  });
}
