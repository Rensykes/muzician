import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('relinkBlock points the block at a new save and clears embedded', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(
        sectionId: s, laneId: l, saveId: 'old', startBar: 0, spanBars: 2);
    final bId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single
        .id;

    n.relinkBlock(sectionId: s, laneId: l, blockId: bId, saveId: 'new');
    final b = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(b.saveId, 'new');
    expect(b.embedded, isNull);
  });
}
