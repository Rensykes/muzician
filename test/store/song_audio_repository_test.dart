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

    test(
      'writeRecording stores file and returns populated AudioAsset',
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
      },
    );

    test(
      'delete removes the file and is idempotent for missing assets',
      () async {
        final samples = Int16List.fromList(List<int>.filled(44100, 0));
        final asset = await repo.writeRecording(
          writeWavPcm16Mono(samples, sampleRate: 44100),
        );
        await repo.delete(asset.id);
        final stored = await repo.resolvePath(asset.id, asset.format);
        expect(stored.existsSync(), isFalse);
        await repo.delete(asset.id); // second call must not throw
      },
    );

    test(
      'importExternalFile imports a WAV file and parses its header',
      () async {
        final samples = Int16List.fromList(List<int>.filled(22050, 5000));
        final wav = writeWavPcm16Mono(samples, sampleRate: 44100);
        final src = File('${tmp.path}/source.wav');
        await src.writeAsBytes(wav, flush: true);

        final asset = await repo.importExternalFile(
          sourcePath: src.path,
          sourceLabel: 'source.wav',
          explicitDurationMs: null,
        );

        expect(asset.format, 'wav');
        expect(asset.sourceLabel, 'source.wav');
        expect(asset.durationMs, closeTo(500, 5));
        final stored = await repo.resolvePath(asset.id, asset.format);
        expect(stored.existsSync(), isTrue);
      },
    );

    test(
      'importExternalFile copies an MP3 using the explicit duration probe',
      () async {
        final src = File('${tmp.path}/loop.mp3');
        await src.writeAsBytes(
          Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xFF)),
          flush: true,
        );

        final asset = await repo.importExternalFile(
          sourcePath: src.path,
          sourceLabel: 'loop.mp3',
          explicitDurationMs: 2500,
        );

        expect(asset.format, 'mp3');
        expect(asset.durationMs, 2500);
        expect(asset.peaks, isEmpty);
        final stored = await repo.resolvePath(asset.id, asset.format);
        expect(stored.existsSync(), isTrue);
      },
    );

    test('importExternalFile rejects unsupported file extensions', () async {
      final src = File('${tmp.path}/note.txt');
      await src.writeAsString('hello', flush: true);
      expect(
        () => repo.importExternalFile(
          sourcePath: src.path,
          sourceLabel: 'note.txt',
          explicitDurationMs: null,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'reconcileOrphans deletes files not referenced by the project',
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
      },
    );
  });
}
