/// WAV and portable Song Bundle export actions for the Song workspace.
library;

import 'dart:typed_data';
import 'dart:io';

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../schema/rules/song_audio_export_rules.dart';
import '../../schema/rules/song_bundle_rules.dart';
import '../../store/song_audio_repository.dart';
import '../../store/song_project_store.dart';
import '../../store/save_system_store.dart';
import '../../store/song_bundle_import.dart';
import '../../ui/core/muzician_dialog.dart';
import '../../ui/glass_snackbar.dart';
import '../../utils/wav_writer.dart';
import '../generated_file_delivery.dart';

const int _kExportSampleRate = 44100;

/// Renders and delivers the current Song as mono PCM16 WAV.
Future<void> exportSongToWav(
  BuildContext context,
  WidgetRef ref, {
  Rect? sharePositionOrigin,
}) async {
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

  try {
    final repository = ref.read(songAudioRepositoryProvider);
    final pcm = await renderSongPcmWithAudio(
      project,
      readAsset: repository.readAssetBytes,
      sampleRate: _kExportSampleRate,
      isWeb: kIsWeb,
    );
    final wav = writeWavPcm16Mono(pcm, sampleRate: _kExportSampleRate);
    final outcome = await deliverGeneratedFile(
      bytes: wav,
      fileName: 'song.wav',
      mimeType: 'audio/wav',
      dialogTitle: 'Export song as WAV',
      allowedExtensions: const ['wav'],
      sharePositionOrigin: sharePositionOrigin,
    );
    if (!context.mounted || outcome == GeneratedFileDeliveryOutcome.cancelled) {
      return;
    }
    final message = switch (outcome) {
      GeneratedFileDeliveryOutcome.shared => 'WAV shared.',
      GeneratedFileDeliveryOutcome.sharedOrDownloaded =>
        'WAV shared or downloaded.',
      GeneratedFileDeliveryOutcome.saved => 'Saved song.wav.',
      GeneratedFileDeliveryOutcome.cancelled => '',
    };
    showGlassSnackbar(
      context,
      title: 'WAV exported',
      message: message,
      contentType: ContentType.success,
    );
  } on SongAudioExportPreflightException catch (error) {
    if (!context.mounted) return;
    showGlassSnackbar(
      context,
      title: 'WAV export blocked',
      message: error.problems.join('\n'),
      contentType: ContentType.failure,
    );
  } catch (_) {
    if (!context.mounted) return;
    showGlassSnackbar(
      context,
      title: 'WAV export failed',
      message: 'Could not render or deliver this Song as a WAV file.',
      contentType: ContentType.failure,
    );
  }
}

