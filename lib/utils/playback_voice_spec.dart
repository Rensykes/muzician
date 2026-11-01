/// Value description of one synthesised voice a playback run will sound.
///
/// [NotePlayer] derives both its WAV cache key and its renderer from the spec,
/// so a voice prepared ahead of a run is the exact cache entry the play paths
/// later look up.
library;

import 'package:flutter/foundation.dart';

import '../models/guitar_sound.dart';
import '../models/song_project.dart' show DrumLaneId;
import 'guitar_synth.dart';

enum PlaybackVoiceKind {
  click,
  drum,
  sequencedNote,
  sequencedChord,
  guitarStroke,
}

@immutable
class PlaybackVoiceSpec {
  const PlaybackVoiceSpec._({
    required this.kind,
    this.accent = false,
    this.lane,
    this.midiNotes = const [],
    this.strokeStrings = const [],
    this.durationMs = 0,
    this.guitarTone,
  });

  /// Metronome click; the accent is the brighter downbeat flavor.
  const PlaybackVoiceSpec.click({required bool accent})
    : this._(kind: PlaybackVoiceKind.click, accent: accent);

  const PlaybackVoiceSpec.drum(DrumLaneId lane)
    : this._(kind: PlaybackVoiceKind.drum, lane: lane);

  /// One duration-aware note. Guitar pitches are clamped to the MIDI range;
  /// piano pitches are kept as given, matching the sequenced play path.
  factory PlaybackVoiceSpec.sequencedNote(
    int midi, {
    required Duration duration,
    GuitarTone? guitarTone,
  }) => PlaybackVoiceSpec._(
    kind: PlaybackVoiceKind.sequencedNote,
    midiNotes: [guitarTone == null ? midi : GuitarSynth.safeMidi(midi)],
    durationMs: guitarTone != null
        ? GuitarSynth.durationMilliseconds(duration)
        : duration.inMilliseconds < 1
        ? 1
        : duration.inMilliseconds,
    guitarTone: guitarTone,
  );

  /// Simultaneous notes bound to one platform voice. [guitarTone] null is piano.
  factory PlaybackVoiceSpec.sequencedChord(
    List<int> midiNotes, {
    required Duration duration,
    GuitarTone? guitarTone,
  }) => PlaybackVoiceSpec._(
    kind: PlaybackVoiceKind.sequencedChord,
    midiNotes: (midiNotes.map(GuitarSynth.safeMidi).toList()..sort()),
    durationMs: GuitarSynth.durationMilliseconds(duration),
    guitarTone: guitarTone,
  );

  /// One guitar stroke bound to one platform voice: each string keeps its own
  /// onset and duration inside the rendered WAV. [strings] are in stroke order.
  factory PlaybackVoiceSpec.guitarStroke(
    List<GuitarStrokeString> strings, {
    required GuitarTone guitarTone,
  }) {
    final normalized = GuitarSynth.normalizeStroke(strings);
    var end = 0;
    for (final string in normalized) {
      end = end > string.onsetMs + string.durationMs
          ? end
          : string.onsetMs + string.durationMs;
    }
    return PlaybackVoiceSpec._(
      kind: PlaybackVoiceKind.guitarStroke,
      strokeStrings: normalized,
      durationMs: end,
      guitarTone: guitarTone,
    );
  }

  final PlaybackVoiceKind kind;
  final bool accent;
  final DrumLaneId? lane;
  final List<int> midiNotes;
  final List<GuitarStrokeString> strokeStrings;

  /// Overall length: the latest end across a stroke's strings.
  final int durationMs;
  final GuitarTone? guitarTone;

  /// Cache key shared with the play paths. Integer ranges are reserved:
  /// MIDI-sized and large sequenced keys are non-negative, clicks are -1/-2,
  /// drums -10…-17.
  Object get cacheKey => switch (kind) {
    PlaybackVoiceKind.click => accent ? -1 : -2,
    PlaybackVoiceKind.drum => drumCacheKey(lane!),
    PlaybackVoiceKind.sequencedNote =>
      guitarTone == null
          ? 1000000 + midiNotes.first * 10000000000 + durationMs
          : GuitarSynth.noteCacheKey(
              midiNotes.first,
              tone: guitarTone!,
              duration: Duration(milliseconds: durationMs),
            ),
    PlaybackVoiceKind.sequencedChord =>
      'chord_v${GuitarSynth.cacheVersion}_${guitarTone?.name ?? 'piano'}_'
          '${midiNotes.join('_')}_$durationMs',
    PlaybackVoiceKind.guitarStroke => GuitarSynth.strokeCacheKey(
      strokeStrings,
      tone: guitarTone!,
    ),
  };

  static int drumCacheKey(DrumLaneId lane) => switch (lane) {
    DrumLaneId.kick => -10,
    DrumLaneId.snare => -11,
    DrumLaneId.closedHiHat => -12,
    DrumLaneId.openHiHat => -13,
    DrumLaneId.clap => -14,
    DrumLaneId.lowTom => -15,
    DrumLaneId.highTom => -16,
    DrumLaneId.crash => -17,
  };

  @override
  bool operator ==(Object other) =>
      other is PlaybackVoiceSpec && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'PlaybackVoiceSpec($cacheKey)';
}
