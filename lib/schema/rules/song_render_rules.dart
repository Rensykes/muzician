/// Offline song renderer: mixes note + drum tracks into mono PCM16 for WAV
/// export. Audio clips are excluded in v1 (noted in the export UI).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/song_project.dart';
import 'song_playback_rules.dart' as pb_rules;
import 'song_rules.dart' as song_rules;

/// Renders [project]'s note and drum tracks to mono PCM16 at [sampleRate].
///
/// Simple synth voices: notes are sine tones with an exponential decay
/// envelope; drums are short sine thumps (kick/toms) or noise bursts
/// (snare/hats/clap/crash). Per-track volume is honored.
Int16List renderSongPcm(SongProject project, {int sampleRate = 44100}) {
  final ticksTotal = song_rules.songTotalTicks(project.config);
  // Match the playback/audio grid: x/8 signatures use 2 ticks per beat, others
  // 4. Hardcoding 4 here double-speeds x/8 exports relative to in-app playback.
  final tickMs =
      (60000 / project.config.tempo) /
      project.config.timeSignature.ticksPerBeat;
  final tailMs = 1000;
  final totalSamples =
      ((ticksTotal * tickMs + tailMs) / 1000 * sampleRate).ceil();
  final mix = Float64List(totalSamples);

  int sampleAtTick(int tick) => (tick * tickMs / 1000 * sampleRate).round();

  final volumeByTrack = {
    for (final t in pb_rules.audibleTracks(project)) t.id: t.volume,
  };

  // ── Notes: per-clip expansion keeps durations. ───────────────────────────
  final notePatternById = {for (final p in project.notePatterns) p.id: p};
  for (final clip in project.clips) {
    if (clip.patternType != SongPatternType.note) continue;
    final volume = volumeByTrack[clip.trackId];
    if (volume == null) continue;
    final pattern = notePatternById[clip.patternId];
    if (pattern == null) continue;
    for (final note in pattern.notes) {
      final start = sampleAtTick(clip.startTick + note.startTick);
      final durMs = (note.durationTicks * tickMs).clamp(60.0, 2000.0);
      _addSine(
        mix,
        start: start,
        freq: 440.0 * math.pow(2.0, (note.midiNote - 69) / 12.0).toDouble(),
        durationSamples: (durMs / 1000 * sampleRate).round(),
        amplitude: 0.18 * volume,
        sampleRate: sampleRate,
      );
    }
  }

  // ── Drums. ───────────────────────────────────────────────────────────────
  final drumPatternById = {for (final p in project.drumPatterns) p.id: p};
  for (final clip in project.clips) {
    if (clip.patternType != SongPatternType.drum) continue;
    final volume = volumeByTrack[clip.trackId];
    if (volume == null) continue;
    final pattern = drumPatternById[clip.patternId];
    if (pattern == null) continue;
    for (final lane in pattern.lanes) {
      for (final tick in lane.activeTicks) {
        final start = sampleAtTick(clip.startTick + tick);
        _addDrum(mix, lane.laneId, start, 0.5 * volume, sampleRate);
      }
    }
  }

  // ── Clamp to PCM16. ──────────────────────────────────────────────────────
  final out = Int16List(totalSamples);
  for (var i = 0; i < totalSamples; i++) {
    out[i] = (mix[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return out;
}

void _addSine(
  Float64List mix, {
  required int start,
  required double freq,
  required int durationSamples,
  required double amplitude,
  required int sampleRate,
}) {
  final end = math.min(start + durationSamples, mix.length);
  for (var i = start; i < end; i++) {
    final t = (i - start) / sampleRate;
    final env = math.exp(-3.0 * (i - start) / durationSamples);
    mix[i] += amplitude * env * math.sin(2 * math.pi * freq * t);
  }
}

void _addDrum(
  Float64List mix,
  DrumLaneId lane,
  int start,
  double amplitude,
  int sampleRate,
) {
  switch (lane) {
    case DrumLaneId.kick:
      _addThump(mix, start, 55, 0.12, amplitude, sampleRate);
    case DrumLaneId.lowTom:
      _addThump(mix, start, 110, 0.12, amplitude * 0.9, sampleRate);
    case DrumLaneId.highTom:
      _addThump(mix, start, 165, 0.10, amplitude * 0.9, sampleRate);
    case DrumLaneId.snare:
      _addNoise(mix, start, 0.12, amplitude, sampleRate);
    case DrumLaneId.clap:
      _addNoise(mix, start, 0.08, amplitude * 0.9, sampleRate);
    case DrumLaneId.closedHiHat:
      _addNoise(mix, start, 0.04, amplitude * 0.6, sampleRate);
    case DrumLaneId.openHiHat:
      _addNoise(mix, start, 0.18, amplitude * 0.6, sampleRate);
    case DrumLaneId.crash:
      _addNoise(mix, start, 0.6, amplitude * 0.7, sampleRate);
  }
}

void _addThump(
  Float64List mix,
  int start,
  double freq,
  double durationSec,
  double amplitude,
  int sampleRate,
) {
  final samples = (durationSec * sampleRate).round();
  final end = math.min(start + samples, mix.length);
  for (var i = start; i < end; i++) {
    final t = (i - start) / sampleRate;
    final env = math.exp(-8.0 * (i - start) / samples);
    // Slight downward pitch sweep for punch.
    mix[i] += amplitude * env * math.sin(2 * math.pi * freq * (1 + 0.5 * env) * t);
  }
}

void _addNoise(
  Float64List mix,
  int start,
  double durationSec,
  double amplitude,
  int sampleRate,
) {
  final samples = (durationSec * sampleRate).round();
  final end = math.min(start + samples, mix.length);
  final rng = math.Random(start); // deterministic per onset
  for (var i = start; i < end; i++) {
    final env = math.exp(-6.0 * (i - start) / samples);
    mix[i] += amplitude * env * (rng.nextDouble() * 2 - 1);
  }
}
