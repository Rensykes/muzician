import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a chord block opens the Voicings / Library sheet',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId =
        container.read(songwriterProvider).sections.first.lanes.first.id;
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
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();

    // The voicings sheet, not the chord editor.
    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    // And the escape hatch to edit the chord.
    expect(find.byKey(const Key('editChordButton')), findsOneWidget);
  });
}
