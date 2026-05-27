/// NotePlayer – pure-Dart additive-synthesis note preview.
///
/// Platform strategy:
///   iOS / macOS   → DeviceFileSource (.wav in Documents; AVPlayer needs extension
///                   and audioplayers_darwin can't guarantee its internal Caches
///                   sub-directory exists on macOS sandbox)
///   Android/Linux → BytesSource (direct bytes over platform channel)
///   Web/Chrome    → BytesSource (dart:io unavailable; Web Audio API handles bytes)
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/song_project.dart';

// Conditional import: note_player_io.dart on native, note_player_web.dart on web.
import 'note_player_io.dart' if (dart.library.html) 'note_player_web.dart';

// ── Platform detection ───────────────────────────────────────────────────────

// Use DeviceFileSource on Apple platforms (iOS + macOS); BytesSource elsewhere.
bool get _needsFile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

// ── Synthesis constants ──────────────────────────────────────────────────────

const _sampleRate = 44100;
const _noteDurationMs = 700;
const _decayRate = 5.5;
const _poolSize = 6;

// Metronome click — short percussive sine with steep decay. Two flavors:
// the accent fires on the downbeat (beat 1), the weak click on other beats.
const _clickDurationMs = 35;
const _clickDecayRate = 140.0;
const _clickFreqAccent = 2000.0;
const _clickFreqWeak = 1500.0;

// Drum synthesis durations (ms) and decay rates.
const _drumKickDurationMs = 200;
const _drumKickFreq = 55.0;
const _drumKickDecay = 22.0;

const _drumSnareDurationMs = 150;
const _drumSnareBodyFreq = 200.0;
const _drumSnareDecay = 18.0;

const _drumHiHatClosedDurationMs = 50;
const _drumHiHatClosedDecay = 80.0;

const _drumHiHatOpenDurationMs = 250;
const _drumHiHatOpenDecay = 15.0;

const _drumClapDurationMs = 150;
const _drumClapBurstCount = 4;

const _drumLowTomDurationMs = 200;
const _drumLowTomFreq = 100.0;
const _drumLowTomDecay = 20.0;

const _drumHighTomDurationMs = 200;
const _drumHighTomFreq = 150.0;
const _drumHighTomDecay = 20.0;

const _drumCrashDurationMs = 400;
const _drumCrashDecay = 8.0;

// ── Pure-Dart synthesis ──────────────────────────────────────────────────────

double _midiToFreq(int midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0);

