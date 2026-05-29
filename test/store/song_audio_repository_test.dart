import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  group('SongAudioRepository (file backend)', () {
    late Directory tmp;
    late SongAudioRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('song_audio_test_');
      repo = SongAudioRepository.testWith(rootDirectory: tmp);
    });

    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('writeRecording stores file and returns populated AudioAsset',
        () async {
      final samples = Int16List.fromList(
        List<int>.generate(44100, (i) => (i % 200) - 100),
      );
      final wav = writeWavPcm16Mono(samples, sampleRate: 44100);

      final asset = await repo.writeRecording(wav);

      expect(asset.format, 'wav');
      expect(asset.sampleRate, 44100);
      expect(asset.channels, 1);
      expect(asset.durationMs, closeTo(1000, 5));
      expect(asset.peaks, isNotEmpty);
      expect(asset.sourceLabel, 'Recording');

      final stored = await repo.resolvePath(asset.id, asset.format);
      expect(stored.existsSync(), isTrue);
      expect(stored.lengthSync(), wav.length);
    });

    test('delete removes the file and is idempotent for missing assets',
        () async {
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final asset = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );
      await repo.delete(asset.id);
      final stored = await repo.resolvePath(asset.id, asset.format);
      expect(stored.existsSync(), isFalse);
      await repo.delete(asset.id); // second call must not throw
    });

    test('reconcileOrphans deletes files not referenced by the project',
        () async {
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final keep = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );
      final orphan = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );

      final result = await repo.reconcileOrphans(
        referencedAssetIds: {keep.id},
      );

      expect(result.deletedAssetIds, contains(orphan.id));
      expect(result.deletedAssetIds, isNot(contains(keep.id)));
      final keepFile = await repo.resolvePath(keep.id, keep.format);
      expect(keepFile.existsSync(), isTrue);
    });
  });
}
