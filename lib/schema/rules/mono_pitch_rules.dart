import 'dart:math';
import 'dart:typed_data';

import '../../models/hum_to_midi.dart';
import '../../models/piano_roll.dart';
import 'piano_roll_rules.dart' as piano_roll_rules;

const minHumFrequencyHz = 80.0;
const maxHumFrequencyHz = 1000.0;
const minStableConfidence = 0.6;
const minStableNoteMs = 80;
const maxMergeGapMs = 180;
const _yinThreshold = 0.15;
const minHumAmplitude = 0.02;
const _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

int? frequencyToMidi(double frequencyHz) {
  if (frequencyHz < minHumFrequencyHz || frequencyHz > maxHumFrequencyHz) {
    return null;
  }
  final midi = 69 + 12 * log(frequencyHz / 440.0) / ln2;
  return midi.round();
}

String midiToNoteLabel(int midiNote) {
  final octave = (midiNote ~/ 12) - 1;
  return '${_noteNames[midiNote % 12]}$octave';
}

double estimateNormalizedAmplitude(Uint8List bytes) {
  if (bytes.isEmpty) return 0;
  final data = ByteData.sublistView(bytes);
  var maxAbs = 0.0;
  for (var i = 0; i < bytes.lengthInBytes; i += 2) {
    final sample = data.getInt16(i, Endian.little).abs() / 32768.0;
    if (sample > maxAbs) maxAbs = sample;
  }
  return maxAbs;
}

double? estimateDominantFrequency(Uint8List bytes, {required int sampleRate}) {
  if (bytes.lengthInBytes < 4) return null;
  final data = ByteData.sublistView(bytes);
  final samples = Float64List(bytes.lengthInBytes ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return estimateDominantFrequencyFromSamples(samples, sampleRate: sampleRate)
      ?.frequencyHz;
}

class PitchEstimate {
  final double frequencyHz;
  final double confidence;
  const PitchEstimate({required this.frequencyHz, required this.confidence});
}

PitchEstimate? estimateDominantFrequencyFromSamples(
  List<double> samples, {
  required int sampleRate,
}) {
  final minLag = sampleRate ~/ maxHumFrequencyHz;
  final maxLag = sampleRate ~/ minHumFrequencyHz;
  if (samples.length <= maxLag) return null;

  final difference = Float64List(maxLag + 1);
  for (var lag = minLag; lag <= maxLag; lag++) {
    var sum = 0.0;
    final limit = samples.length - lag;
    for (var i = 0; i < limit; i++) {
      final delta = samples[i] - samples[i + lag];
      sum += delta * delta;
    }
    difference[lag] = sum;
  }

  final cmndf = Float64List(maxLag + 1);
  cmndf[0] = 1;
  var runningTotal = 0.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    runningTotal += difference[lag];
    cmndf[lag] = runningTotal == 0 ? 1 : difference[lag] * lag / runningTotal;
  }

  var bestLag = -1;
  for (var lag = minLag; lag <= maxLag; lag++) {
    if (cmndf[lag] < _yinThreshold) {
      while (lag + 1 <= maxLag && cmndf[lag + 1] < cmndf[lag]) {
        lag += 1;
      }
      bestLag = lag;
      break;
    }
  }
  if (bestLag < 0) return null;

  double refinedLag = bestLag.toDouble();
  if (bestLag > minLag && bestLag < maxLag) {
    final s0 = cmndf[bestLag - 1];
    final s1 = cmndf[bestLag];
    final s2 = cmndf[bestLag + 1];
    final denom = 2 * (s0 - 2 * s1 + s2);
    if (denom.abs() > 1e-12) {
      final adjust = (s0 - s2) / denom;
      if (adjust.abs() < 1) {
        refinedLag = bestLag + adjust;
      }
    }
  }

  final frequency = sampleRate / refinedLag;
  if (frequency < minHumFrequencyHz || frequency > maxHumFrequencyHz) {
    return null;
  }
  final confidence = (1.0 - cmndf[bestLag]).clamp(0.0, 1.0);
  return PitchEstimate(frequencyHz: frequency, confidence: confidence);
}


