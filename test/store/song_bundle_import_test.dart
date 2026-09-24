import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_bundle_rules.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_bundle_import.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  late Directory root;
  late Directory stagingParent;
  late SongAudioRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('song-bundle-repo-test-');
    stagingParent = await Directory.systemTemp.createTemp(
      'song-bundle-stage-test-',
    );
    repository = SongAudioRepository.testWith(rootDirectory: root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
    if (stagingParent.existsSync()) {
      await stagingParent.delete(recursive: true);
    }
  });

  test(
    'imports WAV, MP3, and M4A under fresh IDs and remaps references',
    () async {
      final project = _audioProject();
      final sourceBytes = <String, Uint8List>{
        'source-wav': Uint8List.fromList([1, 2, 3]),
        'source-mp3': Uint8List.fromList([4, 5, 6, 7]),
        'source-m4a': Uint8List.fromList([8, 9]),
      };
      final bytes = await buildSongBundleBytes(
        project,
        readAsset: (id, _) async => sourceBytes[id],
      );

      final imported = await importSongBundleBytes(
        bytes,
        repository: repository,
        stagingParent: stagingParent,
      );
      final importedAssets = {
        for (final asset in imported.project.audioAssets) asset.id: asset,
      };

      expect(imported.project.tracks.single.name, 'Audio');
      expect(importedAssets.keys, hasLength(3));
      expect(importedAssets.keys, isNot(contains('source-wav')));
      for (final pattern in imported.project.audioPatterns) {
        expect(importedAssets, contains(pattern.assetId));
      }
      for (final entry in project.audioAssets) {
        final copied = imported.project.audioAssets.firstWhere(
          (asset) => asset.format == entry.format,
        );
        expect(copied.id, isNot(entry.id));
        expect(
          await repository.readAssetBytes(copied.id, copied.format),
          sourceBytes[entry.id],
        );
      }
      expect(stagingParent.listSync(), isEmpty);
    },
  );

  test(
    'failed copy rolls back earlier fresh files and removes staging',
    () async {
      final project = _audioProject();
      final bytes = await buildSongBundleBytes(
        project,
        readAsset: (id, _) async => Uint8List.fromList([id.length, 1, 2]),
      );
      var writes = 0;

      await expectLater(
        importSongBundleBytes(
          bytes,
          repository: repository,
          stagingParent: stagingParent,
          assetWriter: (assetBytes, sourceAsset) async {
            writes++;
            if (writes == 2) throw StateError('Injected second-copy failure');
            return repository.writeImportedBundleAsset(
              bytes: assetBytes,
              sourceAsset: sourceAsset,
            );
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(writes, 2);
      final repositoryDirectory = Directory('${root.path}/song_audio');
      expect(
        repositoryDirectory.existsSync()
            ? repositoryDirectory.listSync()
            : const [],
        isEmpty,
      );
      expect(stagingParent.listSync(), isEmpty);
    },
  );

  test(
    'successful replacement undoes and redoes with media still present',
    () async {
      final originalAsset = AudioAsset(
        id: 'existing-audio',
        durationMs: 200,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: const [],
        sourceLabel: 'Existing',
      );
      final oldFile = await repository.resolvePath(originalAsset.id, 'wav');
      await oldFile.writeAsBytes([1, 2, 3]);
      const initial = SongProject(
        config: SongProjectConfig(
          tempo: 100,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: [],
        clips: [],
        notePatterns: [],
        drumPatterns: [],
        audioAssets: [],
        audioPatterns: [],
      );
      final bytes = await buildSongBundleBytes(
        _audioProject(),
        readAsset: (id, _) async => Uint8List.fromList([1, 2, 3]),
      );
      final container = ProviderContainer(
        overrides: [songAudioRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);
      await notifier.loadProject(
        initial.copyWith(audioAssets: [originalAsset]),
      );
      final imported = await importSongBundleBytes(
        bytes,
        repository: repository,
        stagingParent: stagingParent,
      );
      notifier.replaceProjectWithUndo(imported.project);

      expect(notifier.undoCount, 1);
      expect(notifier.undo(), isTrue);
      expect(
        container.read(songProjectProvider).audioAssets.single.id,
        'existing-audio',
      );
      expect(oldFile.existsSync(), isTrue);
      expect(notifier.redo(), isTrue);
      final importedWav = imported.project.audioAssets.firstWhere(
        (asset) => asset.format == 'wav',
      );
      expect(
        container
            .read(songProjectProvider)
            .audioAssets
            .map((asset) => asset.id),
        contains(importedWav.id),
      );
      expect(await repository.readAssetBytes(importedWav.id, 'wav'), [1, 2, 3]);
    },
  );
}

SongProject _audioProject() {
  const formats = ['wav', 'mp3', 'm4a'];
  final assets = [
    for (var index = 0; index < formats.length; index++)
      AudioAsset(
        id: 'source-${formats[index]}',
        durationMs: 1000 + index,
        sampleRate: 44100,
        channels: 2,
        format: formats[index],
        peaks: const [],
        sourceLabel: 'Take ${formats[index]}',
      ),
  ];
  final patterns = [
    for (final asset in assets)
      AudioClipPattern(
        id: 'pattern-${asset.format}',
        name: asset.sourceLabel,
        assetId: asset.id,
        trimStartMs: 15,
      ),
  ];
  return SongProject(
    config: const SongProjectConfig(
      tempo: 120,
      timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
      totalMeasures: 4,
    ),
    tracks: const [
      SongTrack(
        id: 'audio-track',
        name: 'Audio',
        type: SongTrackType.audio,
        order: 0,
      ),
    ],
    clips: [
      for (var index = 0; index < formats.length; index++)
        SongClipInstance(
          id: 'clip-$index',
          trackId: 'audio-track',
          patternId: 'pattern-${formats[index]}',
          patternType: SongPatternType.audio,
          startTick: index * 16,
        ),
    ],
    notePatterns: const [],
    drumPatterns: const [],
    audioAssets: assets,
    audioPatterns: patterns,
    markers: const [],
  );
}
