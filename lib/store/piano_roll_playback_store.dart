/// Piano Roll Playback Transport Store
///
/// Dedicated transport provider that reads note data from [pianoRollProvider],
/// volume from [settingsProvider], and blocks during hum recording.
/// All audio output goes through the injected [pianoRollPlaybackSinkProvider].
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hum_to_midi.dart';
import '../models/piano_roll_playback.dart';
import '../schema/rules/piano_roll_playback_rules.dart' as rules;
import '../utils/note_player.dart';
import '../utils/tick_pacer.dart';
import 'hum_to_midi_store.dart';
import 'piano_roll_store.dart';
import 'settings_store.dart';

/// Signature for a function that plays [midiNotes] as a chord at [volume].
typedef PianoRollPlaybackSink =
    Future<void> Function(List<int> midiNotes, double volume);

/// Signature for a function that plays a metronome click. [accent] is true on
/// the downbeat (beat 1 of a measure), false on other beats.
typedef PianoRollMetronomeSink = Future<void> Function({required bool accent});

/// Injected playback sink that wraps the synthesised [NotePlayer] engine.
///
/// Override this provider in tests to capture events without real audio.
final pianoRollPlaybackSinkProvider = Provider<PianoRollPlaybackSink>((ref) {
  return (List<int> midiNotes, double volume) async {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: volume);
    }
  };
});

/// Injected metronome sink. Defaults to the synthesised click in [NotePlayer];
/// tests override this with a recorder.
final pianoRollMetronomeSinkProvider = Provider<PianoRollMetronomeSink>((ref) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});

/// Riverpod notifier for the piano roll playback transport.
///
/// Snapshots piano-roll state at the moment [startPlayback] is called so that
/// mid-run edits do not affect the active playback.
class PianoRollPlaybackNotifier extends Notifier<PianoRollPlaybackState> {
  int _playbackVersion = 0;

  @override
  PianoRollPlaybackState build() => const PianoRollPlaybackState();

  /// Starts playback from the selected column (or tick 0) through the end of
  /// the piano roll timeline.
  ///
  /// Returns early without starting transport if:
  ///   - already playing
  ///   - hum status is [HumToMidiStatus.recording], [HumToMidiStatus.processing],
  ///     or [HumToMidiStatus.requestingPermission]
  ///   - there are no notes at or after the start tick
  Future<void> startPlayback({Duration? tickDurationOverride}) async {
    if (state.status == PianoRollPlaybackStatus.playing) return;

    // ── Block while hum is active ──────────────────────────────────────────
    final humState = ref.read(humToMidiProvider);
    if (humState.status == HumToMidiStatus.recording ||
        humState.status == HumToMidiStatus.processing ||
        humState.status == HumToMidiStatus.requestingPermission) {
      state = state.copyWith(
        status: PianoRollPlaybackStatus.completed,
        message: () => 'Playback unavailable while humming',
      );
      return;
    }

    // ── Snapshot piano-roll state and settings ─────────────────────────────
    final prState = ref.read(pianoRollProvider);
    final settings = ref.read(settingsProvider);
    final sink = ref.read(pianoRollPlaybackSinkProvider);
    final metronomeSink = ref.read(pianoRollMetronomeSinkProvider);

    final startTick = rules.resolvePlaybackStartTick(prState);
    final endTick = rules.resolvePlaybackEndTick(prState);
    final events = rules.groupPlaybackEvents(prState.notes, startTick);
    final tempo = prState.config.tempo;
    final volume = settings.noteVolume;
    final metronomeOn = settings.metronomeEnabled;
    final timeSig = prState.config.timeSignature;
    // Quarter-note grid (ticksPerQuarter = 4). One "beat" spans 4 ticks for
    // x/4 signatures and 2 ticks for x/8 (eighth-note beats).
    final beatTicks = timeSig.ticksPerBeat;
    final measureTicks = beatTicks * timeSig.beatsPerMeasure;
    final tickDuration = tickDurationOverride ?? rules.tickDuration(tempo);

    if (events.isEmpty && !metronomeOn) {
      state = state.copyWith(
        status: PianoRollPlaybackStatus.completed,
        message: () => 'Nothing to play from the selected column',
      );
      return;
    }

    // ── Enter playing state ────────────────────────────────────────────────
    final version = ++_playbackVersion;

    state = state.copyWith(
      status: PianoRollPlaybackStatus.playing,
      startTick: () => startTick,
      currentTick: () => null,
      endTickExclusive: () => endTick,
      message: () => null,
      errorMessage: () => null,
    );

    final eventsByTick = <int, List<int>>{
      for (final event in events) event.tick: event.midiNotes,
    };

    // ── Advance the playhead one tick at a time ────────────────────────────
    // [TickPacer] anchors each tick to the wall clock so per-tick body work
    // (state mutation → rebuilds, the awaited note sink, the metronome) cannot
    // accumulate into drift.
    final pacer = TickPacer(tickDuration);
    for (var tick = startTick; tick < endTick; tick++) {
      if (_playbackVersion != version) return;

      if (tick > startTick) await pacer.awaitBoundary(tick - startTick);

      if (_playbackVersion != version) return;

      state = state.copyWith(currentTick: () => tick);

      // Metronome click on beat boundaries. Accent = downbeat (beat 1).
      // Fired before notes so the click can layer with chord onsets without
      // blocking the note sink.
      if (metronomeOn && tick % beatTicks == 0) {
        unawaited(metronomeSink(accent: tick % measureTicks == 0));
      }

      final midiNotes = eventsByTick[tick];
      if (midiNotes != null) {
        await sink(midiNotes, volume);
      }
    }

    // ── Hold the final tick for its full duration before completing ────────
    if (_playbackVersion != version) return;
    await pacer.awaitBoundary(endTick - startTick);

    // ── Transition to completed ────────────────────────────────────────────
    if (_playbackVersion != version) return;

    state = state.copyWith(
      status: PianoRollPlaybackStatus.completed,
      currentTick: () => endTick,
    );
  }

  /// Reflects an external transport's position as the visible playhead without
  /// generating any audio.
  ///
  /// Used when the song pattern editor plays a pattern in *song context*: the
  /// song transport produces the sound, while this mirrors the mapped local
  /// tick into the embedded grid so the playhead still animates.  Pass `null`
  /// to clear the mirrored playhead.
  void mirrorExternalTick(int? localTick) {
    _playbackVersion++;
    if (localTick == null) {
      state = const PianoRollPlaybackState();
      return;
    }
    state = PianoRollPlaybackState(
      status: PianoRollPlaybackStatus.playing,
      currentTick: localTick,
    );
  }

  /// Stops active playback and resets the transport to idle.
  ///
  /// Safe to call repeatedly; cancels any pending scheduled work via an
  /// internal version counter.
  void stopPlayback() {
    _playbackVersion++;
    state = const PianoRollPlaybackState();
  }
}

final pianoRollPlaybackProvider =
    NotifierProvider<PianoRollPlaybackNotifier, PianoRollPlaybackState>(
      PianoRollPlaybackNotifier.new,
    );
