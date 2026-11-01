import 'dart:typed_data';

import '../models/hum_to_midi.dart';
import '../schema/rules/mono_pitch_rules.dart' as rules;

/// Turns a PCM16 little-endian mono byte stream into [PitchFrame]s using a
/// sliding window. Pure Dart so it is testable without a microphone.
class HumPcmFramer {
  HumPcmFramer({
    this.sampleRate = 16000,
    this.windowSamples = 1024,
    this.hopSamples = 256,
  }) : _ring = Float64List(windowSamples);

  final int sampleRate;
  final int windowSamples;
  final int hopSamples;

  final Float64List _ring;
  final rules.NoiseFloorTracker _noiseFloor = rules.NoiseFloorTracker();
  int _fill = 0;
  int _processedSamples = 0;
  int? _carryByte;

  List<PitchFrame> addPcm16(Uint8List bytes) {
    final frames = <PitchFrame>[];
    var data = bytes;
    final carry = _carryByte;
    if (carry != null && bytes.isNotEmpty) {
      data = Uint8List(bytes.length + 1)
        ..[0] = carry
        ..setRange(1, bytes.length + 1, bytes);
      _carryByte = null;
    }
    final sampleCount = data.lengthInBytes ~/ 2;
    if (data.lengthInBytes.isOdd) _carryByte = data[data.lengthInBytes - 1];
    final view = ByteData.sublistView(data);
    for (var i = 0; i < sampleCount; i++) {
      _ring[_fill++] = view.getInt16(i * 2, Endian.little) / 32768.0;
      if (_fill < windowSamples) continue;
      frames.add(_analyseWindow());
      _ring.setRange(0, windowSamples - hopSamples, _ring, hopSamples);
      _fill = windowSamples - hopSamples;
      _processedSamples += hopSamples;
    }
    return frames;
  }

  PitchFrame _analyseWindow() {
    final frame = rules.analyzeHumWindow(
      _ring,
      sampleRate: sampleRate,
      // Stamp the window centre (not its start): a window only needs to
      // contain the tail of a new note to score high confidence, so a
      // start-of-window timestamp detects onsets too early.
      timestampMs:
          ((_processedSamples + windowSamples ~/ 2) * 1000) ~/ sampleRate,
      gate: _noiseFloor.gate,
    );
    _noiseFloor.update(
      frame.amplitude,
      pitched:
          frame.midiNote != null &&
          frame.confidence >= rules.minStableConfidence,
    );
    return frame;
  }
}
