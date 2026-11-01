import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../models/hum_to_midi.dart';
import 'hum_pcm_framer.dart';

abstract class MicPitchSession {
  Future<bool> hasPermission();
  Future<Stream<PitchFrame>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordMicPitchSession implements MicPitchSession {
  RecordMicPitchSession({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  // The web recorder resamples to the requested rate, so this holds everywhere.
  static const _sampleRate = 16000;

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
    final framer = HumPcmFramer(sampleRate: _sampleRate);

    _pcmSub = pcmStream.listen(
      (bytes) {
        for (final frame in framer.addPcm16(bytes)) {
          if (!controller.isClosed) controller.add(frame);
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
