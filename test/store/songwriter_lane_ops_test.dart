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
}
