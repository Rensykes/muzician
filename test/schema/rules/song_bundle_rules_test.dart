import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart' show TimeSignature;
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_bundle_rules.dart';

void main() {
  test(
    'bundle ZIP contains versioned manifest, full Song state, and sources',
    () async {
      final source = Uint8List.fromList([0, 1, 2, 3, 255]);
      final bytes = await buildSongBundleBytes(
        _project(),
        readAsset: (id, format) async => source,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = {for (final file in archive.files) file.name: file};

      expect(
        files.keys,
        containsAll(['manifest.json', 'song.json', 'audio/asset-1.wav']),
      );
      final manifest =
          jsonDecode(utf8.decode(files['manifest.json']!.content))
              as Map<String, dynamic>;
      expect(manifest['format'], 'muzician-song-bundle');
      expect(manifest['schemaVersion'], 1);
      expect(manifest['entries'], [
        {
          'sourceAssetId': 'asset-1',
          'format': 'wav',
          'path': 'audio/asset-1.wav',
          'byteLength': source.length,
        },
      ]);
      expect(files['audio/asset-1.wav']!.content, source);

      final song = SongProject.fromJson(
        jsonDecode(utf8.decode(files['song.json']!.content))
            as Map<String, dynamic>,
      );
      expect(song.config.tempo, 120);
      expect(song.tracks.single.name, 'Audio');
      expect(song.clips.single.startTick, 4);
      expect(song.audioAssets.single.id, 'asset-1');
      expect(song.audioPatterns.single.trimStartMs, 50);
    },
  );

  test(
    'bundle without audio still contains Song state and empty manifest',
    () async {
      final bytes = await buildSongBundleBytes(
        _project(withAudio: false),
        readAsset: (id, format) async => null,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = {for (final file in archive.files) file.name: file};
      final manifest =
          jsonDecode(utf8.decode(files['manifest.json']!.content))
              as Map<String, dynamic>;

      expect(files.keys, unorderedEquals(['manifest.json', 'song.json']));
      expect(manifest['entries'], isEmpty);
      final song = SongProject.fromJson(
        jsonDecode(utf8.decode(files['song.json']!.content))
            as Map<String, dynamic>,
      );
      expect(song.tracks.single.name, 'Note');
      expect(song.audioAssets, isEmpty);
    },
  );

  test(
    'import decoder round-trips full Song state and validates asset bytes',
    () async {
      final source = Uint8List.fromList([4, 5, 6, 7]);
      final bytes = await buildSongBundleBytes(
        _project(),
        readAsset: (id, format) async => source,
      );

      final decoded = decodeSongBundleImport(bytes);

      expect(decoded.project.config.tempo, 120);
      expect(decoded.project.audioPatterns.single.assetId, 'asset-1');
      expect(decoded.entries.single.sourceAsset.id, 'asset-1');
      expect(decoded.entries.single.bytes, source);
    },
  );

  test(
    'import decoder rejects corrupt archives, traversal and version mismatch',
    () async {
      expect(
        () => decodeSongBundleImport(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<SongBundleException>()),
      );

      final traversal = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(
              ArchiveFile.string(
                'manifest.json',
                jsonEncode({
                  'format': 'muzician-song-bundle',
                  'schemaVersion': 1,
                  'entries': [],
                }),
              ),
            )
            ..addFile(
              ArchiveFile.string(
                'song.json',
                jsonEncode(_project(withAudio: false).toJson()),
              ),
            )
            ..addFile(ArchiveFile.bytes('../escape.wav', Uint8List(0))),
        ),
      );
      expect(
        () => decodeSongBundleImport(traversal),
        throwsA(isA<SongBundleException>()),
      );

      final valid = await buildSongBundleBytes(
        _project(),
        readAsset: (id, format) async => Uint8List.fromList([1]),
      );
      final archive = ZipDecoder().decodeBytes(valid);
      final files = {for (final file in archive.files) file.name: file};
      final manifest =
          jsonDecode(utf8.decode(files['manifest.json']!.content))
              as Map<String, dynamic>;
      manifest['schemaVersion'] = 2;
      final unsupportedVersion = _repack(
        files.map(
          (name, file) => MapEntry(
            name,
            name == 'manifest.json'
                ? Uint8List.fromList(utf8.encode(jsonEncode(manifest)))
                : file.content,
          ),
        ),
      );
      expect(
        () => decodeSongBundleImport(unsupportedVersion),
        throwsA(isA<SongBundleException>()),
      );
    },
  );

  test(
    'import decoder rejects missing references and mismatched lengths',
    () async {
      final valid = await buildSongBundleBytes(
        _project(),
        readAsset: (id, format) async => Uint8List.fromList([1, 2]),
      );
      final archive = ZipDecoder().decodeBytes(valid);
      final files = {for (final file in archive.files) file.name: file};
      final manifest =
          jsonDecode(utf8.decode(files['manifest.json']!.content))
              as Map<String, dynamic>;

      final missingManifest = Map<String, dynamic>.from(manifest)
        ..['entries'] = const [];
      final missingReference = _repack({
        'manifest.json': Uint8List.fromList(
          utf8.encode(jsonEncode(missingManifest)),
        ),
        'song.json': files['song.json']!.content,
      });
      expect(
        () => decodeSongBundleImport(missingReference),
        throwsA(isA<SongBundleException>()),
      );

      final entry = Map<String, dynamic>.from(
        (manifest['entries'] as List).single as Map<String, dynamic>,
      )..['byteLength'] = 99;
      final badLengthManifest = Map<String, dynamic>.from(manifest)
        ..['entries'] = [entry];
      final badLength = _repack({
        'manifest.json': Uint8List.fromList(
          utf8.encode(jsonEncode(badLengthManifest)),
        ),
        'song.json': files['song.json']!.content,
        'audio/asset-1.wav': files['audio/asset-1.wav']!.content,
      });
      expect(
        () => decodeSongBundleImport(badLength),
        throwsA(isA<SongBundleException>()),
      );
    },
  );

  test(
    'bundle preflight rejects missing sources and unsupported formats',
    () async {
      await expectLater(
        buildSongBundleBytes(_project(), readAsset: (id, format) async => null),
        throwsA(
          isA<SongBundleException>().having(
            (error) => error.message,
            'missing source message',
            contains('missing from this device'),
          ),
        ),
      );

      var readCalled = false;
      await expectLater(
        buildSongBundleBytes(
          _project(format: 'flac'),
          readAsset: (id, format) async {
            readCalled = true;
            return null;
          },
        ),
        throwsA(isA<SongBundleException>()),
      );
      expect(readCalled, isFalse);
    },
  );

  test('bundle rejects an audio entry over the 50 MB source limit', () async {
    final tooLarge = Uint8List(songBundleMaxAudioEntryBytes + 1);
    await expectLater(
      buildSongBundleBytes(
        _project(),
        readAsset: (id, format) async => tooLarge,
      ),
      throwsA(
        isA<SongBundleException>().having(
          (error) => error.message,
          'size limit message',
          contains('50 MB'),
        ),
      ),
    );
  });

  test(
    'bundle rejects path-like source IDs before making archive paths',
    () async {
      await expectLater(
        buildSongBundleBytes(
          _project(assetId: '../escape'),
          readAsset: (id, format) async => Uint8List(0),
        ),
        throwsA(isA<SongBundleException>()),
      );
    },
  );

  test('bundle rejects uncompressed and compressed totals above 100 MB', () {
    expect(
      () => validateSongBundleUncompressedSize(songBundleMaxArchiveBytes + 1),
      throwsA(
        isA<SongBundleException>().having(
          (error) => error.message,
          'declared content limit',
          contains('content'),
        ),
      ),
    );
    expect(
      () => validateSongBundleCompressedSize(songBundleMaxArchiveBytes + 1),
      throwsA(
        isA<SongBundleException>().having(
          (error) => error.message,
          'compressed archive limit',
          contains('Compressed'),
        ),
      ),
    );
  });
}

Uint8List _repack(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

SongProject _project({
  bool withAudio = true,
  String format = 'wav',
  String assetId = 'asset-1',
}) => SongProject(
  config: const SongProjectConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 2,
  ),
  tracks: [
    SongTrack(
      id: 'track-1',
      name: withAudio ? 'Audio' : 'Note',
      type: withAudio ? SongTrackType.audio : SongTrackType.note,
      order: 0,
    ),
  ],
  clips: [
    if (withAudio)
      const SongClipInstance(
        id: 'clip-1',
        trackId: 'track-1',
        patternId: 'pattern-1',
        patternType: SongPatternType.audio,
        startTick: 4,
      ),
  ],
  notePatterns: const [],
  drumPatterns: const [],
  audioAssets: [
    if (withAudio)
      AudioAsset(
        id: assetId,
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: format,
        peaks: [],
        sourceLabel: 'Take',
      ),
  ],
  audioPatterns: [
    if (withAudio)
      AudioClipPattern(
        id: 'pattern-1',
        name: 'Take',
        assetId: assetId,
        trimStartMs: 50,
      ),
  ],
);
