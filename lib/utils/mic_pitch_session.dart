import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../models/hum_to_midi.dart';
import '../schema/rules/mono_pitch_rules.dart' as rules;

abstract class MicPitchSession {
  Future<bool> hasPermission();
  Future<Stream<PitchFrame>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordMicPitchSession implements MicPitchSession {
  RecordMicPitchSession({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const _sampleRate = 16000;
  static const _windowSamples = 1024;
  static const _hopSamples = 512;

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _pcmSub;
  StreamController<PitchFrame>? _controller;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<PitchFrame>> start() async {
    final pcmStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    final controller = StreamController<PitchFrame>();
    _controller = controller;
    final ring = Float64List(_windowSamples);
    var ringFill = 0;
    var processedSamples = 0;

    _pcmSub = pcmStream.listen(
      (bytes) {
        final byteData = ByteData.sublistView(bytes);
        final incomingCount = bytes.lengthInBytes ~/ 2;
        var inIdx = 0;
        while (inIdx < incomingCount) {
          final needed = _windowSamples - ringFill;
          final take = (incomingCount - inIdx) < needed
              ? (incomingCount - inIdx)
              : needed;
          for (var i = 0; i < take; i++) {
            ring[ringFill + i] =
                byteData.getInt16((inIdx + i) * 2, Endian.little) / 32768.0;
          }
          ringFill += take;
          inIdx += take;
          if (ringFill < _windowSamples) break;

          final windowStartSample = processedSamples;
          final timestampMs = (windowStartSample * 1000) ~/ _sampleRate;
          final amplitude = _peakAbs(ring);
          PitchFrame frame;
          if (amplitude < rules.minHumAmplitude) {
            frame = PitchFrame(
              timestampMs: timestampMs,
              frequencyHz: 0,
              midiNote: null,
              centsOffset: 0,
              amplitude: amplitude,
              confidence: 0,
              isSilence: true,
            );
          } else {
            final estimate = rules.estimateDominantFrequencyFromSamples(
              ring,
              sampleRate: _sampleRate,
            );
            final midiNote = estimate == null
                ? null
                : rules.frequencyToMidi(estimate.frequencyHz);
            frame = PitchFrame(
              timestampMs: timestampMs,
              frequencyHz: estimate?.frequencyHz ?? 0,
              midiNote: midiNote,
              centsOffset: 0,
              amplitude: amplitude,
              confidence: estimate?.confidence ?? 0,
              isSilence: midiNote == null,
            );
          }
          if (!controller.isClosed) controller.add(frame);

          for (var i = 0; i < _windowSamples - _hopSamples; i++) {
            ring[i] = ring[i + _hopSamples];
          }
          ringFill = _windowSamples - _hopSamples;
          processedSamples += _hopSamples;
        }
      },
      onError: controller.addError,
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: false,
    );

    return controller.stream;
  }

  static double _peakAbs(Float64List samples) {
    var peak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].abs();
      if (v > peak) peak = v;
    }
    return peak;
  }

  @override
  Future<void> stop() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _recorder.stop();
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _controller?.close();
    _controller = null;
    await _recorder.dispose();
  }
}
