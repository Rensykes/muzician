/// Pure pitch-preserving time-stretch (WSOLA) for mono PCM16.
///
/// Sketch quality, tunable via the constants below. No external deps so it runs
/// in `compute()`.
library;

import 'dart:math';
import 'dart:typed_data';

/// Argument bundle for running [stretchInt16] inside `compute()`.
class StretchRequest {
  final Int16List samples;
  final int sampleRate;
  final int targetMs;
  const StretchRequest(this.samples, this.sampleRate, this.targetMs);
}

/// Top-level `compute()` entry point.
Int16List runStretch(StretchRequest r) =>
    stretchInt16(r.samples, r.sampleRate, r.targetMs);

const int _frame = 1024;
const int _synthHop = _frame ~/ 2; // 512
const int _search = 128;

/// Time-stretches [input] (mono int16) to ~[targetMs] at [sampleRate],
/// preserving pitch. Returns a new buffer.
Int16List stretchInt16(Int16List input, int sampleRate, int targetMs) {
  final targetLen = (targetMs / 1000.0 * sampleRate).round();
  if (input.isEmpty || targetLen <= 0) return Int16List(0);
  // Identity: when the stretch ratio is within 1.5% of 1.0, return the input
  // unchanged (avoids rounding drift from ms→samples round-trips).
  final ratio0 = input.length / targetLen;
  if ((ratio0 - 1.0).abs() < 0.015) {
    return Int16List.fromList(input);
  }
  if (input.length < _frame) return _linearResample(input, targetLen);

  final ratio = input.length / targetLen; // analysis advance per synth hop
  final window = _hann(_frame);
  final out = Float64List(targetLen + _frame);
  final norm = Float64List(targetLen + _frame);
  final ref = Float64List(_frame); // expected continuation to match next frame

  var outPos = 0;
  var analysisPos = 0.0;
  var first = true;
  while (outPos + _frame <= out.length) {
    final centre = analysisPos.floor();
    if (centre + _frame > input.length) break;
    final a = first ? centre : _bestOffset(input, centre, ref);
    for (var i = 0; i < _frame; i++) {
      out[outPos + i] += input[a + i] * window[i];
      norm[outPos + i] += window[i];
    }
    for (var i = 0; i < _frame; i++) {
      final j = a + _synthHop + i;
      ref[i] = j < input.length ? input[j].toDouble() : 0.0;
    }
    outPos += _synthHop;
    analysisPos += _synthHop * ratio;
    first = false;
  }

  final result = Int16List(targetLen);
  for (var i = 0; i < targetLen; i++) {
    final n = norm[i];
    final v = n > 1e-6 ? out[i] / n : 0.0;
    result[i] = v.clamp(-32768.0, 32767.0).round();
  }
  return result;
}

int _bestOffset(Int16List x, int centre, Float64List ref) {
  final maxStart = x.length - _frame;
  if (maxStart <= 0) return 0;
  final lo = (centre - _search).clamp(0, maxStart);
  final hi = (centre + _search).clamp(0, maxStart);
  const overlap = _frame ~/ 2;
  var bestPos = centre.clamp(0, maxStart);
  var bestCorr = -double.infinity;
  for (var p = lo; p <= hi; p++) {
    var corr = 0.0;
    for (var i = 0; i < overlap; i++) {
      corr += x[p + i] * ref[i];
    }
    if (corr > bestCorr) {
      bestCorr = corr;
      bestPos = p;
    }
  }
  return bestPos;
}

Float64List _hann(int n) {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * cos(2 * pi * i / (n - 1));
  }
  return w;
}

Int16List _linearResample(Int16List input, int targetLen) {
  final out = Int16List(targetLen);
  // Guard the degenerate ends: a single source sample, or a single-sample
  // target (which would divide by `targetLen - 1 == 0` below and yield NaN).
  if (input.length == 1 || targetLen == 1) {
    for (var i = 0; i < targetLen; i++) {
      out[i] = input[0];
    }
    return out;
  }
  for (var i = 0; i < targetLen; i++) {
    final srcPos = i * (input.length - 1) / (targetLen - 1);
    final lo = srcPos.floor();
    final hi = min(lo + 1, input.length - 1);
    final frac = srcPos - lo;
    out[i] = (input[lo] * (1 - frac) + input[hi] * frac).round();
  }
  return out;
}
