import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../models/songwriter.dart' show AudioFitMode;
import '../../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../../schema/rules/songwriter_audio_rules.dart';
import '../../schema/rules/songwriter_playback_rules.dart'
    show sectionAuditionBed;
import '../../schema/rules/songwriter_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/song_audio_repository.dart';
import '../../store/songwriter_audio_recorder_store.dart'
    show SongwriterRecordMonitor;
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
        final project = ref.read(songwriterProvider);
        final cfg = project.config;
        final measureTicks = cfg.measureTicks;
        // Bars available from this clip's start to the section end, and the
        // wall-clock duration of one bar at the project tempo — together they
        // drive the recorder's bar-progress indicator.
        final msPerBar =
            (pr_rules.tickDuration(cfg.tempo) * measureTicks).inMicroseconds /
            1000.0;
        final targetBars = audioBlockDefaultSpan(
          sectionLengthBars: sectionLengthBars,
          startBar: startBar,
        );
        // Record-time monitor template (backing + metronome both enabled; the
        // sheet's toggles flip them via copyWith). Null when the section can't
        // be resolved, which disables the backing/metronome toggles.
        final section = project.sections
            .where((s) => s.id == sectionId)
            .firstOrNull;
        SongwriterRecordMonitor? template;
        if (section != null) {
          final sectionClips = songwriterSectionSchedulableClips(
            project,
            sectionId,
          );
          template = SongwriterRecordMonitor(
            backing: true,
            metronome: true,
            tempo: cfg.tempo,
            beatTicks: cfg.ticksPerBeat,
            measureTicks: measureTicks,
            loopTicks: section.lengthBars * measureTicks,
            loopMs: sectionClips.loopMs,
            bed: sectionAuditionBed(
              section,
              cfg,
              ref.read(saveSystemProvider).saves,
              drumPatterns: project.drumPatterns,
            ),
            clips: sectionClips.clips,
          );
        }
        final asset = await showModalBottomSheet<AudioAsset?>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => SongwriterAudioRecorderSheet(
            monitorTemplate: template,
            countInBarMs: songwriterAudioTickToMs(measureTicks, cfg),
            countInBeats: cfg.beatsPerBar,
            targetBars: targetBars,
            msPerBar: msPerBar,
          ),
        );
        if (asset != null) {
          // A mic take plays once and spans only the bars it actually fills
          // (rounded up), not the whole section.
          final recSpan = recordedClipSpanBars(
            durationMs: asset.durationMs,
            msPerBar: msPerBar,
            maxBars: targetBars,
          );
          _commit(
            ref,
            sectionId,
            laneId,
            startBar,
            sectionLengthBars,
            asset,
            fitMode: AudioFitMode.oneShot,
            spanBars: recSpan,
          );
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
  AudioAsset asset, {
  AudioFitMode fitMode = AudioFitMode.loop,
  int? spanBars,
}) {
  final store = ref.read(songwriterProvider.notifier);
  store.addAudioAsset(asset);
  final clipId = store.addAudioClip(
    assetId: asset.id,
    durationMs: asset.durationMs,
    fitMode: fitMode,
  );
  final span =
      spanBars ??
      audioBlockDefaultSpan(
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