Uint8List _renderNote(int midi) {
  final freq = _midiToFreq(midi);
  const numSamples = _sampleRate * _noteDurationMs ~/ 1000;
  final samples = Int16List(numSamples);
  for (var i = 0; i < numSamples; i++) {
    final t = i / _sampleRate;
    final env = math.exp(-t * _decayRate);
    var v = math.sin(2 * math.pi * freq * t) * 0.60;
    v += math.sin(2 * math.pi * freq * 2 * t) * 0.22;
    v += math.sin(2 * math.pi * freq * 3 * t) * 0.10;
    v += math.sin(2 * math.pi * freq * 4 * t) * 0.05;
    v += math.sin(2 * math.pi * freq * 6 * t) * 0.03;
    samples[i] = (v * env * 22000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

Uint8List _renderClick(double freq) {
  const numSamples = _sampleRate * _clickDurationMs ~/ 1000;
  final samples = Int16List(numSamples);
  // Quick fade-in over the first 1ms to avoid an audible click at sample 0.
  final attackSamples = (_sampleRate * 0.001).round();
  for (var i = 0; i < numSamples; i++) {
    final t = i / _sampleRate;
    final attack = i < attackSamples ? i / attackSamples : 1.0;
    final env = math.exp(-t * _clickDecayRate);
    final v = math.sin(2 * math.pi * freq * t);
    samples[i] = (v * env * attack * 26000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

Uint8List _encodeWav(Int16List samples) {
  final dataBytes = samples.length * 2;
  final buf = ByteData(44 + dataBytes);
  void ws(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      buf.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  ws(0, 'RIFF');
  buf.setUint32(4, 36 + dataBytes, Endian.little);
  ws(8, 'WAVE');
  ws(12, 'fmt ');
  buf.setUint32(16, 16, Endian.little);
  buf.setUint16(20, 1, Endian.little); // PCM
  buf.setUint16(22, 1, Endian.little); // mono
  buf.setUint32(24, _sampleRate, Endian.little);
  buf.setUint32(28, _sampleRate * 2, Endian.little);
  buf.setUint16(32, 2, Endian.little);
  buf.setUint16(34, 16, Endian.little);
  ws(36, 'data');
  buf.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    buf.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return buf.buffer.asUint8List();
}

// ── Drum synthesis renderers ──────────────────────────────────────────────────

Uint8List _renderDrumKick(int sampleRate) {
  final numSamples = sampleRate * _drumKickDurationMs ~/ 1000;
  final samples = Int16List(numSamples);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * _drumKickDecay);
    // Quick pitch sweep down for thump.
    final sweep = 1.0 - t * 3.0;
    final freq = _drumKickFreq * (sweep < 0.1 ? 0.1 : sweep);
    final v = math.sin(2 * math.pi * freq * t);
    samples[i] = (v * env * 28000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

Uint8List _renderDrumSnare(int sampleRate) {
  final numSamples = sampleRate * _drumSnareDurationMs ~/ 1000;
  final samples = Int16List(numSamples);
  final rng = math.Random(42);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * _drumSnareDecay);
    final noise = rng.nextDouble() * 2.0 - 1.0;
    final body = math.sin(2 * math.pi * _drumSnareBodyFreq * t) * 0.35;
    final v = noise * 0.65 + body;
    samples[i] = (v * env * 24000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

Uint8List _renderHiHat(bool open, int sampleRate) {
  final durMs = open ? _drumHiHatOpenDurationMs : _drumHiHatClosedDurationMs;
  final decay = open ? _drumHiHatOpenDecay : _drumHiHatClosedDecay;
  final numSamples = sampleRate * durMs ~/ 1000;
  final samples = Int16List(numSamples);
  final rng = math.Random(17);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * decay);
    final noise = rng.nextDouble() * 2.0 - 1.0;
    // Slight high-pass effect via a short delay-difference.
    final hp = i > 1 ? noise - (rng.nextDouble() * 2.0 - 1.0) * 0.5 : noise;
    samples[i] = (hp * env * 20000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

Uint8List _renderClap(int sampleRate) {
  final numSamples = sampleRate * _drumClapDurationMs ~/ 1000;
  final samples = Int16List(numSamples);
  final rng = math.Random(99);
  final burstPeriod = numSamples ~/ _drumClapBurstCount;
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    // Multi-burst envelope: each burst has its own mini decay.
    final burstPhase = i % burstPeriod;
    final burstEnv = math.exp(-burstPhase / sampleRate * 60.0);
    final masterEnv = math.exp(-t * _drumSnareDecay);
    final noise = rng.nextDouble() * 2.0 - 1.0;
    samples[i] = (noise * burstEnv * masterEnv * 22000).round().clamp(
      -32767,
      32767,
    );
  }
  return _encodeWav(samples);
}

Uint8List _renderTom(double freq, int durMs, double decay, int sampleRate) {
  final numSamples = sampleRate * durMs ~/ 1000;
  final samples = Int16List(numSamples);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * decay);
    // Add a quick pitch sweep down for percussive feel.
    final sweep = 1.0 - t * 4.0;
    final f = freq * (sweep < 0.15 ? 0.15 : sweep);
    final body = math.sin(2 * math.pi * f * t);
    samples[i] = (body * env * 26000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

Uint8List _renderCrash(int sampleRate) {
  final numSamples = sampleRate * _drumCrashDurationMs ~/ 1000;
  final samples = Int16List(numSamples);
  final rng = math.Random(73);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    // Slow attack, then decay.
    final attack = (t * 20.0).clamp(0.0, 1.0);
    final env = math.exp(-t * _drumCrashDecay) * attack;
    final noise = rng.nextDouble() * 2.0 - 1.0;
    // Mix in some high-frequency tone for shimmer.
    final shimmer = math.sin(2 * math.pi * 8000 * t) * noise * 0.3;
    final v = noise * 0.7 + shimmer;
    samples[i] = (v * env * 18000).round().clamp(-32767, 32767);
  }
  return _encodeWav(samples);
}

// ── Singleton ────────────────────────────────────────────────────────────────

class NotePlayer {
  NotePlayer._();
  static final NotePlayer instance = NotePlayer._();

  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;

  // Bytes cache — used by BytesSource on all non-iOS platforms.
  final Map<int, Uint8List> _bytesCache = {};

  // File cache — iOS only; DeviceFileSource requires a named .wav file.
  final Map<int, String> _fileCache = {};
  final Map<int, Future<String>> _pending = {};
  String? _tempDir;

  bool _ready = false;

  /// Initialises the player pool. Call once during app startup.
  Future<void> init() async {
    if (_needsFile) {
      _tempDir = await ioTempDir(); // resolves via note_player_io.dart
    }
    for (var i = 0; i < _poolSize; i++) {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      _pool.add(player);
    }
    _ready = true;
  }

  /// Plays [midiNote] as a short synthesised tone at [volume] (0.0–1.0).
  void previewNote(int midiNote, {double volume = 0.8}) {
    if (!_ready) return;
    unawaited(_play(midiNote, volume));
  }

  /// Plays a short metronome click at [volume] (0.0–1.0). [accent] picks the
  /// brighter downbeat click; otherwise the softer beat click.
  ///
  /// Clicks reuse the same audio pool as notes, so a click never blocks a
  /// concurrent chord. Cache keys live in a reserved negative integer range
  /// (`-1` / `-2`) so they cannot collide with real MIDI notes.
  void playClick({bool accent = false, double volume = 0.6}) {
    if (!_ready) return;
    unawaited(_playClick(accent, volume));
  }

  /// Plays a synthesised drum voice for [lane] at [volume] (0.0–1.0).
  ///
  /// Drum voices are short synthesised waveforms cached with negative integer
  /// keys (-10 through -17) to avoid collision with MIDI notes (0–127) and
  /// metronome clicks (-1, -2).
  void playDrumLane(DrumLaneId lane, {double volume = 0.8}) {
    if (!_ready) return;
    unawaited(_playDrum(lane, volume));
  }

  static int _drumCacheKey(DrumLaneId lane) {
    switch (lane) {
      case DrumLaneId.kick:
        return -10;
      case DrumLaneId.snare:
        return -11;
      case DrumLaneId.closedHiHat:
        return -12;
      case DrumLaneId.openHiHat:
        return -13;
      case DrumLaneId.clap:
        return -14;
      case DrumLaneId.lowTom:
        return -15;
      case DrumLaneId.highTom:
        return -16;
      case DrumLaneId.crash:
        return -17;
    }
  }

  Future<void> _playDrum(DrumLaneId lane, double volume) async {
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    await player.setVolume(volume.clamp(0.0, 1.0));
    final cacheKey = _drumCacheKey(lane);
    if (_needsFile) {
      final path = await _ensureFile(cacheKey, () => _renderDrum(lane));
      await player.play(DeviceFileSource(path));
    } else {
      final bytes = _bytesCache.putIfAbsent(cacheKey, () => _renderDrum(lane));
      await player.play(BytesSource(bytes));
    }
  }

  Uint8List _renderDrum(DrumLaneId lane) {
    switch (lane) {
      case DrumLaneId.kick:
        return _renderDrumKick(_sampleRate);
      case DrumLaneId.snare:
        return _renderDrumSnare(_sampleRate);
      case DrumLaneId.closedHiHat:
        return _renderHiHat(false, _sampleRate);
      case DrumLaneId.openHiHat:
        return _renderHiHat(true, _sampleRate);
      case DrumLaneId.clap:
        return _renderClap(_sampleRate);
      case DrumLaneId.lowTom:
        return _renderTom(
          _drumLowTomFreq,
          _drumLowTomDurationMs,
          _drumLowTomDecay,
          _sampleRate,
        );
      case DrumLaneId.highTom:
        return _renderTom(
          _drumHighTomFreq,
          _drumHighTomDurationMs,
          _drumHighTomDecay,
          _sampleRate,
        );
      case DrumLaneId.crash:
        return _renderCrash(_sampleRate);
    }
  }

  Future<void> _play(int midi, double volume) async {
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    await player.setVolume(volume.clamp(0.0, 1.0));
    if (_needsFile) {
      final path = await _ensureFile(midi, () => _renderNote(midi));
      await player.play(DeviceFileSource(path));
    } else {
      final bytes = _bytesCache.putIfAbsent(midi, () => _renderNote(midi));
      await player.play(BytesSource(bytes));
    }
  }

  Future<void> _playClick(bool accent, double volume) async {
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    await player.setVolume(volume.clamp(0.0, 1.0));
    final cacheKey = accent ? -1 : -2;
    if (_needsFile) {
      final path = await _ensureFile(
        cacheKey,
        () => _renderClick(accent ? _clickFreqAccent : _clickFreqWeak),
      );
      await player.play(DeviceFileSource(path));
    } else {
      final bytes = _bytesCache.putIfAbsent(
        cacheKey,
        () => _renderClick(accent ? _clickFreqAccent : _clickFreqWeak),
      );
      await player.play(BytesSource(bytes));
    }
  }

  Future<String> _ensureFile(int cacheKey, Uint8List Function() render) {
    if (_fileCache.containsKey(cacheKey)) {
      return Future.value(_fileCache[cacheKey]);
    }
    return _pending.putIfAbsent(cacheKey, () async {
      final name = cacheKey >= 0
          ? 'note_$cacheKey'
          : cacheKey <= -10
          ? 'drum_${-cacheKey}'
          : 'click_${-cacheKey}';
      final path = '${_tempDir!}/$name.wav';
      final bytes = _bytesCache.putIfAbsent(cacheKey, render);
      await ioWriteIfAbsent(path, bytes); // resolves via note_player_io.dart
      _fileCache[cacheKey] = path;
      _pending.remove(cacheKey);
      return path;
    });
  }
}
