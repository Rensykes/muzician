import 'dart:math';
import 'dart:typed_data';

/// One hum-like note: fundamental plus a weaker 2nd harmonic, with a short
/// attack/release so onsets are not clicks.
class HumNote {
  final double frequencyHz;
  final int startMs;
  final int endMs;
  final double amplitude;
  const HumNote(
    this.frequencyHz,
    this.startMs,
    this.endMs, {
    this.amplitude = 0.3,
  });
}

/// Renders [notes] plus uniform noise of peak [noiseAmplitude] as mono floats.
Float64List renderHum(
  List<HumNote> notes, {
  required int totalMs,
  int sampleRate = 16000,
  double noiseAmplitude = 0,
  int seed = 7,
}) {
  final random = Random(seed);
  final out = Float64List(totalMs * sampleRate ~/ 1000);
  for (var i = 0; i < out.length; i++) {
    out[i] = (random.nextDouble() * 2 - 1) * noiseAmplitude;
  }
  for (final note in notes) {
    final from = note.startMs * sampleRate ~/ 1000;
    final to = min(out.length, note.endMs * sampleRate ~/ 1000);
    const ramp = 160; // 10 ms at 16 kHz
    for (var i = from; i < to; i++) {
      final t = (i - from) / sampleRate;
      final edge = min(min((i - from) / ramp, (to - i) / ramp), 1.0);
      final v =
          sin(2 * pi * note.frequencyHz * t) +
          0.5 * sin(2 * pi * note.frequencyHz * 2 * t);
      out[i] += v / 1.5 * note.amplitude * edge;
    }
  }
  return out;
}

Uint8List toPcm16(Float64List samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(
      i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

double midiToHz(int midi) => 440.0 * pow(2, (midi - 69) / 12);
