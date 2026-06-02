import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setBlockPlacement moves/resizes; overlap is rejected', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 16);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final bId =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single.id;

    n.setBlockPlacement(
        sectionId: s, laneId: l, blockId: bId, startBar: 4, spanBars: 4);
    final b =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    expect(b.startBar, 4);
    expect(b.spanBars, 4);

    // Add a second block then try to overlap it onto the first — rejected.
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'y', startBar: 10, spanBars: 2);
    final yId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .firstWhere((blk) => blk.saveId == 'y')
        .id;
    n.setBlockPlacement(
        sectionId: s, laneId: l, blockId: yId, startBar: 4, spanBars: 2);
    final y = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .firstWhere((blk) => blk.saveId == 'y');
    expect(y.startBar, 10); // unchanged — overlap rejected
  });
}
