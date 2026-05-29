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
  final activeTrackIds = audibleTracks(
    project,
  ).map((track) => track.id).toSet();
  final tickMap = <int, ({Set<int> midiNotes, Set<DrumLaneId> drumLanes})>{};

  for (final clip in project.clips.where(
    (clip) => activeTrackIds.contains(clip.trackId),
  )) {
    switch (clip.patternType) {
      case SongPatternType.note:
        final pattern = project.notePatterns.firstWhere(
          (pattern) => pattern.id == clip.patternId,
        );
        for (final note in pattern.notes) {
          final tick = clip.startTick + note.startTick;
          final bucket = tickMap.putIfAbsent(
            tick,
            () => (midiNotes: <int>{}, drumLanes: <DrumLaneId>{}),
          );
          bucket.midiNotes.add(note.midiNote);
        }
      case SongPatternType.drum:
        final pattern = project.drumPatterns.firstWhere(
          (pattern) => pattern.id == clip.patternId,
        );
        for (final lane in pattern.lanes) {
          for (final activeTick in lane.activeTicks) {
            final absoluteTick = clip.startTick + activeTick;
            final bucket = tickMap.putIfAbsent(
              absoluteTick,
              () => (midiNotes: <int>{}, drumLanes: <DrumLaneId>{}),
            );
            bucket.drumLanes.add(lane.laneId);
          }
        }
      case SongPatternType.audio:
        // Audio clips have no per-tick events; they are scheduled by the
        // playback notifier through the audio sink.
        break;
    }
  }

  final sortedTicks = tickMap.keys.toList()..sort();
  return [
    for (final tick in sortedTicks)
      SongPlaybackEvent(
        tick: tick,
        midiNotes: tickMap[tick]!.midiNotes.toList()..sort(),
        drumLanes: tickMap[tick]!.drumLanes.toList(),
      ),
  ];
}
