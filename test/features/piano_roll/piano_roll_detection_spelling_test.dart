import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_detection_panel.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import '../../support/test_settings_notifier.dart';

class _PianoRollNotifier extends PianoRollNotifier {
  _PianoRollNotifier(this._initial);

  final PianoRollState _initial;

  @override
  PianoRollState build() => _initial;
}

const _state = PianoRollState(
  config: PianoRollConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 1,
  ),
  notes: [
    PianoRollNote(
      id: 'root',
      midiNote: 61,
      pitchClass: 'C#',
      noteWithOctave: 'C#4',
      startTick: 0,
      durationTicks: 4,
    ),
    PianoRollNote(
      id: 'third',
      midiNote: 65,
      pitchClass: 'F',
      noteWithOctave: 'F4',
      startTick: 0,
      durationTicks: 4,
    ),
    PianoRollNote(
      id: 'fifth',
      midiNote: 68,
      pitchClass: 'G#',
      noteWithOctave: 'G#4',
      startTick: 0,
      durationTicks: 4,
    ),
  ],
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
  selectedColumnTick: 0,
);

void main() {
  testWidgets('Roll detection note and chord labels follow spelling', (
    tester,
  ) async {
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => settings),
        pianoRollProvider.overrideWith(() => _PianoRollNotifier(_state)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PianoRollDetectionPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Db4'), findsOneWidget);
    expect(find.text('Ab4'), findsOneWidget);
    expect(find.text('Db'), findsOneWidget);

    settings.changeSpelling(NoteSpelling.sharps);
    await tester.pumpAndSettle();
    expect(find.text('C#4'), findsOneWidget);
    expect(find.text('G#4'), findsOneWidget);
    expect(find.text('C#'), findsOneWidget);
  });
}
