import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_slice_rules.dart';

Int16List _clickTrain(int sampleRate, List<int> onsetMs, int totalMs) {
  final n = (sampleRate * totalMs / 1000).round();
  final out = Int16List(n);
  for (final ms in onsetMs) {
    final start = (sampleRate * ms / 1000).round();
    for (var i = 0; i < 1500 && start + i < n; i++) {
      // Short decaying burst = a transient.
      out[start + i] = (20000 * (1 - i / 1500)).round();
    }
  }
  return out;
}

void main() {
  const sr = 44100;

  test('detectOnsets finds bursts near known positions', () {
    final samples = _clickTrain(sr, [0, 500, 1000, 1500], 2000);
    final onsets = detectOnsets(samples, sr, sensitivity: 0.5);
    // 0 is excluded (implicit region start); expect ~3 internal onsets.
    expect(onsets.length, inInclusiveRange(2, 5));
    for (final target in [500, 1000, 1500]) {
      final targetSample = sr * target ~/ 1000;
      final near = onsets.any(
        (o) => (o - targetSample).abs() < sr * 60 ~/ 1000,
      );
      expect(near, isTrue, reason: 'no onset near ${target}ms');
    }
  });

  test('higher sensitivity never yields fewer onsets', () {
    final samples = _clickTrain(sr, [0, 250, 500, 750, 1000], 1300);
    final low = detectOnsets(samples, sr, sensitivity: 0.1).length;
    final high = detectOnsets(samples, sr, sensitivity: 0.9).length;
    expect(high, greaterThanOrEqualTo(low));
  });

  test('slicePlacements maps cuts to consecutive bars and clamps overflow', () {
    final plan = slicePlacements(
      cutSamples: [sr, 2 * sr, 3 * sr],
      totalSamples: 4 * sr,
      sampleRate: sr,
      startBar: 2,
      sectionLengthBars: 4,
    );
    // 4 regions requested, only bars 2 and 3 free -> 2 placed, 2 dropped.
    expect(plan.slices.length, 2);
    expect(plan.droppedCount, 2);
    expect(plan.slices[0].bar, 2);
    expect(plan.slices[1].bar, 3);
    expect(plan.slices[0].trimStartMs, 0);
    expect(plan.slices[0].trimEndMs, 1000);
    expect(plan.slices[1].trimStartMs, 1000);
    expect(plan.slices[1].trimEndMs, 2000);
  });
}
