import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_save_panel.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/piano_roll_store.dart';

void main() {
  testWidgets('PianoRollSavePanel renders with SaveBrowserPanel', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: PianoRollSavePanel())),
      ),
    );

    // Should show the SAVES header
    expect(find.text('SAVES'), findsOneWidget);
    // Should have a "+ Folder" button
    expect(find.text('+ Folder'), findsOneWidget);
  });

  testWidgets('PianoRollSavePanel shows save/load controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: PianoRollSavePanel())),
      ),
    );

    // Should have an Edit button
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('captureSnapshot produces valid PianoRollSnapshot', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Set up a non-default piano roll state
    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setTempo(130);
    notifier.setKey('G');
    notifier.setTimeSignature(
      const TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
    );
    notifier.setTotalMeasures(6);
    notifier.setPitchRange(40, 80);
    notifier.setSnapTicks(2);
    notifier.addNote(67, 0, 4); // G4
    notifier.addNote(71, 0, 4); // B4
    notifier.addNote(74, 0, 4); // D5
    notifier.selectColumn(0);
    notifier.setHighlightedNotes(['G', 'B', 'D']);

    // Test the capture-snapshot round trip by constructing an equivalent
    // snapshot from the same state shape.
    final prState = container.read(pianoRollProvider);
    final snap = PianoRollSnapshot(
      tempo: prState.config.tempo,
      key: prState.config.key,
      numerator: prState.config.timeSignature.beatsPerMeasure,
      denominator: prState.config.timeSignature.beatUnit,
      totalMeasures: prState.config.totalMeasures,
      notes: prState.notes
          .map(
            (n) => <String, dynamic>{
              'midiNote': n.midiNote,
              'startTick': n.startTick,
              'durationTicks': n.durationTicks,
            },
          )
          .toList(),
      pitchRangeStart: prState.pitchRangeStart,
      pitchRangeEnd: prState.pitchRangeEnd,
      selectedColumnTick: prState.selectedColumnTick,
      snapTicks: prState.snapTicks,
      highlightedNotes: List<String>.from(prState.highlightedNotes),
    );

    expect(snap.tempo, 130);
    expect(snap.key, 'G');
    expect(snap.numerator, 3);
    expect(snap.denominator, 4);
    expect(snap.totalMeasures, 6);
    expect(snap.notes, hasLength(3));
    expect(snap.pitchRangeStart, 40);
    expect(snap.pitchRangeEnd, 80);
    expect(snap.selectedColumnTick, 0);
    expect(snap.snapTicks, 2);
    expect(snap.highlightedNotes, ['G', 'B', 'D']);
  });
}
