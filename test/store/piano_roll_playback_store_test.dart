import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/piano_roll_playback.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/hum_to_midi_store.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/settings_store.dart';

/// Creates a [ProviderContainer] configured for playback tests with an
/// overridden [pianoRollPlaybackSinkProvider] that records calls into
/// [sinkCalls] and an overridden [pianoRollMetronomeSinkProvider] that
/// records click `accent` flags into [clickCalls].
///
/// Caller must dispose the container via [addTearDown].
({
  ProviderContainer container,
  List<List<int>> sinkCalls,
  List<bool> clickCalls,
})
_createContainer({
  List<(int midiNote, int startTick)> notes = const [],
  int? selectedColumnTick,
  HumToMidiStatus humStatus = HumToMidiStatus.idle,
  int tempo = 300,
  int totalMeasures = 1,
  // Legacy tests assume metronome OFF so the "Nothing to play" early-return
  // still fires when notes are empty. New tests opt in.
  bool metronomeEnabled = false,
}) {
  final sinkCalls = <List<int>>[];
  final clickCalls = <bool>[];

  final container = ProviderContainer(
    overrides: [
      pianoRollPlaybackSinkProvider.overrideWithValue((
        List<int> midiNotes,
        double volume,
      ) async {
        sinkCalls.add(List<int>.unmodifiable(midiNotes));
      }),
      pianoRollMetronomeSinkProvider.overrideWithValue(({
        required bool accent,
      }) async {
        clickCalls.add(accent);
      }),
    ],
  );

  // ignore: invalid_use_of_protected_member
  container.read(settingsProvider.notifier).state = AppSettings(
    metronomeEnabled: metronomeEnabled,
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
    container.read(humToMidiProvider.notifier).state = HumToMidiState(
      status: humStatus,
    );
  }

  return (container: container, sinkCalls: sinkCalls, clickCalls: clickCalls);
}

