import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll_playback.dart';
import 'package:muzician/store/hum_to_midi_store.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/store/piano_roll_store.dart';

/// Creates a [ProviderContainer] configured for playback tests with an
/// overridden [pianoRollPlaybackSinkProvider] that records calls into
/// [sinkCalls].
///
/// Caller must dispose the container via [addTearDown].
({ProviderContainer container, List<List<int>> sinkCalls})
_createContainer({
  List<(int midiNote, int startTick)> notes = const [],
  int? selectedColumnTick,
  HumToMidiStatus humStatus = HumToMidiStatus.idle,
  int tempo = 300,
  int totalMeasures = 1,
}) {
  final sinkCalls = <List<int>>[];

  final container = ProviderContainer(
    overrides: [
      pianoRollPlaybackSinkProvider.overrideWithValue(
        (List<int> midiNotes, double volume) async {
          sinkCalls.add(List<int>.unmodifiable(midiNotes));
        },
      ),
    ],
  );

  final pr = container.read(pianoRollProvider.notifier);
  pr.setTempo(tempo);
  pr.setTotalMeasures(totalMeasures);
  for (final (midi, tick) in notes) {
    pr.addNote(midi, tick, 1);
  }
  pr.selectColumn(selectedColumnTick);

  if (humStatus != HumToMidiStatus.idle) {
    // ignore: invalid_use_of_protected_member
    container.read(humToMidiProvider.notifier).state =
        HumToMidiState(status: humStatus);
  }

  return (container: container, sinkCalls: sinkCalls);
}

void main() {
  group('PianoRollPlaybackNotifier', () {
    test(
      'startPlayback emits note groups from selectedColumnTick to '
      'timeline end',
      () async {
        final env = _createContainer(
          selectedColumnTick: 4,
          notes: [(60, 0), (64, 4), (67, 8)],
        );

        final notifier =
            env.container.read(pianoRollPlaybackProvider.notifier);
        await notifier.startPlayback();

        expect(env.sinkCalls, hasLength(2));
        expect(env.sinkCalls[0], [64]);
        expect(env.sinkCalls[1], [67]);

        final state = env.container.read(pianoRollPlaybackProvider);
        expect(state.status, PianoRollPlaybackStatus.completed);
        expect(state.startTick, 4);
        // 1 measure = 16 ticks at 4/4 time (4 beats * 4 ticks/beat)
        expect(state.endTickExclusive, 16);
      },
    );

    test(
      'stopPlayback cancels pending transport work and returns to idle',
      () async {
        final env = _createContainer(
          selectedColumnTick: 0,
          notes: [(60, 0), (64, 4)],
        );

        final notifier =
            env.container.read(pianoRollPlaybackProvider.notifier);

        // Start without awaiting completion.
        final playbackFuture = notifier.startPlayback();

        // Let the first event (tick 0, Duration.zero delay) fire.
        await Future<void>.delayed(Duration.zero);

        expect(env.sinkCalls, hasLength(1));
        expect(env.sinkCalls[0], [60]);

        notifier.stopPlayback();

        expect(
          env.container.read(pianoRollPlaybackProvider).status,
          PianoRollPlaybackStatus.idle,
        );

        // Let the pending loop timer settle.
        await playbackFuture;

        // No additional events should have fired.
        expect(env.sinkCalls, hasLength(1));
      },
    );

    test(
      'playback completes cleanly when the timeline end is reached',
      () async {
        final env = _createContainer(
          selectedColumnTick: 0,
          notes: [(60, 0), (64, 4)],
        );

        final notifier =
            env.container.read(pianoRollPlaybackProvider.notifier);
        await notifier.startPlayback();

        expect(
          env.container.read(pianoRollPlaybackProvider).status,
          PianoRollPlaybackStatus.completed,
        );
        expect(env.sinkCalls, hasLength(2));
        expect(env.sinkCalls[0], [60]);
        expect(env.sinkCalls[1], [64]);
      },
    );

    test(
      'playback does nothing when there are no notes at or after the start tick',
      () async {
        final env = _createContainer(
          selectedColumnTick: 8,
          notes: [(60, 0)],
        );

        final notifier =
            env.container.read(pianoRollPlaybackProvider.notifier);
        await notifier.startPlayback();

        expect(env.sinkCalls, isEmpty);
        expect(
          env.container.read(pianoRollPlaybackProvider).status,
          PianoRollPlaybackStatus.completed,
        );
        expect(
          env.container.read(pianoRollPlaybackProvider).message,
          'Nothing to play from the selected column',
        );
      },
    );

    test('playback is blocked while hum recording is active', () async {
      final env = _createContainer(
        humStatus: HumToMidiStatus.recording,
        selectedColumnTick: 0,
        notes: [(60, 0)],
      );

      final notifier =
          env.container.read(pianoRollPlaybackProvider.notifier);
      await notifier.startPlayback();

      expect(env.sinkCalls, isEmpty);
      expect(
        env.container.read(pianoRollPlaybackProvider).status,
        PianoRollPlaybackStatus.completed,
      );
      expect(
        env.container.read(pianoRollPlaybackProvider).message,
        'Playback unavailable while humming',
      );
    });

    test(
      'playback snapshots piano roll notes at start so mid-run edits '
      'do not affect the active transport',
      () async {
        final env = _createContainer(
          selectedColumnTick: 0,
          notes: [(60, 0), (64, 4)],
        );

        final notifier =
            env.container.read(pianoRollPlaybackProvider.notifier);
        final prNotifier =
            env.container.read(pianoRollProvider.notifier);

        // Start playback without awaiting completion.
        final playbackFuture = notifier.startPlayback();

        // Let the first event (tick 0) fire before mutating.
        await Future<void>.delayed(Duration.zero);

        // Mutate piano-roll state mid-playback.
        prNotifier.addNote(67, 8, 1);

        // Wait for the transport to finish.
        await playbackFuture;

        // Only the original snapshotted notes should have played.
        expect(env.sinkCalls, hasLength(2));
        expect(env.sinkCalls[0], [60]);
        expect(env.sinkCalls[1], [64]);
        expect(
          env.container.read(pianoRollPlaybackProvider).status,
          PianoRollPlaybackStatus.completed,
        );
      },
    );
  });
}
