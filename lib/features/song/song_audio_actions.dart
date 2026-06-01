import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../store/song_audio_repository.dart';
import '../../store/song_project_store.dart';
import 'song_audio_recorder_sheet.dart';

const int _kAudioImportMaxBytes = 50 * 1024 * 1024;

/// Opens the file picker, imports the chosen file via the repository, and
/// commits an audio clip to the project at [startTick].
Future<void> importAudioFile(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required int startTick,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['wav', 'mp3', 'm4a'],
  );
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.first;
  final path = file.path;
  if (path == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not access file on this platform')),
    );
    return;
  }
  if (file.size > _kAudioImportMaxBytes) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audio file is larger than 50 MB')),
    );
    return;
  }

  try {
    final repo = ref.read(songAudioRepositoryProvider);
    final asset = await repo.importExternalFile(
      sourcePath: path,
      sourceLabel: file.name,
      explicitDurationMs: null,
    );
    ref
        .read(songProjectProvider.notifier)
        .addAudioClip(
          trackId: trackId,
          startTick: startTick,
          asset: asset,
          clipName: file.name.replaceAll(RegExp(r'\.(wav|mp3|m4a)$'), ''),
        );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}

/// Opens the audio recorder sheet and, on confirm, commits the take as a clip
/// on the project at [startTick].
Future<void> openAudioRecorder(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required int startTick,
}) async {
  final asset = await showModalBottomSheet<AudioAsset?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        SongAudioRecorderSheet(trackId: trackId, startTick: startTick),
  );
  if (asset == null) return;
  ref
      .read(songProjectProvider.notifier)
      .addAudioClip(trackId: trackId, startTick: startTick, asset: asset);
}
