/// Portable Song bundle creation rules.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/song_project.dart';

const int songBundleMaxArchiveBytes = 100 * 1024 * 1024;
const int songBundleMaxAudioEntryBytes = 50 * 1024 * 1024;
const String songBundleMimeType = 'application/zip';
const String songBundleExtension = 'mzbundle';

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);

void validateSongBundleUncompressedSize(int byteLength) {
  if (byteLength > songBundleMaxArchiveBytes) {
    throw const SongBundleException(
      'Song Bundle content is larger than the 100 MB limit.',
    );
  }
}

void validateSongBundleCompressedSize(int byteLength) {
  if (byteLength > songBundleMaxArchiveBytes) {
    throw const SongBundleException(
      'Compressed Song Bundle is larger than the 100 MB limit.',
    );
  }
}

typedef SongBundleAssetReader =
    Future<Uint8List?> Function(String assetId, String format);

class SongBundleException implements Exception {
  final String message;
  const SongBundleException(this.message);

  @override
  String toString() => message;
}

class SongBundleImportEntry {
  const SongBundleImportEntry({required this.sourceAsset, required this.bytes});

  final AudioAsset sourceAsset;
  final Uint8List bytes;
}

class SongBundleImportData {
  const SongBundleImportData({required this.project, required this.entries});

  final SongProject project;
  final List<SongBundleImportEntry> entries;
}

