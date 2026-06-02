import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('insertSection restores a removed section at its index', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'A', lengthBars: 4);
    n.addSection(label: 'B', lengthBars: 4);
    n.addSection(label: 'C', lengthBars: 4);

    final removed = c.read(songwriterProvider).sections[1]; // 'B'
    n.removeSection(removed.id);
    expect(c.read(songwriterProvider).sections.map((s) => s.label), ['A', 'C']);

    n.insertSection(removed, 1);
    final labels =
        c.read(songwriterProvider).sections.map((s) => s.label).toList();
    expect(labels, ['A', 'B', 'C']);
    final orders =
        c.read(songwriterProvider).sections.map((s) => s.order).toList();
    expect(orders, [0, 1, 2]);
  });

  test('insertLane restores a removed lane at its index', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'H');
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'G');
    final lane = c.read(songwriterProvider).sections.single.lanes[0];
    n.removeLane(sectionId: s, laneId: lane.id);
    expect(c.read(songwriterProvider).sections.single.lanes.length, 1);
    n.insertLane(sectionId: s, lane: lane, index: 0);
    expect(
        c.read(songwriterProvider).sections.single.lanes.map((l) => l.label),
        ['H', 'G']);
  });

  test('insertBlock restores a removed block', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(
        sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final block =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    n.removeBlock(sectionId: s, laneId: l, blockId: block.id);
    expect(c.read(songwriterProvider).sections.single.lanes.single.blocks,
        isEmpty);
    n.insertBlock(sectionId: s, laneId: l, block: block);
    expect(
        c
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .id,
        block.id);
  });
}
