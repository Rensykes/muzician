/// Song Playback Transport Store
///
/// Dedicated transport provider that reads the [SongProject] at start time,
/// expands it into playback events, and drives the tick loop.  All audio
/// output goes through the injected [songNotePlaybackSinkProvider] and
/// [songDrumPlaybackSinkProvider] so that tests can capture events without
/// real audio.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_playback.dart';
import '../models/song_project.dart';
import '../schema/rules/song_playback_rules.dart' as pb_rules;
import '../schema/rules/song_rules.dart' as song_rules;
import '../utils/note_player.dart';
import 'song_project_store.dart';

/// Signature for a function that plays [midiNotes] as a chord at [volume].
typedef SongNotePlaybackSink =
    Future<void> Function(List<int> midiNotes, double volume);

/// Signature for a function that plays [lanes] as drum voices at [volume].
typedef SongDrumPlaybackSink =
    Future<void> Function(List<DrumLaneId> lanes, double volume);

/// Note playback sink backed by [NotePlayer]. Override in tests to capture events.
final songNotePlaybackSinkProvider = Provider<SongNotePlaybackSink>((ref) {
  return (midiNotes, volume) async {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: volume);
    }
  };
});

final songDrumPlaybackSinkProvider = Provider<SongDrumPlaybackSink>((ref) {
  return (lanes, volume) async {
    for (final lane in lanes) {
      NotePlayer.instance.playDrumLane(lane, volume: volume);
    }
  };
});

/// Riverpod notifier for the song playback transport.
///
/// Snapshots the [SongProject] at the moment [startPlayback] is called so
/// that mid-run edits do not affect the active playback.  Uses an internal
/// version counter for cancellation.
class SongPlaybackNotifier extends Notifier<SongPlaybackState> {
  int _playbackVersion = 0;

  @override
  SongPlaybackState build() => const SongPlaybackState();

  /// Starts playback from [startTick] through [endTickExclusive].
  ///
  /// Returns early without starting transport if already playing or if the
  /// requested range is empty.
  Future<void> startPlayback({int? startTick, int? endTickExclusive}) async {
    if (state.status == SongPlaybackStatus.playing) return;

    // ── Snapshot project state at start ────────────────────────────────────
    final project = ref.read(songProjectProvider);
    final noteSink = ref.read(songNotePlaybackSinkProvider);
    final drumSink = ref.read(songDrumPlaybackSinkProvider);

    final totalTicks = song_rules.songTotalTicks(project.config);
    final start = startTick ?? 0;
    final end = endTickExclusive ?? totalTicks;

    if (start >= end) return;

    final events = pb_rules.buildPlaybackEvents(project);
    final tickDuration = Duration(
      milliseconds: ((60000 / project.config.tempo) / 4).round(),
    );

    // ── Cancel any previous playback ───────────────────────────────────────
    final version = ++_playbackVersion;

    state = SongPlaybackState(
      status: SongPlaybackStatus.playing,
      startTick: start,
      endTickExclusive: end,
      currentTick: start,
    );

    try {
      // Filter events to the requested range.
      final rangeEvents = events
          .where((e) => e.tick >= start && e.tick < end)
          .toList();

      if (rangeEvents.isEmpty) {
        // No events in range, just advance ticks.
        for (
          var tick = start;
          tick < end && _playbackVersion == version;
          tick++
        ) {
          if (tick > start) await Future<void>.delayed(tickDuration);
          if (_playbackVersion != version) return;
          state = state.copyWith(currentTick: () => tick);
        }
      } else {
        var eventIndex = 0;
        for (
          var tick = start;
          tick < end && _playbackVersion == version;
          tick++
        ) {
          if (tick > start) await Future<void>.delayed(tickDuration);
          if (_playbackVersion != version) return;
          state = state.copyWith(currentTick: () => tick);

          // Fire all events at this tick.
          while (eventIndex < rangeEvents.length &&
              rangeEvents[eventIndex].tick == tick) {
            final event = rangeEvents[eventIndex];
            if (event.midiNotes.isNotEmpty) {
              unawaited(noteSink(event.midiNotes, 0.8));
            }
            if (event.drumLanes.isNotEmpty) {
              unawaited(drumSink(event.drumLanes, 0.8));
            }
            eventIndex++;
          }
        }
      }

      if (_playbackVersion == version) {
        // Let last notes decay.
        await Future<void>.delayed(
          Duration(milliseconds: (60000 / project.config.tempo).round()),
        );
        state = const SongPlaybackState(status: SongPlaybackStatus.completed);
      }
    } catch (e) {
      state = SongPlaybackState(
        status: SongPlaybackStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Stops active playback and resets the transport to idle.
  ///
  /// Safe to call repeatedly; cancels any pending scheduled work via an
  /// internal version counter.
  void stopPlayback() {
    _playbackVersion++;
    state = const SongPlaybackState();
  }
}

/// The song playback provider.  Widgets watch this for the current tick,
/// status, and error message.
final songPlaybackProvider =
    NotifierProvider<SongPlaybackNotifier, SongPlaybackState>(
      SongPlaybackNotifier.new,
    );
