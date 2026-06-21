import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/song_from_writer_rules.dart';

void main() {
  SongwriterProjectSnapshot writerProject() => const SongwriterProjectSnapshot(
    name: 'My tune',
    config: SongwriterConfig(
      tempo: 96,
      beatsPerBar: 4,
      beatUnit: 4,
      keyRoot: 0,
      keyScaleName: 'major',
    ),
    sections: [
      SongSection(
        id: 's1',
        label: 'Verse',
        lengthBars: 2,
        order: 0,
        repeat: 2,
        lanes: [
          SongLane(
            id: 'l1',
            kind: SongLaneKind.harmony,
            order: 0,
            blocks: [
              SongBlock(
                id: 'b1',
                startBar: 0,
                spanBars: 2,
                chordSymbol: 'C',
                chordNotes: ['C', 'E', 'G'],
              ),
            ],
          ),
          SongLane(
            id: 'l2',
            kind: SongLaneKind.drum,
            order: 1,
            blocks: [
              SongBlock(id: 'b2', startBar: 0, spanBars: 2, patternId: 'dp1'),
            ],
          ),
        ],
      ),
      SongSection(id: 's2', label: 'Chorus', lengthBars: 2, order: 1),
    ],
    drumPatterns: [
      DrumPattern(
        id: 'dp1',
        name: 'Beat',
        lengthTicks: 16,
        lanes: [
          DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
        ],
      ),
    ],
  );

  test('songFromSongwriter maps config, markers, tracks and clips', () {
    final song = songFromSongwriter(writerProject(), const []);

    // Config carried over; bars = 2*2 + 2 = 6 measures.
    expect(song.config.tempo, 96);
    expect(song.config.timeSignature.beatsPerMeasure, 4);
    expect(song.config.totalMeasures, 6);
    expect(song.config.scaleRoot, 'C');
    expect(song.config.scaleName, 'major');

    // One marker per expanded section instance.
    expect(song.markers.map((m) => m.label).toList(), [
      'Verse',
      'Verse',
      'Chorus',
    ]);
    expect(song.markers.map((m) => m.tick).toList(), [0, 32, 64]);

    // Harmony note track + drum track.
    final noteTracks = song.tracks
        .where((t) => t.type == SongTrackType.note)
        .toList();
    final drumTracks = song.tracks
        .where((t) => t.type == SongTrackType.drum)
        .toList();
    expect(noteTracks, hasLength(1));
    expect(drumTracks, hasLength(1));

    // Harmony block repeats across both section instances, sharing a pattern.
    final harmonyClips = song.clips
        .where((c) => c.trackId == noteTracks.single.id)
        .toList();
    expect(harmonyClips, hasLength(2));
    expect(harmonyClips.map((c) => c.startTick).toSet(), {0, 32});
    expect(harmonyClips.map((c) => c.patternId).toSet(), hasLength(1));

    // Chord stabs: one per bar in the 2-bar block.
    final pattern = song.notePatterns.firstWhere(
      (p) => p.id == harmonyClips.first.patternId,
    );
    expect(pattern.lengthTicks, 32);
    expect(pattern.notes.where((n) => n.startTick == 0), hasLength(3));
    expect(pattern.notes.where((n) => n.startTick == 16), hasLength(3));

    // Drum pattern carried over and tiled.
    final drumClips = song.clips
        .where((c) => c.trackId == drumTracks.single.id)
        .toList();
    expect(drumClips, hasLength(2));
    expect(song.drumPatterns, hasLength(1));
  });

  test('empty writer project yields a default-sized song', () {
    const writer = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );
    final song = songFromSongwriter(writer, const []);
    expect(song.tracks, isEmpty);
    expect(song.config.totalMeasures, greaterThanOrEqualTo(1));
  });
}
