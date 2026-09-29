import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';

void main() {
  group('chordMidiNotes', () {
    test(
      'maps chordNotes pitch classes to an ascending stack from octave 4',
      () {
        const block = SongBlock(
          id: 'b1',
          startBar: 0,
          spanBars: 1,
          chordNotes: ['G', 'B', 'D'],
        );
        // G4=67, B4=71, D above B -> D5=74.
        expect(chordMidiNotes(block), [67, 71, 74]);
      },
    );

    test('falls back to chordRootPc + chordQuality intervals', () {
      const block = SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        chordRootPc: 9, // A
        chordQuality: 'm',
      );
      // A4=69, C5=72, E5=76.
      expect(chordMidiNotes(block), [69, 72, 76]);
    });

    test('returns empty for chord-less blocks', () {
      const block = SongBlock(id: 'b1', startBar: 0, spanBars: 1);
      expect(chordMidiNotes(block), isEmpty);
    });

    test('returns empty for silent blocks even when chord data present', () {
      const block = SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        chordNotes: ['C'],
        isSilent: true,
      );
      expect(chordMidiNotes(block), isEmpty);
    });
  });

  group('snapshotMidiNotes', () {
    test('piano snapshot uses selectedKeys midiNote', () {
      final snap = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 0, midiNote: 64, noteName: 'E4'),
          PianoCoordinate(keyIndex: 1, midiNote: 60, noteName: 'C4'),
        ],
        selectedNotes: const ['E', 'C'],
        viewMode: PianoViewMode.exact,
      );
      expect(snapshotMidiNotes(snap), [60, 64]);
    });

    test('fretboard snapshot maps string+fret through the tuning', () {
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        // stringIndex 0 = high E (midi 64); fret 3 -> G4=67.
        selectedCells: const [
          FretCoordinate(stringIndex: 0, fret: 3, noteName: 'G'),
          FretCoordinate(stringIndex: 5, fret: 0, noteName: 'E'),
        ],
        selectedNotes: const ['G', 'E'],
        viewMode: FretboardViewMode.exact,
      );
      expect(snapshotMidiNotes(snap), [40, 67]);
    });

    test('null snapshot yields empty', () {
      expect(snapshotMidiNotes(null), isEmpty);
    });
  });

  group('flattenPlaybackEvents', () {
    SongwriterProjectSnapshot projectWith({
      required List<SongSection> sections,
      List<DrumPattern> drumPatterns = const [],
      List<NotePattern> melodyPatterns = const [],
      List<GuitarStrumPattern> guitarStrumPatterns = const [],
      int beatsPerBar = 4,
      int beatUnit = 4,
    }) => SongwriterProjectSnapshot(
      config: SongwriterConfig(
        tempo: 120,
        beatsPerBar: beatsPerBar,
        beatUnit: beatUnit,
      ),
      sections: sections,
      drumPatterns: drumPatterns,
      melodyPatterns: melodyPatterns,
      guitarStrumPatterns: guitarStrumPatterns,
    );

    test('harmony block fires a chord stab at every bar it spans', () {
      const block = SongBlock(
        id: 'b1',
        startBar: 1,
        spanBars: 2,
        chordNotes: ['C', 'E', 'G'],
      );
      const lane = SongLane(
        id: 'l1',
        kind: SongLaneKind.harmony,
        order: 0,
        blocks: [block],
      );
      const section = SongSection(
        id: 's1',
        lengthBars: 4,
        order: 0,
        lanes: [lane],
      );
      final events = flattenPlaybackEvents(
        projectWith(sections: [section]),
        const [],
      );
      // measureTicks = 16; bars 1 and 2 -> ticks 16 and 32.
      expect(events.map((e) => e.tick).toList(), [16, 32]);
      expect(events.first.midiNotes, [60, 64, 67]);
    });

    test('section repeat re-fires events at each repeat offset', () {
      const block = SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        chordNotes: ['C'],
      );
      const lane = SongLane(
        id: 'l1',
        kind: SongLaneKind.harmony,
        order: 0,
        blocks: [block],
      );
      const section = SongSection(
        id: 's1',
        lengthBars: 2,
        order: 0,
        repeat: 2,
        lanes: [lane],
      );
      final events = flattenPlaybackEvents(
        projectWith(sections: [section]),
        const [],
      );
      // Section instance 0 at bar 0 (tick 0), instance 1 at bar 2 (tick 32).
      expect(events.map((e) => e.tick).toList(), [0, 32]);
    });

    test('block spanning past section end is clipped', () {
      const block = SongBlock(
        id: 'b1',
        startBar: 1,
        spanBars: 5, // section is only 2 bars long
        chordNotes: ['C'],
      );
      const lane = SongLane(
        id: 'l1',
        kind: SongLaneKind.harmony,
        order: 0,
        blocks: [block],
      );
      const section = SongSection(
        id: 's1',
        lengthBars: 2,
        order: 0,
        lanes: [lane],
      );
      final events = flattenPlaybackEvents(
        projectWith(sections: [section]),
        const [],
      );
      expect(events.map((e) => e.tick).toList(), [16]); // bar 1 only
    });

    test(
      'drum block fires pattern hits at native ticks, tiled to block span',
      () {
        const pattern = DrumPattern(
          id: 'p1',
          name: 'beat',
          lengthTicks: 16, // one bar
          lanes: [
            DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
          ],
        );
        const block = SongBlock(
          id: 'b1',
          startBar: 0,
          spanBars: 2,
          patternId: 'p1',
        );
        const lane = SongLane(
          id: 'l1',
          kind: SongLaneKind.drum,
          order: 0,
          blocks: [block],
        );
        const section = SongSection(
          id: 's1',
          lengthBars: 2,
          order: 0,
          lanes: [lane],
        );
        final events = flattenPlaybackEvents(
          projectWith(sections: [section], drumPatterns: [pattern]),
          const [],
        );
        expect(events.map((e) => e.tick).toList(), [0, 8, 16, 24]);
        expect(events.first.drumLanes, [DrumLaneId.kick]);
      },
    );

    test(
      'melody loops from block origin and clips at each pattern boundary',
      () {
        const pattern = NotePattern(
          id: 'melody',
          name: 'Lead',
          lengthTicks: 8,
          notes: [
            NotePatternNote(
              id: 'a',
              midiNote: 60,
              startTick: 2,
              durationTicks: 7,
            ),
            NotePatternNote(
              id: 'b',
              midiNote: 64,
              startTick: 7,
              durationTicks: 4,
              onsetOffsetMs: 12,
            ),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        );
        const lane = SongLane(
          id: 'melody-lane',
          kind: SongLaneKind.melody,
          order: 0,
          repeat: 2,
          blocks: [
            SongBlock(
              id: 'melody-block',
              startBar: 0,
              spanBars: 1,
              patternId: 'melody',
            ),
          ],
        );
        const section = SongSection(
          id: 'repeated',
          lengthBars: 2,
          order: 0,
          repeat: 2,
          lanes: [lane],
        );

        final events = flattenPlaybackEvents(
          projectWith(sections: [section], melodyPatterns: [pattern]),
          const [],
        );

        expect(events.map((event) => event.tick), [
          2,
          7,
          10,
          15,
          18,
          23,
          26,
          31,
          34,
          39,
          42,
          47,
          50,
          55,
          58,
          63,
        ]);
        final clipped = events.firstWhere((event) => event.tick == 7);
        expect(
          clipped.sequencedNoteGroups.single.notes.single.durationTicks,
          1,
        );
        expect(
          clipped.sequencedNoteGroups.single.notes.single.onsetOffsetMs,
          12,
        );
        expect(
          events.first.tick,
          2,
          reason: 'pattern origin is the block start, not timeline zero',
        );
        expect(
          events.last.tick,
          63,
          reason: 'the final repeat is clipped to the section boundary',
        );
      },
    );

    test(
      'strum uses the explicitly anchored chord and staggers low-to-high',
      () {
        const primary = SongLane(
          id: 'primary',
          kind: SongLaneKind.harmony,
          order: 0,
          blocks: [
            SongBlock(
              id: 'c',
              startBar: 0,
              spanBars: 1,
              chordNotes: ['C', 'E', 'G'],
            ),
          ],
        );
        const selected = SongLane(
          id: 'selected',
          kind: SongLaneKind.harmony,
          order: 1,
          blocks: [
            SongBlock(
              id: 'g',
              startBar: 0,
              spanBars: 1,
              chordNotes: ['G', 'B', 'D'],
            ),
          ],
        );
        const strumLane = SongLane(
          id: 'strum',
          kind: SongLaneKind.guitarStrum,
          order: 2,
          anchorLaneId: 'selected',
          blocks: [
            SongBlock(
              id: 'strum-block',
              startBar: 0,
              spanBars: 1,
              patternId: 'strum-pattern',
            ),
          ],
        );
        const pattern = GuitarStrumPattern(
          id: 'strum-pattern',
          name: 'Down',
          lengthTicks: 16,
          events: [
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
          ],
        );
        const section = SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [primary, selected, strumLane],
        );
        final events = flattenPlaybackEvents(
          projectWith(sections: [section], guitarStrumPatterns: [pattern]),
          const [],
        );
        final strumNotes =
            events.single.sequencedNoteGroups
                .expand((group) => group.notes)
                .where((note) => note.midiNote >= 67)
                .toList()
              ..sort((a, b) => a.onsetOffsetMs.compareTo(b.onsetOffsetMs));
        expect(strumNotes.map((note) => note.midiNote), [67, 71, 74]);
        expect(strumNotes.map((note) => note.onsetOffsetMs), [0, 12, 24]);
        expect(strumNotes.map((note) => note.durationTicks), [2, 2, 2]);
      },
    );

    test(
      'strum stays silent when its explicit harmony anchor has no chord',
      () {
        const primary = SongLane(
          id: 'primary',
          kind: SongLaneKind.harmony,
          order: 0,
          blocks: [
            SongBlock(id: 'c', startBar: 0, spanBars: 1, chordNotes: ['C']),
          ],
        );
        const emptyAnchor = SongLane(
          id: 'empty',
          kind: SongLaneKind.harmony,
          order: 1,
        );
        const strumLane = SongLane(
          id: 'strum',
          kind: SongLaneKind.guitarStrum,
          order: 2,
          anchorLaneId: 'empty',
          blocks: [
            SongBlock(
              id: 'block',
              startBar: 0,
              spanBars: 1,
              patternId: 'pattern',
            ),
          ],
        );
        const section = SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [primary, emptyAnchor, strumLane],
        );
        const pattern = GuitarStrumPattern(
          id: 'pattern',
          name: 'Down',
          lengthTicks: 16,
          events: [
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
          ],
        );
        final events = flattenPlaybackEvents(
          projectWith(sections: [section], guitarStrumPatterns: [pattern]),
          const [],
        );
        expect(events.map((event) => event.tick), [
          0,
        ]); // Primary chord still plays.
        expect(events.single.sequencedNoteGroups, isEmpty);
      },
    );

    test('strum requires an explicit live Fretboard Harmony anchor', () {
      const primary = SongLane(
        id: 'primary',
        kind: SongLaneKind.harmony,
        order: 0,
        blocks: [
          SongBlock(
            id: 'chord',
            startBar: 0,
            spanBars: 1,
            chordNotes: ['C', 'E', 'G'],
          ),
        ],
      );
      const pattern = GuitarStrumPattern(
        id: 'pattern',
        name: 'Down',
        lengthTicks: 16,
        events: [
          GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
        ],
      );

      for (final (anchorLaneId, shouldStrum) in [
        ('primary', true),
        (null, false),
        ('deleted-harmony', false),
      ]) {
        final section = SongSection(
          id: 'section',
          lengthBars: 1,
          order: 0,
          lanes: [
            primary,
            SongLane(
              id: 'strum',
              kind: SongLaneKind.guitarStrum,
              order: 1,
              anchorLaneId: anchorLaneId,
              blocks: const [
                SongBlock(
                  id: 'strum-block',
                  startBar: 0,
                  spanBars: 1,
                  patternId: 'pattern',
                ),
              ],
            ),
          ],
        );
        final events = flattenPlaybackEvents(
          projectWith(sections: [section], guitarStrumPatterns: [pattern]),
          const [],
        );
        final sequencedNotes = [
          for (final event in events)
            for (final group in event.sequencedNoteGroups) ...group.notes,
        ];
        expect(sequencedNotes, shouldStrum ? hasLength(3) : isEmpty);
      }
    });

    test('delayed voices shorten at the melody and strum block boundary', () {
      const section = SongSection(
        id: 'boundary-section',
        lengthBars: 1,
        order: 0,
        lanes: [
          SongLane(
            id: 'harmony',
            kind: SongLaneKind.harmony,
            order: 0,
            blocks: [
              SongBlock(
                id: 'chord',
                startBar: 0,
                spanBars: 1,
                chordNotes: ['C', 'E', 'G'],
              ),
            ],
          ),
          SongLane(
            id: 'melody-lane',
            kind: SongLaneKind.melody,
            order: 1,
            blocks: [
              SongBlock(
                id: 'melody-block',
                startBar: 0,
                spanBars: 1,
                patternId: 'melody-pattern',
              ),
            ],
          ),
          SongLane(
            id: 'strum-lane',
            kind: SongLaneKind.guitarStrum,
            order: 2,
            anchorLaneId: 'harmony',
            blocks: [
              SongBlock(
                id: 'strum-block',
                startBar: 0,
                spanBars: 1,
                patternId: 'strum-pattern',
              ),
            ],
          ),
        ],
      );
      const melody = NotePattern(
        id: 'melody-pattern',
        name: 'Lead',
        lengthTicks: 16,
        notes: [
          NotePatternNote(
            id: 'boundary-melody',
            midiNote: 72,
            startTick: 15,
            durationTicks: 3,
            onsetOffsetMs: 36,
          ),
        ],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        snapTicks: 1,
        highlightedNotes: [],
      );
      const strum = GuitarStrumPattern(
        id: 'strum-pattern',
        name: 'Down',
        lengthTicks: 16,
        events: [
          GuitarStrumEvent(tick: 15, direction: GuitarStrumDirection.down),
        ],
      );

      final notes =
          flattenPlaybackEvents(
                projectWith(
                  sections: [section],
                  melodyPatterns: [melody],
                  guitarStrumPatterns: [strum],
                ),
                const [],
              )
              .singleWhere((event) => event.tick == 15)
              .sequencedNoteGroups
              .expand((group) => group.notes)
              .toList();

      expect(notes.where((note) => note.id == 'boundary-melody'), hasLength(1));
      expect(notes.where((note) => note.id.startsWith('strum_')), hasLength(3));
      for (final note in notes) {
        final availableWindowMs = (16 - note.startTick) * 125;
        final effectiveDurationMs =
            note.durationTicks * 125 + note.durationOffsetMs;
        expect(note.durationTicks, 1);
        expect(note.durationOffsetMs, lessThanOrEqualTo(0));
        expect(
          note.onsetOffsetMs + effectiveDurationMs,
          lessThanOrEqualTo(availableWindowMs),
        );
        expect(effectiveDurationMs, greaterThan(0));
      }
    });

    test('save block resolves embedded snapshot to per-bar stabs', () {
      final snap = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C4'),
        ],
        selectedNotes: const ['C'],
        viewMode: PianoViewMode.exact,
      );
      final block = SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        embedded: snap,
      );
      final lane = SongLane(
        id: 'l1',
        kind: SongLaneKind.save,
        order: 0,
        blocks: [block],
      );
      final section = SongSection(
        id: 's1',
        lengthBars: 1,
        order: 0,
        lanes: [lane],
      );
      final events = flattenPlaybackEvents(
        projectWith(sections: [section]),
        const [],
      );
      expect(events.single.tick, 0);
      expect(events.single.midiNotes, [60]);
    });

    test('events at the same tick merge midiNotes and drumLanes', () {
      const drumPattern = DrumPattern(
        id: 'p1',
        name: 'beat',
        lengthTicks: 16,
        lanes: [
          DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
        ],
      );
      const harmony = SongLane(
        id: 'l1',
        kind: SongLaneKind.harmony,
        order: 0,
        blocks: [
          SongBlock(id: 'b1', startBar: 0, spanBars: 1, chordNotes: ['C']),
        ],
      );
      const drums = SongLane(
        id: 'l2',
        kind: SongLaneKind.drum,
        order: 1,
        blocks: [
          SongBlock(id: 'b2', startBar: 0, spanBars: 1, patternId: 'p1'),
        ],
      );
      const section = SongSection(
        id: 's1',
        lengthBars: 1,
        order: 0,
        lanes: [harmony, drums],
      );
      final events = flattenPlaybackEvents(
        projectWith(sections: [section], drumPatterns: [drumPattern]),
        const [],
      );
      expect(events, hasLength(1));
      expect(events.single.midiNotes, isNotEmpty);
      expect(events.single.drumLanes, [DrumLaneId.kick]);
    });
  });
}
