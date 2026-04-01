/// NotePlayer – pure-Dart additive-synthesis note preview.
///
/// Renders a piano-like tone (fundamental + harmonics, exponential decay) as a
/// WAV file in the temp directory (one file per MIDI note, kept for the app
/// lifetime) and plays it via audioplayers DeviceFileSource.
/// No native assets or soundfont files required.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

// ── Synthesis constants ──────────────────────────────────────────────────────

const _sampleRate = 44100;
const _noteDurationMs = 700;
const _decayRate = 5.5;
const _poolSize = 6;

// ── Pure-Dart helpers ────────────────────────────────────────────────────────

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

// ── Singleton ────────────────────────────────────────────────────────────────

class NotePlayer {
  NotePlayer._();
  static final NotePlayer instance = NotePlayer._();

  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;

  // midi → path of the written .wav file
  final Map<int, String> _fileCache = {};
  // midi → Future that resolves once the file is written (prevents races)
  final Map<int, Future<String>> _pending = {};

  String? _tempDir;
  bool _ready = false;

  /// Initialises the player pool and resolves the temp directory.
  /// Call once during app startup.
  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    _tempDir = dir.path;
    for (var i = 0; i < _poolSize; i++) {
      _pool.add(AudioPlayer());
    }
    _ready = true;
  }

  /// Plays [midiNote] as a short synthesised tone.
  /// First call per note writes the WAV file; subsequent calls are instant.
  void previewNote(int midiNote, {int velocity = 90}) {
    if (!_ready) return;
    unawaited(_play(midiNote));
  }

  Future<void> _play(int midi) async {
    final path = await _ensureFile(midi);
    final player = _pool[_poolIndex % _poolSize];
    _poolIndex++;
    await player.play(DeviceFileSource(path));
  }

  Future<String> _ensureFile(int midi) {
    if (_fileCache.containsKey(midi)) {
      return Future.value(_fileCache[midi]);
    }
    return _pending.putIfAbsent(midi, () async {
      final path = '${_tempDir!}/note_$midi.wav';
      final file = File(path);
      if (!file.existsSync()) {
        await file.writeAsBytes(_renderNote(midi));
      }
      _fileCache[midi] = path;
      _pending.remove(midi);
      return path;
    });
  }
}
