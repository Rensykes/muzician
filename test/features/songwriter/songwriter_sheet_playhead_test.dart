import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('melody continuation highlights only the active row', (
    tester,
  ) async {
    String? sectionId;
    final container = ProviderContainer(
      overrides: [
        songwriterActivePositionProvider.overrideWith(
          (ref) => SongwriterActivePosition(
            sectionId: sectionId!,
            instanceIndex: 0,
            localBar: 5,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    sectionId = section.id;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final patternId = writer.addMelodyPattern();
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 6,
    );
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final first = tester.widget<Container>(
      find.byKey(Key('melodySegment_${block.id}_0_0_0')),
    );
    final second = tester.widget<Container>(
      find.byKey(Key('melodySegment_${block.id}_0_0_4')),
    );
    expect((first.decoration! as BoxDecoration).border!.top.width, 1);
    expect((second.decoration! as BoxDecoration).border!.top.width, 2);
  });

  testWidgets('active bar cell shows the playhead highlight key', (
    tester,
  ) async {
    String? sectionId;
    final container = ProviderContainer(
      overrides: [
        songwriterActivePositionProvider.overrideWith(
          (ref) => SongwriterActivePosition(
            sectionId: sectionId!,
            instanceIndex: 0,
            localBar: 0,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    sectionId = section.id;
    final laneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .id;
    n.addHarmonyBlock(
      sectionId: section.id,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(Key('activeBarCell_${section.id}_0_0')), findsOneWidget);
    // Bar 1 (and instance) not active.
    expect(find.byKey(Key('activeBarCell_${section.id}_0_1')), findsNothing);
  });

  testWidgets('no highlight when transport idle', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(Key('activeBarCell_${section.id}_0_0')), findsNothing);
  });
}
