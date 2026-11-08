/// Pure audio sample helpers shared by Writer and the audio repository.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Collapses interleaved multi-channel PCM16 to a single mono channel by
/// averaging the channels of each frame. Returns [samples] unchanged when
/// [channels] is 1 or less.
///
/// Onset detection and time-stretch treat their input as mono; feeding them a
/// raw interleaved stereo buffer would both halve every sample-position math
/// (`ms * sampleRate` counts frames, not interleaved samples) and mangle the
/// signal. Downmix first so those pipelines see true mono frames.
Int16List downmixToMono(Int16List samples, int channels) {
  if (channels <= 1 || samples.isEmpty) return samples;
  final frames = samples.length ~/ channels;
  final out = Int16List(frames);
  for (var f = 0; f < frames; f++) {
    final base = f * channels;
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += samples[base + c];
    }
    out[f] = (sum / channels).round();
  }
  return out;
}

/// Compresses a PCM 16-bit sample buffer down to [targetBins] amplitude bins
/// scaled to 0..255.  Each bin holds the absolute maximum across the samples
/// assigned to it.  Used to render audio clip waveforms on the timeline.
List<int> computePeaksFromInt16(Int16List samples, {int targetBins = 400}) {
  if (samples.isEmpty) return const [];
  final bins = math.min(targetBins, samples.length);
  final step = samples.length / bins;
  final out = List<int>.filled(bins, 0);
  for (var i = 0; i < bins; i++) {
    final from = (i * step).floor();
    final to = math.min(samples.length, ((i + 1) * step).floor());
    var peak = 0;
    for (var s = from; s < to; s++) {
      final v = samples[s].abs();
      if (v > peak) peak = v;
    }
    out[i] = (peak * 255 / 32767).round().clamp(0, 255);
  }
  return out;
}
