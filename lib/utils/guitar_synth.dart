import 'dart:math' as math;
import 'dart:typed_data';

import '../models/guitar_sound.dart';

/// Offline plucked-string synthesis. No samples or network access are needed.
///
/// A damped delay loop models the string, an allpass tunes fractional periods,
/// and a feedforward comb models the magnetic pickup's position. The distorted
/// voice adds oversampled soft clipping and a simple cabinet low-pass response.
/// Based on the model described in Julius O. Smith's Physical Audio Signal
/// Processing: https://www.dsprelated.com/freebooks/pasp/Electric_Guitars.html
abstract final class GuitarSynth {
  static const sampleRate = 44100;
  static const previewDuration = Duration(milliseconds: 1800);
  static const strumSpacing = Duration(milliseconds: 25);
  static const maxDuration = Duration(seconds: 30);
  static const maxStrings = 12;

  // Bump when synthesis changes: native WAVs can survive application launches.
  static const cacheVersion = 3;

  static int safeMidi(int midi) => midi.clamp(0, 127);

  static int durationMilliseconds(Duration duration) =>
      duration.inMilliseconds.clamp(1, maxDuration.inMilliseconds);

  static String noteCacheKey(
    int midi, {
    GuitarTone tone = GuitarTone.clean,
    Duration duration = previewDuration,
  }) =>
      'guitar_v${cacheVersion}_${tone.name}_${safeMidi(midi)}_'
      '${durationMilliseconds(duration)}';

  static List<int> strokeNotes(List<int> midiNotes) =>
      midiNotes.take(maxStrings).map(safeMidi).toList(growable: false);

  static String strumCacheKey(
    List<int> midiNotes, {
    GuitarTone tone = GuitarTone.clean,
  }) =>
      'guitar_strum_v${cacheVersion}_${tone.name}_'
      '${strokeNotes(midiNotes).join('_')}';

  static Uint8List renderNote(
    int midi, {
    GuitarTone tone = GuitarTone.clean,
    Duration duration = previewDuration,
  }) {
    final samples = _string(safeMidi(midi), durationMilliseconds(duration), 0);
    _amplify(samples, tone);
    return _wav(samples);
  }

  /// Notes are already in stroke order; do not sort or deduplicate unisons.
  /// All onsets live in the same PCM buffer, independent of platform latency.
  static Uint8List renderStrum(
    List<int> midiNotesInStrokeOrder, {
    GuitarTone tone = GuitarTone.clean,
  }) {
    return _renderChord(
      midiNotesInStrokeOrder,
      tone: tone,
      duration: previewDuration,
      spacing: strumSpacing,
    );
  }

  /// Simultaneous voices share one buffer and one amplifier, preserving attack
  /// alignment even when the platform takes different times to prepare sources.
  static Uint8List renderChord(
    List<int> midiNotes, {
    GuitarTone tone = GuitarTone.clean,
    Duration duration = previewDuration,
  }) => _renderChord(
    midiNotes,
    tone: tone,
    duration: duration,
    spacing: Duration.zero,
  );

  static Uint8List _renderChord(
    List<int> midiNotes, {
    required GuitarTone tone,
    required Duration duration,
    required Duration spacing,
  }) {
    // A Writer mix bucket may contain several guitar lanes. Only physical
    // strum audition has a string-count limit; keep every simultaneous voice.
    final notes = spacing == Duration.zero
        ? midiNotes.map(safeMidi).toList(growable: false)
        : strokeNotes(midiNotes);
    if (notes.isEmpty) return _wav(Float64List(0));
    final durationMs = durationMilliseconds(duration);
    final length = sampleRate * durationMs ~/ 1000;
    int onset(int index) =>
        sampleRate * spacing.inMicroseconds * index ~/ 1000000;
    final lastOnset = onset(notes.length - 1);
    final mixed = Float64List(length + lastOnset);
    // Correlated unisons and dense chords must retain safe headroom.
    final gain = 1.0 / math.sqrt(notes.length);
    for (var string = 0; string < notes.length; string++) {
      final pluck = _string(notes[string], durationMs, string);
      final offset = onset(string);
      // A small, deterministic pick-strength variation avoids machine-like
      // repeated string attacks without detuning the requested notes.
      final strength = gain * (1.0 - 0.025 * (string % 3));
      for (var i = 0; i < pluck.length; i++) {
        mixed[offset + i] += pluck[i] * strength;
      }
    }
    // Distort the combined pickup signal, as a single guitar amplifier does.
    _amplify(mixed, tone);
    return _wav(mixed);
  }

