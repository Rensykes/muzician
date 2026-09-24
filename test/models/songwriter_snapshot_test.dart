import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  test('snapshot round-trips through InstrumentSnapshot.fromJson', () {
    const snap = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 4,
          order: 0,
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
                  romanNumeral: 'I',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final json = snap.toJson();
    expect(json['type'], 'songwriter');

    final back = InstrumentSnapshot.fromJson(json);
    expect(back, isA<SongwriterProjectSnapshot>());
    final sw = back as SongwriterProjectSnapshot;
    expect(sw.sections.single.lanes.single.blocks.single.romanNumeral, 'I');
    expect(sw.instrument, 'songwriter');
    expect(sw.pendingChord, isNull);
    expect(sw.selectedNotes, containsAll(['C', 'E', 'G']));
  });

  test(
    'old JSON defaults new patterns and note offsets; new fields round-trip',
    () {
      final old = SongwriterProjectSnapshot.fromJson({
        'type': 'songwriter',
        'name': 'Old song',
        'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
        'sections': [],
        'drumPatterns': [],
      });
      expect(old.melodyPatterns, isEmpty);
      expect(old.guitarStrumPatterns, isEmpty);
      expect(
        NotePatternNote.fromJson({
          'id': 'legacy',
          'midiNote': 60,
          'startTick': 0,
          'durationTicks': 4,
        }).onsetOffsetMs,
        0,
      );
      expect(
        NotePatternNote.fromJson({
          'id': 'legacy',
          'midiNote': 60,
          'startTick': 0,
          'durationTicks': 4,
        }).durationOffsetMs,
        0,
      );

      final snapshot = old.copyWith(
        melodyPatterns: const [
          NotePattern(
            id: 'melody',
            name: 'Melody',
            lengthTicks: 16,
            notes: [
              NotePatternNote(
                id: 'n1',
                midiNote: 64,
                startTick: 3,
                durationTicks: 5,
                onsetOffsetMs: 12,
                durationOffsetMs: -4,
              ),
            ],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
        guitarStrumPatterns: const [
          GuitarStrumPattern(
            id: 'strum',
            name: 'Strum',
            lengthTicks: 16,
            events: [
              GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
              GuitarStrumEvent(tick: 4, direction: GuitarStrumDirection.up),
            ],
          ),
        ],
      );
      final restored = SongwriterProjectSnapshot.fromJson(snapshot.toJson());
      expect(restored.melodyPatterns.single.notes.single.onsetOffsetMs, 12);
      expect(restored.melodyPatterns.single.notes.single.durationOffsetMs, -4);
      expect(
        restored.guitarStrumPatterns.single.events
            .map((event) => (event.tick, event.direction))
            .toList(),
        [(0, GuitarStrumDirection.down), (4, GuitarStrumDirection.up)],
      );
    },
  );
}
