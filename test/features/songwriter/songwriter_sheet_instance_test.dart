import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders section.repeat instances, each with its own lyric row',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(() { container.dispose(); });
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
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
      ).copyWith(lyrics: ['hello', 'goodbye']),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Two instances rendered.
    expect(find.byKey(Key('sectionInstance_${section.id}_0')), findsOneWidget);
    expect(find.byKey(Key('sectionInstance_${section.id}_1')), findsOneWidget);

    // Chord symbol appears once per instance (i.e. twice total).
    expect(find.text('C'), findsNWidgets(2));

    // Each instance shows its own lyric.
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('goodbye'), findsOneWidget);
  });

  testWidgets('silent placeholder dot renders inside each instance',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(() { container.dispose(); });
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Bridge', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;

    n.addSilentBlock(
      sectionId: section.id,
      laneId: laneId,
      startBar: 0,
      spanBars: 1,
      verseCount: 2,
    );
    final blockId = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single.id;
    n.setBlockLyric(
      sectionId: section.id,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 0,
      text: '(ahh)',
    );
    n.setBlockLyric(
      sectionId: section.id,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 1,
      text: '(ooh)',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Silent dot appears in both instances.
    expect(find.byKey(Key('silentCell_${blockId}_0')), findsOneWidget);
    expect(find.byKey(Key('silentCell_${blockId}_1')), findsOneWidget);
    expect(find.text('(ahh)'), findsOneWidget);
    expect(find.text('(ooh)'), findsOneWidget);
  });
}
