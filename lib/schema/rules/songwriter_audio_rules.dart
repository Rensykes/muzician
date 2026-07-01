/// Pure scheduling helpers for Songwriter audio-lane playback.
library;

import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import 'songwriter_rules.dart';

/// Ticks → milliseconds at the project tempo. Parallels `audioTickToMs` in
/// `song_audio_rules.dart` (same formula, different config type).
int songwriterAudioTickToMs(int tick, SongwriterConfig config) {
  final msPerBeat = 60000.0 / config.tempo;
  return (tick * msPerBeat / config.ticksPerBeat).round();
}

/// A placed audio clip resolved to absolute transport milliseconds.
class SongwriterScheduledClip {
  final AudioAsset asset;
  final int startMs;
  final int endMs;
  final int trimStartMs;
  final bool loop;
  final double volume;
  const SongwriterScheduledClip({
    required this.asset,
    required this.startMs,
    required this.endMs,
    required this.trimStartMs,
    required this.loop,
    this.volume = 1.0,
  });

  /// In-asset position to seek to when the playhead is at [nowMs]. Clamped to
  /// the asset bounds so a future mid-song seek can never pass a negative
  /// duration to the player.
  int offsetIntoAsset(int nowMs) =>
      (trimStartMs + (nowMs - startMs)).clamp(0, asset.durationMs);
}

/// Flattens placed audio clips across section repeats into absolute-ms records.
///
/// Stretch mode resolves to the pre-rendered [AudioClip.stretchedAssetId] when
/// present (Plan 4); until then it plays the source one-shot.
List<SongwriterScheduledClip> songwriterSchedulableAudioClips(
  SongwriterProjectSnapshot project,
) {
  final cfg = project.config;
  final measureTicks = cfg.measureTicks;
  final assetsById = {for (final a in project.audioAssets) a.id: a};
  final clipsById = {for (final c in project.audioClips) c.id: c};
  final out = <SongwriterScheduledClip>[];

  for (final exp in expandSections(project.sections)) {
    final section = project.sections
        .where((s) => s.id == exp.sectionId)
        .firstOrNull;
    if (section == null) continue;
    for (final lane in section.lanes) {
      if (lane.kind != SongLaneKind.audio) continue;
      for (final block in tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      )) {
        final clip = clipsById[block.audioClipId];
        if (clip == null) continue;
        final usesStretched =
            clip.fitMode == AudioFitMode.stretch &&
            clip.stretchedAssetId != null;
        final playAsset = usesStretched
            ? assetsById[clip.stretchedAssetId]
            : assetsById[clip.assetId];
        if (playAsset == null) continue;

        final clippedEnd = block.endBar > section.lengthBars
            ? section.lengthBars
            : block.endBar;
        final startTick = (exp.globalStartBar + block.startBar) * measureTicks;
        final spanEndTick = (exp.globalStartBar + clippedEnd) * measureTicks;
        final startMs = songwriterAudioTickToMs(startTick, cfg);
        final spanMs = songwriterAudioTickToMs(spanEndTick, cfg) - startMs;
        // trimEndMs == 0 is the documented "no end-trim" sentinel (play to the
        // natural asset end); see AudioClip. Honour it so legacy saves whose
        // JSON predates the field do not silence one-shot clips.
        final trimEnd = clip.trimEndMs == 0
            ? playAsset.durationMs
            : clip.trimEndMs;
        final regionMs = (trimEnd - clip.trimStartMs).clamp(
          0,
          playAsset.durationMs,
        );

        final loop = clip.fitMode == AudioFitMode.loop;
        final endMs = loop || usesStretched
            ? startMs + spanMs
            : startMs + (regionMs < spanMs ? regionMs : spanMs);

        out.add(
          SongwriterScheduledClip(
            asset: playAsset,
            startMs: startMs,
            endMs: endMs,
            trimStartMs: usesStretched ? 0 : clip.trimStartMs,
            loop: loop,
          ),
        );
      }
    }
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out;
}

/// Section-local sibling of [songwriterSchedulableAudioClips] for the
/// record-time monitor. Returns the section's audio-lane clips with
/// `startMs`/`endMs` relative to the section's own bar 0 (no flattened
/// `globalStartBar` offset, no per-repeat duplication), plus [loopMs] — the
/// section length in ms, used to wrap the monitor loop. Stretch/trim/loop
/// resolution matches the flattened rule. Includes every audio clip in the
/// section (the in-progress recording's clip does not exist yet).
({int loopMs, List<SongwriterScheduledClip> clips})
songwriterSectionSchedulableClips(
  SongwriterProjectSnapshot project,
  String sectionId,
) {
  final cfg = project.config;
  final measureTicks = cfg.measureTicks;
  final section = project.sections.where((s) => s.id == sectionId).firstOrNull;
  if (section == null) return (loopMs: 0, clips: const []);

  final assetsById = {for (final a in project.audioAssets) a.id: a};
  final clipsById = {for (final c in project.audioClips) c.id: c};
  final out = <SongwriterScheduledClip>[];

  for (final lane in section.lanes) {
    if (lane.kind != SongLaneKind.audio) continue;
    for (final block in tileLaneBlocks(
      lane,
      sectionLengthBars: section.lengthBars,
    )) {
      final clip = clipsById[block.audioClipId];
      if (clip == null) continue;
      final usesStretched =
          clip.fitMode == AudioFitMode.stretch && clip.stretchedAssetId != null;
      final playAsset = usesStretched
          ? assetsById[clip.stretchedAssetId]
          : assetsById[clip.assetId];
      if (playAsset == null) continue;

      final clippedEnd = block.endBar > section.lengthBars
          ? section.lengthBars
          : block.endBar;
      final startTick = block.startBar * measureTicks; // section-local
      final spanEndTick = clippedEnd * measureTicks;
      final startMs = songwriterAudioTickToMs(startTick, cfg);
      final spanMs = songwriterAudioTickToMs(spanEndTick, cfg) - startMs;
      // trimEndMs == 0 is the documented "no end-trim" sentinel (play to the
      // natural asset end); see AudioClip. Honour it so legacy saves whose
      // JSON predates the field do not silence one-shot clips.
      final trimEnd = clip.trimEndMs == 0
          ? playAsset.durationMs
          : clip.trimEndMs;
      final regionMs = (trimEnd - clip.trimStartMs).clamp(
        0,
        playAsset.durationMs,
      );
      final loop = clip.fitMode == AudioFitMode.loop;
      final endMs = loop || usesStretched
          ? startMs + spanMs
          : startMs + (regionMs < spanMs ? regionMs : spanMs);

      out.add(
        SongwriterScheduledClip(
          asset: playAsset,
          startMs: startMs,
          endMs: endMs,
          trimStartMs: usesStretched ? 0 : clip.trimStartMs,
          loop: loop,
        ),
      );
    }
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return (
    loopMs: songwriterAudioTickToMs(section.lengthBars * measureTicks, cfg),
    clips: out,
  );
}
