import 'dart:math' as math;
import 'dart:typed_data';

/// Detected onset sample positions in [samples], strictly increasing and
/// excluding 0. Energy-novelty peaks above an adaptive threshold whose
/// strictness is set by [sensitivity] in [0,1] (higher -> more onsets).
List<int> detectOnsets(
  Int16List samples,
  int sampleRate, {
  double sensitivity = 0.5,
}) {
  const frame = 1024;
  const hop = 512;
  if (samples.length < frame * 2) return const [];

  final frames = ((samples.length - frame) / hop).floor() + 1;
  final energy = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    final start = f * hop;
    var sum = 0.0;
    for (var i = 0; i < frame; i++) {
      final s = samples[start + i] / 32768.0;
      sum += s * s;
    }
    energy[f] = sum / frame;
  }

  // Positive energy difference = novelty curve.
  final novelty = Float64List(frames);
  for (var f = 1; f < frames; f++) {
    final d = energy[f] - energy[f - 1];
    novelty[f] = d > 0 ? d : 0.0;
  }

  // Adaptive threshold: local mean + k*std over a sliding window.
  // k shrinks with sensitivity so more peaks pass when sensitivity is high.
  final k = 2.4 - 2.0 * sensitivity.clamp(0.0, 1.0); // ~2.4 .. 0.4
  const win = 16;
  final refractoryFrames = (sampleRate * 0.05 / hop).ceil(); // >=50 ms apart
  final onsets = <int>[];
  var lastFrame = -refractoryFrames - 1;
  for (var f = 1; f < frames; f++) {
    final lo = math.max(1, f - win);
    final hi = math.min(frames - 1, f + win);
    var mean = 0.0;
    for (var j = lo; j <= hi; j++) {
      mean += novelty[j];
    }
    mean /= (hi - lo + 1);
    var varSum = 0.0;
    for (var j = lo; j <= hi; j++) {
      final d = novelty[j] - mean;
      varSum += d * d;
    }
    final std = math.sqrt(varSum / (hi - lo + 1));
    final thr = mean + k * std;
    final isPeak =
        novelty[f] > thr &&
        novelty[f] >= novelty[f - 1] &&
        (f + 1 >= frames || novelty[f] >= novelty[f + 1]);
    if (isPeak && f - lastFrame > refractoryFrames) {
      final pos = f * hop;
      if (pos > 0) onsets.add(pos);
      lastFrame = f;
    }
  }
  return onsets;
}

/// Argument bundle for running [detectOnsets] inside `compute()`.
class DetectOnsetsRequest {
  const DetectOnsetsRequest(this.samples, this.sampleRate, this.sensitivity);
  final Int16List samples;
  final int sampleRate;
  final double sensitivity;
}

/// Top-level `compute()` entry, mirrors `runStretch`.
List<int> runDetectOnsets(DetectOnsetsRequest r) =>
    detectOnsets(r.samples, r.sampleRate, sensitivity: r.sensitivity);

/// One placeable slice: a trim region (ms, clip-local) on a target bar.
class PlacedSlice {
  const PlacedSlice({
    required this.trimStartMs,
    required this.trimEndMs,
    required this.bar,
  });
  final int trimStartMs;
  final int trimEndMs;
  final int bar;
}

/// Result of [slicePlacements]: the slices that fit, and how many were dropped
/// for lack of bars.
class SlicePlan {
  const SlicePlan({required this.slices, required this.droppedCount});
  final List<PlacedSlice> slices;
  final int droppedCount;
}

/// Turn ordered cut positions (sample indexes; 0 and end are implicit) into
/// regions placed on consecutive bars from [startBar]. The region count is
/// `cutSamples.length + 1`; it is clamped to the bars available from
/// [startBar] to [sectionLengthBars], and the overflow is reported.
SlicePlan slicePlacements({
  required List<int> cutSamples,
  required int totalSamples,
  required int sampleRate,
  required int startBar,
  required int sectionLengthBars,
}) {
  final bounds = <int>[0, ...cutSamples, totalSamples];
  final regions = bounds.length - 1;
  final available = (sectionLengthBars - startBar).clamp(0, sectionLengthBars);
  final placeable = math.min(regions, available);
  int msOf(int sample) => (sample * 1000 / sampleRate).round();
  final slices = <PlacedSlice>[
    for (var i = 0; i < placeable; i++)
      PlacedSlice(
        trimStartMs: msOf(bounds[i]),
        trimEndMs: msOf(bounds[i + 1]),
        bar: startBar + i,
      ),
  ];
  return SlicePlan(slices: slices, droppedCount: regions - placeable);
}