/// Decodes and validates a complete Song Bundle before any repository writes.
/// ZIP entry sizes are checked before content is inflated, then extracted byte
/// lengths and manifest references are checked before returning the payload.
SongBundleImportData decodeSongBundleImport(Uint8List bytes) {
  validateSongBundleCompressedSize(bytes.length);

  try {
    final decodedNames = <String>[];
    var containsSymlink = false;
    final archive = ZipDecoder().decodeBytes(
      bytes,
      callback: (entry) {
        decodedNames.add(entry.name);
        if (entry.isSymbolicLink) containsSymlink = true;
      },
    );
    if (containsSymlink || decodedNames.length != archive.files.length) {
      throw const SongBundleException(
        'Song Bundle contains duplicate or linked archive entries.',
      );
    }
    for (final name in decodedNames) {
      if (name.startsWith('/') ||
          name.contains('\\') ||
          name.contains('\u0000') ||
          name.split('/').any((part) => part == '.' || part == '..')) {
        throw const SongBundleException(
          'Song Bundle contains an unsafe archive path.',
        );
      }
    }

    final files = <String, ArchiveFile>{};
    var declaredArchiveTotal = 0;
    for (final file in archive.files) {
      if (!file.isFile || file.isSymbolicLink) {
        throw const SongBundleException(
          'Song Bundle contains an unsupported archive entry.',
        );
      }
      files[file.name] = file;
      declaredArchiveTotal += file.size;
      if (file.name.startsWith('audio/') &&
          file.size > songBundleMaxAudioEntryBytes) {
        throw const SongBundleException(
          'A Song Bundle audio entry is larger than the 50 MB limit.',
        );
      }
    }
    validateSongBundleUncompressedSize(declaredArchiveTotal);
    final manifestFile = files['manifest.json'];
    final songFile = files['song.json'];
    if (manifestFile == null || songFile == null) {
      throw const SongBundleException(
        'Song Bundle must contain manifest.json and song.json.',
      );
    }

    final manifestBytes = manifestFile.content;
    if (manifestBytes.length != manifestFile.size) {
      throw const SongBundleException(
        'Song Bundle manifest length does not match its ZIP entry.',
      );
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    if (manifest is! Map<String, dynamic> ||
        manifest['format'] != 'muzician-song-bundle' ||
        manifest['schemaVersion'] != 1 ||
        manifest['entries'] is! List) {
      throw const SongBundleException(
        'Song Bundle format or schema version is unsupported.',
      );
    }

    final manifestEntries =
        <String, ({String format, String path, int size})>{};
    for (final rawEntry in manifest['entries'] as List) {
      if (rawEntry is! Map<String, dynamic>) {
        throw const SongBundleException(
          'Song Bundle manifest contains an invalid audio entry.',
        );
      }
      final id = rawEntry['sourceAssetId'];
      final format = rawEntry['format'];
      final path = rawEntry['path'];
      final byteLength = rawEntry['byteLength'];
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
          format is! String ||
          !const {'wav', 'mp3', 'm4a'}.contains(format) ||
          path is! String ||
          byteLength is! int ||
          byteLength < 0 ||
          byteLength > songBundleMaxAudioEntryBytes ||
          path != 'audio/$id.$format') {
        throw const SongBundleException(
          'Song Bundle manifest contains an invalid or unsafe audio path.',
        );
      }
      if (manifestEntries.containsKey(id)) {
        throw const SongBundleException(
          'Song Bundle manifest contains duplicate audio asset IDs.',
        );
      }
      manifestEntries[id] = (format: format, path: path, size: byteLength);
    }

    final expectedNames = <String>{
      'manifest.json',
      'song.json',
      for (final entry in manifestEntries.values) entry.path,
    };
    if (files.keys.toSet().length != files.length ||
        !_sameSet(files.keys.toSet(), expectedNames)) {
      throw const SongBundleException(
        'Song Bundle archive entries do not match its manifest.',
      );
    }

    final songBytes = songFile.content;
    if (songBytes.length != songFile.size) {
      throw const SongBundleException(
        'Song Bundle Song data length does not match its ZIP entry.',
      );
    }
    final rawSong = jsonDecode(utf8.decode(songBytes));
    if (rawSong is! Map<String, dynamic>) {
      throw const SongBundleException('Song Bundle Song data is invalid.');
    }
    final project = SongProject.fromJson(rawSong);
    final assetsById = <String, AudioAsset>{};
    for (final asset in project.audioAssets) {
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(asset.id) ||
          !const {'wav', 'mp3', 'm4a'}.contains(asset.format.toLowerCase()) ||
          assetsById.containsKey(asset.id)) {
        throw const SongBundleException(
          'Song Bundle Song data contains an invalid audio asset.',
        );
      }
      assetsById[asset.id] = asset;
    }

    final patternsById = {
      for (final pattern in project.audioPatterns) pattern.id: pattern,
    };
    final referencedPatternIds = <String>{};
    final referencedAssetIds = <String>{};
    for (final clip in project.clips) {
      if (clip.patternType != SongPatternType.audio) continue;
      final pattern = patternsById[clip.patternId];
      if (pattern == null || !assetsById.containsKey(pattern.assetId)) {
        throw const SongBundleException(
          'Song Bundle contains an audio clip with a missing pattern or asset.',
        );
      }
      referencedPatternIds.add(pattern.id);
      referencedAssetIds.add(pattern.assetId);
    }
    if (!_sameSet(referencedPatternIds, patternsById.keys.toSet()) ||
        !_sameSet(referencedAssetIds, assetsById.keys.toSet()) ||
        !_sameSet(referencedAssetIds, manifestEntries.keys.toSet())) {
      throw const SongBundleException(
        'Song Bundle is missing a referenced audio asset or includes an unused one.',
      );
    }

    final resultEntries = <SongBundleImportEntry>[];
    var extractedTotal = manifestBytes.length + songBytes.length;
    for (final id in referencedAssetIds) {
      final asset = assetsById[id]!;
      final manifestEntry = manifestEntries[id]!;
      if (asset.format.toLowerCase() != manifestEntry.format) {
        throw const SongBundleException(
          'Song Bundle audio format does not match its Song asset.',
        );
      }
      final file = files[manifestEntry.path]!;
      if (file.size != manifestEntry.size) {
        throw const SongBundleException(
          'Song Bundle audio length does not match its manifest.',
        );
      }
      final content = file.content;
      if (content.length != file.size || content.length != manifestEntry.size) {
        throw const SongBundleException(
          'Song Bundle audio data is incomplete or corrupt.',
        );
      }
      extractedTotal += content.length;
      resultEntries.add(
        SongBundleImportEntry(
          sourceAsset: asset,
          bytes: Uint8List.fromList(content),
        ),
      );
    }
    validateSongBundleUncompressedSize(extractedTotal);
    return SongBundleImportData(project: project, entries: resultEntries);
  } on SongBundleException {
    rethrow;
  } catch (_) {
    throw const SongBundleException(
      'Song Bundle is corrupt or uses an unsupported schema.',
    );
  }
}