void main() {
  group('PianoRollPlaybackNotifier', () {
    test('startPlayback emits note groups from selectedColumnTick to '
        'timeline end', () async {
      final env = _createContainer(
        selectedColumnTick: 4,
        notes: [(60, 0), (64, 4), (67, 8)],
      );

      final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
      await notifier.startPlayback();

      expect(env.sinkCalls, hasLength(2));
      expect(env.sinkCalls[0], [64]);
      expect(env.sinkCalls[1], [67]);

      final state = env.container.read(pianoRollPlaybackProvider);
      expect(state.status, PianoRollPlaybackStatus.completed);
      expect(state.startTick, 4);
      // 1 measure = 16 ticks at 4/4 time (4 beats * 4 ticks/beat)
      expect(state.endTickExclusive, 16);
    });

    test(
      'stopPlayback cancels pending transport work and returns to idle',
      () async {
        final env = _createContainer(
          selectedColumnTick: 0,
          notes: [(60, 0), (64, 4)],
        );

        final notifier = env.container.read(pianoRollPlaybackProvider.notifier);

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

        final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
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
        final env = _createContainer(selectedColumnTick: 8, notes: [(60, 0)]);

        final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
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

      final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
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

    test('playback snapshots piano roll notes at start so mid-run edits '
        'do not affect the active transport', () async {
      final env = _createContainer(
        selectedColumnTick: 0,
        notes: [(60, 0), (64, 4)],
      );

      final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
      final prNotifier = env.container.read(pianoRollProvider.notifier);

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
    });

    test('metronome plays a click on each beat with accent on the downbeat '
        '(4/4, no notes)', () async {
      final env = _createContainer(
        selectedColumnTick: 0,
        notes: const [],
        totalMeasures: 1,
        metronomeEnabled: true,
      );

      final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
      await notifier.startPlayback();

      // 4/4 1 measure = 16 ticks; beats at ticks 0,4,8,12 → 4 clicks total.
      // Tick 0 is the downbeat (accent=true); others are weak (accent=false).
      expect(env.clickCalls, [true, false, false, false]);
      expect(env.sinkCalls, isEmpty);
      expect(
        env.container.read(pianoRollPlaybackProvider).status,
        PianoRollPlaybackStatus.completed,
      );
    });

    test('metronome aligns clicks to absolute tick boundaries even when '
        'playback starts mid-measure', () async {
      final env = _createContainer(
        selectedColumnTick: 8,
        notes: const [],
        totalMeasures: 1,
        metronomeEnabled: true,
      );

      final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
      await notifier.startPlayback();

      // Start at tick 8 (beat 3 of 4/4). Remaining beats: 8 (weak), 12 (weak).
      expect(env.clickCalls, [false, false]);
    });

    test('metronome respects the time signature beat unit (6/8 → eighth-note '
        'beats every 2 ticks)', () async {
      final env = _createContainer(
        selectedColumnTick: 0,
        notes: const [],
        totalMeasures: 1,
        metronomeEnabled: true,
      );
      env.container
          .read(pianoRollProvider.notifier)
          .setTimeSignature(
            const TimeSignature(beatsPerMeasure: 6, beatUnit: 8),
          );

      final notifier = env.container.read(pianoRollPlaybackProvider.notifier);
      await notifier.startPlayback();

      // 6/8 1 measure = 6 beats × 2 ticks = 12 ticks.
      // Clicks at ticks 0,2,4,6,8,10 → 6 clicks; first is accent.
      expect(env.clickCalls, [true, false, false, false, false, false]);
    });

    test(
      'currentTick advances during silent spans before the next note event',
      () async {
        final env = _createContainer(
          selectedColumnTick: 0,
          notes: [(60, 4)],
          tempo: 300,
        );

        final notifier = env.container.read(pianoRollPlaybackProvider.notifier);

        final playbackFuture = notifier.startPlayback();

        await Future<void>.delayed(const Duration(milliseconds: 120));

        final playingState = env.container.read(pianoRollPlaybackProvider);
        expect(playingState.status, PianoRollPlaybackStatus.playing);
        expect(playingState.currentTick, isNotNull);
        expect(playingState.currentTick, greaterThan(0));
        expect(playingState.currentTick, lessThan(4));
        expect(env.sinkCalls, isEmpty);

        notifier.stopPlayback();
        await playbackFuture;
      },
    );

    test(
      'tick clock is wall-anchored: per-beat body cost does not accumulate '
      'as drift',
      () async {
        // Inject a heavy synchronous cost on every metronome beat. Without
        // wall-clock anchoring the loop adds this on top of every tick's fixed
        // delay, so total playback time balloons past the ideal span. With
        // anchoring it is absorbed into the per-tick budget.
        final container = ProviderContainer(
          overrides: [
            pianoRollPlaybackSinkProvider.overrideWithValue(
              (notes, volume) async {},
            ),
            pianoRollMetronomeSinkProvider.overrideWithValue(({
              required bool accent,
            }) async {
              final spin = Stopwatch()..start();
              while (spin.elapsedMilliseconds < 12) {
                // Busy-wait simulating per-beat UI/audio work on the loop.
              }
            }),
          ],
        );
        addTearDown(container.dispose);

        // ignore: invalid_use_of_protected_member
        container.read(settingsProvider.notifier).state = AppSettings(
          metronomeEnabled: true,
        );
        final pr = container.read(pianoRollProvider.notifier);
        pr.setTotalMeasures(2); // 2 bars 4/4 → 32 ticks, 8 beats.
        pr.selectColumn(0);

        final notifier = container.read(pianoRollPlaybackProvider.notifier);
        final clock = Stopwatch()..start();
        // 32 ticks × 4ms ≈ 128ms ideal span; 8 beats × 12ms = 96ms injected
        // cost. Anchored, total stays near the ideal span (cost overlaps the
        // waits). Unanchored it would be ~128 + 96 ≈ 224ms.
        await notifier.startPlayback(
          tickDurationOverride: const Duration(milliseconds: 4),
        );
        final elapsedMs = clock.elapsedMilliseconds;

        expect(
          container.read(pianoRollPlaybackProvider).status,
          PianoRollPlaybackStatus.completed,
        );
        expect(
          elapsedMs,
          lessThan(180),
          reason: 'drift not absorbed; loop ran for ${elapsedMs}ms',
        );
      },
    );
  });
}
