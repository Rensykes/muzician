/// NotePlayer – offline note, plucked-guitar and percussion preview.
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

import '../models/guitar_sound.dart';
import '../models/piano_roll.dart';
import '../models/song_project.dart';
import 'guitar_synth.dart';
import 'playback_voice_spec.dart';
import 'playback_profiling.dart';
import 'playback_profile_source.dart';
import 'timbre_synth.dart';

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
// Completion handling (seek back to the start) after a one-shot's own length.
const _poolHoldMarginMs = 60;
const _previewStrumHoldMs = 1800;

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

// ── Voice rendering (pure; safe to run in a background isolate) ──────────────

Uint8List _renderDrumWav(DrumLaneId lane) {
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

Uint8List _renderPianoChord(List<int> notes, int durationMs) {
  final mixed = Float64List(_sampleRate * durationMs ~/ 1000);
  final gain = 1 / math.sqrt(notes.length);
  for (final midi in notes) {
    final wav = _renderSequencedNote(midi, durationMs);
    final bytes = ByteData.sublistView(wav);
    for (var i = 0; i < mixed.length; i++) {
      mixed[i] += bytes.getInt16(44 + i * 2, Endian.little) * gain;
    }
  }
  final peak = mixed.fold<double>(
    32767,
    (peak, value) => math.max(peak, value.abs()),
  );
  final samples = Int16List(mixed.length);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = (mixed[i] * 32767 / peak).round();
  }
  return _encodeWav(samples);
}

/// Renders the WAV for [voice]. The single source of truth for every play and
/// prepare path, keyed by [PlaybackVoiceSpec.cacheKey].
Uint8List _renderPlaybackVoice(PlaybackVoiceSpec voice) {
  switch (voice.kind) {
    case PlaybackVoiceKind.click:
      return _renderClick(voice.accent ? _clickFreqAccent : _clickFreqWeak);
    case PlaybackVoiceKind.drum:
      return _renderDrumWav(voice.lane!);
    case PlaybackVoiceKind.sequencedNote:
      final tone = voice.guitarTone;
      return tone == null
          ? _renderSequencedNote(voice.midiNotes.first, voice.durationMs)
          : GuitarSynth.renderNote(
              voice.midiNotes.first,
              tone: tone,
              duration: Duration(milliseconds: voice.durationMs),
            );
    case PlaybackVoiceKind.sequencedChord:
      final tone = voice.guitarTone;
      return tone == null
          ? _renderPianoChord(voice.midiNotes, voice.durationMs)
          : GuitarSynth.renderChord(
              voice.midiNotes,
              tone: tone,
              duration: Duration(milliseconds: voice.durationMs),
            );
    case PlaybackVoiceKind.guitarStroke:
      return GuitarSynth.renderStroke(
        voice.strokeStrings,
        tone: voice.guitarTone!,
      );
  }
}

List<Uint8List> _renderPlaybackVoices(List<PlaybackVoiceSpec> voices) => [
  for (final voice in voices) _renderPlaybackVoice(voice),
];

/// Renders [voices] on at most [_maxRenderIsolates] background isolates.
Future<List<Uint8List>> _renderOffIsolate(
  List<PlaybackVoiceSpec> voices,
) async {
  final lanes = math.min(_maxRenderIsolates, voices.length);
  final chunks = [for (var i = 0; i < lanes; i++) <PlaybackVoiceSpec>[]];
  for (var i = 0; i < voices.length; i++) {
    chunks[i % lanes].add(voices[i]);
  }
  final rendered = await Future.wait([
    for (final chunk in chunks) compute(_renderPlaybackVoices, chunk),
  ]);
  return [
    for (var i = 0; i < voices.length; i++) rendered[i % lanes][i ~/ lanes],
  ];
}

/// Renders the WAVs for [voices], in order. Replaceable for tests.
typedef PlaybackVoiceRenderer =
    Future<List<Uint8List>> Function(List<PlaybackVoiceSpec> voices);

const _maxRenderIsolates = 3;
const _maxPreparedVoices = 256;
const _maxPreparedSequencedPlayers = 16;
// Hard cap on native sequenced players; prepare pre-creates only the plan's
// peak (at most [_maxPreparedSequencedPlayers]).
const _maxSequencedPlayers = 32;

// ── Singleton ────────────────────────────────────────────────────────────────

class NotePlayer {
  NotePlayer._() : _renderVoices = _renderOffIsolate;

