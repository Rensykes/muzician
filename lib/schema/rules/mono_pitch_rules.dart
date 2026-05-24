import 'dart:math';
import 'dart:typed_data';

import '../../models/hum_to_midi.dart';
import '../../models/piano_roll.dart';
import 'piano_roll_rules.dart' as piano_roll_rules;

const minHumFrequencyHz = 80.0;
const maxHumFrequencyHz = 1000.0;
const minStableConfidence = 0.85;
const minStableNoteMs = 120;
const maxMergeGapMs = 120;
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
  final samples = <double>[
    for (var i = 0; i < bytes.lengthInBytes; i += 2)
      data.getInt16(i, Endian.little) / 32768.0,
  ];
  final minLag = sampleRate ~/ maxHumFrequencyHz;
  final maxLag = sampleRate ~/ minHumFrequencyHz;
  if (samples.length <= maxLag) return null;

  final difference = List<double>.filled(maxLag + 1, 0);
  for (var lag = minLag; lag <= maxLag; lag++) {
    var sum = 0.0;
    for (var i = 0; i + lag < samples.length; i++) {
      final delta = samples[i] - samples[i + lag];
      sum += delta * delta;
    }
    difference[lag] = sum;
  }

  final cmndf = List<double>.filled(maxLag + 1, 1);
  var runningTotal = 0.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    runningTotal += difference[lag];
    cmndf[lag] = runningTotal == 0 ? 1 : difference[lag] * lag / runningTotal;
  }

  for (var lag = minLag; lag <= maxLag; lag++) {
    if (cmndf[lag] < 0.15) {
      return sampleRate / lag;
    }
  }

  return null;
}

List<DetectedMonoNote> segmentStableNotes(List<PitchFrame> frames) {
  if (frames.isEmpty) return const [];
  final notes = <DetectedMonoNote>[];
  int? activeMidi;
  int? startMs;
  double confidenceTotal = 0;
  int confidenceCount = 0;
  int lastVoicedMs = frames.first.timestampMs;

  for (final frame in frames) {
    final isVoiced =
        !frame.isSilence &&
        frame.midiNote != null &&
        frame.confidence >= minStableConfidence;
    if (isVoiced) {
      if (activeMidi == null) {
        activeMidi = frame.midiNote;
        startMs = frame.timestampMs;
      } else if (frame.midiNote != activeMidi) {
        final endMs = lastVoicedMs;
        if (startMs != null && endMs - startMs >= minStableNoteMs) {
          notes.add(
            DetectedMonoNote(
              startMs: startMs,
              endMs: endMs,
              midiNote: activeMidi,
              confidence: confidenceCount == 0
                  ? 0
                  : confidenceTotal / confidenceCount,
            ),
          );
        }
        activeMidi = frame.midiNote;
        startMs = frame.timestampMs;
        confidenceTotal = 0;
        confidenceCount = 0;
      }
      lastVoicedMs = frame.timestampMs;
      confidenceTotal += frame.confidence;
      confidenceCount += 1;
      continue;
    }

    if (activeMidi != null &&
        frame.timestampMs - lastVoicedMs > maxMergeGapMs) {
      if (startMs != null && lastVoicedMs - startMs >= minStableNoteMs) {
        notes.add(
          DetectedMonoNote(
            startMs: startMs,
            endMs: lastVoicedMs,
            midiNote: activeMidi,
            confidence: confidenceCount == 0
                ? 0
                : confidenceTotal / confidenceCount,
          ),
        );
      }
      activeMidi = null;
      startMs = null;
      confidenceTotal = 0;
      confidenceCount = 0;
    }
  }

  if (activeMidi != null &&
      startMs != null &&
      lastVoicedMs - startMs >= minStableNoteMs) {
    notes.add(
      DetectedMonoNote(
        startMs: startMs,
        endMs: lastVoicedMs,
        midiNote: activeMidi,
        confidence: confidenceCount == 0
            ? 0
            : confidenceTotal / confidenceCount,
      ),
    );
  }

  return notes;
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
