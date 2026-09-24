/// Native Song Bundle extraction and repository transaction.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/song_project.dart';
import '../schema/rules/song_bundle_rules.dart';
import 'song_audio_repository.dart';

typedef SongBundleAssetWriter =
    Future<AudioAsset> Function(Uint8List bytes, AudioAsset sourceAsset);
typedef SongBundleAssetDeleter = Future<void> Function(String assetId);

class ImportedSongBundle {
  const ImportedSongBundle({
    required this.project,
    required this.copiedAssetIds,
  });

  final SongProject project;
  final List<String> copiedAssetIds;
}

/// Validates, stages, and copies a bundle before returning its remapped Song.
/// A caller should replace project state only after this Future succeeds.
/// [assetWriter] and [assetDeleter] are injectable for rollback verification.
Future<ImportedSongBundle> importSongBundleBytes(
  Uint8List bytes, {
  required SongAudioRepository repository,
  SongBundleAssetWriter? assetWriter,
  SongBundleAssetDeleter? assetDeleter,
  Directory? stagingParent,
}) async {
  final decoded = decodeSongBundleImport(bytes);
  final writeAsset =
      assetWriter ??
      ((assetBytes, source) => repository.writeImportedBundleAsset(
        bytes: assetBytes,
        sourceAsset: source,
      ));
  final deleteAsset = assetDeleter ?? repository.delete;
  final copiedIds = <String>[];
  Directory? stagingDirectory;

  try {
    stagingDirectory = await (stagingParent ?? Directory.systemTemp).createTemp(
      'muzician-song-bundle-',
    );
    final stagedAudioDirectory = Directory(
      p.join(stagingDirectory.path, 'audio'),
    );
    await stagedAudioDirectory.create();

    final stagedEntries = <({AudioAsset source, Uint8List bytes})>[];
    for (final entry in decoded.entries) {
      final file = File(
        p.join(
          stagingDirectory.path,
          'audio',
          '${entry.sourceAsset.id}.${entry.sourceAsset.format.toLowerCase()}',
        ),
      );
      await file.writeAsBytes(entry.bytes, flush: true);
      stagedEntries.add((
        source: entry.sourceAsset,
        bytes: await file.readAsBytes(),
      ));
    }

    final remappedAssets = <String, AudioAsset>{};
    for (final entry in stagedEntries) {
      final copied = await writeAsset(entry.bytes, entry.source);
      copiedIds.add(copied.id);
      remappedAssets[entry.source.id] = copied;
    }

    final project = decoded.project.copyWith(
      audioAssets: [
        for (final asset in decoded.project.audioAssets)
          remappedAssets[asset.id]!,
      ],
      audioPatterns: [
        for (final pattern in decoded.project.audioPatterns)
          pattern.copyWith(assetId: remappedAssets[pattern.assetId]!.id),
      ],
    );
    return ImportedSongBundle(project: project, copiedAssetIds: copiedIds);
  } catch (_) {
    for (final id in copiedIds) {
      try {
        await deleteAsset(id);
      } catch (_) {
        // Keep trying to roll back the rest of the attempt's copied files.
      }
    }
    rethrow;
  } finally {
    if (stagingDirectory != null && stagingDirectory.existsSync()) {
      try {
        await stagingDirectory.delete(recursive: true);
      } catch (_) {
        // Staging data is temporary and never referenced by the project.
      }
    }
  }
}

Future<void> deleteImportedSongBundleAssets(
  ImportedSongBundle imported,
  SongAudioRepository repository,
) async {
  for (final id in imported.copiedAssetIds) {
    await repository.delete(id);
  }
}
