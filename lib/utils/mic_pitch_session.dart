import 'dart:async';

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

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<PitchFrame>> start() async {
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    return stream.map((bytes) {
      final frequency = rules.estimateDominantFrequency(
        bytes,
        sampleRate: 16000,
      );
      final midiNote = frequency == null
          ? null
          : rules.frequencyToMidi(frequency);
      return PitchFrame(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        frequencyHz: frequency ?? 0,
        midiNote: midiNote,
        centsOffset: 0,
        amplitude: rules.estimateNormalizedAmplitude(bytes),
        confidence: midiNote == null ? 0 : 1,
        isSilence: midiNote == null,
      );
    });
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
