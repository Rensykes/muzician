/// Production implementation of [SongAudioRecorderDriver] backed by the
/// `record` package.  Always records mono WAV 16-bit at 44.1 kHz so the in-app
/// peak/waveform pipeline can decode the bytes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'song_audio_recorder_store.dart';

class RecordPackageDriver implements SongAudioRecorderDriver {
  final AudioRecorder _recorder = AudioRecorder();
  File? _currentFile;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'song_audio_tmp'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(
      p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.wav'),
    );
    _currentFile = file;
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 44100,
        bitRate: 16 * 44100,
      ),
      path: file.path,
    );
  }

  @override
  Future<Uint8List> stop() async {
    final returnedPath = await _recorder.stop();
    final filePath = returnedPath ?? _currentFile?.path;
    if (filePath == null) {
      throw StateError('No recording file produced');
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('Recording file missing at $filePath');
    }
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } on FileSystemException {
      // ignore
    }
    _currentFile = null;
    return bytes;
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {
      // already disposed
    }
  }
}
