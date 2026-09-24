/// Song Playback Pure Expansion Rules
///
/// Expands a [SongProject] into a sorted list of [SongPlaybackEvent]s.
/// All functions are deterministic and testable without any Riverpod wiring.
library;

import '../../models/song_playback.dart';
import '../../models/song_project.dart';

/// Returns tracks that should be audible based on mute/solo state.
///
/// If any track is soloed, only soloed tracks are audible.
/// Otherwise, non-muted tracks are audible.
List<SongTrack> audibleTracks(SongProject project) {
  final soloed = project.tracks.where((track) => track.isSolo).toList();
  if (soloed.isNotEmpty) return soloed;
  return project.tracks.where((track) => !track.isMuted).toList();
}

/// Expands all clip instances into absolute-tick playback events.
///
/// Applies mute/solo filtering via [audibleTracks] before expansion.
/// Events are returned in ascending tick order with de-duplicated,
/// sorted MIDI notes and drum lanes per tick.
List<SongPlaybackEvent> buildPlaybackEvents(SongProject project) {
  final volumeByTrack = {
    for (final t in audibleTracks(project)) t.id: t.volume,
  };
  // tick → volume → notes / lanes
  final drumsAt = <int, Map<double, Set<DrumLaneId>>>{};
  final sequencedAt =
      <int, Map<(double, int, int, int), List<NotePatternNote>>>{};

  for (final clip in project.clips.where(
    (clip) => volumeByTrack.containsKey(clip.trackId),
  )) {
    final volume = volumeByTrack[clip.trackId]!;
    switch (clip.patternType) {
      case SongPatternType.note:
        final pattern = project.notePatterns.firstWhere(
          (pattern) => pattern.id == clip.patternId,
        );
        for (final note in pattern.notes) {
          final tick = clip.startTick + note.startTick;
          final key = (
            volume,
            note.durationTicks,
            note.onsetOffsetMs,
            note.durationOffsetMs,
          );
          ((sequencedAt[tick] ??= {})[key] ??= []).add(note);
        }
      case SongPatternType.drum:
        final pattern = project.drumPatterns.firstWhere(
          (pattern) => pattern.id == clip.patternId,
        );
        for (final lane in pattern.lanes) {
          for (final activeTick in lane.activeTicks) {
            final tick = clip.startTick + activeTick;
            ((drumsAt[tick] ??= {})[volume] ??= {}).add(lane.laneId);
          }
        }
      case SongPatternType.audio:
        // Audio clips have no per-tick events; they are scheduled by the
        // playback notifier through the audio sink.
        break;
    }
  }

  final sortedTicks = {...drumsAt.keys, ...sequencedAt.keys}.toList()..sort();
  return [
    for (final tick in sortedTicks)
      SongPlaybackEvent(
        tick: tick,
        drumGroups: [
          for (final entry
              in (drumsAt[tick] ?? const <double, Set<DrumLaneId>>{}).entries)
            (volume: entry.key, drumLanes: entry.value.toList()),
        ],
        sequencedNoteGroups: [
          for (final entry in (sequencedAt[tick] ?? const {}).entries)
            (volume: entry.key.$1, notes: entry.value),
        ],
      ),
  ];
}
