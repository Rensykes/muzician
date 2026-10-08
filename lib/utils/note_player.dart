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
import 'playback_profiling.dart';
import 'playback_profile_source.dart';

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

Uint8List _renderSequencedNote(int midi, int durationMs) {
  final freq = _midiToFreq(midi);
  final safeDuration = durationMs < 1 ? 1 : durationMs;
  final numSamples = _sampleRate * safeDuration ~/ 1000;
  final samples = Int16List(numSamples);
  final releaseSamples = math.min(numSamples ~/ 3, _sampleRate * 35 ~/ 1000);
  final attackSamples = math.min(numSamples ~/ 4, _sampleRate * 5 ~/ 1000);
  for (var i = 0; i < numSamples; i++) {
    final attack = attackSamples == 0
        ? 1.0
        : (i / attackSamples).clamp(0.0, 1.0);
    final remaining = numSamples - i;
    final release = releaseSamples == 0 || remaining > releaseSamples
        ? 1.0
        : (remaining / releaseSamples).clamp(0.0, 1.0);
    final t = i / _sampleRate;
    var value = math.sin(2 * math.pi * freq * t) * 0.60;
    value += math.sin(2 * math.pi * freq * 2 * t) * 0.22;
    value += math.sin(2 * math.pi * freq * 3 * t) * 0.10;
    value += math.sin(2 * math.pi * freq * 4 * t) * 0.05;
    value += math.sin(2 * math.pi * freq * 6 * t) * 0.03;
    samples[i] = (value * attack * release * 22000).round().clamp(
      -32767,
      32767,
    );
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
  final List<AudioPlayer> _sequencedPool = [];
  final Map<AudioPlayer, int> _activeSequencedVoices = {};
  final Map<AudioPlayer, int> _pendingSequencedVoices = {};
  final Map<AudioPlayer, Future<void>> _sequencedStops = {};
  final Map<AudioPlayer, PlaybackProfileVoiceContext>
  _activePreviewProfileVoices = {};
  final Map<AudioPlayer, PlaybackProfileVoiceContext>
  _pendingPreviewProfileVoices = {};
  final Map<AudioPlayer, PlaybackProfileVoiceContext> _sequencedProfileVoices =
      {};
  final List<StreamSubscription<void>> _profileCompletionSubscriptions = [];
  int _sequencedVoiceId = 0;
  int _sequencedGeneration = 0;

  /// Last balance set on each pool player (see [_applyBalance]). Players
  /// start centered, so an absent entry means 0.0 has effectively been set.
  final Map<AudioPlayer, double> _balanceByPlayer = {};
  int _poolIndex = 0;

  // Bytes cache — used by BytesSource on all non-iOS platforms.
  final Map<int, Uint8List> _bytesCache = {};

  // File cache — iOS only; DeviceFileSource requires a named .wav file.
  final Map<int, String> _fileCache = {};
  final Map<int, Future<String>> _pending = {};
  String? _tempDir;

  bool _ready = false;

  /// Initialises the player pool. Call once during app startup.
  Future<void> init({String? tempDirectoryOverride}) async {
    final initTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'note_player.init',
            arguments: {
              'source_strategy': _needsFile
                  ? 'DeviceFileSource'
                  : 'BytesSource',
              'pool_size': _poolSize,
            },
          )
        : null;
    try {
      if (_needsFile) {
        _tempDir =
            tempDirectoryOverride ??
            await ioTempDir(); // resolves via note_player_io.dart
      }
      for (var i = 0; i < _poolSize; i++) {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        _pool.add(player);
        if (playbackProfilingEnabled) {
          playbackProfileInstant(
            'note_player.player_created',
            arguments: {
              'kind': 'preview_pool',
              'player_id': identityHashCode(player),
              'pool_size': _pool.length,
            },
          );
          _profileCompletionSubscriptions.add(
            player.onPlayerComplete.listen((_) {
              final voice = _activePreviewProfileVoices.remove(player);
              if (voice == null) return;
              voice.run.outcome(voice, 'natural_completion');
              playbackProfileInstant(
                'note_player.voice_terminated',
                arguments: {
                  ...voice.timelineArguments,
                  'player_id': identityHashCode(player),
                  'outcome': 'natural_completion',
                  'active_voice_count': _activePreviewProfileVoices.length,
                  'pending_voice_count': _pendingPreviewProfileVoices.length,
                },
              );
            }),
          );
        }
      }
      _ready = true;
      initTrace?.finish(
        arguments: {'outcome': 'ready', 'pool_size': _pool.length},
      );
    } catch (error) {
      initTrace?.finishError(error, stage: 'player_pool');
      rethrow;
    }
  }

  /// Plays [midiNote] as a short synthesised tone at [volume] (0.0–1.0),
  /// panned by [pan] (-1.0 left .. 1.0 right).
  void previewNote(int midiNote, {double volume = 0.8, double pan = 0.0}) {
    final profileVoice = playbackProfilingEnabled
        ? playbackProfileVoiceContext()
        : null;
    if (profileVoice != null) {
      profileVoice.run.request(profileVoice);
    }
    if (!_ready) {
      if (profileVoice != null) {
        profileVoice.run.outcome(profileVoice, 'dropped_not_ready');
        playbackProfileInstant(
          'note_player.voice_requested',
          arguments: {
            ...profileVoice.timelineArguments,
            'midi': midiNote,
            'outcome': 'dropped_not_ready',
            'active_voice_count': _activePreviewProfileVoices.length,
            'pending_voice_count': _pendingPreviewProfileVoices.length,
          },
        );
      }
      return;
    }
    unawaited(_play(midiNote, volume, pan, profileVoice: profileVoice));
  }

  /// Starts one duration-aware voice for a sequenced note. Each voice releases
  /// after [duration] and is also stopped immediately by
  /// [stopSequencedNotes]. [onsetDelay] preserves sub-tick offsets such as a
  /// guitar strum's string stagger.
  void playSequencedNote(
    int midiNote, {
    required Duration duration,
    Duration onsetDelay = Duration.zero,
    double volume = 0.8,
    double pan = 0.0,
  }) {
    final profileVoice = playbackProfilingEnabled
        ? playbackProfileVoiceContext(onsetOffsetUs: onsetDelay.inMicroseconds)
        : null;
    if (profileVoice != null) profileVoice.run.request(profileVoice);
    if (!_ready) {
      if (profileVoice != null) {
        profileVoice.run.outcome(profileVoice, 'dropped_not_ready');
        playbackProfileInstant(
          'note_player.voice_requested',
          arguments: {
            ...profileVoice.timelineArguments,
            'midi': midiNote,
            'duration_ms': duration.inMilliseconds,
            'outcome': 'dropped_not_ready',
          },
        );
      }
      return;
    }
    unawaited(
      _playSequencedNote(
        midiNote,
        duration: duration,
        onsetDelay: onsetDelay,
        volume: volume,
        pan: pan,
        generation: _sequencedGeneration,
        profileVoice: profileVoice,
      ),
    );
  }

  /// Releases every voice started through [playSequencedNote].
  void stopSequencedNotes() {
    _sequencedGeneration++;
    for (final entry in _activeSequencedVoices.entries.toList()) {
      unawaited(
        _stopSequencedVoice(entry.key, entry.value, reason: 'cancelled'),
      );
    }
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
  void playDrumLane(DrumLaneId lane, {double volume = 0.8, double pan = 0.0}) {
    if (!_ready) return;
    unawaited(_playDrum(lane, volume, pan));
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

  /// Applies [pan] to a pool [player] only when it differs from the last
  /// value set — skips the platform-channel round trip in the common
  /// unpanned case (and lets clicks recenter for free).
  Future<void> _applyBalance(AudioPlayer player, double pan) async {
    final clamped = pan.clamp(-1.0, 1.0);
    if ((_balanceByPlayer[player] ?? 0.0) == clamped) return;
    _balanceByPlayer[player] = clamped;
    await player.setBalance(clamped);
  }

  Future<void> _playDrum(DrumLaneId lane, double volume, double pan) async {
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    await player.setVolume(volume.clamp(0.0, 1.0));
    await _applyBalance(player, pan);
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

  Future<void> _play(
    int midi,
    double volume,
    double pan, {
    PlaybackProfileVoiceContext? profileVoice,
  }) async {
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    if (profileVoice != null) profileVoice.run.playerReusedCount++;
    final previewTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'note_player.preview_voice',
            arguments: {
              ...?profileVoice?.timelineArguments,
              'midi': midi,
              'volume': volume,
              'pan': pan,
              'source_strategy': _needsFile
                  ? 'DeviceFileSource'
                  : 'BytesSource',
              'player_id': identityHashCode(player),
              'player_reused': true,
              'active_voice_count': _activePreviewProfileVoices.length,
              'pending_voice_count': _pendingPreviewProfileVoices.length,
            },
          )
        : null;
    final startWatch = playbackProfilingEnabled ? (Stopwatch()..start()) : null;
    try {
      final configureTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'note_player.configure_voice',
              arguments: {
                ...?profileVoice?.timelineArguments,
                'kind': 'preview',
                'midi': midi,
                'player_id': identityHashCode(player),
                'pan': pan,
              },
            )
          : null;
      try {
        await player.setVolume(volume.clamp(0.0, 1.0));
        await _applyBalance(player, pan);
        configureTrace?.finish(arguments: {'outcome': 'configured'});
      } catch (error) {
        configureTrace?.finishError(error, stage: 'configure');
        rethrow;
      }

      final Source source;
      final sourceName = _needsFile ? 'DeviceFileSource' : 'BytesSource';
      final fileWasCached = playbackProfilingEnabled
          ? _fileCache.containsKey(midi)
          : false;
      final bytesWereCached = playbackProfilingEnabled
          ? _bytesCache.containsKey(midi)
          : false;
      if (_needsFile) {
        final path = await _ensureFile(midi, () => _renderNote(midi));
        source = DeviceFileSource(path);
      } else {
        final bytes = _bytesCache.putIfAbsent(midi, () => _renderNote(midi));
        source = BytesSource(bytes);
      }

      if (playbackProfilingEnabled) {
        final previousActive = _activePreviewProfileVoices.remove(player);
        final previousPending = _pendingPreviewProfileVoices.remove(player);
        final previous = previousActive ?? previousPending;
        if (previous != null && previous.voiceId != profileVoice?.voiceId) {
          previous.run.outcome(previous, 'stolen_before_completion');
          playbackProfileInstant(
            'note_player.voice_terminated',
            arguments: {
              ...previous.timelineArguments,
              'player_id': identityHashCode(player),
              'outcome': 'stolen_before_completion',
              'active_voice_count': _activePreviewProfileVoices.length,
              'pending_voice_count': _pendingPreviewProfileVoices.length,
            },
          );
        }
        if (profileVoice != null) {
          _pendingPreviewProfileVoices[player] = profileVoice;
        }
      }

      final playTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'note_player.play_request',
              arguments: {
                ...?profileVoice?.timelineArguments,
                'kind': 'preview',
                'midi': midi,
                'player_id': identityHashCode(player),
                'source': sourceName,
                'file_cache_hit': fileWasCached,
                'wav_cache_hit': bytesWereCached,
                if (startWatch != null)
                  'request_to_play_us': startWatch.elapsedMicroseconds,
                if (profileVoice != null)
                  'dispatch_error_us':
                      profileVoice.clock.elapsedMicroseconds -
                      profileVoice.intendedDeadlineUs,
              },
            )
          : null;
      try {
        if (profileVoice != null) profileVoice.run.launched(profileVoice);
        await player.play(
          playbackProfilingEnabled
              ? PlaybackProfileSource(source, {
                  ...?profileVoice?.timelineArguments,
                  'kind': 'preview',
                  'midi': midi,
                  'player_id': identityHashCode(player),
                })
              : source,
        );
        playTrace?.finish(arguments: {'outcome': 'play_future_completed'});
      } catch (error) {
        playTrace?.finishError(error, stage: 'play');
        rethrow;
      }
      if (profileVoice != null) {
        profileVoice.run.outcome(profileVoice, 'play_future_completed');
        _pendingPreviewProfileVoices.remove(player);
        if (!profileVoice.run.isTerminated(profileVoice)) {
          _activePreviewProfileVoices[player] = profileVoice;
        }
      }
      previewTrace?.finish(
        arguments: {
          ...?profileVoice?.timelineArguments,
          'outcome': 'play_future_completed',
          if (startWatch != null)
            'request_to_play_us': startWatch.elapsedMicroseconds,
          'active_voice_count': _activePreviewProfileVoices.length,
          'pending_voice_count': _pendingPreviewProfileVoices.length,
        },
      );
    } catch (error, stackTrace) {
      if (profileVoice != null) {
        profileVoice.run.outcome(profileVoice, 'error');
        if (_activePreviewProfileVoices[player]?.voiceId ==
            profileVoice.voiceId) {
          _activePreviewProfileVoices.remove(player);
        }
        if (_pendingPreviewProfileVoices[player]?.voiceId ==
            profileVoice.voiceId) {
          _pendingPreviewProfileVoices.remove(player);
        }
      }
      previewTrace?.finishError(error, stage: 'preview');
      playbackProfileInstant(
        'note_player.voice_terminated',
        arguments: {
          ...?profileVoice?.timelineArguments,
          'player_id': identityHashCode(player),
          'outcome': 'error',
          'error_type': error.runtimeType.toString(),
          'active_voice_count': _activePreviewProfileVoices.length,
          'pending_voice_count': _pendingPreviewProfileVoices.length,
        },
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _playSequencedNote(
    int midi, {
    required Duration duration,
    required Duration onsetDelay,
    required double volume,
    required double pan,
    required int generation,
    required PlaybackProfileVoiceContext? profileVoice,
  }) async {
    final noteTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'note_player.sequenced_voice',
            arguments: {
              ...?profileVoice?.timelineArguments,
              'midi': midi,
              'duration_ms': duration.inMilliseconds,
              'onset_delay_ms': onsetDelay.inMilliseconds,
              'pan': pan,
              'generation': generation,
              'source_strategy': _needsFile
                  ? 'DeviceFileSource'
                  : 'BytesSource',
              'active_voice_count': _activeSequencedVoices.length,
              'pending_voice_count': _pendingSequencedVoices.length,
            },
          )
        : null;
    final startWatch = playbackProfilingEnabled ? (Stopwatch()..start()) : null;
    int? sequencedVoiceId;
    try {
      if (onsetDelay > Duration.zero) await Future<void>.delayed(onsetDelay);
      if (generation != _sequencedGeneration) {
        if (profileVoice != null) {
          profileVoice.run.outcome(profileVoice, 'cancelled');
        }
        noteTrace?.finish(
          arguments: sequencedPlaybackProfileArguments(
            profileTimelineArguments: profileVoice?.timelineArguments,
            sequencedVoiceId: sequencedVoiceId,
            additionalArguments: {
              'outcome': 'cancelled',
              'stage': 'onset_delay',
            },
          ),
        );
        return;
      }
      noteTrace?.instant('note_player.onset_delay_complete');

      AudioPlayer? availablePlayer;
      for (final candidate in _sequencedPool) {
        if (!_activeSequencedVoices.containsKey(candidate)) {
          availablePlayer = candidate;
          break;
        }
      }
      final AudioPlayer player;
      if (availablePlayer == null) {
        player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        _sequencedPool.add(player);
        if (profileVoice != null) profileVoice.run.playerCreatedCount++;
        playbackProfileInstant(
          'note_player.player_created',
          arguments: {
            ...?profileVoice?.timelineArguments,
            'kind': 'sequenced',
            'player_id': identityHashCode(player),
          },
        );
        if (generation != _sequencedGeneration) {
          unawaited(player.dispose());
          _sequencedPool.remove(player);
          if (profileVoice != null) {
            profileVoice.run.outcome(profileVoice, 'cancelled');
          }
          noteTrace?.finish(
            arguments: sequencedPlaybackProfileArguments(
              profileTimelineArguments: profileVoice?.timelineArguments,
              sequencedVoiceId: sequencedVoiceId,
              additionalArguments: {
                'outcome': 'cancelled',
                'stage': 'player_create',
              },
            ),
          );
          return;
        }
      } else {
        player = availablePlayer;
        if (profileVoice != null) profileVoice.run.playerReusedCount++;
      }

      final voiceId = ++_sequencedVoiceId;
      sequencedVoiceId = voiceId;
      _activeSequencedVoices[player] = voiceId;
      _pendingSequencedVoices[player] = voiceId;
      if (profileVoice != null) _sequencedProfileVoices[player] = profileVoice;
      final durationMs = duration.inMilliseconds < 1
          ? 1
          : duration.inMilliseconds;
      var started = false;
      var cancelled = false;
      Object? operationError;
      try {
        final configureTrace = playbackProfilingEnabled
            ? PlaybackProfileTask.begin(
                'note_player.configure_voice',
                arguments: sequencedPlaybackProfileArguments(
                  profileTimelineArguments: profileVoice?.timelineArguments,
                  sequencedVoiceId: voiceId,
                  additionalArguments: {
                    'kind': 'sequenced',
                    'midi': midi,
                    'player_id': identityHashCode(player),
                    'player_lifecycle': availablePlayer == null
                        ? 'created'
                        : 'reused',
                    'pan': pan,
                    'active_voice_count': _activeSequencedVoices.length,
                    'pending_voice_count': _pendingSequencedVoices.length,
                  },
                ),
              )
            : null;
        try {
          await player.setVolume(volume.clamp(0.0, 1.0));
          await _applyBalance(player, pan);
          configureTrace?.finish(
            arguments: sequencedPlaybackProfileArguments(
              profileTimelineArguments: profileVoice?.timelineArguments,
              sequencedVoiceId: voiceId,
              additionalArguments: {'outcome': 'configured'},
            ),
          );
        } catch (error) {
          configureTrace?.finish(
            arguments: sequencedPlaybackProfileArguments(
              profileTimelineArguments: profileVoice?.timelineArguments,
              sequencedVoiceId: voiceId,
              additionalArguments: {
                'outcome': 'error',
                'error_type': error.runtimeType.toString(),
                'stage': 'configure',
              },
            ),
          );
          rethrow;
        }
        if (generation != _sequencedGeneration ||
            _activeSequencedVoices[player] != voiceId) {
          cancelled = true;
          if (profileVoice != null) {
            profileVoice.run.outcome(profileVoice, 'cancelled');
          }
          noteTrace?.finish(
            arguments: sequencedPlaybackProfileArguments(
              profileTimelineArguments: profileVoice?.timelineArguments,
              sequencedVoiceId: sequencedVoiceId,
              additionalArguments: {
                'outcome': 'cancelled',
                'stage': 'configure',
              },
            ),
          );
          return;
        }

        final cacheKey = 1000000 + midi * 10000000000 + durationMs;
        if (_needsFile) {
          final fileWasCached = playbackProfilingEnabled
              ? _fileCache.containsKey(cacheKey)
              : false;
          final bytesWereCached = playbackProfilingEnabled
              ? _bytesCache.containsKey(cacheKey)
              : false;
          final path = await _ensureFile(
            cacheKey,
            () => _renderSequencedNote(midi, durationMs),
          );
          if (generation != _sequencedGeneration ||
              _activeSequencedVoices[player] != voiceId) {
            cancelled = true;
            if (profileVoice != null) {
              profileVoice.run.outcome(profileVoice, 'cancelled');
            }
            noteTrace?.finish(
              arguments: sequencedPlaybackProfileArguments(
                profileTimelineArguments: profileVoice?.timelineArguments,
                sequencedVoiceId: sequencedVoiceId,
                additionalArguments: {
                  'outcome': 'cancelled',
                  'stage': 'source_prepare',
                },
              ),
            );
            return;
          }
          final playTrace = playbackProfilingEnabled
              ? PlaybackProfileTask.begin(
                  'note_player.play_request',
                  arguments: sequencedPlaybackProfileArguments(
                    profileTimelineArguments: profileVoice?.timelineArguments,
                    sequencedVoiceId: voiceId,
                    additionalArguments: {
                      'kind': 'sequenced',
                      'midi': midi,
                      'duration_ms': durationMs,
                      'player_id': identityHashCode(player),
                      'source': 'DeviceFileSource',
                      'player_lifecycle': availablePlayer == null
                          ? 'created'
                          : 'reused',
                      'file_cache_hit': fileWasCached,
                      'wav_cache_hit': bytesWereCached,
                      if (startWatch != null)
                        'dispatch_to_play_us': startWatch.elapsedMicroseconds,
                      if (profileVoice != null)
                        'dispatch_error_us':
                            profileVoice.clock.elapsedMicroseconds -
                            profileVoice.intendedDeadlineUs,
                    },
                  ),
                )
              : null;
          try {
            if (profileVoice != null) profileVoice.run.launched(profileVoice);
            await player.play(
              playbackProfilingEnabled
                  ? PlaybackProfileSource(DeviceFileSource(path), {
                      ...sequencedPlaybackProfileArguments(
                        profileTimelineArguments:
                            profileVoice?.timelineArguments,
                        sequencedVoiceId: voiceId,
                        additionalArguments: {
                          'kind': 'sequenced',
                          'midi': midi,
                          'duration_ms': durationMs,
                          'player_id': identityHashCode(player),
                        },
                      ),
                    })
                  : DeviceFileSource(path),
            );
            playTrace?.finish(
              arguments: sequencedPlaybackProfileArguments(
                profileTimelineArguments: profileVoice?.timelineArguments,
                sequencedVoiceId: voiceId,
                additionalArguments: {'outcome': 'play_future_completed'},
              ),
            );
          } catch (error) {
            playTrace?.finish(
              arguments: sequencedPlaybackProfileArguments(
                profileTimelineArguments: profileVoice?.timelineArguments,
                sequencedVoiceId: voiceId,
                additionalArguments: {
                  'outcome': 'error',
                  'error_type': error.runtimeType.toString(),
                  'stage': 'play',
                },
              ),
            );
            rethrow;
          }
        } else {
          final bytesWereCached = playbackProfilingEnabled
              ? _bytesCache.containsKey(cacheKey)
              : false;
          final bytes = _bytesCache.putIfAbsent(
            cacheKey,
            () => _renderSequencedNote(midi, durationMs),
          );
          if (generation != _sequencedGeneration ||
              _activeSequencedVoices[player] != voiceId) {
            cancelled = true;
            if (profileVoice != null) {
              profileVoice.run.outcome(profileVoice, 'cancelled');
            }
            noteTrace?.finish(
              arguments: sequencedPlaybackProfileArguments(
                profileTimelineArguments: profileVoice?.timelineArguments,
                sequencedVoiceId: sequencedVoiceId,
                additionalArguments: {
                  'outcome': 'cancelled',
                  'stage': 'source_prepare',
                },
              ),
            );
            return;
          }
          final playTrace = playbackProfilingEnabled
              ? PlaybackProfileTask.begin(
                  'note_player.play_request',
                  arguments: sequencedPlaybackProfileArguments(
                    profileTimelineArguments: profileVoice?.timelineArguments,
                    sequencedVoiceId: voiceId,
                    additionalArguments: {
                      'kind': 'sequenced',
                      'midi': midi,
                      'duration_ms': durationMs,
                      'player_id': identityHashCode(player),
                      'source': 'BytesSource',
                      'player_lifecycle': availablePlayer == null
                          ? 'created'
                          : 'reused',
                      'wav_cache_hit': bytesWereCached,
                      if (startWatch != null)
                        'dispatch_to_play_us': startWatch.elapsedMicroseconds,
                      if (profileVoice != null)
                        'dispatch_error_us':
                            profileVoice.clock.elapsedMicroseconds -
                            profileVoice.intendedDeadlineUs,
                    },
                  ),
                )
              : null;
          try {
            if (profileVoice != null) profileVoice.run.launched(profileVoice);
            await player.play(
              playbackProfilingEnabled
                  ? PlaybackProfileSource(BytesSource(bytes), {
                      ...sequencedPlaybackProfileArguments(
                        profileTimelineArguments:
                            profileVoice?.timelineArguments,
                        sequencedVoiceId: voiceId,
                        additionalArguments: {
                          'kind': 'sequenced',
                          'midi': midi,
                          'duration_ms': durationMs,
                          'player_id': identityHashCode(player),
                        },
                      ),
                    })
                  : BytesSource(bytes),
            );
            playTrace?.finish(
              arguments: sequencedPlaybackProfileArguments(
                profileTimelineArguments: profileVoice?.timelineArguments,
                sequencedVoiceId: voiceId,
                additionalArguments: {'outcome': 'play_future_completed'},
              ),
            );
          } catch (error) {
            playTrace?.finish(
              arguments: sequencedPlaybackProfileArguments(
                profileTimelineArguments: profileVoice?.timelineArguments,
                sequencedVoiceId: voiceId,
                additionalArguments: {
                  'outcome': 'error',
                  'error_type': error.runtimeType.toString(),
                  'stage': 'play',
                },
              ),
            );
            rethrow;
          }
        }
        started = true;
        if (profileVoice != null) {
          profileVoice.run.outcome(profileVoice, 'play_future_completed');
        }
      } catch (error) {
        // A platform playback failure should not leave this voice reserved.
        operationError = error;
        if (profileVoice != null) {
          profileVoice.run.outcome(profileVoice, 'error');
        }
        playbackProfileInstant(
          'note_player.voice_terminated',
          arguments: sequencedPlaybackProfileArguments(
            profileTimelineArguments: profileVoice?.timelineArguments,
            sequencedVoiceId: voiceId,
            additionalArguments: {
              'player_id': identityHashCode(player),
              'outcome': 'error',
              'error_type': error.runtimeType.toString(),
              'active_voice_count': _activeSequencedVoices.length,
              'pending_voice_count': _pendingSequencedVoices.length,
            },
          ),
        );
      } finally {
        if (_pendingSequencedVoices[player] == voiceId) {
          _pendingSequencedVoices.remove(player);
        }
        if (!started ||
            generation != _sequencedGeneration ||
            _activeSequencedVoices[player] != voiceId) {
          await _stopSequencedVoice(
            player,
            voiceId,
            reason: started
                ? 'cancelled'
                : cancelled
                ? 'cancelled'
                : 'error_cleanup',
          );
        }
      }

      if (operationError != null) {
        noteTrace?.finish(
          arguments: sequencedPlaybackProfileArguments(
            profileTimelineArguments: profileVoice?.timelineArguments,
            sequencedVoiceId: sequencedVoiceId,
            additionalArguments: {
              'outcome': 'error',
              'error_type': operationError.runtimeType.toString(),
              'stage': 'platform_playback',
            },
          ),
        );
        return;
      }

      if (!started ||
          generation != _sequencedGeneration ||
          _activeSequencedVoices[player] != voiceId) {
        if (profileVoice != null &&
            !profileVoice.run.isTerminated(profileVoice)) {
          profileVoice.run.outcome(profileVoice, 'cancelled');
        }
        noteTrace?.finish(
          arguments: sequencedPlaybackProfileArguments(
            profileTimelineArguments: profileVoice?.timelineArguments,
            sequencedVoiceId: sequencedVoiceId,
            additionalArguments: {
              'outcome': 'cancelled',
              'stage': 'play_request',
              'active_voice_count': _activeSequencedVoices.length,
              'pending_voice_count': _pendingSequencedVoices.length,
            },
          ),
        );
        return;
      }
      noteTrace?.finish(
        arguments: sequencedPlaybackProfileArguments(
          profileTimelineArguments: profileVoice?.timelineArguments,
          sequencedVoiceId: sequencedVoiceId,
          additionalArguments: {
            'outcome': 'play_future_completed',
            if (startWatch != null)
              'dispatch_to_play_us': startWatch.elapsedMicroseconds,
            if (profileVoice != null)
              'dispatch_error_us':
                  profileVoice.clock.elapsedMicroseconds -
                  profileVoice.intendedDeadlineUs,
            'active_voice_count': _activeSequencedVoices.length,
            'pending_voice_count': _pendingSequencedVoices.length,
          },
        ),
      );
      unawaited(
        Future<void>.delayed(Duration(milliseconds: durationMs), () async {
          await _stopSequencedVoice(
            player,
            voiceId,
            reason: 'natural_completion',
          );
        }),
      );
    } catch (error, stackTrace) {
      if (profileVoice != null) profileVoice.run.outcome(profileVoice, 'error');
      noteTrace?.finish(
        arguments: sequencedPlaybackProfileArguments(
          profileTimelineArguments: profileVoice?.timelineArguments,
          sequencedVoiceId: sequencedVoiceId,
          additionalArguments: {
            'outcome': 'error',
            'error_type': error.runtimeType.toString(),
            'stage': 'sequenced_setup',
          },
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _stopSequencedVoice(
    AudioPlayer player,
    int voiceId, {
    String reason = 'cancelled',
  }) async {
    if (_activeSequencedVoices[player] != voiceId) return;
    final existingStop = _sequencedStops[player];
    if (existingStop != null) {
      await existingStop;
      return;
    }
    final stopping = _stopSequencedVoiceInternal(
      player,
      voiceId,
      reason: reason,
    );
    _sequencedStops[player] = stopping;
    await stopping;
    if (identical(_sequencedStops[player], stopping)) {
      _sequencedStops.remove(player);
    }
  }

  Future<void> _stopSequencedVoiceInternal(
    AudioPlayer player,
    int voiceId, {
    required String reason,
  }) async {
    final profileVoice = _sequencedProfileVoices[player];
    final stopTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'note_player.sequenced_voice_stop',
            arguments: sequencedPlaybackProfileArguments(
              profileTimelineArguments: profileVoice?.timelineArguments,
              sequencedVoiceId: voiceId,
              additionalArguments: {
                'player_id': identityHashCode(player),
                'reason': reason,
                'active_voice_count': _activeSequencedVoices.length,
                'pending_voice_count': _pendingSequencedVoices.length,
              },
            ),
          )
        : null;
    try {
      await player.stop();
      if (_activeSequencedVoices[player] == voiceId &&
          _pendingSequencedVoices[player] != voiceId) {
        _activeSequencedVoices.remove(player);
      }
      if (_sequencedProfileVoices[player]?.voiceId == profileVoice?.voiceId) {
        _sequencedProfileVoices.remove(player);
      }
      final outcome = reason == 'natural_completion'
          ? 'natural_completion'
          : reason == 'cancelled'
          ? 'cancelled'
          : reason;
      if (profileVoice != null) profileVoice.run.outcome(profileVoice, outcome);
      stopTrace?.finish(
        arguments: sequencedPlaybackProfileArguments(
          profileTimelineArguments: profileVoice?.timelineArguments,
          sequencedVoiceId: voiceId,
          additionalArguments: {
            'outcome': outcome,
            'stop_future_completed': true,
            'active_voice_count': _activeSequencedVoices.length,
            'pending_voice_count': _pendingSequencedVoices.length,
          },
        ),
      );
    } catch (error) {
      if (profileVoice != null) profileVoice.run.outcome(profileVoice, 'error');
      stopTrace?.finish(
        arguments: sequencedPlaybackProfileArguments(
          profileTimelineArguments: profileVoice?.timelineArguments,
          sequencedVoiceId: voiceId,
          additionalArguments: {
            'outcome': 'error',
            'error_type': error.runtimeType.toString(),
            'stage': 'stop',
          },
        ),
      );
      rethrow;
    }
  }

  Future<void> _playClick(bool accent, double volume) async {
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    await player.setVolume(volume.clamp(0.0, 1.0));
    // Pool players are shared with panned notes/drums — recenter for clicks.
    await _applyBalance(player, 0.0);
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
    final cachedPath = _fileCache[cacheKey];
    if (cachedPath != null) {
      return Future.value(cachedPath);
    }
    final existingWrite = _pending[cacheKey];
    if (existingWrite != null) {
      if (!playbackProfilingEnabled) return existingWrite;
      final pendingTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'note_player.wav_file_wait',
              arguments: {'cache_key': cacheKey},
            )
          : null;
      return () async {
        try {
          final path = await existingWrite;
          pendingTrace?.finish(arguments: {'outcome': 'shared_write_ready'});
          return path;
        } catch (error) {
          pendingTrace?.finishError(error, stage: 'shared_write');
          rethrow;
        }
      }();
    }
    final fileTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'note_player.wav_file_prepare',
            arguments: {
              'cache_key': cacheKey,
              'pending_write': _pending.containsKey(cacheKey),
              'wav_cache_hit': _bytesCache.containsKey(cacheKey),
            },
          )
        : null;
    bool? wavWasCached;
    int? renderUs;
    int? byteCount;
    final writeFuture = _pending.putIfAbsent(cacheKey, () async {
      final name = cacheKey >= 0
          ? 'note_$cacheKey'
          : cacheKey <= -10
          ? 'drum_${-cacheKey}'
          : 'click_${-cacheKey}';
      final path = '${_tempDir!}/$name.wav';
      wavWasCached = playbackProfilingEnabled
          ? _bytesCache.containsKey(cacheKey)
          : false;
      final renderWatch = playbackProfilingEnabled
          ? (Stopwatch()..start())
          : null;
      final bytes = _bytesCache.putIfAbsent(cacheKey, render);
      renderUs = renderWatch?.elapsedMicroseconds;
      byteCount = bytes.length;
      await ioWriteIfAbsent(path, bytes); // resolves via note_player_io.dart
      _fileCache[cacheKey] = path;
      _pending.remove(cacheKey);
      return path;
    });
    return () async {
      try {
        final path = await writeFuture;
        fileTrace?.finish(
          arguments: {
            'outcome': 'file_ready',
            'bytes': byteCount,
            'wav_cache_hit': wavWasCached,
            'render_or_cache_lookup_us': renderUs,
          },
        );
        return path;
      } catch (error) {
        _pending.remove(cacheKey);
        fileTrace?.finishError(error, stage: 'file_write');
        rethrow;
      }
    }();
  }
}
