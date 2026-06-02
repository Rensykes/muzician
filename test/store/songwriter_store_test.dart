import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add section, add lane, add block', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 8);
    final sectionId = c.read(songwriterProvider).sections.single.id;

    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final laneId =
        c.read(songwriterProvider).sections.single.lanes.single.id;

    n.addSaveBlock(
        sectionId: sectionId, laneId: laneId, saveId: 'save-1',
        startBar: 0, spanBars: 4);

    final block = c
        .read(songwriterProvider)
        .sections.single.lanes.single.blocks.single;
    expect(block.saveId, 'save-1');
    expect(block.spanBars, 4);
  });

  test('overlapping block add is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'a', startBar: 0, spanBars: 4);
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'b', startBar: 2, spanBars: 4);
    expect(
        c.read(songwriterProvider).sections.single.lanes.single.blocks.length, 1);
  });
}
