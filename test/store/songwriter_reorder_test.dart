import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reorderLanes moves a lane and renumbers order', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'A');
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'B');
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'C');

    n.reorderLanes(s, 2, 0); // move C to front

    final lanes = c.read(songwriterProvider).sections.single.lanes;
    expect(lanes.map((l) => l.label).toList(), ['C', 'A', 'B']);
    expect(lanes.map((l) => l.order).toList(), [0, 1, 2]);
  });
}
