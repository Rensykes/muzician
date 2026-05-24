import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_hum_recorder.dart';
import 'package:muzician/models/hum_to_midi.dart';

void main() {
  testWidgets('shows the live note and stop button while recording', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PianoRollHumRecorderCard(
            status: HumToMidiStatus.recording,
            liveNoteLabel: 'A4',
            statusLabel: 'Stable',
            elapsedLabel: '00:03',
            onStart: null,
            onStop: null,
          ),
        ),
      ),
    );

    expect(find.text('Hum to MIDI'), findsOneWidget);
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('Stable'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });
}
