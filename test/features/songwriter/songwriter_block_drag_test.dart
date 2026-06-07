import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_block_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('horizontal drag moves the block by whole bars', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l =
        container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(
        sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final bId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single
        .id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 44,
            child: SongwriterBlockTile(
              sectionId: s,
              laneId: l,
              blockId: bId,
              barWidth: 40,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.drag(find.byKey(Key('block_$bId')), const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .startBar,
        2);
  });

  testWidgets('resize handle extends the block span', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l =
        container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(
        sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final bId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single
        .id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 44,
            child: SongwriterBlockTile(
              sectionId: s,
              laneId: l,
              blockId: bId,
              barWidth: 40,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.drag(
        find.byKey(Key('resizeHandle_$bId')), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .spanBars,
        3);
  });
}
