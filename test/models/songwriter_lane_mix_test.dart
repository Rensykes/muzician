import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongLane defaults volume 1, pan 0, unmuted', () {
    const lane = SongLane(id: 'l1', kind: SongLaneKind.harmony, order: 0);
    expect(lane.volume, 1.0);
    expect(lane.pan, 0.0);
    expect(lane.muted, false);
  });

  test('SongLane mix fields survive JSON round-trip', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.harmony,
      order: 0,
      volume: 0.5,
      pan: -0.7,
      muted: true,
    );
    final back = SongLane.fromJson(lane.toJson());
    expect(back.volume, 0.5);
    expect(back.pan, -0.7);
    expect(back.muted, true);
  });

  test('legacy JSON without mix fields loads defaults', () {
    final back = SongLane.fromJson({'id': 'l1', 'kind': 'harmony', 'order': 0});
    expect(back.volume, 1.0);
    expect(back.pan, 0.0);
    expect(back.muted, false);
  });

  test('copyWith sets mix fields', () {
    const lane = SongLane(id: 'l1', kind: SongLaneKind.harmony, order: 0);
    final c = lane.copyWith(volume: 0.3, pan: 0.4, muted: true);
    expect((c.volume, c.pan, c.muted), (0.3, 0.4, true));
  });
}