  @visibleForTesting
  NotePlayer.forTesting({PlaybackVoiceRenderer? voiceRenderer})
    : _renderVoices = voiceRenderer ?? _renderOffIsolate;

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

  /// Last volume set on each sequenced player; absent until first applied.
  final Map<AudioPlayer, double> _volumeByPlayer = {};
  int _poolIndex = 0;

  /// Which sample each pool player last held, and until when it is ringing.
  final Map<AudioPlayer, Object> _poolSourceKey = {};
  final Map<AudioPlayer, int> _poolBusyUntilMs = {};
  final Stopwatch _poolClock = Stopwatch()..start();

  // Bytes cache — used by BytesSource on all non-iOS platforms.
  final Map<Object, Uint8List> _bytesCache = {};

  // File cache — iOS only; DeviceFileSource requires a named .wav file.
  final Map<Object, String> _fileCache = {};
  final Map<Object, Future<String>> _pending = {};
  String? _tempDir;
  final Set<String> _guitarStrumCacheKeys = {};
  static const _maxCachedGuitarStrums = 16;

  // Prepared Writer strokes are LRU-bounded at the prepare cap, so one run's
  // prepared set can never evict itself.
  final Set<String> _strokeCacheKeys = {};
  static const _maxCachedStrokes = _maxPreparedVoices;