/// Creates a versioned ZIP bundle containing the Song state and every source
/// audio file reachable from an audio clip.
Future<Uint8List> buildSongBundleBytes(
  SongProject project, {
  required SongBundleAssetReader readAsset,
}) async {
  final patternsById = {
    for (final pattern in project.audioPatterns) pattern.id: pattern,
  };
  final assetsById = {for (final asset in project.audioAssets) asset.id: asset};
  final referencedPatternIds = <String>{};
  final referencedAssetIds = <String>{};

  for (final clip in project.clips) {
    if (clip.patternType != SongPatternType.audio) continue;
    final pattern = patternsById[clip.patternId];
    if (pattern == null) {
      throw SongBundleException(
        'Audio clip ${clip.id} has no source pattern and cannot be bundled.',
      );
    }
    if (!assetsById.containsKey(pattern.assetId)) {
      throw SongBundleException(
        'Audio clip “${pattern.name}” is missing its source asset.',
      );
    }
    referencedPatternIds.add(pattern.id);
    referencedAssetIds.add(pattern.assetId);
  }

  final audioFiles = <({AudioAsset asset, Uint8List bytes, String path})>[];
  for (final assetId in referencedAssetIds) {
    final asset = assetsById[assetId]!;
    final format = asset.format.toLowerCase();
    if (!const {'wav', 'mp3', 'm4a'}.contains(format)) {
      throw SongBundleException(
        '“${asset.sourceLabel}” uses an unsupported audio format.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(asset.id)) {
      throw SongBundleException('An audio asset has an invalid source ID.');
    }
    final bytes = await readAsset(asset.id, asset.format);
    if (bytes == null) {
      throw SongBundleException(
        '“${asset.sourceLabel}” is missing from this device. Re-import it '
        'before exporting a Song Bundle.',
      );
    }
    if (bytes.length > songBundleMaxAudioEntryBytes) {
      throw SongBundleException(
        '“${asset.sourceLabel}” is larger than the 50 MB Song Bundle limit.',
      );
    }
    audioFiles.add((
      asset: asset,
      bytes: bytes,
      path: 'audio/${asset.id}.$format',
    ));
  }

  final portableProject = project.copyWith(
    audioAssets: project.audioAssets
        .where((asset) => referencedAssetIds.contains(asset.id))
        .toList(),
    audioPatterns: project.audioPatterns
        .where((pattern) => referencedPatternIds.contains(pattern.id))
        .toList(),
  );
  final songJson = Uint8List.fromList(
    utf8.encode(jsonEncode(portableProject.toJson())),
  );
  final manifest = <String, Object>{
    'format': 'muzician-song-bundle',
    'schemaVersion': 1,
    'entries': [
      for (final file in audioFiles)
        {
          'sourceAssetId': file.asset.id,
          'format': file.asset.format.toLowerCase(),
          'path': file.path,
          'byteLength': file.bytes.length,
        },
    ],
  };
  final manifestJson = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
  final uncompressedTotal =
      manifestJson.length +
      songJson.length +
      audioFiles.fold<int>(0, (total, file) => total + file.bytes.length);
  validateSongBundleUncompressedSize(uncompressedTotal);

  final archive = Archive()
    ..addFile(ArchiveFile.bytes('manifest.json', manifestJson))
    ..addFile(ArchiveFile.bytes('song.json', songJson));
  for (final file in audioFiles) {
    archive.addFile(ArchiveFile.bytes(file.path, file.bytes));
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  validateSongBundleCompressedSize(bytes.length);
  return bytes;
}
