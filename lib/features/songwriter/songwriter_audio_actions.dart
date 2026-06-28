import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../../schema/rules/songwriter_rules.dart';
import '../../store/song_audio_repository.dart';
import '../../store/songwriter_store.dart';
import '../song/song_audio_picker_sheet.dart';
import 'songwriter_audio_recorder_sheet.dart';

/// Opens the record/import picker for an audio lane and commits the result as
/// an AudioAsset + AudioClip + audio block at [startBar].
Future<void> showSongwriterAudioPicker(
  WidgetRef ref, {
  required BuildContext context,
  required String sectionId,
  required String laneId,
  required int startBar,
  required int sectionLengthBars,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => SongAudioPickerSheet(
      trackId: '',
      startTick: 0,
      onRecord: () async {
        Navigator.of(sheetCtx).pop();
        // Bars available from this clip's start to the section end, and the
        // wall-clock duration of one bar at the project tempo — together they
        // drive the recorder's bar-progress indicator.
        final cfg = ref.read(songwriterProvider).config;
        final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
        final msPerBar =
            (pr_rules.tickDuration(cfg.tempo) * measureTicks).inMicroseconds /
            1000.0;
        final targetBars = audioBlockDefaultSpan(
          sectionLengthBars: sectionLengthBars,
          startBar: startBar,
        );
        final asset = await showModalBottomSheet<AudioAsset?>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => SongwriterAudioRecorderSheet(
            countInMs: 0,
            targetBars: targetBars,
            msPerBar: msPerBar,
          ),
        );
        if (asset != null) {
          _commit(ref, sectionId, laneId, startBar, sectionLengthBars, asset);
        }
      },
      onImport: () async {
        Navigator.of(sheetCtx).pop();
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['wav', 'mp3', 'm4a'],
          withData: kIsWeb,
        );
        final file = picked?.files.isNotEmpty == true
            ? picked!.files.first
            : null;
        final path = file?.path;
        if (file == null || path == null) return;
        final repo = ref.read(songwriterAudioRepositoryProvider);
        int? durationMs;
        final ext = file.name.split('.').last.toLowerCase();
        if (ext != 'wav') {
          final probe = AudioPlayer();
          try {
            await probe.setSource(DeviceFileSource(path));
            durationMs = (await probe.getDuration())?.inMilliseconds;
          } catch (_) {
            // leave null; repository falls back to 0
          } finally {
            await probe.dispose();
          }
        }
        final asset = await repo.importExternalFile(
          sourcePath: path,
          sourceLabel: file.name,
          explicitDurationMs: durationMs,
        );
        _commit(ref, sectionId, laneId, startBar, sectionLengthBars, asset);
      },
    ),
  );
}

void _commit(
  WidgetRef ref,
  String sectionId,
  String laneId,
  int startBar,
  int sectionLengthBars,
  AudioAsset asset,
) {
  final store = ref.read(songwriterProvider.notifier);
  store.addAudioAsset(asset);
  final clipId = store.addAudioClip(
    assetId: asset.id,
    durationMs: asset.durationMs,
  );
  final span = audioBlockDefaultSpan(
    sectionLengthBars: sectionLengthBars,
    startBar: startBar,
  );
  store.addAudioBlock(
    sectionId: sectionId,
    laneId: laneId,
    audioClipId: clipId,
    startBar: startBar,
    spanBars: span,
  );
}