  static Float64List _string(int midi, int durationMs, int variation) {
    final frequency = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    final period = sampleRate / frequency;
    final omega = 2.0 * math.pi / period;
    // The loss filter contributes phase delay. Compensate that delay and use
    // a first-order allpass for the remainder, preserving string tuning.
    const damping = 0.25;
    final filterPhase = math.atan2(
      damping * math.sin(omega),
      1.0 - damping + damping * math.cos(omega),
    );
    final delay = math.max(2, (period - filterPhase / omega).floor() - 1);
    final fraction = period - filterPhase / omega - delay;
    final allpass =
        math.sin(omega * (1.0 - fraction) / 2.0) /
        math.sin(omega * (1.0 + fraction) / 2.0);
    final line = Float64List(delay);
    final random = math.Random(131 + midi * 37 + variation * 101);
    final pickPosition = 0.19 + (variation % 3) * 0.012;
    var pickNoise = 0.0;
    var mean = 0.0;
    for (var i = 0; i < delay; i++) {
      final position = i / delay;
      final displacement = position < pickPosition
          ? position / pickPosition
          : (1.0 - position) / (1.0 - pickPosition);
      pickNoise = pickNoise * 0.55 + (random.nextDouble() * 2.0 - 1.0) * 0.45;
      line[i] = displacement * 1.7 + pickNoise * 0.12;
      mean += line[i];
    }
    mean /= delay;
    for (var i = 0; i < delay; i++) {
      line[i] -= mean;
    }

    final samples = Float64List(sampleRate * durationMs ~/ 1000);
    final pickupDelay = math.max(1, (period * 0.17).round());
    final pickupLine = Float64List(pickupDelay);
    // Start from the displaced string, avoiding an artificial pickup impulse.
    for (var i = 0; i < pickupDelay; i++) {
      pickupLine[i] = line[(delay - pickupDelay + i) % delay];
    }
    final loss = math.exp(-(1.5 + frequency / 1700.0) / frequency);
    final pickupLowPass = 1.0 - math.exp(-2.0 * math.pi * 4800 / sampleRate);
    final dcPole = math.exp(-2.0 * math.pi * 28 / sampleRate);
    final attackLength = math.max(1, math.min(samples.length ~/ 4, 66));
    final releaseLength = math.max(
      1,
      math.min(samples.length ~/ 3, sampleRate * 45 ~/ 1000),
    );
    var previous = line.last;
    var allpassInput = 0.0;
    var allpassOutput = 0.0;
    var pickupFiltered = 0.0;
    var dcInput = 0.0;
    var dcOutput = 0.0;
    var cursor = 0;
    var pickupCursor = 0;
    for (var i = 0; i < samples.length; i++) {
      final stringValue = line[cursor];
      final damped = (1.0 - damping) * stringValue + damping * previous;
      previous = stringValue;
      final tuned = allpass * damped + allpassInput - allpass * allpassOutput;
      allpassInput = damped;
      allpassOutput = tuned;
      line[cursor] = tuned * loss;
      cursor = (cursor + 1) % delay;

      final pickup = stringValue - pickupLine[pickupCursor];
      pickupLine[pickupCursor] = stringValue;
      pickupCursor = (pickupCursor + 1) % pickupDelay;
      pickupFiltered += pickupLowPass * (pickup - pickupFiltered);
      final centered = pickupFiltered - dcInput + dcPole * dcOutput;
      dcInput = pickupFiltered;
      dcOutput = centered;
      final attack = (i / attackLength).clamp(0.0, 1.0);
      final release = ((samples.length - 1 - i) / releaseLength).clamp(
        0.0,
        1.0,
      );
      samples[i] = centered * attack * release;
    }
    return samples;
  }

  static void _amplify(Float64List samples, GuitarTone tone) {
    if (tone == GuitarTone.clean) {
      for (var i = 0; i < samples.length; i++) {
        samples[i] *= 0.85;
      }
      return;
    }
    // Tighten the bass before driving the amp: low strings should not swamp
    // the chord with intermodulation. Two moderate saturation stages retain
    // the pluck, followed by a cabinet rolloff to remove brittle harmonics.
    const oversampling = 4;
    const rate = sampleRate * oversampling;
    final cabinet = 1.0 - math.exp(-2 * math.pi * 4200 / rate);
    final bassPole = math.exp(-2 * math.pi * 110 / rate);
    final couplingPole = math.exp(-2 * math.pi * 45 / rate);
    var previousInput = 0.0;
    var bassInput = 0.0;
    var bassOutput = 0.0;
    var couplingInput = 0.0;
    var couplingOutput = 0.0;
    var cabinetOne = 0.0;
    var cabinetTwo = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final input = samples[i];
      var output = 0.0;
      for (var sub = 1; sub <= oversampling; sub++) {
        final interpolated =
            previousInput + (input - previousInput) * sub / oversampling;
        final tightened = interpolated - bassInput + bassPole * bassOutput;
        bassInput = interpolated;
        bassOutput = tightened;
        final driven = tightened * 3.2;
        final preamp = driven / math.sqrt(1.0 + driven * driven);
        final coupled = preamp - couplingInput + couplingPole * couplingOutput;
        couplingInput = preamp;
        couplingOutput = coupled;
        final power = coupled * 1.6;
        final saturated = power / math.sqrt(1.0 + power * power);
        cabinetOne += cabinet * (saturated - cabinetOne);
        cabinetTwo += cabinet * (cabinetOne - cabinetTwo);
        output += cabinetTwo;
      }
      samples[i] = output / oversampling * 0.62;
      previousInput = input;
    }
    // The cabinet has filter memory; fade its final tail to exact silence.
    final release = math.min(samples.length, sampleRate * 5 ~/ 1000);
    for (var i = 0; i < release; i++) {
      samples[samples.length - 1 - i] *= i / release;
    }
  }

  static Uint8List _wav(Float64List samples) {
    var peak = 0.0;
    for (final value in samples) {
      peak = math.max(peak, value.abs());
    }
    // Reduce only when necessary. Never boost a quiet or decaying waveform.
    final gain = peak > 0.85 ? 0.85 / peak : 1.0;
    final bytes = ByteData(44 + samples.length * 2);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(
        44 + i * 2,
        (samples[i] * gain * 32767).round(),
        Endian.little,
      );
    }
    return bytes.buffer.asUint8List();
  }
}
