import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('stretch_repo_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'writeStretched writes a wav whose duration matches the samples',
    () async {
      final repo = SongAudioRepository.testWith(
        rootDirectory: tmp,
        subdir: 'songwriter_audio',
      );
      final samples = Int16List.fromList(
        List<int>.filled(88200, 0),
      ); // 2s @44.1k
      final asset = await repo.writeStretched(
        samples: samples,
        sampleRate: 44100,
      );
      expect(asset.durationMs, inInclusiveRange(1990, 2010));
      expect(asset.sourceLabel, 'Stretched');
      final f = await repo.resolvePath(asset.id, 'wav');
      expect(f.existsSync(), isTrue);
    },
  );

  test('readInt16Samples round-trips written samples', () async {
    final repo = SongAudioRepository.testWith(
      rootDirectory: tmp,
      subdir: 'songwriter_audio',
    );
    final wav = writeWavPcm16Mono(
      Int16List.fromList([10, -20, 30, -40]),
      sampleRate: 44100,
    );
    final asset = await repo.writeRecording(wav);
    final back = await repo.readInt16Samples(asset.id, 'wav');
    expect(back.sublist(0, 4), [10, -20, 30, -40]);
  });
}
