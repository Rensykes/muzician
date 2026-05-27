import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/piano_roll.dart';

void main() {
  group('PianoRollSnapshot round-trip serialization', () {
    test('toJson → fromJson restores all persisted fields', () {
      final original = PianoRollSnapshot(
        tempo: 140,
        key: 'D',
        numerator: 3,
        denominator: 4,
        totalMeasures: 8,
        notes: [
          {'midiNote': 62, 'startTick': 0, 'durationTicks': 4},
          {'midiNote': 66, 'startTick': 0, 'durationTicks': 4},
          {'midiNote': 69, 'startTick': 4, 'durationTicks': 4},
        ],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: 0,
        snapTicks: 2,
        highlightedNotes: ['D', 'F#', 'A'],
      );

      final json = original.toJson();
      final restored = PianoRollSnapshot.fromJson(json);

      // Config fields
      expect(restored.tempo, 140);
      expect(restored.key, 'D');
      expect(restored.numerator, 3);
      expect(restored.denominator, 4);
      expect(restored.totalMeasures, 8);

      // Notes
      expect(restored.notes, hasLength(3));
      expect(restored.notes[0]['midiNote'], 62);
      expect(restored.notes[0]['startTick'], 0);
      expect(restored.notes[0]['durationTicks'], 4);
      expect(restored.notes[1]['midiNote'], 66);
      expect(restored.notes[2]['midiNote'], 69);

      // Pitch range
      expect(restored.pitchRangeStart, 48);
      expect(restored.pitchRangeEnd, 84);

      // Selected column
      expect(restored.selectedColumnTick, 0);

      // Snap
      expect(restored.snapTicks, 2);

      // Highlighted
      expect(restored.highlightedNotes, ['D', 'F#', 'A']);

      // Instrument discriminator
      expect(restored.instrument, 'piano_roll');
    });

    test(
      'PianoRollSnapshot with null selectedColumnTick survives round-trip',
      () {
        final original = PianoRollSnapshot(
          tempo: 100,
          key: null,
          numerator: 4,
          denominator: 4,
          totalMeasures: 2,
          notes: [],
          pitchRangeStart: 36,
          pitchRangeEnd: 72,
          selectedColumnTick: null,
          snapTicks: 1,
          highlightedNotes: [],
        );

        final json = original.toJson();
        final restored = PianoRollSnapshot.fromJson(json);

        expect(restored.selectedColumnTick, isNull);
        expect(restored.key, isNull);
        expect(restored.notes, isEmpty);
        expect(restored.highlightedNotes, isEmpty);
      },
    );

    test('PianoRollSnapshot deserialized from minimal JSON uses defaults', () {
      final restored = PianoRollSnapshot.fromJson({
        'type': 'piano_roll',
        'instrument': 'piano_roll',
      });

      expect(restored.tempo, 120);
      expect(restored.numerator, 4);
      expect(restored.denominator, 4);
      expect(restored.totalMeasures, 4);
      expect(restored.notes, isEmpty);
      expect(restored.pitchRangeStart, 48);
      expect(restored.pitchRangeEnd, 84);
      expect(restored.selectedColumnTick, isNull);
      expect(restored.snapTicks, 1);
      expect(restored.highlightedNotes, isEmpty);
    });
  });

  group('PianoRollSnapshot computed getters', () {
    test('selectedNotes returns pitch classes at selectedColumnTick', () {
      final snap = PianoRollSnapshot(
        tempo: 120,
        numerator: 4,
        denominator: 4,
        totalMeasures: 4,
        notes: [
          {'midiNote': 62, 'startTick': 0, 'durationTicks': 4}, // D
          {'midiNote': 66, 'startTick': 0, 'durationTicks': 4}, // F#
          {'midiNote': 69, 'startTick': 0, 'durationTicks': 4}, // A
          {'midiNote': 64, 'startTick': 4, 'durationTicks': 4}, // E
        ],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: 0,
        snapTicks: 1,
        highlightedNotes: [],
      );

      final notes = snap.selectedNotes;
      expect(notes, hasLength(3));
      expect(notes, containsAll(['D', 'F#', 'A']));
    });

    test(
      'selectedNotes falls back to all notes when column tick matches none',
      () {
        final snap = PianoRollSnapshot(
          tempo: 120,
          numerator: 4,
          denominator: 4,
          totalMeasures: 4,
          notes: [
            {'midiNote': 60, 'startTick': 4, 'durationTicks': 4}, // C
            {'midiNote': 64, 'startTick': 8, 'durationTicks': 4}, // E
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          selectedColumnTick: 0, // no notes here
          snapTicks: 1,
          highlightedNotes: [],
        );

        final notes = snap.selectedNotes;
        expect(notes, hasLength(2));
        expect(notes, containsAll(['C', 'E']));
      },
    );

    test('pendingChord is derived from selectedNotes', () {
      final snap = PianoRollSnapshot(
        tempo: 120,
        numerator: 4,
        denominator: 4,
        totalMeasures: 4,
        notes: [
          {'midiNote': 62, 'startTick': 0, 'durationTicks': 4}, // D
          {'midiNote': 66, 'startTick': 0, 'durationTicks': 4}, // F#
          {'midiNote': 69, 'startTick': 0, 'durationTicks': 4}, // A
        ],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: 0,
        snapTicks: 1,
        highlightedNotes: [],
      );

      final chord = snap.pendingChord;
      expect(chord, isNotNull);
      expect(chord!.root, 'D');
      expect(chord.quality, '');
      expect(chord.symbol, 'D');
    });

    test('pendingChord is null when no notes', () {
      final snap = PianoRollSnapshot(
        tempo: 120,
        numerator: 4,
        denominator: 4,
        totalMeasures: 4,
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: null,
        snapTicks: 1,
        highlightedNotes: [],
      );

      expect(snap.pendingChord, isNull);
    });
  });

  group('InstrumentSnapshot.fromJson dispatches to PianoRollSnapshot', () {
    test('when type is piano_roll', () {
      final json = <String, dynamic>{
        'type': 'piano_roll',
        'instrument': 'piano_roll',
        'tempo': 80,
        'numerator': 4,
        'denominator': 4,
        'totalMeasures': 1,
        'notes': [],
        'pitchRangeStart': 48,
        'pitchRangeEnd': 84,
        'snapTicks': 1,
        'highlightedNotes': [],
      };
      final snap = InstrumentSnapshot.fromJson(json);
      expect(snap, isA<PianoRollSnapshot>());
      expect(snap.instrument, 'piano_roll');
    });

    test('when instrument is piano_roll', () {
      final json = <String, dynamic>{
        'instrument': 'piano_roll',
        'tempo': 80,
        'numerator': 4,
        'denominator': 4,
        'totalMeasures': 1,
        'notes': [],
        'pitchRangeStart': 48,
        'pitchRangeEnd': 84,
        'snapTicks': 1,
        'highlightedNotes': [],
      };
      final snap = InstrumentSnapshot.fromJson(json);
      expect(snap, isA<PianoRollSnapshot>());
    });

    test('existing PianoSnapshot still dispatches correctly', () {
      final json = <String, dynamic>{
        'instrument': 'piano',
        'currentRange': 'key61',
        'selectedKeys': [],
        'selectedNotes': [],
        'viewMode': 'exact',
      };
      final snap = InstrumentSnapshot.fromJson(json);
      expect(snap, isA<PianoSnapshot>());
    });

    test('existing FretboardSnapshot still dispatches correctly', () {
      final json = <String, dynamic>{
        'instrument': 'fretboard',
        'tuning': 'standard',
        'numFrets': 12,
        'capo': 0,
        'selectedCells': [],
        'selectedNotes': [],
        'viewMode': 'exact',
      };
      final snap = InstrumentSnapshot.fromJson(json);
      expect(snap, isA<FretboardSnapshot>());
    });
  });

  group('InstrumentSnapshot.fromJson dispatches to SongProjectSnapshot', () {
    test('when type is song', () {
      final json = <String, dynamic>{
        'type': 'song',
        'instrument': 'song',
        'project': {
          'config': {
            'tempo': 120,
            'timeSignature': {'beatsPerMeasure': 4, 'beatUnit': 4},
            'totalMeasures': 4,
          },
          'tracks': [],
          'clips': [],
          'notePatterns': [],
          'drumPatterns': [],
        },
      };
      final snapshot = InstrumentSnapshot.fromJson(json);
      expect(snapshot, isA<SongProjectSnapshot>());
    });

    test('when instrument is song without type field', () {
      final json = <String, dynamic>{
        'instrument': 'song',
        'project': {
          'config': {
            'tempo': 120,
            'timeSignature': {'beatsPerMeasure': 4, 'beatUnit': 4},
            'totalMeasures': 4,
          },
          'tracks': [],
          'clips': [],
          'notePatterns': [],
          'drumPatterns': [],
        },
      };
      final snapshot = InstrumentSnapshot.fromJson(json);
      expect(snapshot, isA<SongProjectSnapshot>());
    });
  });

  group('SongProjectSnapshot serialization', () {
    test('toJson → fromJson round-trips track, clip, and pattern counts', () {
      final snapshot = SongProjectSnapshot(
        project: SongProject(
          config: const SongProjectConfig(
            tempo: 128,
            timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            totalMeasures: 8,
          ),
          tracks: const [
            SongTrack(
              id: 't1',
              name: 'Lead',
              type: SongTrackType.note,
              order: 0,
            ),
            SongTrack(
              id: 't2',
              name: 'Drums',
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
            SongClipInstance(
              id: 'c2',
              trackId: 't2',
              patternId: 'd1',
              patternType: SongPatternType.drum,
              startTick: 16,
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
              highlightedNotes: ['C'],
            ),
          ],
          drumPatterns: const [
            DrumPattern(
              id: 'd1',
              name: 'Beat',
              lengthTicks: 16,
              lanes: [
                DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
              ],
            ),
          ],
        ),
      );
      final restored = SongProjectSnapshot.fromJson(snapshot.toJson());
      expect(restored.project.tracks, hasLength(2));
      expect(restored.project.clips, hasLength(2));
      expect(restored.project.notePatterns, hasLength(1));
      expect(restored.project.drumPatterns, hasLength(1));
    });

    test(
      'selectedNotes returns unique pitch classes across all note patterns',
      () {
        final snapshot = SongProjectSnapshot(
          project: SongProject(
            config: const SongProjectConfig(
              tempo: 120,
              timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
              totalMeasures: 4,
            ),
            tracks: const [],
            clips: const [],
            notePatterns: const [
              NotePattern(
                id: 'p1',
                name: 'Pattern 1',
                lengthTicks: 8,
                notes: [
                  NotePatternNote(
                    id: 'n1',
                    midiNote: 60,
                    startTick: 0,
                    durationTicks: 4,
                  ),
                  NotePatternNote(
                    id: 'n2',
                    midiNote: 64,
                    startTick: 4,
                    durationTicks: 4,
                  ),
                ],
                pitchRangeStart: 48,
                pitchRangeEnd: 84,
                snapTicks: 1,
                highlightedNotes: ['C'],
              ),
              NotePattern(
                id: 'p2',
                name: 'Pattern 2',
                lengthTicks: 8,
                notes: [
                  NotePatternNote(
                    id: 'n3',
                    midiNote: 60,
                    startTick: 0,
                    durationTicks: 4,
                  ),
                  NotePatternNote(
                    id: 'n4',
                    midiNote: 67,
                    startTick: 4,
                    durationTicks: 4,
                  ),
                ],
                pitchRangeStart: 48,
                pitchRangeEnd: 84,
                snapTicks: 1,
                highlightedNotes: ['C'],
              ),
            ],
            drumPatterns: const [],
          ),
        );
        final notes = snapshot.selectedNotes;
        expect(notes, hasLength(3));
        expect(notes, containsAll(['C', 'E', 'G']));
      },
    );

    test('pendingChord and pendingScale return null', () {
      final snapshot = SongProjectSnapshot(
        project: SongProject(
          config: const SongProjectConfig(
            tempo: 120,
            timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            totalMeasures: 4,
          ),
          tracks: const [],
          clips: const [],
          notePatterns: const [],
          drumPatterns: const [],
        ),
      );
      expect(snapshot.pendingChord, isNull);
      expect(snapshot.pendingScale, isNull);
    });
  });
}
