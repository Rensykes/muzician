import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_hum_recorder.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/store/hum_to_midi_store.dart';
import 'package:muzician/store/piano_roll_store.dart';

class FakeHumNotifier extends HumToMidiNotifier {
  FakeHumNotifier(this._initial);

  final HumToMidiState _initial;

  @override
  HumToMidiState build() => _initial;
}

class FakePianoRollNotifier extends PianoRollNotifier {
  FakePianoRollNotifier(this._initial);

  final PianoRollState _initial;

  @override
  PianoRollState build() => _initial;
}

const _defaultPRState = PianoRollState(
  config: PianoRollConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 4,
  ),
  notes: [],
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
);

void main() {
  testWidgets('shows jump to latest when latest imported range exists', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => FakePianoRollNotifier(
            _defaultPRState.copyWith(
              latestImportedRange: () => const PianoRollImportedRange(
                startTick: 32,
                endTickExclusive: 40,
              ),
            ),
          ),
        ),
        humToMidiProvider.overrideWith(
          () => FakeHumNotifier(
            const HumToMidiState(status: HumToMidiStatus.completed),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PianoRollHumRecorderPanel()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Jump to latest'), findsOneWidget);
  });

  testWidgets(
    'tapping jump to latest emits scroll tick and preserves selected column',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          pianoRollProvider.overrideWith(
            () => FakePianoRollNotifier(
              _defaultPRState.copyWith(
                selectedColumnTick: () => 12,
                latestImportedRange: () => const PianoRollImportedRange(
                  startTick: 32,
                  endTickExclusive: 40,
                ),
              ),
            ),
          ),
          humToMidiProvider.overrideWith(
            () => FakeHumNotifier(
              const HumToMidiState(
                status: HumToMidiStatus.completed,
                feedbackMessage: 'Imported',
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
            home: Scaffold(body: PianoRollHumRecorderPanel()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Jump to latest'));
      await tester.pump();

      expect(container.read(pianoRollScrollToTickProvider), 32);
      expect(container.read(pianoRollProvider).selectedColumnTick, 12);
    },
  );

  testWidgets('hides jump to latest when remembered range is absent', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => FakePianoRollNotifier(_defaultPRState),
        ),
        humToMidiProvider.overrideWith(
          () => FakeHumNotifier(
            const HumToMidiState(status: HumToMidiStatus.completed),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PianoRollHumRecorderPanel()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Jump to latest'), findsNothing);
  });

  testWidgets('shows the live note and stop button while recording', (
    tester,
  ) async {
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
