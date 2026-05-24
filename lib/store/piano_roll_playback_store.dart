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
import 'hum_to_midi_store.dart';
import 'piano_roll_store.dart';
import 'settings_store.dart';

/// Signature for a function that plays [midiNotes] as a chord at [volume].
typedef PianoRollPlaybackSink =
    Future<void> Function(List<int> midiNotes, double volume);

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
  Future<void> startPlayback() async {
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

    final startTick = rules.resolvePlaybackStartTick(prState);
    final endTick = rules.resolvePlaybackEndTick(prState);
    final events = rules.groupPlaybackEvents(prState.notes, startTick);
    final tempo = prState.config.tempo;
    final volume = settings.noteVolume;

    if (events.isEmpty) {
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

    // ── Iterate events with timing ─────────────────────────────────────────
    var previousTick = startTick;
    for (final event in events) {
      if (_playbackVersion != version) return;

      final delay = rules.durationForTickDelta(event.tick - previousTick, tempo);
      await Future<void>.delayed(delay);

      if (_playbackVersion != version) return;

      await sink(event.midiNotes, volume);
      state = state.copyWith(currentTick: () => event.tick);
      previousTick = event.tick;
    }

    // ── Wait out remaining silent span ─────────────────────────────────────
    if (_playbackVersion != version) return;

    final remaining = rules.durationForTickDelta(endTick - previousTick, tempo);
    await Future<void>.delayed(remaining);

    // ── Transition to completed ────────────────────────────────────────────
    if (_playbackVersion != version) return;

    state = state.copyWith(
      status: PianoRollPlaybackStatus.completed,
      currentTick: () => endTick,
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
