import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  group('Writer Harmony eligibility', () {
    FretboardSnapshot fretboard({
      FretboardInputMode inputMode = FretboardInputMode.chord,
      List<FretCoordinate>? selectedCells,
    }) => FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells:
          selectedCells ??
          const [
            FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
            FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
            FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
          ],
      selectedNotes: const ['C', 'E', 'G'],
      viewMode: FretboardViewMode.exact,
      inputMode: inputMode,
    );

    PianoSnapshot piano({List<int> midiNotes = const [60, 64, 67]}) =>
        PianoSnapshot(
          currentRange: PianoRangeName.key88,
          selectedKeys: [
            for (final midi in midiNotes)
              PianoCoordinate(
                keyIndex: midi - 21,
                midiNote: midi,
                noteName: 'C',
              ),
          ],
          selectedNotes: const ['C', 'E', 'G'],
          viewMode: PianoViewMode.exact,
        );

    test('accepts non-empty Piano and Chord-mode Fretboard selections', () {
      expect(isWriterEligibleNativeSelection(piano()), isTrue);
      expect(isWriterEligibleNativeSelection(fretboard()), isTrue);
    });

    test('rejects empty, duplicate, and out-of-range Piano selections', () {
      expect(
        isWriterEligibleNativeSelection(piano(midiNotes: const [])),
        isFalse,
      );
      expect(
        isWriterEligibleNativeSelection(piano(midiNotes: const [60, 60])),
        isFalse,
      );
      expect(
        isWriterEligibleNativeSelection(piano(midiNotes: const [20])),
        isFalse,
      );
    });

    test(
      'rejects Free, repeated-string, empty, and out-of-bounds Fretboard',
      () {
        expect(
          isWriterEligibleNativeSelection(
            fretboard(inputMode: FretboardInputMode.free),
          ),
          isFalse,
        );
        expect(
          isWriterEligibleNativeSelection(
            fretboard(
              selectedCells: const [
                FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
                FretCoordinate(stringIndex: 0, fret: 1, noteName: 'F'),
              ],
            ),
          ),
          isFalse,
        );
        expect(
          isWriterEligibleNativeSelection(fretboard(selectedCells: const [])),
          isFalse,
        );
        expect(
          isWriterEligibleNativeSelection(
            fretboard(
              selectedCells: const [
                FretCoordinate(stringIndex: 0, fret: 13, noteName: 'F'),
              ],
            ),
          ),
          isFalse,
        );
      },
    );

    test('exact Harmony has a label and notes but no symbolic identity', () {
      final exact = WriterBlockSnapshot(
        laneKind: SongLaneKind.harmony,
        chordSymbol: 'Cluster',
        chordNotes: const ['C', 'E', 'G'],
      );
      expect(hasHarmonyContent(exact), isTrue);
      expect(
        hasHarmonyContent(
          const WriterBlockSnapshot(
            laneKind: SongLaneKind.harmony,
            chordSymbol: 'Cluster',
            chordNotes: ['C', 'E', 'G'],
            romanNumeral: 'I',
          ),
        ),
        isFalse,
      );
      expect(
        hasHarmonyContent(
          const WriterBlockSnapshot(
            laneKind: SongLaneKind.harmony,
            chordSymbol: 'Cluster',
            chordNotes: ['C', 'E', 'G'],
            chordRootPc: 0,
          ),
        ),
        isFalse,
      );
      expect(
        hasHarmonyBlockContent(
          const SongBlock(
            id: 'exact',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'Cluster',
            chordNotes: ['C', 'E', 'G'],
          ),
        ),
        isTrue,
      );
    });

    test('Harmony composites never infer exact identity from native notes', () {
      final native = PianoSnapshot(
        currentRange: PianoRangeName.key88,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 39, midiNote: 60, noteName: 'C'),
          PianoCoordinate(keyIndex: 43, midiNote: 64, noteName: 'E'),
          PianoCoordinate(keyIndex: 46, midiNote: 67, noteName: 'G'),
        ],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: PianoViewMode.exact,
        pendingChord: const PendingChord(root: 'C', quality: '', symbol: 'C'),
      );
      final exact = HarmonyChordSnapshot(
        harmonyInstrument: HarmonyLaneInstrument.piano,
        writerBlock: const WriterBlockSnapshot(
          laneKind: SongLaneKind.harmony,
          chordSymbol: 'C shape',
          chordNotes: ['C', 'E', 'G'],
        ),
        instrumentState: native,
      );
      final recognized = HarmonyChordSnapshot(
        harmonyInstrument: HarmonyLaneInstrument.piano,
        writerBlock: const WriterBlockSnapshot(
          laneKind: SongLaneKind.harmony,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
        ),
        instrumentState: native,
      );

      expect(resolveSnapshotChord(exact), isNull);
      expect(resolveSnapshotChord(recognized)?.rootPc, 0);
    });
  });

  group('diatonic chord wheel capability', () {
    test('requires exactly seven scale degrees', () {
      for (final scale in [
        'major pentatonic',
        'minor pentatonic',
        'blues',
        'whole tone',
        'diminished',
        'unknown scale',
      ]) {
        expect(
          diatonicTriads(3, scale),
          isEmpty,
          reason: '$scale cannot fill the seven-wedge wheel',
        );
      }
    });

    test('seven-degree scales keep all seven derived triads', () {
      for (final scale in ['major', 'minor', 'dorian', 'mixolydian']) {
        expect(
          diatonicTriads(0, scale),
          hasLength(7),
          reason: '$scale has seven degrees',
        );
      }

      expect(diatonicTriads(0, 'major').map((triad) => triad.symbol), [
        'C',
        'Dm',
        'Em',
        'F',
        'G',
        'Am',
        'Bdim',
      ]);
      expect(diatonicTriads(0, 'major').map((triad) => triad.romanNumeral), [
        'I',
        'ii',
        'iii',
        'IV',
        'V',
        'vi',
        'vii°',
      ]);
    });
  });

  group('saveAnchorLane', () {
    const primary = SongLane(
      id: 'primary',
      kind: SongLaneKind.harmony,
      order: 0,
    );
    const secondary = SongLane(
      id: 'secondary',
      kind: SongLaneKind.harmony,
      order: 1,
    );
    const legacySave = SongLane(
      id: 'legacy-save',
      kind: SongLaneKind.save,
      order: 2,
    );
    const secondarySave = SongLane(
      id: 'secondary-save',
      kind: SongLaneKind.save,
      order: 3,
      anchorLaneId: 'secondary',
    );
    const staleSave = SongLane(
      id: 'stale-save',
      kind: SongLaneKind.save,
      order: 4,
      anchorLaneId: 'deleted-harmony',
    );
    const section = SongSection(
      id: 'section',
      lengthBars: 4,
      order: 0,
      lanes: [primary, secondary, legacySave, secondarySave, staleSave],
    );

    test(
      'null anchor resolves to primary and valid explicit anchor resolves',
      () {
        expect(saveAnchorLane(section, legacySave), same(primary));
        expect(saveAnchorLane(section, secondarySave), same(secondary));
      },
    );

    test(
      'stale explicit anchor remains unresolved and save lane keeps its mix',
      () {
        expect(saveAnchorLane(section, staleSave), isNull);
        expect(mixGoverningLane(section, staleSave), same(staleSave));
      },
    );

    test('legacy save lane has no resolved harmony when section has none', () {
      const sectionWithoutHarmony = SongSection(
        id: 'empty',
        lengthBars: 4,
        order: 0,
        lanes: [legacySave],
      );
      expect(saveAnchorLane(sectionWithoutHarmony, legacySave), isNull);
    });
  });

  group('harmony lane factories', () {
    test(
      'makeSection seeds its primary harmony lane with the selected instrument',
      () {
        final defaultSection = makeSection(
          id: 'stable-section',
          lengthBars: 4,
          order: 0,
        );
        expect(defaultSection.id, 'stable-section');
        expect(defaultSection.lanes, hasLength(1));
        expect(defaultSection.lanes.single.kind, SongLaneKind.harmony);
        expect(
          defaultSection.lanes.single.harmonyInstrument,
          HarmonyLaneInstrument.fretboard,
        );

        final pianoSection = makeSection(
          lengthBars: 4,
          order: 1,
          harmonyInstrument: HarmonyLaneInstrument.piano,
        );
        expect(
          pianoSection.lanes.single.harmonyInstrument,
          HarmonyLaneInstrument.piano,
        );
      },
    );

    test('makeLane injects instrument metadata only for harmony lanes', () {
      final harmony = makeLane(
        kind: SongLaneKind.harmony,
        order: 0,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      final drum = makeLane(
        kind: SongLaneKind.drum,
        order: 1,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      expect(harmony.harmonyInstrument, HarmonyLaneInstrument.piano);
      expect(drum.harmonyInstrument, isNull);
    });
  });

  group('legacy guitar-strum anchor migration', () {
    SongwriterProjectSnapshot legacy({required List<SongLane> lanes}) =>
        SongwriterProjectSnapshot.fromJson({
          'type': 'songwriter',
          'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
          'sections': [
            {
              'id': 'section',
              'lengthBars': 4,
              'order': 0,
              'lanes': lanes.map((lane) => lane.toJson()).toList(),
            },
          ],
        });

    const primary = SongLane(
      id: 'primary',
      kind: SongLaneKind.harmony,
      order: 0,
    );
    const strum = SongLane(
      id: 'strum',
      kind: SongLaneKind.guitarStrum,
      order: 1,
    );

    test('pins legacy null anchor to a Fretboard primary exactly once', () {
      final old = legacy(lanes: const [primary, strum]);
      final migrated = migrateLegacyStrumAnchors(
        old,
        projectDefault: HarmonyLaneInstrument.fretboard,
      );
      expect(migrated.sections.single.lanes.last.anchorLaneId, 'primary');
      expect(
        migrated.strumAnchorMigrationVersion,
        strumAnchorMigrationCurrentVersion,
      );

      final later = migrated.copyWith(
        sections: [
          migrated.sections.single.copyWith(
            lanes: [
              ...migrated.sections.single.lanes,
              const SongLane(
                id: 'later-guitar',
                kind: SongLaneKind.harmony,
                order: 2,
                harmonyInstrument: HarmonyLaneInstrument.fretboard,
              ),
            ],
          ),
        ],
      );
      expect(
        migrateLegacyStrumAnchors(
          later,
          projectDefault: HarmonyLaneInstrument.fretboard,
        ).sections.single.lanes[1].anchorLaneId,
        'primary',
      );
    });

    test('does not choose a secondary guitar when primary is Piano', () {
      final old = legacy(
        lanes: const [
          SongLane(
            id: 'primary',
            kind: SongLaneKind.harmony,
            order: 0,
            harmonyInstrument: HarmonyLaneInstrument.piano,
          ),
          SongLane(
            id: 'guitar',
            kind: SongLaneKind.harmony,
            order: 1,
            harmonyInstrument: HarmonyLaneInstrument.fretboard,
          ),
          strum,
        ],
      );
      final migrated = migrateLegacyStrumAnchors(
        old,
        projectDefault: HarmonyLaneInstrument.fretboard,
      );
      expect(migrated.sections.single.lanes.last.anchorLaneId, isNull);
    });

    test('marks no-source snapshots so later guitar lanes stay unassigned', () {
      final old = legacy(
        lanes: const [
          SongLane(
            id: 'primary',
            kind: SongLaneKind.harmony,
            order: 0,
            harmonyInstrument: HarmonyLaneInstrument.piano,
          ),
          strum,
        ],
      );
      final migrated = migrateLegacyStrumAnchors(
        old,
        projectDefault: HarmonyLaneInstrument.fretboard,
      );
      final withLaterGuitar = migrated.copyWith(
        sections: [
          migrated.sections.single.copyWith(
            lanes: [
              ...migrated.sections.single.lanes,
              const SongLane(
                id: 'guitar',
                kind: SongLaneKind.harmony,
                order: 2,
                harmonyInstrument: HarmonyLaneInstrument.fretboard,
              ),
            ],
          ),
        ],
      );
      final reopened = SongwriterProjectSnapshot.fromJson(
        withLaterGuitar.toJson(),
      );
      expect(
        migrateLegacyStrumAnchors(
          reopened,
          projectDefault: HarmonyLaneInstrument.fretboard,
        ).sections.single.lanes[1].anchorLaneId,
        isNull,
      );
    });
  });

  group('Guitar Strum Harmony source availability', () {
    const projectDefault = HarmonyLaneInstrument.fretboard;

    test(
      'hides sources used by another lane but retains the current source',
      () {
        const primary = SongLane(
          id: 'primary',
          kind: SongLaneKind.harmony,
          order: 0,
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
        );
        const secondary = SongLane(
          id: 'secondary',
          kind: SongLaneKind.harmony,
          order: 1,
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
        );
        const firstStrum = SongLane(
          id: 'first-strum',
          kind: SongLaneKind.guitarStrum,
          order: 2,
          anchorLaneId: 'primary',
        );
        const secondStrum = SongLane(
          id: 'second-strum',
          kind: SongLaneKind.guitarStrum,
          order: 3,
          anchorLaneId: 'secondary',
        );
        const section = SongSection(
          id: 'section',
          lengthBars: 4,
          order: 0,
          lanes: [primary, secondary, firstStrum, secondStrum],
        );

        expect(
          availableGuitarStrumHarmonyLanes(
            section,
            projectDefault: projectDefault,
            excludingLaneId: firstStrum.id,
          ).map((lane) => lane.id),
          ['primary'],
        );
        expect(
          availableGuitarStrumHarmonyLanes(
            section,
            projectDefault: projectDefault,
            excludingLaneId: secondStrum.id,
          ).map((lane) => lane.id),
          ['secondary'],
        );
      },
    );

    test('Unassigned, stale and Piano anchors reserve no Fretboard source', () {
      const fretboard = SongLane(
        id: 'fretboard',
        kind: SongLaneKind.harmony,
        order: 0,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      const piano = SongLane(
        id: 'piano',
        kind: SongLaneKind.harmony,
        order: 1,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      const unassignedA = SongLane(
        id: 'unassigned-a',
        kind: SongLaneKind.guitarStrum,
        order: 2,
      );
      const unassignedB = SongLane(
        id: 'unassigned-b',
        kind: SongLaneKind.guitarStrum,
        order: 3,
      );
      const stale = SongLane(
        id: 'stale',
        kind: SongLaneKind.guitarStrum,
        order: 4,
        anchorLaneId: 'deleted',
      );
      const pianoAnchored = SongLane(
        id: 'piano-anchored',
        kind: SongLaneKind.guitarStrum,
        order: 5,
        anchorLaneId: 'piano',
      );
      const section = SongSection(
        id: 'section',
        lengthBars: 4,
        order: 0,
        lanes: [
          fretboard,
          piano,
          unassignedA,
          unassignedB,
          stale,
          pianoAnchored,
        ],
      );

      expect(
        availableGuitarStrumHarmonyLanes(
          section,
          projectDefault: projectDefault,
        ).map((lane) => lane.id),
        ['fretboard'],
      );
      expect(
        hasUniqueGuitarStrumHarmonyAnchors(
          section,
          projectDefault: projectDefault,
        ),
        isTrue,
      );
    });

    test(
      'availability is scoped to the section and detects duplicate anchors',
      () {
        const source = SongLane(
          id: 'source',
          kind: SongLaneKind.harmony,
          order: 0,
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
        );
        const assigned = SongLane(
          id: 'assigned',
          kind: SongLaneKind.guitarStrum,
          order: 1,
          anchorLaneId: 'source',
        );
        const unassigned = SongLane(
          id: 'unassigned',
          kind: SongLaneKind.guitarStrum,
          order: 2,
        );
        const firstSection = SongSection(
          id: 'first',
          lengthBars: 4,
          order: 0,
          lanes: [source, assigned],
        );
        const secondSection = SongSection(
          id: 'second',
          lengthBars: 4,
          order: 1,
          lanes: [source, unassigned],
        );

        expect(
          availableGuitarStrumHarmonyLanes(
            firstSection,
            projectDefault: projectDefault,
            excludingLaneId: assigned.id,
          ).map((lane) => lane.id),
          ['source'],
        );
        expect(
          availableGuitarStrumHarmonyLanes(
            secondSection,
            projectDefault: projectDefault,
          ).map((lane) => lane.id),
          ['source'],
        );
        expect(
          hasUniqueGuitarStrumHarmonyAnchors(
            firstSection.copyWith(
              lanes: [
                ...firstSection.lanes,
                const SongLane(
                  id: 'duplicate',
                  kind: SongLaneKind.guitarStrum,
                  order: 3,
                  anchorLaneId: 'source',
                ),
              ],
            ),
            projectDefault: projectDefault,
          ),
          isFalse,
        );
      },
    );
  });

  group('Writer melody bar-aligned length', () {
    const measureTicks = 16;

    NotePattern melody({
      String name = 'Lead',
      int lengthTicks = 16,
      List<NotePatternNote> notes = const [],
    }) => NotePattern(
      id: 'melody',
      name: name,
      lengthTicks: lengthTicks,
      notes: notes,
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 1,
      highlightedNotes: const [],
    );

    test('empty melodies occupy one bar', () {
      expect(melodyBarCount(melody(), measureTicks), 1);
      expect(
        quantizeMelodyPatternLength(
          melody(lengthTicks: 48),
          measureTicks,
        ).lengthTicks,
        measureTicks,
      );
    });

    test('a note ending exactly on a barline keeps that bar', () {
      final pattern = melody(
        notes: const [
          NotePatternNote(
            id: 'note',
            midiNote: 60,
            startTick: 8,
            durationTicks: 8,
          ),
        ],
      );
      expect(melodyBarCount(pattern, measureTicks), 1);
      expect(
        quantizeMelodyPatternLength(pattern, measureTicks).lengthTicks,
        measureTicks,
      );
    });

    test('a note ending one tick into a bar adds the next bar', () {
      final pattern = melody(
        notes: const [
          NotePatternNote(
            id: 'note',
            midiNote: 60,
            startTick: 15,
            durationTicks: 2,
          ),
        ],
      );
      expect(melodyBarCount(pattern, measureTicks), 2);
      expect(
        quantizeMelodyPatternLength(pattern, measureTicks).lengthTicks,
        2 * measureTicks,
      );
    });

    test('bar counts cap at the editor maximum of 32 bars', () {
      final pattern = melody(
        notes: const [
          NotePatternNote(
            id: 'note',
            midiNote: 60,
            startTick: 32 * measureTicks,
            durationTicks: 1,
          ),
        ],
      );
      expect(melodyBarCount(pattern, measureTicks), 32);
      expect(
        quantizeMelodyPatternLength(pattern, measureTicks).lengthTicks,
        32 * measureTicks,
      );
    });

    test('quantizing changes only the length', () {
      final pattern = melody(
        name: 'Verse motif',
        lengthTicks: 20,
        notes: const [
          NotePatternNote(
            id: 'a',
            midiNote: 64,
            startTick: 4,
            durationTicks: 16,
            onsetOffsetMs: 12,
            durationOffsetMs: -4,
          ),
        ],
      ).copyWith(pitchRangeStart: 40, pitchRangeEnd: 90, snapTicks: 2);
      final highlighted = pattern.copyWith(
        highlightedNotes: const ['C', 'E', 'G'],
      );
      final quantized = quantizeMelodyPatternLength(highlighted, measureTicks);
      expect(quantized.lengthTicks, 2 * measureTicks);
      expect(quantized.id, highlighted.id);
      expect(quantized.name, highlighted.name);
      expect(quantized.notes, highlighted.notes);
      expect(quantized.pitchRangeStart, highlighted.pitchRangeStart);
      expect(quantized.pitchRangeEnd, highlighted.pitchRangeEnd);
      expect(quantized.snapTicks, highlighted.snapTicks);
      expect(quantized.highlightedNotes, highlighted.highlightedNotes);
    });
  });
}
