import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';

void main() {
  group('chordMidiNotes', () {
    test('maps chordNotes pitch classes to an ascending stack from octave 4',
        () {
      const block = SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        chordNotes: ['G', 'B', 'D'],
      );
      // G4=67, B4=71, D above B -> D5=74.
      expect(chordMidiNotes(block), [67, 71, 74]);
    });

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
      int beatsPerBar = 4,
      int beatUnit = 4,
    }) =>
        SongwriterProjectSnapshot(
          config: SongwriterConfig(
            tempo: 120,
            beatsPerBar: beatsPerBar,
            beatUnit: beatUnit,
          ),
          sections: sections,
          drumPatterns: drumPatterns,
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
      const section =
          SongSection(id: 's1', lengthBars: 4, order: 0, lanes: [lane]);
      final events =
          flattenPlaybackEvents(projectWith(sections: [section]), const []);
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
      final events =
          flattenPlaybackEvents(projectWith(sections: [section]), const []);
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
      const section =
          SongSection(id: 's1', lengthBars: 2, order: 0, lanes: [lane]);
      final events =
          flattenPlaybackEvents(projectWith(sections: [section]), const []);
      expect(events.map((e) => e.tick).toList(), [16]); // bar 1 only
    });

    test('drum block fires pattern hits at native ticks, tiled to block span',
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
      const section =
          SongSection(id: 's1', lengthBars: 2, order: 0, lanes: [lane]);
      final events = flattenPlaybackEvents(
        projectWith(sections: [section], drumPatterns: [pattern]),
        const [],
      );
      expect(events.map((e) => e.tick).toList(), [0, 8, 16, 24]);
      expect(events.first.drumLanes, [DrumLaneId.kick]);
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
      final section =
          SongSection(id: 's1', lengthBars: 1, order: 0, lanes: [lane]);
      final events =
          flattenPlaybackEvents(projectWith(sections: [section]), const []);
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
