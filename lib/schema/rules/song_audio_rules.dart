/// Pure functions linking audio assets to the project's tick grid.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'song_rules.dart' show songTicksPerMeasure;

int _ticksPerBeat(TimeSignature ts) => ts.beatUnit == 8 ? 2 : 4;

/// Returns the grid length, in ticks, that the given asset should occupy at
/// the project's current tempo.  Audio always plays at native rate, so the
/// real duration is the source of truth and this is a derived view.
int audioClipLengthTicks(AudioAsset asset, SongProjectConfig config) {
  final beatsPerSecond = config.tempo / 60.0;
  final ticksPerBeat = _ticksPerBeat(config.timeSignature);
  final ticks = (asset.durationMs / 1000.0) * beatsPerSecond * ticksPerBeat;
  return math.max(1, ticks.round());
}

/// Returns the wall-clock time, in milliseconds since transport start, of the
/// given absolute tick at the project's current tempo.
int audioTickToMs(int tick, SongProjectConfig config) {
  final beatsPerSecond = config.tempo / 60.0;
  final ticksPerBeat = _ticksPerBeat(config.timeSignature);
  final beats = tick / ticksPerBeat;
  return (beats / beatsPerSecond * 1000.0).round();
}

/// Ensures the project's total measure count covers the given end tick — same
/// behaviour as the note/drum side, exposed here so the audio paths do not
/// need to import `song_rules` directly.
int requiredMeasuresForEndTick(int endTick, SongProjectConfig config) {
  final perMeasure = songTicksPerMeasure(config.timeSignature);
  return math.max(config.totalMeasures, (endTick / perMeasure).ceil());
}

class ScheduledAudioClip {
  final SongClipInstance clip;
  final AudioClipPattern pattern;
  final AudioAsset asset;
  final int startMs;
  final int endMs;

  const ScheduledAudioClip({
    required this.clip,
    required this.pattern,
    required this.asset,
    required this.startMs,
    required this.endMs,
  });
}

/// Returns every audio clip that should play given the project's current
/// mute/solo state, with its absolute start and end times in milliseconds.
List<ScheduledAudioClip> schedulableAudioClips(SongProject project) {
  final hasSolo = project.tracks.any((t) => t.isSolo);
  final audible = <String>{
    for (final t in project.tracks)
      if (t.type == SongTrackType.audio && (hasSolo ? t.isSolo : !t.isMuted))
        t.id,
  };
  final patternById = {for (final p in project.audioPatterns) p.id: p};
  final assetById = {for (final a in project.audioAssets) a.id: a};

  final out = <ScheduledAudioClip>[];
  for (final clip in project.clips) {
    if (clip.patternType != SongPatternType.audio) continue;
    if (!audible.contains(clip.trackId)) continue;
    final pattern = patternById[clip.patternId];
    if (pattern == null) continue;
    final asset = assetById[pattern.assetId];
    if (asset == null) continue;
    final startMs = audioTickToMs(clip.startTick, project.config);
    out.add(
      ScheduledAudioClip(
        clip: clip,
        pattern: pattern,
        asset: asset,
        startMs: startMs,
        endMs: startMs + asset.durationMs,
      ),
    );
  }
  return out;
}

/// Compresses a PCM 16-bit sample buffer down to [targetBins] amplitude bins
/// scaled to 0..255.  Each bin holds the absolute maximum across the samples
/// assigned to it.  Used to render audio clip waveforms on the timeline.
List<int> computePeaksFromInt16(Int16List samples, {int targetBins = 400}) {
  if (samples.isEmpty) return const [];
  final bins = math.min(targetBins, samples.length);
  final step = samples.length / bins;
  final out = List<int>.filled(bins, 0);
  for (var i = 0; i < bins; i++) {
    final from = (i * step).floor();
    final to = math.min(samples.length, ((i + 1) * step).floor());
    var peak = 0;
    for (var s = from; s < to; s++) {
      final v = samples[s].abs();
      if (v > peak) peak = v;
    }
    out[i] = (peak * 255 / 32767).round().clamp(0, 255);
  }
  return out;
}
