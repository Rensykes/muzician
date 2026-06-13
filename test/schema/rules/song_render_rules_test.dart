import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart' show TimeSignature;
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_render_rules.dart';

void main() {
  SongProject project({
    List<SongTrack> tracks = const [],
    List<SongClipInstance> clips = const [],
    List<NotePattern> notePatterns = const [],
    List<DrumPattern> drumPatterns = const [],
    int totalMeasures = 1,
  }) => SongProject(
    config: SongProjectConfig(
      tempo: 120,
      timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
      totalMeasures: totalMeasures,
    ),
    tracks: tracks,
    clips: clips,
    notePatterns: notePatterns,
    drumPatterns: drumPatterns,
  );

  test('empty song renders silence sized to its length + tail', () {
    final pcm = renderSongPcm(project(), sampleRate: 8000);
    // 1 measure @ 120bpm 4/4 = 2s + 1s tail = 3s * 8000 = 24000 samples.
    expect(pcm.length, greaterThan(20000));
    expect(pcm.every((s) => s == 0), isTrue);
  });

  test('a note produces non-silent audio at its onset', () {
    final pcm = renderSongPcm(
      project(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Lead',
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
            name: 'P',
            lengthTicks: 16,
            notes: [
              NotePatternNote(
                id: 'n1',
                midiNote: 69,
                startTick: 0,
                durationTicks: 8,
              ),
            ],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      ),
      sampleRate: 8000,
    );
    final peak = pcm.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m);
    expect(peak, greaterThan(1000));
  });

  test('muted track is silent', () {
    final pcm = renderSongPcm(
      project(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Lead',
            type: SongTrackType.note,
            order: 0,
            isMuted: true,
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
            name: 'P',
            lengthTicks: 16,
            notes: [
              NotePatternNote(
                id: 'n1',
                midiNote: 69,
                startTick: 0,
                durationTicks: 8,
              ),
            ],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
      ),
      sampleRate: 8000,
    );
    expect(pcm.every((s) => s == 0), isTrue);
  });

  test('a drum hit produces audio', () {
    final pcm = renderSongPcm(
      project(
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Drums',
            type: SongTrackType.drum,
            order: 0,
          ),
        ],
        clips: const [
          SongClipInstance(
            id: 'c1',
            trackId: 't1',
            patternId: 'd1',
            patternType: SongPatternType.drum,
            startTick: 0,
          ),
        ],
        drumPatterns: const [
          DrumPattern(
            id: 'd1',
            name: 'Beat',
            lengthTicks: 16,
            lanes: [
              DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
            ],
          ),
        ],
      ),
      sampleRate: 8000,
    );
    final peak = pcm.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m);
    expect(peak, greaterThan(1000));
  });
}
