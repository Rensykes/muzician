import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('addLyricBlock inserts a positioned lyric block; overlap is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.lyrics, label: 'Lyrics');
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;

    n.addLyricBlock(sectionId: s, laneId: l, startBar: 0, spanBars: 2, text: 'hi');
    var lane = c.read(songwriterProvider).sections.single.lanes.single;
    expect(lane.blocks.single.lyrics, ['hi']);
    expect(lane.blocks.single.startBar, 0);

    // Overlapping insert is rejected, leaving one block.
    n.addLyricBlock(sectionId: s, laneId: l, startBar: 1, spanBars: 2, text: 'no');
    lane = c.read(songwriterProvider).sections.single.lanes.single;
    expect(lane.blocks.length, 1);

    // Non-overlapping insert succeeds.
    n.addLyricBlock(sectionId: s, laneId: l, startBar: 4, spanBars: 2, text: 'bye');
    lane = c.read(songwriterProvider).sections.single.lanes.single;
    expect(lane.blocks.length, 2);
  });

  test('setBlockLyric updates a lyric-lane block per verse index', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.lyrics, label: 'Lyrics');
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addLyricBlock(sectionId: s, laneId: l, startBar: 0, spanBars: 4);
    final b = c.read(songwriterProvider).sections.single.lanes.single.blocks.single.id;

    n.setBlockLyric(sectionId: s, laneId: l, blockId: b, verseIndex: 0, text: 'verse one');
    final block =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    expect(block.lyrics, ['verse one']);
  });
}