List<DetectedMonoNote> segmentStableNotes(List<PitchFrame> frames) {
  if (frames.isEmpty) return const [];

  final frameSpanMs = _estimateMedianFrameSpanMs(frames);

  final notes = <DetectedMonoNote>[];
  int? activeMidi;
  int? startMs;
  double confidenceTotal = 0;
  int confidenceCount = 0;
  int lastVoicedMs = frames.first.timestampMs;
  int? pendingMidi;
  int pendingFrames = 0;

  void emit() {
    final midi = activeMidi;
    final start = startMs;
    if (midi == null || start == null) return;
    final rawDuration = lastVoicedMs - start;
    final duration = rawDuration <= 0 ? frameSpanMs : rawDuration;
    if (duration < minStableNoteMs) return;
    notes.add(
      DetectedMonoNote(
        startMs: start,
        endMs: start + duration,
        midiNote: midi,
        confidence: confidenceCount == 0 ? 0 : confidenceTotal / confidenceCount,
      ),
    );
  }

  for (final frame in frames) {
    final isVoiced =
        !frame.isSilence &&
        frame.midiNote != null &&
        frame.confidence >= minStableConfidence;
    if (isVoiced) {
      final midi = frame.midiNote!;
      if (activeMidi == null) {
        activeMidi = midi;
        startMs = frame.timestampMs;
        pendingMidi = null;
        pendingFrames = 0;
      } else if (midi != activeMidi) {
        if (pendingMidi == midi) {
          pendingFrames += 1;
        } else {
          pendingMidi = midi;
          pendingFrames = 1;
        }
        if (pendingFrames >= 2) {
          emit();
          activeMidi = midi;
          startMs = frame.timestampMs;
          confidenceTotal = 0;
          confidenceCount = 0;
          pendingMidi = null;
          pendingFrames = 0;
        }
      } else {
        pendingMidi = null;
        pendingFrames = 0;
      }
      lastVoicedMs = frame.timestampMs;
      confidenceTotal += frame.confidence;
      confidenceCount += 1;
      continue;
    }

    if (activeMidi != null &&
        frame.timestampMs - lastVoicedMs > maxMergeGapMs) {
      emit();
      activeMidi = null;
      startMs = null;
      confidenceTotal = 0;
      confidenceCount = 0;
      pendingMidi = null;
      pendingFrames = 0;
    }
  }

  if (activeMidi != null) {
    emit();
  }

  return notes;
}

int _estimateMedianFrameSpanMs(List<PitchFrame> frames) {
  if (frames.length < 2) return 32;
  final deltas = <int>[];
  for (var i = 1; i < frames.length; i++) {
    final delta = frames[i].timestampMs - frames[i - 1].timestampMs;
    if (delta > 0) deltas.add(delta);
  }
  if (deltas.isEmpty) return 32;
  deltas.sort();
  return deltas[deltas.length ~/ 2];
}

List<QuantizedHumNote> quantizeNotesToTicks({
  required List<DetectedMonoNote> notes,
  required int anchorTick,
  required int tempo,
  required TimeSignature timeSignature,
  required int snapTicks,
}) {
  final msPerTick = 60000 / tempo / piano_roll_rules.ticksPerQuarter;
  return notes.map((note) {
    final rawStartTick = anchorTick + (note.startMs / msPerTick);
    final rawEndTick = anchorTick + (note.endMs / msPerTick);
    final roundedStart = rawStartTick.round();
    final roundedEnd = max(roundedStart + 1, rawEndTick.round());
    final snappedStart =
        snapTicks > 1 &&
            (roundedStart % snapTicks).abs() <= max(1, snapTicks ~/ 2)
        ? (roundedStart / snapTicks).round() * snapTicks
        : roundedStart;
    return QuantizedHumNote(
      midiNote: note.midiNote,
      startTick: snappedStart,
      durationTicks: max(1, roundedEnd - snappedStart),
    );
  }).toList();
}

List<QuantizedHumNote> normalizeQuantizedHumNotesMonophonically(
  List<QuantizedHumNote> notes,
) {
  if (notes.isEmpty) return const [];

  final orderedIndexes = List<int>.generate(notes.length, (index) => index)
    ..sort((a, b) {
      final startTickCompare = notes[a].startTick.compareTo(notes[b].startTick);
      if (startTickCompare != 0) return startTickCompare;
      return a.compareTo(b);
    });

  final normalized = <QuantizedHumNote>[];
  for (final index in orderedIndexes) {
    final note = notes[index];
    normalized.add(
      QuantizedHumNote(
        midiNote: note.midiNote,
        startTick: note.startTick,
        durationTicks: note.durationTicks,
      ),
    );

    if (normalized.length < 2) continue;

    final previousIndex = normalized.length - 2;
    final previous = normalized[previousIndex];
    final current = normalized.last;
    final previousEnd = previous.startTick + previous.durationTicks;

    if (current.startTick < previousEnd) {
      final trimmedDuration = current.startTick - previous.startTick;
      if (trimmedDuration <= 0) {
        normalized.removeAt(previousIndex);
      } else {
        normalized[previousIndex] = QuantizedHumNote(
          midiNote: previous.midiNote,
          startTick: previous.startTick,
          durationTicks: trimmedDuration,
        );
      }
    }
  }

  return normalized;
}
