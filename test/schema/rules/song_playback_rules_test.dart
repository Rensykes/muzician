import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_playback_rules.dart' as rules;
import 'package:muzician/schema/rules/song_rules.dart' as song_rules;

void main() {
  test('buildPlaybackEvents expands note clips to absolute ticks', () {
    final project = song_rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(
          id: 'noteTrack',
          name: 'Lead',
          type: SongTrackType.note,
          order: 0,
        ),
      ],
      clips: const [
        SongClipInstance(
          id: 'clip1',
          trackId: 'noteTrack',
          patternId: 'pattern1',
          patternType: SongPatternType.note,
          startTick: 16,
        ),
      ],
      notePatterns: const [
        NotePattern(
          id: 'pattern1',
          name: 'Lead Pattern',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'n1',
              midiNote: 60,
              startTick: 0,
              durationTicks: 4,
            ),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
    );

    final events = rules.buildPlaybackEvents(project);
    expect(events, hasLength(1));
    expect(events.single.tick, 16);
    expect(events.single.midiNotes, [60]);
  });

  test('mute and solo are applied before event expansion', () {
    final project = song_rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(id: 't1', name: 'Lead', type: SongTrackType.note, order: 0),
        SongTrack(
          id: 't2',
          name: 'Bass',
          type: SongTrackType.note,
          order: 1,
          isMuted: true,
        ),
        SongTrack(
          id: 't3',
          name: 'Solo',
          type: SongTrackType.note,
          order: 2,
          isSolo: true,
        ),
      ],
      clips: const [
        SongClipInstance(
          id: 'c1',
          trackId: 't1',
          patternId: 'p1',
          patternType: SongPatternType.note,
          startTick: 0,
        ),
        SongClipInstance(
          id: 'c2',
          trackId: 't2',
          patternId: 'p2',
          patternType: SongPatternType.note,
          startTick: 0,
        ),
        SongClipInstance(
          id: 'c3',
          trackId: 't3',
          patternId: 'p3',
          patternType: SongPatternType.note,
          startTick: 0,
        ),
      ],
      notePatterns: const [
        NotePattern(
          id: 'p1',
          name: 'Lead',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'n1',
              midiNote: 60,
              startTick: 0,
              durationTicks: 4,
            ),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
        NotePattern(
          id: 'p2',
          name: 'Bass',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'n2',
              midiNote: 48,
              startTick: 0,
              durationTicks: 4,
            ),
          ],
          pitchRangeStart: 36,
          pitchRangeEnd: 72,
          snapTicks: 1,
          highlightedNotes: [],
        ),
        NotePattern(
          id: 'p3',
          name: 'Solo',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'n3',
              midiNote: 72,
              startTick: 0,
              durationTicks: 4,
            ),
          ],
          pitchRangeStart: 60,
          pitchRangeEnd: 96,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
    );

    final events = rules.buildPlaybackEvents(project);
    expect(events, hasLength(1));
    expect(events.single.midiNotes, [72]); // Only soloed track plays
  });

  test('buildPlaybackEvents expands drum lanes to absolute ticks', () {
    final project = song_rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(
          id: 'drumTrack',
          name: 'Drums',
          type: SongTrackType.drum,
          order: 0,
        ),
      ],
      clips: const [
        SongClipInstance(
          id: 'dc1',
          trackId: 'drumTrack',
          patternId: 'dp1',
          patternType: SongPatternType.drum,
          startTick: 0,
        ),
      ],
      drumPatterns: const [
        DrumPattern(
          id: 'dp1',
          name: 'Beat',
          lengthTicks: 16,
          lanes: [
            DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
            DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [4, 12]),
          ],
        ),
      ],
    );

    final events = rules.buildPlaybackEvents(project);
    // Should have events at ticks 0, 4, 8, 12
    expect(events.map((e) => e.tick), [0, 4, 8, 12]);
    expect(events[0].drumLanes, [DrumLaneId.kick]);
    expect(events[1].drumLanes, [DrumLaneId.snare]);
  });

  test('audibleTracks returns soloed tracks when any are soloed', () {
    final project = song_rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(
          id: 't1',
          name: 'A',
          type: SongTrackType.note,
          order: 0,
          isMuted: false,
        ),
        SongTrack(
          id: 't2',
          name: 'B',
          type: SongTrackType.note,
          order: 1,
          isSolo: true,
          isMuted: true,
        ),
        SongTrack(
          id: 't3',
          name: 'C',
          type: SongTrackType.note,
          order: 2,
          isMuted: false,
        ),
      ],
    );

    final audible = rules.audibleTracks(project);
    expect(audible, hasLength(1));
    expect(
      audible.single.id,
      't2',
    ); // soloed track is audible even if also muted
  });
}
