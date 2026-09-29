import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setBlockPlacement moves/resizes; overlap is rejected', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 16);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.save)
        .id;
    n.addSaveBlock(
      sectionId: s,
      laneId: l,
      saveId: 'x',
      startBar: 0,
      spanBars: 2,
    );
    final bId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == l)
        .blocks
        .single
        .id;

    n.setBlockPlacement(
      sectionId: s,
      laneId: l,
      blockId: bId,
      startBar: 4,
      spanBars: 4,
    );
    final b = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == l)
        .blocks
        .single;
    expect(b.startBar, 4);
    expect(b.spanBars, 4);

    // Add a second block then try to overlap it onto the first — rejected.
    n.addSaveBlock(
      sectionId: s,
      laneId: l,
      saveId: 'y',
      startBar: 10,
      spanBars: 2,
    );
    final yId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == l)
        .blocks
        .firstWhere((blk) => blk.saveId == 'y')
        .id;
    n.setBlockPlacement(
      sectionId: s,
      laneId: l,
      blockId: yId,
      startBar: 4,
      spanBars: 2,
    );
    final y = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == l)
        .blocks
        .firstWhere((blk) => blk.saveId == 'y');
    expect(y.startBar, 10); // unchanged — overlap rejected

    n.setBlockPlacement(
      sectionId: s,
      laneId: l,
      blockId: yId,
      startBar: 15,
      spanBars: 2,
    );
    final outOfBounds = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == l)
        .blocks
        .firstWhere((block) => block.saveId == 'y');
    expect((outOfBounds.startBar, outOfBounds.spanBars), (10, 2));
  });

  test('new melody pattern placement expansion is atomic and undoable', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 6);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    final laneId = n.addLane(sectionId: sectionId, kind: SongLaneKind.melody);
    final patternId = n.addMelodyPattern(lengthTicks: 16);
    n.addMelodyBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 1,
    );
    final blockId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single
        .id;
    final before = c.read(songwriterProvider);
    final updated = c
        .read(songwriterProvider)
        .melodyPatterns
        .single
        .copyWith(
          lengthTicks: 48,
          notes: const [
            NotePatternNote(
              id: 'melody-note',
              midiNote: 72,
              startTick: 0,
              durationTicks: 2,
            ),
          ],
        );

    n.saveMelodyPattern(
      updated,
      initialPlacement: (
        sectionId: sectionId,
        laneId: laneId,
        blockId: blockId,
      ),
    );

    var block = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    expect(block.spanBars, 3);
    expect(c.read(songwriterProvider).melodyPatterns.single.lengthTicks, 48);
    expect(n.undo(), isTrue);
    block = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    expect(block.spanBars, 1);
    expect(c.read(songwriterProvider).melodyPatterns.single.lengthTicks, 16);
    expect(c.read(songwriterProvider).name, before.name);
  });

  test(
    'initial melody expansion rejects overlap and later edits do not resize reuse',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final laneId = n.addLane(sectionId: sectionId, kind: SongLaneKind.melody);
      final patternId = n.addMelodyPattern(lengthTicks: 16);
      n.addMelodyBlock(
        sectionId: sectionId,
        laneId: laneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 1,
      );
      n.addMelodyBlock(
        sectionId: sectionId,
        laneId: laneId,
        patternId: patternId,
        startBar: 2,
        spanBars: 1,
      );
      final blockId = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .first
          .id;
      final updated = c
          .read(songwriterProvider)
          .melodyPatterns
          .single
          .copyWith(
            lengthTicks: 48,
            notes: const [
              NotePatternNote(
                id: 'melody-note',
                midiNote: 72,
                startTick: 0,
                durationTicks: 2,
              ),
            ],
          );

      n.saveMelodyPattern(
        updated,
        initialPlacement: (
          sectionId: sectionId,
          laneId: laneId,
          blockId: blockId,
        ),
      );
      n.saveMelodyPattern(updated.copyWith(lengthTicks: 64));

      final lane = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((item) => item.id == laneId);
      final firstBlock = lane.blocks.firstWhere((block) => block.id == blockId);
      expect(firstBlock.spanBars, 1);
      expect(lane.blocks.map((block) => block.startBar), [0, 2]);
      final playedTicks = [
        for (final event in flattenPlaybackEvents(
          c.read(songwriterProvider),
          const [],
        ))
          for (final group in event.sequencedNoteGroups)
            for (final note in group.notes)
              if (note.id == 'melody-note') event.tick,
      ];
      expect(playedTicks, [0, 32]);
    },
  );

  test('initial melody expansion is bounded by section end', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    final laneId = n.addLane(sectionId: sectionId, kind: SongLaneKind.melody);
    final patternId = n.addMelodyPattern(lengthTicks: 16);
    n.addMelodyBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 3,
      spanBars: 1,
    );
    final blockId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single
        .id;

    n.saveMelodyPattern(
      c
          .read(songwriterProvider)
          .melodyPatterns
          .single
          .copyWith(lengthTicks: 32),
      initialPlacement: (
        sectionId: sectionId,
        laneId: laneId,
        blockId: blockId,
      ),
    );

    final block = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    expect((block.startBar, block.spanBars), (3, 1));
  });

  test(
    'moving and resizing a melody block preserves and retimes its pattern',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final laneId = n.addLane(sectionId: sectionId, kind: SongLaneKind.melody);
      final patternId = n.addMelodyPattern(lengthTicks: 4);
      const source = NotePattern(
        id: 'melody-pattern',
        name: 'Lead',
        lengthTicks: 4,
        notes: [
          NotePatternNote(
            id: 'first',
            midiNote: 72,
            startTick: 0,
            durationTicks: 2,
            onsetOffsetMs: 7,
          ),
          NotePatternNote(
            id: 'second',
            midiNote: 74,
            startTick: 3,
            durationTicks: 2,
            onsetOffsetMs: 11,
          ),
        ],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        snapTicks: 1,
        highlightedNotes: [],
      );
      n.updateMelodyPattern(source.copyWith(id: patternId));
      n.addMelodyBlock(
        sectionId: sectionId,
        laneId: laneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 1,
      );
      final blockId = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single
          .id;

      List<(int, int, int, int)> noteTimeline() => [
        for (final event in flattenPlaybackEvents(
          c.read(songwriterProvider),
          const [],
        ))
          for (final group in event.sequencedNoteGroups)
            for (final note in group.notes)
              (
                event.tick,
                note.midiNote,
                note.durationTicks,
                note.onsetOffsetMs,
              ),
      ];

      final before = noteTimeline();
      expect(before.map((note) => note.$1), [0, 3, 4, 7, 8, 11, 12, 15]);

      n.setBlockPlacement(
        sectionId: sectionId,
        laneId: laneId,
        blockId: blockId,
        startBar: 1,
        spanBars: 1,
      );
      final moved = noteTimeline();
      expect(moved, [
        for (final note in before) (note.$1 + 16, note.$2, note.$3, note.$4),
      ]);

      n.setBlockPlacement(
        sectionId: sectionId,
        laneId: laneId,
        blockId: blockId,
        startBar: 1,
        spanBars: 2,
      );
      final resized = noteTimeline();
      expect(resized.map((note) => note.$1), [
        16,
        19,
        20,
        23,
        24,
        27,
        28,
        31,
        32,
        35,
        36,
        39,
        40,
        43,
        44,
        47,
      ]);
      final savedPattern = c.read(songwriterProvider).melodyPatterns.single;
      expect(
        savedPattern.notes.map(
          (note) => (
            note.id,
            note.midiNote,
            note.startTick,
            note.durationTicks,
            note.onsetOffsetMs,
          ),
        ),
        [('first', 72, 0, 2, 7), ('second', 74, 3, 2, 11)],
      );
    },
  );

  test(
    'moving and resizing a strum block preserves and repeats its pattern',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final harmonyLaneId = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
          .id;
      n.addHarmonyBlock(
        sectionId: sectionId,
        laneId: harmonyLaneId,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 4,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G'],
        ),
      );
      final strumLaneId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.guitarStrum,
      );
      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: strumLaneId,
        harmonyLaneId: harmonyLaneId,
      );
      final patternId = n.addGuitarStrumPattern(lengthTicks: 4);
      n.updateGuitarStrumPattern(
        GuitarStrumPattern(
          id: patternId,
          name: 'Down-up',
          lengthTicks: 4,
          events: const [
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
            GuitarStrumEvent(tick: 3, direction: GuitarStrumDirection.up),
          ],
        ),
      );
      n.addGuitarStrumBlock(
        sectionId: sectionId,
        laneId: strumLaneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 1,
      );
      final blockId = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == strumLaneId)
          .blocks
          .single
          .id;

      List<int> strumTicks() => [
        for (final event in flattenPlaybackEvents(
          c.read(songwriterProvider),
          const [],
        ))
          if (event.sequencedNoteGroups.any(
            (group) => group.notes.any((note) => note.id.startsWith('strum_')),
          ))
            event.tick,
      ];

      expect(strumTicks(), [0, 3, 4, 7, 8, 11, 12, 15]);
      n.setBlockPlacement(
        sectionId: sectionId,
        laneId: strumLaneId,
        blockId: blockId,
        startBar: 1,
        spanBars: 2,
      );
      expect(strumTicks(), [
        16,
        19,
        20,
        23,
        24,
        27,
        28,
        31,
        32,
        35,
        36,
        39,
        40,
        43,
        44,
        47,
      ]);
      expect(
        c
            .read(songwriterProvider)
            .guitarStrumPatterns
            .single
            .events
            .map((event) => (event.tick, event.direction))
            .toList(),
        [(0, GuitarStrumDirection.down), (3, GuitarStrumDirection.up)],
      );
    },
  );
}
