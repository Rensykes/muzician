import 'dart:math' as math;
import 'dart:typed_data';

import '../models/piano_roll.dart';

/// Pure-Dart renderers for the non-piano, non-guitar Piano Roll timbres.
class TimbreSynth {
  TimbreSynth._();

  static const sampleRate = 44100;
  static const _durationMs = 700;

  /// Bump when a renderer changes so cached audio is not reused.
  static const cacheVersion = 1;

  static Object cacheKey(PianoRollSound sound, int midi) =>
      'timbre_v${cacheVersion}_${sound.name}_$midi';

  static Int16List render(PianoRollSound sound, int midi) {
    final freq = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    final n = sampleRate * _durationMs ~/ 1000;
    final samples = Int16List(n);
    final voice = switch (sound) {
      PianoRollSound.organ => _organ,
      PianoRollSound.synthLead => _synthLead,
      PianoRollSound.bell => _bell,
      _ => throw ArgumentError.value(sound, 'sound', 'not a synth timbre'),
    };
    final release = sampleRate * 40 ~/ 1000;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final fade = n - i < release ? (n - i) / release : 1.0;
      samples[i] = (voice(freq, t) * fade * 20000).round().clamp(-32767, 32767);
    }
    return samples;
  }

  static double _sin(double f, double t) => math.sin(2 * math.pi * f * t);

  static double _organ(double f, double t) {
    final attack = math.min(t / 0.01, 1.0);
    final decay = 0.8 + 0.2 * math.exp(-t * 2);
    final v =
        _sin(f, t) * 0.5 +
        _sin(f * 2, t) * 0.3 +
        _sin(f * 3, t) * 0.15 +
        _sin(f * 4, t) * 0.08;
    return v * attack * decay;
  }

  static double _synthLead(double f, double t) {
    final attack = math.min(t / 0.005, 1.0);
    final vibrato = 1 + 0.004 * _sin(5.5, t);
    // Band-limited saw: first eight partials.
    var v = 0.0;
    for (var k = 1; k <= 8; k++) {
      v += _sin(f * k * vibrato, t) / k;
    }
    return v * 0.5 * attack * math.exp(-t * 1.2);
  }

  static double _bell(double f, double t) {
    // Inharmonic partials with faster decay on the upper ones.
    const partials = [
      (1.0, 1.0, 3.0),
      (2.76, 0.6, 5.0),
      (5.4, 0.35, 8.0),
      (8.93, 0.2, 12.0),
    ];
    var v = 0.0;
    for (final (ratio, gain, decay) in partials) {
      v += _sin(f * ratio, t) * gain * math.exp(-t * decay);
    }
    return v * 0.6;
  }
}
