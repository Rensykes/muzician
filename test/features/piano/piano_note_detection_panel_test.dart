import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano/piano_note_detection_panel.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/store/piano_store.dart';

class FakePianoNotifier extends PianoNotifier {
  FakePianoNotifier(this._initial);

  final PianoState _initial;

  @override
  PianoState build() => _initial;
}

void main() {
  testWidgets('shows contextual flat label for a detected scale', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoProvider.overrideWith(
          () => FakePianoNotifier(
            const PianoState(
              currentRange: PianoRangeName.key61,
              highlightedNotes: [],
              selectedNotes: ['D#', 'F', 'F#', 'G#', 'A#', 'C', 'C#'],
              selectedKeys: [
                PianoCoordinate(keyIndex: 0, midiNote: 51, noteName: 'D#'),
                PianoCoordinate(keyIndex: 1, midiNote: 53, noteName: 'F'),
                PianoCoordinate(keyIndex: 2, midiNote: 54, noteName: 'F#'),
                PianoCoordinate(keyIndex: 3, midiNote: 56, noteName: 'G#'),
                PianoCoordinate(keyIndex: 4, midiNote: 58, noteName: 'A#'),
                PianoCoordinate(keyIndex: 5, midiNote: 60, noteName: 'C'),
                PianoCoordinate(keyIndex: 6, midiNote: 61, noteName: 'C#'),
              ],
              viewMode: PianoViewMode.exact,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PianoNoteDetectionPanel()),
        ),
      ),
    );

    expect(find.text('Eb dorian'), findsOneWidget);
    await tester.tap(find.text('Eb dorian'));
    await tester.pump();
    expect(container.read(pianoPendingScaleProvider), (
      root: 'D#',
      scaleName: 'dorian',
    ));
  });
}
