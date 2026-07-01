/// Pure helpers for stretch re-rendering decisions.
library;

import '../../models/songwriter.dart';

/// Bar span of the audio block that references [clipId], or null if none.
int? audioClipSpanBars(SongwriterProjectSnapshot project, String clipId) {
  for (final section in project.sections) {
    for (final lane in section.lanes) {
      if (lane.kind != SongLaneKind.audio) continue;
      for (final block in lane.blocks) {
        if (block.audioClipId == clipId) return block.spanBars;
      }
    }
  }
  return null;
}

/// Target stretched length in ms = span bars x bar duration, or null if the
/// clip is unplaced.
int? stretchTargetMs(SongwriterProjectSnapshot project, String clipId) {
  final span = audioClipSpanBars(project, clipId);
  if (span == null) return null;
  final cfg = project.config;
  final barMs = cfg.beatsPerBar * 60000.0 / cfg.tempo;
  return (span * barMs).round();
}
