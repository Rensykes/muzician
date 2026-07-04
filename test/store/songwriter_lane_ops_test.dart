import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('set lane repeat and remove lane', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'Guitar');
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;

    n.setLaneRepeat(sectionId: s, laneId: l, repeat: 3);
    expect(c.read(songwriterProvider).sections.single.lanes.single.repeat, 3);

    n.removeLane(sectionId: s, laneId: l);
    expect(c.read(songwriterProvider).sections.single.lanes, isEmpty);
  });

  group('lane mix ops', () {
    test('volume and pan set with clamping, mute toggles', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'V', lengthBars: 4);
      final s = c.read(songwriterProvider).sections.single.id;
      n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
      final l = c.read(songwriterProvider).sections.single.lanes.single.id;
      SongLane lane() => c.read(songwriterProvider).sections.single.lanes.single;

      n.setLaneVolume(sectionId: s, laneId: l, volume: 0.5);
      expect(lane().volume, 0.5);
      n.setLaneVolume(sectionId: s, laneId: l, volume: 1.7);
      expect(lane().volume, 1.0);
      n.setLaneVolume(sectionId: s, laneId: l, volume: -0.2);
      expect(lane().volume, 0.0);

      n.setLanePan(sectionId: s, laneId: l, pan: -2.0);
      expect(lane().pan, -1.0);
      n.setLanePan(sectionId: s, laneId: l, pan: 0.4);
      expect(lane().pan, 0.4);

      n.setLaneMuted(sectionId: s, laneId: l, muted: true);
      expect(lane().muted, true);
      n.setLaneMuted(sectionId: s, laneId: l, muted: false);
      expect(lane().muted, false);
    });
  });
}
