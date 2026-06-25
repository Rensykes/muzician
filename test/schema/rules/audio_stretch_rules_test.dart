import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/audio_stretch_rules.dart';

Int16List _sine(int n, double freq, int sr) => Int16List.fromList([
  for (var i = 0; i < n; i++) (sin(2 * pi * freq * i / sr) * 12000).round(),
]);

double _rms(Int16List x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final s in x) {
    sum += s * s;
  }
  return sqrt(sum / x.length);
}

void main() {
  const sr = 44100;

  test('stretches to ~target length (2x longer)', () {
    final out = stretchInt16(_sine(sr, 220, sr), sr, 2000); // 1s -> 2s
    expect(out.length, closeTo(sr * 2, sr * 0.02));
  });

  test('compresses to ~target length (0.5x)', () {
    final out = stretchInt16(_sine(sr, 220, sr), sr, 500);
    expect(out.length, closeTo(sr ~/ 2, sr * 0.02));
  });

  test('preserves energy (output is not silence)', () {
    final input = _sine(sr, 220, sr);
    final out = stretchInt16(input, sr, 1500);
    expect(_rms(out), greaterThan(_rms(input) * 0.4));
  });

  test('handles sub-frame input via resample', () {
    final out = stretchInt16(_sine(200, 220, sr), sr, 20);
    expect(out.length, closeTo(sr * 20 ~/ 1000, 4));
  });

  test('identity when target ~= source length', () {
    final input = _sine(1000, 220, sr);
    final out = stretchInt16(input, sr, (1000 * 1000 / sr).round());
    expect(out.length, closeTo(1000, 4));
  });
}
