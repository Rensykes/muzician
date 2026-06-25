import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_recorder_store.dart'
    show
        SongAudioRecorderDriver,
        SongAudioRecorderStatus,
        songAudioRecorderDriverProvider;
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/songwriter_audio_recorder_store.dart';
import 'package:muzician/utils/wav_writer.dart';

class _FakeDriver implements SongAudioRecorderDriver {
  bool started = false;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async => started = true;
  @override
  Future<Uint8List> stop() async => writeWavPcm16Mono(
    Int16List.fromList(List<int>.filled(4410, 0)),
    sampleRate: 44100,
  );
  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sw_rec_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('record -> ready exposes a ~100ms asset', () async {
    final c = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
        songwriterAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(
            rootDirectory: tmp,
            subdir: 'songwriter_audio',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(countInMs: 0);
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.recording,
    );
    await n.stop();
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.ready,
    );

    final asset = n.consumePendingAsset();
    expect(asset, isNotNull);
    expect(asset!.durationMs, inInclusiveRange(90, 110));
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.idle,
    );
  });
}