  bool _ready = false;
  final PlaybackVoiceRenderer _renderVoices;

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
        final player = _newOneShotPlayer();
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
    _previewNote(midiNote, volume: volume, pan: pan);
  }

  /// Previews one clean or distorted electric guitar string.
  void previewGuitarNote(
    int midiNote, {
    GuitarTone tone = GuitarTone.clean,
    double volume = 0.8,
    double pan = 0.0,
  }) {
    final midi = GuitarSynth.safeMidi(midiNote);
    _previewNote(
      midi,
      volume: volume,
      pan: pan,
      cacheKey: GuitarSynth.noteCacheKey(midi, tone: tone),
      render: () => GuitarSynth.renderNote(midi, tone: tone),
    );
  }

  /// Plays an entire stroke as one WAV with sample-accurate string onsets.
  /// The caller supplies physical string order; repeated pitches are retained.
  void previewGuitarStrum(
    List<int> midiNotesInStrokeOrder, {
    GuitarTone tone = GuitarTone.clean,
    double volume = 0.8,
    double pan = 0.0,
  }) {
    final notes = GuitarSynth.strokeNotes(midiNotesInStrokeOrder);
    if (notes.isEmpty) return;
    _previewNote(
      notes.first,
      volume: volume,
      pan: pan,
      cacheKey: GuitarSynth.strumCacheKey(notes, tone: tone),
      render: () => GuitarSynth.renderStrum(notes, tone: tone),
    );
  }

  /// Previews [midiNote] with the Piano Roll [sound].
  void previewTimbre(
    PianoRollSound sound,
    int midiNote, {
    double volume = 0.8,
    double pan = 0.0,
  }) {
    switch (sound) {
      case PianoRollSound.piano:
        previewNote(midiNote, volume: volume, pan: pan);
      case PianoRollSound.cleanGuitar:
        previewGuitarNote(
          midiNote,
          tone: GuitarTone.clean,
          volume: volume,
          pan: pan,
        );
      case PianoRollSound.distortedGuitar:
        previewGuitarNote(
          midiNote,
          tone: GuitarTone.distorted,
          volume: volume,
          pan: pan,
        );
      case PianoRollSound.organ:
      case PianoRollSound.synthLead:
      case PianoRollSound.bell:
        _previewNote(
          midiNote,
          volume: volume,
          pan: pan,
          cacheKey: TimbreSynth.cacheKey(sound, midiNote),
          render: () => _encodeWav(TimbreSynth.render(sound, midiNote)),
        );
    }
  }

  void _previewNote(
    int midiNote, {
    required double volume,
    required double pan,
    Object? cacheKey,
    Uint8List Function()? render,
  }) {
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
    unawaited(
      _play(
        midiNote,
        volume,
        pan,
        profileVoice: profileVoice,
        cacheKey: cacheKey,
        render: render,
      ),
    );
  }

  /// A simultaneous chord uses one platform voice instead of racing several
  /// source bindings. It participates in transport stop/cancellation.
  void playSequencedChord(
    List<int> midiNotes, {
    required Duration duration,
    double volume = 0.8,
    double pan = 0.0,
    GuitarTone? guitarTone,
  }) {
    if (!_ready || midiNotes.isEmpty) return;
    final voice = PlaybackVoiceSpec.sequencedChord(
      midiNotes,
      duration: duration,
      guitarTone: guitarTone,
    );
    final profileVoice = playbackProfilingEnabled
        ? playbackProfileVoiceContext()
        : null;
    if (profileVoice != null) profileVoice.run.request(profileVoice);
    unawaited(
      _playSequencedNote(
        voice.midiNotes.first,
        duration: Duration(milliseconds: voice.durationMs),
        onsetDelay: Duration.zero,
        volume: volume,
        pan: pan,
        generation: _sequencedGeneration,
        profileVoice: profileVoice,
        cacheKeyOverride: voice.cacheKey,
        renderOverride: () => _renderPlaybackVoice(voice),
      ),
    );
  }

  /// Plays one whole guitar stroke as a single voice. The stroke WAV carries
  /// every string's own onset and duration, so the voice releases at the latest
  /// string end and is cancelled by [stopSequencedNotes] like any sequenced
  /// voice.
  void playSequencedStroke(
    List<GuitarStrokeString> strings, {
    required GuitarTone guitarTone,
    double volume = 0.8,
    double pan = 0.0,
  }) {
    if (!_ready || strings.isEmpty) return;
    final voice = PlaybackVoiceSpec.guitarStroke(
      strings,
      guitarTone: guitarTone,
    );
    final profileVoice = playbackProfilingEnabled
        ? playbackProfileVoiceContext()
        : null;
    if (profileVoice != null) profileVoice.run.request(profileVoice);
    final cacheKey = voice.cacheKey as String;
    _rememberStrokes([cacheKey]);
    unawaited(
      _playSequencedNote(
        voice.strokeStrings.first.midi,
        duration: Duration(milliseconds: voice.durationMs),
        onsetDelay: Duration.zero,
        volume: volume,
        pan: pan,
        generation: _sequencedGeneration,
        profileVoice: profileVoice,
        cacheKeyOverride: cacheKey,
        renderOverride: () => _renderPlaybackVoice(voice),
      ),
    );
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
    GuitarTone? guitarTone,
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
        guitarTone == null ? midiNote : GuitarSynth.safeMidi(midiNote),
        duration: duration,
        onsetDelay: onsetDelay,
        volume: volume,
        pan: pan,
        generation: _sequencedGeneration,
        profileVoice: profileVoice,
        guitarTone: guitarTone,
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

  /// Renders [voices] off the UI isolate, registers them in the WAV caches
  /// (and the native file cache on Apple platforms), and pre-creates up to
  /// [sequencedPlayers] sequenced players, so a run starts without synthesis
  /// or player construction on its hot path.
  ///
  /// Idempotent: voices already cached and players already pooled cost nothing.
  /// Best effort: a failure leaves the lazy play-time path to cover the voice.
  /// A call that outlives its transport's Stop still fills the caches, which
  /// the next run reuses.
  Future<void> prepareForPlayback(
    Iterable<PlaybackVoiceSpec> voices, {
    int sequencedPlayers = 0,
  }) async {
    if (!_ready) return;
    final unique = <Object, PlaybackVoiceSpec>{};
    for (final voice in voices) {
      if (unique.length >= _maxPreparedVoices) break;
      unique.putIfAbsent(voice.cacheKey, () => voice);
    }
    final trace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'note_player.prepare_for_playback',
            arguments: {
              'voice_count': unique.length,
              'sequenced_players': sequencedPlayers,
            },
          )
        : null;
    try {
      _rememberStrokes([
        for (final voice in unique.values)
          if (voice.kind == PlaybackVoiceKind.guitarStroke)
            voice.cacheKey as String,
      ]);
      final toRender = [
        for (final voice in unique.values)
          if (!_bytesCache.containsKey(voice.cacheKey)) voice,
      ];
      if (toRender.isNotEmpty) {
        List<Uint8List> rendered;
        try {
          rendered = await _renderVoices(toRender);
          if (rendered.length != toRender.length) {
            throw StateError('Renderer returned ${rendered.length} voices.');
          }
        } catch (_) {
          rendered = _renderPlaybackVoices(toRender);
        }
        for (var i = 0; i < toRender.length; i++) {
          _bytesCache.putIfAbsent(toRender[i].cacheKey, () => rendered[i]);
        }
      }
      if (_needsFile) {
        await Future.wait([
          for (final voice in unique.values)
            if (!_fileCache.containsKey(voice.cacheKey))
              _ensureFile(
                voice.cacheKey,
                () => _renderPlaybackVoice(voice),
              ).then<void>((_) {}, onError: (Object _) {}),
        ]);
      }
      await _ensureSequencedPlayers(
        sequencedPlayers.clamp(0, _maxPreparedSequencedPlayers),
      );
      trace?.finish(
        arguments: {
          'outcome': 'prepared',
          'rendered_count': toRender.length,
          'pooled_sequenced_players': _sequencedPool.length,
        },
      );
    } catch (error) {
      trace?.finishError(error, stage: 'prepare_for_playback');
    }
  }

  int _sequencedPlayersBeingCreated = 0;

  Future<void> _ensureSequencedPlayers(int count) async {
    final missing =
        count - _sequencedPool.length - _sequencedPlayersBeingCreated;
    if (missing <= 0) return;
    _sequencedPlayersBeingCreated += missing;
    try {
      final created = await Future.wait([
        for (var i = 0; i < missing; i++) _createSequencedPlayer(),
      ]);
      _sequencedPool.addAll(created.whereType<AudioPlayer>());
    } finally {
      _sequencedPlayersBeingCreated -= missing;
    }
  }

  /// A player for short one-shots. Nothing here listens to the position
  /// stream, and the default per-frame updater queries the platform for every
  /// ringing player on each frame, which loads the platform thread in step with
  /// the number of simultaneous voices.
  AudioPlayer _newOneShotPlayer() => AudioPlayer()..positionUpdater = null;

  Future<AudioPlayer?> _createSequencedPlayer() async {
    AudioPlayer? player;
    try {
      player = _newOneShotPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
    } catch (_) {
      if (player != null) unawaited(player.dispose());
      return null;
    }
    playbackProfileInstant(
      'note_player.player_created',
      arguments: {
        'kind': 'sequenced_prepared',
        'player_id': identityHashCode(player),
      },
    );
    return player;
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

  /// Applies [pan] to a pool [player] only when it differs from the last
  /// value set — skips the platform-channel round trip in the common
  /// unpanned case (and lets clicks recenter for free).
  Future<void> _applyBalance(AudioPlayer player, double pan) async {
    final clamped = pan.clamp(-1.0, 1.0);
    if ((_balanceByPlayer[player] ?? 0.0) == clamped) return;
    _balanceByPlayer[player] = clamped;
    await player.setBalance(clamped);
  }

  /// Applies [volume] to a sequenced [player] only when it differs from the
  /// last value set, avoiding a platform round trip per voice.
  Future<void> _applyVolume(AudioPlayer player, double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (_volumeByPlayer[player] == clamped) return;
    final previous = _volumeByPlayer[player];
    // Recorded before the await so concurrent voices on the same player skip
    // the redundant call; platform calls keep their issue order.
    _volumeByPlayer[player] = clamped;
    try {
      await player.setVolume(clamped);
    } catch (_) {
      if (previous == null) {
        _volumeByPlayer.remove(player);
      } else {
        _volumeByPlayer[player] = previous;
      }
      rethrow;
    }
  }

  /// Chooses the pool player for a short one-shot of [cacheKey].
  ///
  /// The Darwin player rebuilds its native item whenever the source URL
  /// changes, which costs far more than replaying the URL it already holds. A
  /// player that is idle and already holds this sample is therefore preferred;
  /// otherwise the least recently used idle player, and only when every player
  /// is still ringing the oldest one is taken over. A ringing player is never
  /// chosen for the same sample, so a retrigger is not swallowed.
  AudioPlayer _acquirePoolPlayer(Object cacheKey, int sampleMs) {
    final nowMs = _poolClock.elapsedMilliseconds;
    AudioPlayer? holder;
    AudioPlayer? idle;
    var idleSince = 0;
    for (final candidate in _pool) {
      final busyUntil = _poolBusyUntilMs[candidate] ?? 0;
      if (busyUntil > nowMs) continue;
      if (_poolSourceKey[candidate] == cacheKey) {
        holder = candidate;
        break;
      }
      if (idle == null || busyUntil < idleSince) {
        idle = candidate;
        idleSince = busyUntil;
      }
    }
    final player = holder ?? idle ?? _pool[_poolIndex++ % _poolSize];
    _markPoolPlayer(player, cacheKey, sampleMs);
    return player;
  }

  void _markPoolPlayer(AudioPlayer player, Object cacheKey, int sampleMs) {
    _poolSourceKey[player] = cacheKey;
    _poolBusyUntilMs[player] =
        _poolClock.elapsedMilliseconds + sampleMs + _poolHoldMarginMs;
  }

  static int _drumSampleMs(DrumLaneId lane) => switch (lane) {
    DrumLaneId.kick => _drumKickDurationMs,
    DrumLaneId.snare => _drumSnareDurationMs,
    DrumLaneId.closedHiHat => _drumHiHatClosedDurationMs,
    DrumLaneId.openHiHat => _drumHiHatOpenDurationMs,
    DrumLaneId.clap => _drumClapDurationMs,
    DrumLaneId.lowTom => _drumLowTomDurationMs,
    DrumLaneId.highTom => _drumHighTomDurationMs,
    DrumLaneId.crash => _drumCrashDurationMs,
  };

  Future<void> _playDrum(DrumLaneId lane, double volume, double pan) async {
    final voice = PlaybackVoiceSpec.drum(lane);
    final cacheKey = voice.cacheKey;
    final player = _acquirePoolPlayer(cacheKey, _drumSampleMs(lane));
    await player.setVolume(volume.clamp(0.0, 1.0));
    await _applyBalance(player, pan);
    if (_needsFile) {
      final path = await _ensureFile(
        cacheKey,
        () => _renderPlaybackVoice(voice),
      );
      await player.play(DeviceFileSource(path));
    } else {
      final bytes = _bytesCache.putIfAbsent(
        cacheKey,
        () => _renderPlaybackVoice(voice),
      );
      await player.play(BytesSource(bytes));
    }
  }

  Future<void> _play(
    int midi,
    double volume,
    double pan, {
    PlaybackProfileVoiceContext? profileVoice,
    Object? cacheKey,
    Uint8List Function()? render,
  }) async {
    cacheKey ??= midi;
    render ??= () => _renderNote(midi);
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    _markPoolPlayer(
      player,
      cacheKey,
      cacheKey is String ? _previewStrumHoldMs : _noteDurationMs,
    );
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
          ? _fileCache.containsKey(cacheKey)
          : false;
      final bytesWereCached = playbackProfilingEnabled
          ? _bytesCache.containsKey(cacheKey)
          : false;
      if (_needsFile) {
        final path = await _ensureFile(cacheKey, render);
        source = DeviceFileSource(path);
      } else {
        final bytes = _bytesCache.putIfAbsent(cacheKey, render);
        source = BytesSource(bytes);
      }
      if (cacheKey is String && cacheKey.startsWith('guitar_strum_')) {
        _rememberGuitarStrum(cacheKey);
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
    GuitarTone? guitarTone,
    Object? cacheKeyOverride,
    Uint8List Function()? renderOverride,
  }) async {
    final voiceClock = Stopwatch()..start();
    final releaseDeadline = onsetDelay + duration;
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
        if (_sequencedPool.length + _sequencedPlayersBeingCreated >=
            _maxSequencedPlayers) {
          // Bounded pool: a voice that finds every player busy is dropped
          // instead of growing the native player count without limit.
          if (profileVoice != null) {
            profileVoice.run.outcome(profileVoice, 'dropped_pool_exhausted');
          }
          noteTrace?.finish(
            arguments: sequencedPlaybackProfileArguments(
              profileTimelineArguments: profileVoice?.timelineArguments,
              sequencedVoiceId: sequencedVoiceId,
              additionalArguments: {
                'outcome': 'dropped_pool_exhausted',
                'pool_size': _sequencedPool.length,
              },
            ),
          );
          return;
        }
        _sequencedPlayersBeingCreated++;
        try {
          player = _newOneShotPlayer();
          await player.setReleaseMode(ReleaseMode.stop);
          _sequencedPool.add(player);
        } finally {
          _sequencedPlayersBeingCreated--;
        }
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
      final durationMs = guitarTone != null
          ? GuitarSynth.durationMilliseconds(duration)
          : duration.inMilliseconds < 1
          ? 1
          : duration.inMilliseconds;
      var expired = false;
      bool pastRelease() => expired || voiceClock.elapsed >= releaseDeadline;
      // Release against the requested score time, including source preparation.
      // A delayed platform prepare must never add its latency to note duration.
      final remaining = releaseDeadline - voiceClock.elapsed;
      final releaseTimer = Timer(
        remaining > Duration.zero ? remaining : Duration.zero,
        () {
          expired = true;
          unawaited(
            _stopSequencedVoice(player, voiceId, reason: 'natural_completion'),
          );
        },
      );
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
          await _applyVolume(player, volume);
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
        if (pastRelease() ||
            generation != _sequencedGeneration ||
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

        final noteVoice = PlaybackVoiceSpec.sequencedNote(
          midi,
          duration: Duration(milliseconds: durationMs),
          guitarTone: guitarTone,
        );
        final Object cacheKey = cacheKeyOverride ?? noteVoice.cacheKey;
        Uint8List render() =>
            renderOverride?.call() ?? _renderPlaybackVoice(noteVoice);
        if (_needsFile) {
          final fileWasCached = playbackProfilingEnabled
              ? _fileCache.containsKey(cacheKey)
              : false;
          final bytesWereCached = playbackProfilingEnabled
              ? _bytesCache.containsKey(cacheKey)
              : false;
          final path = await _ensureFile(cacheKey, render);
          if (pastRelease() ||
              generation != _sequencedGeneration ||
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
          final bytes = _bytesCache.putIfAbsent(cacheKey, render);
          if (pastRelease() ||
              generation != _sequencedGeneration ||
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
            pastRelease() ||
            generation != _sequencedGeneration ||
            _activeSequencedVoices[player] != voiceId) {
          releaseTimer.cancel();
          await _stopSequencedVoice(
            player,
            voiceId,
            reason: pastRelease()
                ? 'natural_completion'
                : started
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
          pastRelease() ||
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
      // A pending play can finish while stop is waiting inside the platform.
      // Retry for the same still-owned voice after that operation settles;
      // otherwise its late resume can outlive the transport's Stop.
      if (identical(_sequencedStops[player], existingStop)) {
        _sequencedStops.remove(player);
      }
      if (_activeSequencedVoices[player] != voiceId) return;
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
    final wasPending = _pendingSequencedVoices[player] == voiceId;
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
          !wasPending &&
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
    final voice = PlaybackVoiceSpec.click(accent: accent);
    final cacheKey = voice.cacheKey;
    final player = _acquirePoolPlayer(cacheKey, _clickDurationMs);
    await player.setVolume(volume.clamp(0.0, 1.0));
    // Pool players are shared with panned notes/drums — recenter for clicks.
    await _applyBalance(player, 0.0);
    if (_needsFile) {
      final path = await _ensureFile(
        cacheKey,
        () => _renderPlaybackVoice(voice),
      );
      await player.play(DeviceFileSource(path));
    } else {
      final bytes = _bytesCache.putIfAbsent(
        cacheKey,
        () => _renderPlaybackVoice(voice),
      );
      await player.play(BytesSource(bytes));
    }
  }

  void _rememberGuitarStrum(String cacheKey) =>
      _rememberLru(_guitarStrumCacheKeys, [cacheKey], _maxCachedGuitarStrums);

  void _rememberStrokes(Iterable<String> cacheKeys) =>
      _rememberLru(_strokeCacheKeys, cacheKeys, _maxCachedStrokes);

  /// Marks [cacheKeys] most recent, then evicts the oldest beyond [maxKeys].
  /// Touching the whole set first keeps a run's own keys from evicting each
  /// other.
  void _rememberLru(Set<String> keys, Iterable<String> cacheKeys, int maxKeys) {
    for (final cacheKey in cacheKeys) {
      keys
        ..remove(cacheKey)
        ..add(cacheKey);
    }
    while (keys.length > maxKeys) {
      final oldest = keys.first;
      keys.remove(oldest);
      _bytesCache.remove(oldest);
      final path = _fileCache.remove(oldest);
      if (path == null) continue;
      // Let any current preview finish before reclaiming its native WAV.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 4), () async {
          if (_fileCache.containsKey(oldest) || _pending.containsKey(oldest)) {
            return;
          }
          try {
            await ioDeleteIfExists(path);
          } catch (_) {
            // Cache cleanup must never interrupt playing an instrument.
          }
        }),
      );
    }
  }

  Future<String> _ensureFile(Object cacheKey, Uint8List Function() render) {
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
      final name = cacheKey is String
          ? cacheKey
          : (cacheKey as int) >= 0
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