/// Creates and delivers the current Song and its referenced audio sources as
/// a versioned `.mzbundle` archive on native platforms.
Future<void> exportSongBundle(
  BuildContext context,
  WidgetRef ref, {
  Rect? sharePositionOrigin,
}) async {
  if (kIsWeb) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Song Bundle unavailable on Web',
        content: const Text(
          'Song Bundles include local audio files that do not persist across '
          'Web reloads. Open this Song on Android, iOS, macOS, Windows, or '
          'Linux to export a portable bundle.',
        ),
        actions: [
          MuzicianDialogButton(
            'Got it',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    return;
  }

  try {
    final project = ref.read(songProjectProvider);
    final repository = ref.read(songAudioRepositoryProvider);
    final bytes = await buildSongBundleBytes(
      project,
      readAsset: repository.readAssetBytes,
    );
    final outcome = await deliverGeneratedFile(
      bytes: bytes,
      fileName: 'song.$songBundleExtension',
      mimeType: songBundleMimeType,
      dialogTitle: 'Export Song Bundle',
      allowedExtensions: const [songBundleExtension],
      sharePositionOrigin: sharePositionOrigin,
    );
    if (!context.mounted || outcome == GeneratedFileDeliveryOutcome.cancelled) {
      return;
    }
    final message = switch (outcome) {
      GeneratedFileDeliveryOutcome.shared => 'Song Bundle shared.',
      GeneratedFileDeliveryOutcome.sharedOrDownloaded =>
        'Song Bundle shared or downloaded.',
      GeneratedFileDeliveryOutcome.saved => 'Saved song.$songBundleExtension.',
      GeneratedFileDeliveryOutcome.cancelled => '',
    };
    showGlassSnackbar(
      context,
      title: 'Song Bundle exported',
      message: message,
      contentType: ContentType.success,
    );
  } on SongBundleException catch (error) {
    if (!context.mounted) return;
    showGlassSnackbar(
      context,
      title: 'Song Bundle export blocked',
      message: error.message,
      contentType: ContentType.failure,
    );
  } catch (_) {
    if (!context.mounted) return;
    showGlassSnackbar(
      context,
      title: 'Song Bundle export failed',
      message: 'Could not package or deliver this Song.',
      contentType: ContentType.failure,
    );
  }
}

/// Opens the native picker and transactionally replaces the active Song from
/// a validated `.mzbundle`. Web cannot persist imported audio assets.
typedef SongBundleBytePicker = Future<Uint8List?> Function();

Future<void> importSongBundle(
  BuildContext context,
  WidgetRef ref, {
  SongBundleBytePicker? pickBundleBytes,
}) async {
  if (kIsWeb) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Song Bundle unavailable on Web',
        content: const Text(
          'Song Bundles include local audio files that do not persist across '
          'Web reloads. Import this bundle on Android, iOS, macOS, Windows, '
          'or Linux.',
        ),
        actions: [
          MuzicianDialogButton(
            'Got it',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    return;
  }

  final projectBefore = ref.read(songProjectProvider);
  final projectIdBefore = ref.read(saveSystemProvider).selectedProjectId;
  if (_hasSongContent(projectBefore)) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Replace this Song?',
        content: const Text(
          'Importing a Song Bundle replaces the current arrangement. You can '
          'undo the replacement after a successful import.',
        ),
        actions: [
          MuzicianDialogButton(
            'Keep current Song',
            buttonKey: const Key('cancelSongBundleReplacement'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          MuzicianDialogButton(
            'Continue',
            emphasis: MuzicianDialogEmphasis.primary,
            buttonKey: const Key('confirmSongBundleReplacement'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    if (!identical(ref.read(songProjectProvider), projectBefore) ||
        ref.read(saveSystemProvider).selectedProjectId != projectIdBefore) {
      showGlassSnackbar(
        context,
        title: 'Song Bundle not imported',
        message: 'The active project changed while confirming replacement.',
        contentType: ContentType.warning,
      );
      return;
    }
  }

  try {
    final bytes = await (pickBundleBytes ?? _pickSongBundleBytes)();
    if (bytes == null) return;
    final repository = ref.read(songAudioRepositoryProvider);
    final imported = await importSongBundleBytes(bytes, repository: repository);
    if (!context.mounted) {
      await deleteImportedSongBundleAssets(imported, repository);
      return;
    }
    if (!identical(ref.read(songProjectProvider), projectBefore) ||
        ref.read(saveSystemProvider).selectedProjectId != projectIdBefore) {
      await deleteImportedSongBundleAssets(imported, repository);
      if (!context.mounted) return;
      showGlassSnackbar(
        context,
        title: 'Song Bundle not imported',
        message: 'The active project changed while the bundle was loading.',
        contentType: ContentType.warning,
      );
      return;
    }

    ref
        .read(songProjectProvider.notifier)
        .replaceProjectWithUndo(imported.project);
    showGlassSnackbar(
      context,
      title: 'Song Bundle imported',
      message: 'The previous Song can be restored with Undo.',
      contentType: ContentType.success,
    );
  } on SongBundleException catch (error) {
    if (!context.mounted) return;
    showGlassSnackbar(
      context,
      title: 'Song Bundle import blocked',
      message: error.message,
      contentType: ContentType.failure,
    );
  } catch (_) {
    if (!context.mounted) return;
    showGlassSnackbar(
      context,
      title: 'Song Bundle import failed',
      message: 'Could not read or install this Song Bundle.',
      contentType: ContentType.failure,
    );
  }
}

bool _hasSongContent(SongProject project) {
  final config = project.config;
  return project.tracks.isNotEmpty ||
      project.clips.isNotEmpty ||
      project.notePatterns.isNotEmpty ||
      project.drumPatterns.isNotEmpty ||
      project.audioAssets.isNotEmpty ||
      project.audioPatterns.isNotEmpty ||
      project.markers.isNotEmpty ||
      config.tempo != 120 ||
      config.timeSignature.beatsPerMeasure != 4 ||
      config.timeSignature.beatUnit != 4 ||
      config.totalMeasures != 4 ||
      config.scaleRoot != null ||
      config.scaleName != null;
}

Future<Uint8List?> _pickSongBundleBytes() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [songBundleExtension],
    allowMultiple: false,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final selected = picked.files.single;
  if (selected.size > songBundleMaxArchiveBytes) {
    throw const SongBundleException(
      'Compressed Song Bundle is larger than the 100 MB limit.',
    );
  }
  final path = selected.path;
  if (path == null) {
    throw const SongBundleException(
      'The selected Song Bundle could not be read from this device.',
    );
  }
  return File(path).readAsBytes();
}

/// Exposed for tests of the generated WAV byte contract.
Uint8List songWavBytes(Int16List samples) =>
    writeWavPcm16Mono(samples, sampleRate: _kExportSampleRate);
