import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_rules.dart' as rules;

void main() {
  group('songTotalTicks', () {
    test('uses shared time-signature math', () {
      const config = SongProjectConfig(
        tempo: 120,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 4,
      );
      expect(rules.songTotalTicks(config), 64);
    });
  });

  group('canPlaceClipOnTrack', () {
    test('rejects same-track overlap', () {
      final project = rules.getDefaultSongProject().copyWith(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Track 1',
            type: SongTrackType.note,
            order: 0,
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
        ],
        notePatterns: const [
          NotePattern(
            id: 'p1',
            name: 'Pattern 1',
            lengthTicks: 16,
            notes: [],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      );
      final candidate = const SongClipInstance(
        id: 'c2',
        trackId: 't1',
        patternId: 'p2',
        patternType: SongPatternType.note,
        startTick: 8,
      );
      expect(
        rules.canPlaceClipOnTrack(project, candidate, patternLengthTicks: 16),
        isFalse,
      );
    });

    test('allows non-overlapping placement', () {
      final project = rules.getDefaultSongProject().copyWith(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Track 1',
            type: SongTrackType.note,
            order: 0,
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
        ],
        notePatterns: const [
          NotePattern(
            id: 'p1',
            name: 'Pattern 1',
            lengthTicks: 16,
            notes: [],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      );
      final candidate = const SongClipInstance(
        id: 'c2',
        trackId: 't1',
        patternId: 'p2',
        patternType: SongPatternType.note,
        startTick: 16,
      );
      expect(
        rules.canPlaceClipOnTrack(project, candidate, patternLengthTicks: 16),
        isTrue,
      );
    });

    test('allows clips on different tracks at same position', () {
      final project = rules.getDefaultSongProject().copyWith(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Track 1',
            type: SongTrackType.note,
            order: 0,
          ),
          SongTrack(
            id: 't2',
            name: 'Track 2',
            type: SongTrackType.drum,
            order: 1,
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
        ],
        notePatterns: const [
          NotePattern(
            id: 'p1',
            name: 'Pattern 1',
            lengthTicks: 16,
            notes: [],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      );
      final projectWithDrums = project.copyWith(
        drumPatterns: const [
          DrumPattern(id: 'd1', name: 'Beat', lengthTicks: 16, lanes: []),
        ],
      );
      final candidate = const SongClipInstance(
        id: 'c2',
        trackId: 't2',
        patternId: 'd1',
        patternType: SongPatternType.drum,
        startTick: 0,
      );
      expect(
        rules.canPlaceClipOnTrack(
          projectWithDrums,
          candidate,
          patternLengthTicks: 16,
        ),
        isTrue,
      );
    });
  });

  group('cloneNotePatternForClip', () {
    test('creates a new pattern id and relinks only one clip', () {
      final project = rules.getDefaultSongProject().copyWith(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Track 1',
            type: SongTrackType.note,
            order: 0,
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
            trackId: 't1',
            patternId: 'p1',
            patternType: SongPatternType.note,
            startTick: 16,
          ),
        ],
        notePatterns: const [
          NotePattern(
            id: 'p1',
            name: 'Shared Pattern',
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
      final result = rules.cloneNotePatternForClip(
        project,
        clipId: 'c2',
        newPatternId: 'p2',
        newPatternName: 'Shared Pattern Copy',
      );
      expect(result.clonedPattern.id, 'p2');
      expect(result.updatedClip.patternId, 'p2');
    });
  });

  group('createEmptyDrumPattern', () {
    test('creates pattern with all 8 lanes empty', () {
      final pattern = rules.createEmptyDrumPattern(
        id: 'dp1',
        name: 'Beat',
        lengthTicks: 16,
      );
      expect(pattern.lanes, hasLength(8));
      expect(pattern.lanes.every((lane) => lane.activeTicks.isEmpty), isTrue);
      expect(
        pattern.lanes.map((l) => l.laneId).toSet(),
        DrumLaneId.values.toSet(),
      );
    });
  });

  group('canApplyPatternLength', () {
    test('rejects if resized pattern would overlap on any track', () {
      final project = rules.getDefaultSongProject().copyWith(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Track 1',
            type: SongTrackType.note,
            order: 0,
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
            trackId: 't1',
            patternId: 'p1',
            patternType: SongPatternType.note,
            startTick: 24,
          ),
        ],
        notePatterns: const [
          NotePattern(
            id: 'p1',
            name: 'Shared',
            lengthTicks: 16,
            notes: [],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      );
      expect(rules.canApplyPatternLength(project, 'p1', 25), isFalse);
    });

    test('allows resize if no overlap results', () {
      final project = rules.getDefaultSongProject().copyWith(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Track 1',
            type: SongTrackType.note,
            order: 0,
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
        ],
        notePatterns: const [
          NotePattern(
            id: 'p1',
            name: 'Solo',
            lengthTicks: 8,
            notes: [],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      );
      expect(rules.canApplyPatternLength(project, 'p1', 16), isTrue);
    });
  });
}
