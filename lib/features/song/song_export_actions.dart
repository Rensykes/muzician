/// WAV export for the Song workspace.
///
/// Renders the current song's note + drum tracks to PCM16 (audio clips are
/// excluded in v1) and writes a `.wav` via the platform save dialog.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../schema/rules/song_render_rules.dart';
import '../../store/song_project_store.dart';
import '../../ui/core/muzician_dialog.dart';
import '../../ui/glass_snackbar.dart';
import '../../utils/wav_writer.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

const int _kExportSampleRate = 44100;

/// Renders + exports the current song. Shows a confirmation that audio clips
/// are excluded when the project has any, then writes the WAV via the save
/// dialog.
Future<void> exportSongToWav(BuildContext context, WidgetRef ref) async {
  final project = ref.read(songProjectProvider);
  if (project.tracks.isEmpty) {
    showGlassSnackbar(
      context,
      title: 'Nothing to export',
      message: 'Add some tracks first.',
      contentType: ContentType.warning,
    );
    return;
  }

  final hasAudio = project.clips.any((c) => c.patternType.name == 'audio');
  if (hasAudio) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => MuzicianDialog(
        title: 'Export WAV',
        content: const Text(
          'Audio clips are not included in the export yet — only note and '
          'drum tracks are rendered.',
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          MuzicianDialogButton(
            'Export',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (proceed != true) return;
  }

  final pcm = renderSongPcm(project, sampleRate: _kExportSampleRate);
  final wav = writeWavPcm16Mono(pcm, sampleRate: _kExportSampleRate);

  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export song as WAV',
    fileName: 'song.wav',
    type: FileType.custom,
    allowedExtensions: const ['wav'],
    bytes: wav,
  );

  if (!context.mounted) return;
  if (path == null) return; // user cancelled
  showGlassSnackbar(
    context,
    title: 'Exported',
    message: 'Saved song.wav',
    contentType: ContentType.success,
  );
}
