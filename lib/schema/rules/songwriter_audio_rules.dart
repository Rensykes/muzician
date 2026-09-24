/// Pure scheduling helpers for Songwriter audio-lane playback.
library;

import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import 'piano_roll_playback_rules.dart' as playback;
import 'songwriter_rules.dart';

/// Ticks → milliseconds at the project tempo. Parallels `audioTickToMs` in
/// `song_audio_rules.dart` (same formula, different config type).
int songwriterAudioTickToMs(int tick, SongwriterConfig config) {
  return (tick * playback.millisecondsPerTick(config.tempo)).round();
}

/// A placed audio clip resolved to absolute transport milliseconds.
class SongwriterScheduledClip {
  final AudioAsset asset;
  final int startMs;
  final int endMs;
  final int trimStartMs;
  final bool loop;
  final double volume;
  final double pan; // -1.0 (left) .. 1.0 (right)
  const SongwriterScheduledClip({
    required this.asset,
    required this.startMs,
    required this.endMs,
    required this.trimStartMs,
    required this.loop,
    this.volume = 1.0,
    this.pan = 0.0,
  });

  /// In-asset position to seek to when the playhead is at [nowMs]. Clamped to
  /// the asset bounds so a future mid-song seek can never pass a negative
  /// duration to the player.
  int offsetIntoAsset(int nowMs) =>
      (trimStartMs + (nowMs - startMs)).clamp(0, asset.durationMs);
}

/// Resolves one placed audio [block] on [lane] to an absolute-ms record, with
/// the block's bars offset by [globalStartBar] (0 for section-local callers).
/// Returns null for unresolvable blocks (missing clip or asset).
///
/// Stretch mode resolves to the pre-rendered [AudioClip.stretchedAssetId] when
/// present (Plan 4); until then it plays the source one-shot. trimEndMs == 0
/// is the documented "no end-trim" sentinel (play to the natural asset end);
/// see [AudioClip]. Honour it so legacy saves whose JSON predates the field
/// do not silence one-shot clips.
SongwriterScheduledClip? _scheduledClipForBlock({
  required SongBlock block,
  required SongLane lane,
  required SongSection section,
  required SongwriterConfig cfg,
  required int globalStartBar,
  required Map<String, AudioAsset> assetsById,
  required Map<String, AudioClip> clipsById,
}) {
  final clip = clipsById[block.audioClipId];
  if (clip == null) return null;
  final usesStretched =
      clip.fitMode == AudioFitMode.stretch && clip.stretchedAssetId != null;
  final playAsset = usesStretched
      ? assetsById[clip.stretchedAssetId]
      : assetsById[clip.assetId];
  if (playAsset == null) return null;

  final measureTicks = cfg.measureTicks;
  final clippedEnd = block.endBar > section.lengthBars
      ? section.lengthBars
      : block.endBar;
  final startTick = (globalStartBar + block.startBar) * measureTicks;
  final spanEndTick = (globalStartBar + clippedEnd) * measureTicks;
  final startMs = songwriterAudioTickToMs(startTick, cfg);
  final spanMs = songwriterAudioTickToMs(spanEndTick, cfg) - startMs;
  final trimEnd = clip.trimEndMs == 0 ? playAsset.durationMs : clip.trimEndMs;
  final regionMs = (trimEnd - clip.trimStartMs).clamp(0, playAsset.durationMs);

  final loop = clip.fitMode == AudioFitMode.loop;
  final endMs = loop || usesStretched
      ? startMs + spanMs
      : startMs + (regionMs < spanMs ? regionMs : spanMs);

  return SongwriterScheduledClip(
    asset: playAsset,
    startMs: startMs,
    endMs: endMs,
    trimStartMs: usesStretched ? 0 : clip.trimStartMs,
    loop: loop,
    volume: lane.volume,
    pan: lane.pan,
  );
}

/// Flattens placed audio clips across section repeats into absolute-ms records.
List<SongwriterScheduledClip> songwriterSchedulableAudioClips(
  SongwriterProjectSnapshot project,
) {
  final cfg = project.config;
  final assetsById = {for (final a in project.audioAssets) a.id: a};
  final clipsById = {for (final c in project.audioClips) c.id: c};
  final out = <SongwriterScheduledClip>[];

  for (final exp in expandSections(project.sections)) {
    final section = project.sections
        .where((s) => s.id == exp.sectionId)
        .firstOrNull;
    if (section == null) continue;
    for (final lane in section.lanes) {
      if (lane.kind != SongLaneKind.audio || lane.muted) continue;
      for (final block in tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      )) {
        final scheduled = _scheduledClipForBlock(
          block: block,
          lane: lane,
          section: section,
          cfg: cfg,
          globalStartBar: exp.globalStartBar,
          assetsById: assetsById,
          clipsById: clipsById,
        );
        if (scheduled != null) out.add(scheduled);
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
    if (lane.kind != SongLaneKind.audio || lane.muted) continue;
    for (final block in tileLaneBlocks(
      lane,
      sectionLengthBars: section.lengthBars,
    )) {
      final scheduled = _scheduledClipForBlock(
        block: block,
        lane: lane,
        section: section,
        cfg: cfg,
        globalStartBar: 0, // section-local
        assetsById: assetsById,
        clipsById: clipsById,
      );
      if (scheduled != null) out.add(scheduled);
    }
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return (
    loopMs: songwriterAudioTickToMs(section.lengthBars * measureTicks, cfg),
    clips: out,
  );
}
