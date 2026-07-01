import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('repo_subdir_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('subdir scopes files and reconcile to one feature', () async {
    final songRepo = SongAudioRepository.testWith(
      rootDirectory: tmp,
      subdir: 'song_audio',
    );
    final writerRepo = SongAudioRepository.testWith(
      rootDirectory: tmp,
      subdir: 'songwriter_audio',
    );

    final wav = writeWavPcm16Mono(
      Int16List.fromList(List<int>.filled(4410, 0)),
      sampleRate: 44100,
    );

    final a = await songRepo.writeRecording(wav);
    final b = await writerRepo.writeRecording(wav);

    expect(File('${tmp.path}/song_audio/${a.id}.wav').existsSync(), isTrue);
    expect(
      File('${tmp.path}/songwriter_audio/${b.id}.wav').existsSync(),
      isTrue,
    );

    final result = await writerRepo.reconcileOrphans(referencedAssetIds: {});
    expect(result.deletedAssetIds, [b.id]);
    expect(File('${tmp.path}/song_audio/${a.id}.wav').existsSync(), isTrue);
    expect(
      File('${tmp.path}/songwriter_audio/${b.id}.wav').existsSync(),
      isFalse,
    );
  });
}
