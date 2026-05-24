import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_toolbar.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/piano_roll_playback.dart';
import 'package:muzician/store/hum_to_midi_store.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/store/piano_roll_store.dart';

// ── Fake notifiers ────────────────────────────────────────────────────────────

class FakePlaybackNotifier extends PianoRollPlaybackNotifier {
  FakePlaybackNotifier(this._initial);

  final PianoRollPlaybackState _initial;

  @override
  PianoRollPlaybackState build() => _initial;

  @override
  Future<void> startPlayback() async {
    if (state.status == PianoRollPlaybackStatus.playing) return;

    final prState = ref.read(pianoRollProvider);
    final startTick = prState.selectedColumnTick ?? 0;
    state = state.copyWith(
      status: PianoRollPlaybackStatus.playing,
      startTick: () => startTick,
      currentTick: () => startTick,
    );
  }

  @override
  void stopPlayback() {
    state = const PianoRollPlaybackState();
  }
}

class FakeHumNotifier extends HumToMidiNotifier {
  FakeHumNotifier(this._initial);

  final HumToMidiState _initial;

  @override
  HumToMidiState build() => _initial;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Default piano-roll state with a 4/4, 4-measure, 120 BPM config.
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

Widget _buildApp({
  required PianoRollPlaybackState playbackState,
  PianoRollState prState = _defaultPRState,
  HumToMidiState humState = const HumToMidiState(),
}) {
  final container = ProviderContainer(
    overrides: [
      pianoRollPlaybackProvider.overrideWith(
        () => FakePlaybackNotifier(playbackState),
      ),
      pianoRollProvider.overrideWith(
        () => FakePianoRollNotifier(prState),
      ),
      humToMidiProvider.overrideWith(
        () => FakeHumNotifier(humState),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PianoRollPlaybackConfig(),
        ),
      ),
    ),
  );
}

class FakePianoRollNotifier extends PianoRollNotifier {
  FakePianoRollNotifier(this._initial);

  final PianoRollState _initial;

  @override
  PianoRollState build() => _initial;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('PianoRollPlaybackConfig', () {
    testWidgets('shows Play when idle and Stop while playing', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          playbackState: const PianoRollPlaybackState(
            status: PianoRollPlaybackStatus.idle,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);

      // Tap Play
      await tester.tap(find.text('Play'));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
    });

    testWidgets(
      'shows the selected start tick in the playback panel',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            playbackState: const PianoRollPlaybackState(
              status: PianoRollPlaybackStatus.idle,
            ),
            prState: _defaultPRState.copyWith(selectedColumnTick: () => 16),
          ),
        );
        await tester.pump();

        expect(find.textContaining('Selected column'), findsOneWidget);
        expect(find.textContaining('tick 17'), findsOneWidget);
      },
    );

    testWidgets(
      'disables Play while hum recording is active',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            playbackState: const PianoRollPlaybackState(
              status: PianoRollPlaybackStatus.idle,
            ),
            humState: const HumToMidiState(
              status: HumToMidiStatus.recording,
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Playback unavailable while humming'),
          findsOneWidget,
        );
        expect(find.text('Play'), findsNothing);
        expect(find.text('Stop'), findsNothing);
      },
    );

    testWidgets(
      'shows a fallback start label when no selected column exists',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            playbackState: const PianoRollPlaybackState(
              status: PianoRollPlaybackStatus.idle,
            ),
            prState: _defaultPRState.copyWith(selectedColumnTick: () => null),
          ),
        );
        await tester.pump();

        expect(find.textContaining('Beginning of roll'), findsOneWidget);
      },
    );
  });
}
