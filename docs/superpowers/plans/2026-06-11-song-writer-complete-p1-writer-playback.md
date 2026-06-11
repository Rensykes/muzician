# Phase 1 — Writer Playback Engine + Sheet Playhead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Writer playback audible — harmony chords, save-block voicings, and drum lanes all sound during transport — and show a playhead highlight in the sheet UI.

**Architecture:** A new pure rules file flattens the songwriter project (sections × repeats × lane tiling) into a sorted tick-indexed event list. `SongwriterPlaybackNotifier` (already a 16th-note tick clock) walks that list and fires injectable sinks: a new chord/note sink (`NotePlayer.previewNote` per pitch) and the existing `drumPatternPlaybackSinkProvider`. A derived provider maps the playback bar back to (sectionId, instanceIndex, localBar) for the sheet highlight.

**Tech Stack:** Flutter, Riverpod `Notifier`, `package:test`/`flutter_test`. Spec: `docs/superpowers/specs/2026-06-11-song-writer-complete-design.md` §1–2.

**Key existing facts (verified):**
- Tick conventions: `beatTicks = beatUnit == 8 ? 2 : 4`, `measureTicks = beatTicks * beatsPerBar` (`songwriter_playback_store.dart:71-72`). Tick = 16th note for quarter beat unit — same resolution as `DrumPattern.lanes[].activeTicks`.
- `expandSections` / `sectionAtGlobalBar` / `tileLaneBlocks` / `resolveBlockSnapshot` in `lib/schema/rules/songwriter_rules.dart:233-330`.
- `chordIntervals` map keys: `''`, `'m'`, `'7'`, `'maj7'`, `'m7'`, `'dim'`, `'aug'`, `'5'`, `'sus2'`, `'sus4'`, `'m7b5'`, `'add9'`, `'maj9'`, `'6'`, `'m6'`, `'dim7'`, `'7sus4'` (`lib/utils/note_utils.dart:126`). `noteToPC` map (`note_utils.dart:40`).
- `PianoCoordinate.midiNote` direct; fretboard midi = `tunings[snapshot.tuning].strings[cell.stringIndex].midiNote + cell.fret` (`fretboard_rules.dart:51`).
- `NotePlayer.instance.previewNote(int midiNote, {double volume})` (`note_player.dart:273`).
- Drum sink: `typedef DrumPatternPlaybackSink = Future<void> Function(List<DrumLaneId> lanes, double volume)`; provider `drumPatternPlaybackSinkProvider` (`drum_pattern_playback_store.dart:15-20`).
- `SongBlock`: `chordNotes List<String>` (pitch classes), `chordRootPc`, `chordQuality`, `patternId` (drum), `isSilent`, `saveId`/`embedded`.
- Saves: `ref.read(saveSystemProvider).saves` (`List<SaveEntry>`).

---

### Task 1: Playback event model + chord/snapshot pitch resolution

**Files:**
- Create: `lib/schema/rules/songwriter_playback_rules.dart`
- Test: `test/schema/rules/songwriter_playback_rules_test.dart`

- [ ] **Step 1: Write failing tests for `chordMidiNotes` and `snapshotMidiNotes`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
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

    test('returns empty for silent / chord-less blocks', () {
      const block = SongBlock(id: 'b1', startBar: 0, spanBars: 1);
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

    test('null / non-instrument snapshots yield empty', () {
      expect(snapshotMidiNotes(null), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL (file missing)**

Run: `flutter test test/schema/rules/songwriter_playback_rules_test.dart`
Expected: compile error, `songwriter_playback_rules.dart` not found.

- [ ] **Step 3: Implement the rules file (event class + pitch helpers)**

```dart
/// Pure playback flattening for the Songwriter transport.
///
/// Turns a [SongwriterProjectSnapshot] into a sorted, tick-indexed event list
/// the transport can walk: harmony chords and save-block voicings fire as
/// per-bar stabs; drum lane blocks fire their pattern hits at native tick
/// resolution.
library;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';
import 'fretboard_rules.dart';
import 'songwriter_rules.dart';

/// One audible moment on the flattened songwriter timeline.
class SongwriterPlaybackEvent {
  const SongwriterPlaybackEvent({
    required this.tick,
    this.midiNotes = const [],
    this.drumLanes = const [],
  });

  final int tick;
  final List<int> midiNotes;
  final List<DrumLaneId> drumLanes;
}

/// Midi pitches for a harmony block as an ascending stack from octave 4.
///
/// Uses [SongBlock.chordNotes] (pitch-class names, root first) when present;
/// falls back to [SongBlock.chordRootPc] + [SongBlock.chordQuality] intervals.
/// Returns empty for silent / chord-less blocks.
List<int> chordMidiNotes(SongBlock block) {
  if (block.isSilent) return const [];
  if (block.chordNotes.isNotEmpty) {
    final pcs = <int>[];
    for (final name in block.chordNotes) {
      final pc = noteToPC[name];
      if (pc != null) pcs.add(pc);
    }
    if (pcs.isNotEmpty) return _ascendingStack(pcs);
  }
  final rootPc = block.chordRootPc;
  if (rootPc == null) return const [];
  final intervals = chordIntervals[block.chordQuality ?? ''] ?? const [0, 4, 7];
  return [for (final i in intervals) 60 + rootPc + i];
}

/// Stacks pitch classes upward starting at octave 4 (midi 60..71 for the
/// first note); each subsequent note lands at the next pitch above its
/// predecessor.
List<int> _ascendingStack(List<int> pcs) {
  final out = <int>[60 + pcs.first];
  for (var i = 1; i < pcs.length; i++) {
    var midi = 60 + pcs[i];
    while (midi <= out.last) {
      midi += 12;
    }
    out.add(midi);
  }
  return out;
}

/// Midi pitches for a save-block snapshot, sorted ascending.
///
/// Piano snapshots read [PianoCoordinate.midiNote]; fretboard snapshots map
/// string+fret through the tuning's open-string midi. Other snapshot types
/// (and broken blocks resolved to null) are silent.
List<int> snapshotMidiNotes(InstrumentSnapshot? snapshot) {
  if (snapshot is PianoSnapshot) {
    return [for (final k in snapshot.selectedKeys) k.midiNote]..sort();
  }
  if (snapshot is FretboardSnapshot) {
    final tuning = tunings[snapshot.tuning];
    if (tuning == null) return const [];
    final out = <int>[];
    for (final cell in snapshot.selectedCells) {
      if (cell.stringIndex < 0 || cell.stringIndex >= tuning.strings.length) {
        continue;
      }
      out.add(tuning.strings[cell.stringIndex].midiNote + cell.fret);
    }
    return out..sort();
  }
  return const [];
}
```

(`flattenPlaybackEvents` comes in Task 2 — same file.)

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/schema/rules/songwriter_playback_rules_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_playback_rules.dart test/schema/rules/songwriter_playback_rules_test.dart
git commit -m "feat(songwriter): chord + snapshot midi pitch resolution rules"
```

---

### Task 2: `flattenPlaybackEvents`

**Files:**
- Modify: `lib/schema/rules/songwriter_playback_rules.dart`
- Test: `test/schema/rules/songwriter_playback_rules_test.dart`

- [ ] **Step 1: Write failing tests**

Append to the existing test file (add imports `package:muzician/schema/rules/songwriter_rules.dart` if factories are used):

```dart
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
```

- [ ] **Step 2: Run — expect FAIL (`flattenPlaybackEvents` undefined)**

Run: `flutter test test/schema/rules/songwriter_playback_rules_test.dart`

- [ ] **Step 3: Implement `flattenPlaybackEvents`**

Append to `lib/schema/rules/songwriter_playback_rules.dart`:

```dart
/// Flattens [project] into a sorted, tick-indexed event list.
///
/// Sections expand by repeat (via [expandSections]); lane block patterns tile
/// by lane repeat (via [tileLaneBlocks]). Harmony and save blocks fire their
/// pitches at the block's start bar and every later bar boundary inside the
/// block (clipped to the section); drum blocks fire their referenced
/// [DrumPattern] hits at native tick resolution, tiled across the block span.
/// Events sharing a tick are merged.
List<SongwriterPlaybackEvent> flattenPlaybackEvents(
  SongwriterProjectSnapshot project,
  List<SaveEntry> saves,
) {
  final cfg = project.config;
  final beatTicks = cfg.beatUnit == 8 ? 2 : 4;
  final measureTicks = beatTicks * cfg.beatsPerBar;

  final byId = {for (final s in project.sections) s.id: s};
  final patterns = {for (final p in project.drumPatterns) p.id: p};
  final notesAt = <int, List<int>>{};
  final drumsAt = <int, Set<DrumLaneId>>{};

  for (final exp in expandSections(project.sections)) {
    final section = byId[exp.sectionId];
    if (section == null) continue;
    for (final lane in section.lanes) {
      final blocks = tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      );
      for (final block in blocks) {
        final clippedEnd = block.endBar > section.lengthBars
            ? section.lengthBars
            : block.endBar;
        switch (lane.kind) {
          case SongLaneKind.harmony:
          case SongLaneKind.save:
            final pitches = lane.kind == SongLaneKind.harmony
                ? chordMidiNotes(block)
                : snapshotMidiNotes(resolveBlockSnapshot(block, saves));
            if (pitches.isEmpty) break;
            for (var bar = block.startBar; bar < clippedEnd; bar++) {
              final tick = (exp.globalStartBar + bar) * measureTicks;
              (notesAt[tick] ??= []).addAll(pitches);
            }
          case SongLaneKind.drum:
            final pattern = patterns[block.patternId];
            if (pattern == null || pattern.lengthTicks <= 0) break;
            final startTick =
                (exp.globalStartBar + block.startBar) * measureTicks;
            final endTick = (exp.globalStartBar + clippedEnd) * measureTicks;
            for (var origin = 0;
                startTick + origin < endTick;
                origin += pattern.lengthTicks) {
              for (final seq in pattern.lanes) {
                for (final t in seq.activeTicks) {
                  final tick = startTick + origin + t;
                  if (tick >= endTick) continue;
                  (drumsAt[tick] ??= {}).add(seq.laneId);
                }
              }
            }
        }
      }
    }
  }

  final ticks = {...notesAt.keys, ...drumsAt.keys}.toList()..sort();
  return [
    for (final tick in ticks)
      SongwriterPlaybackEvent(
        tick: tick,
        midiNotes: notesAt[tick] ?? const [],
        drumLanes: drumsAt[tick]?.toList() ?? const [],
      ),
  ];
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/schema/rules/songwriter_playback_rules_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_playback_rules.dart test/schema/rules/songwriter_playback_rules_test.dart
git commit -m "feat(songwriter): flattenPlaybackEvents — full-project audible event list"
```

---

### Task 3: Wire events into `SongwriterPlaybackNotifier`

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_playback_store_test.dart` (extend existing if present, else create)

- [ ] **Step 1: Write failing test**

The transport test overrides sinks and runs with `tickDurationOverride: Duration.zero`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startPlayback fires chord and drum sinks from flattened events',
      () async {
    final chordCalls = <List<int>>[];
    final drumCalls = <List<DrumLaneId>>[];

    final container = ProviderContainer(
      overrides: [
        songwriterNoteSinkProvider.overrideWithValue(
          (notes) => chordCalls.add(notes),
        ),
        drumPatternPlaybackSinkProvider.overrideWithValue(
          (lanes, volume) async => drumCalls.add(lanes),
        ),
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(container.dispose);

    // Build a 1-section project: harmony C at bar 0 + kick at tick 0/8.
    final notifier = container.read(songwriterProvider.notifier);
    notifier.loadProject(
      SongwriterProjectSnapshot(
        config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        sections: const [
          SongSection(
            id: 's1',
            lengthBars: 1,
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
                    spanBars: 1,
                    chordNotes: ['C', 'E', 'G'],
                  ),
                ],
              ),
              SongLane(
                id: 'l2',
                kind: SongLaneKind.drum,
                order: 1,
                blocks: [
                  SongBlock(
                    id: 'b2',
                    startBar: 0,
                    spanBars: 1,
                    patternId: 'p1',
                  ),
                ],
              ),
            ],
          ),
        ],
        drumPatterns: const [
          DrumPattern(
            id: 'p1',
            name: 'beat',
            lengthTicks: 16,
            lanes: [
              DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
            ],
          ),
        ],
      ),
    );

    await container
        .read(songwriterPlaybackProvider.notifier)
        .startPlayback(tickDurationOverride: Duration.zero);

    expect(chordCalls, [
      [60, 64, 67],
    ]);
    expect(drumCalls, [
      [DrumLaneId.kick],
      [DrumLaneId.kick],
    ]);
  });
}
```

Note: if `songwriterProvider`'s `build()` requires save-system hydration, follow the override pattern used by the existing songwriter store tests (check `test/store/` for prior art and reuse their setup).

- [ ] **Step 2: Run — expect FAIL (`songwriterNoteSinkProvider` undefined)**

Run: `flutter test test/store/songwriter_playback_store_test.dart`

- [ ] **Step 3: Implement store wiring**

In `lib/store/songwriter_playback_store.dart`:

1. Update the library doc comment (blocks are audible now).
2. Add imports: `../schema/rules/songwriter_playback_rules.dart`, `../models/save_system.dart` (if needed for types), `drum_pattern_playback_store.dart`, `save_system_store.dart`.
3. Add the note sink:

```dart
/// Sink that sounds a chord / voicing stab. Override in tests.
typedef SongwriterNoteSink = void Function(List<int> midiNotes);

final songwriterNoteSinkProvider = Provider<SongwriterNoteSink>((ref) {
  return (midiNotes) {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6);
    }
  };
});
```

4. In `startPlayback`, after reading providers:

```dart
    final noteSink = ref.read(songwriterNoteSinkProvider);
    final drumSink = ref.read(drumPatternPlaybackSinkProvider);
    final saves = ref.read(saveSystemProvider).saves;
    final events = flattenPlaybackEvents(project, saves);
```

5. Inside the tick loop, after the metronome block, fire events (keep an
   `eventIndex` cursor declared before the loop — events are tick-sorted):

```dart
      while (eventIndex < events.length && events[eventIndex].tick == tick) {
        final event = events[eventIndex];
        eventIndex++;
        if (event.midiNotes.isNotEmpty) noteSink(event.midiNotes);
        if (event.drumLanes.isNotEmpty) {
          unawaited(drumSink(event.drumLanes, 0.8));
        }
      }
```

- [ ] **Step 4: Run — expect PASS; run full suite**

Run: `flutter test test/store/songwriter_playback_store_test.dart && flutter test`
Expected: new test passes; no regressions.

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_playback_store.dart test/store/songwriter_playback_store_test.dart
git commit -m "feat(songwriter): audible playback — chord, voicing and drum events drive sinks"
```

---

### Task 4: Active-position provider for the sheet playhead

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_playback_store_test.dart`

- [ ] **Step 1: Write failing test**

```dart
  test('songwriterActivePositionProvider maps currentBar to section instance',
      () async {
    final container = ProviderContainer(overrides: [/* sinks as above */]);
    addTearDown(container.dispose);
    // Project: section s1 lengthBars 2 repeat 2 -> global bars 0..3.
    // (loadProject as in the previous test, no lanes needed)
    // Simulate playback state at bar 3 (= s1 instance 1, local bar 1).
    // Drive via startPlayback with Duration.zero and capture during run is
    // racy — instead test the pure mapping helper:
    final pos = activePositionForBar(
      [
        const SongSection(id: 's1', lengthBars: 2, order: 0, repeat: 2),
      ],
      3,
    );
    expect(pos, isNotNull);
    expect(pos!.sectionId, 's1');
    expect(pos.instanceIndex, 1);
    expect(pos.localBar, 1);
  });
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

In `songwriter_playback_store.dart` (or the rules file — rules file preferred, it's pure):

```dart
/// Where the playhead sits inside the sheet layout.
class SongwriterActivePosition {
  const SongwriterActivePosition({
    required this.sectionId,
    required this.instanceIndex,
    required this.localBar,
  });
  final String sectionId;
  final int instanceIndex;
  final int localBar;
}

/// Maps a global playback bar to (sectionId, instanceIndex, localBar).
SongwriterActivePosition? activePositionForBar(
  List<SongSection> sections,
  int globalBar,
) {
  final hit = sectionAtGlobalBar(expandSections(sections), globalBar);
  if (hit == null) return null;
  return SongwriterActivePosition(
    sectionId: hit.section.sectionId,
    instanceIndex: hit.section.repeatIndex,
    localBar: hit.localBar,
  );
}
```

And the derived provider in the store file:

```dart
final songwriterActivePositionProvider = Provider<SongwriterActivePosition?>((
  ref,
) {
  final playback = ref.watch(songwriterPlaybackProvider);
  final bar = playback.currentBar;
  if (playback.status != SongwriterPlaybackStatus.playing || bar == null) {
    return null;
  }
  final sections = ref.watch(songwriterProvider.select((p) => p.sections));
  return activePositionForBar(sections, bar);
});
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_playback_rules.dart lib/store/songwriter_playback_store.dart test/store/songwriter_playback_store_test.dart
git commit -m "feat(songwriter): active playhead position provider"
```

---

### Task 5: Sheet UI highlight + auto-scroll

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
- Test: `test/features/songwriter/songwriter_sheet_playhead_test.dart`

- [ ] **Step 1: Write failing widget test**

Pump `SongwriterScreenSheet` inside a `ProviderScope` with a loaded project and
the playback provider overridden to a fixed playing state (override
`songwriterPlaybackProvider` with a notifier stub, or simpler: override
`songwriterActivePositionProvider` directly):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';
// ... model imports

void main() {
  testWidgets('active bar cell shows playhead highlight', (tester) async {
    // Project: one section 's1', 2 bars, harmony block at bar 0.
    // Override songwriterActivePositionProvider to
    // SongwriterActivePosition(sectionId: 's1', instanceIndex: 0, localBar: 0).
    // Pump the sheet, expect a widget keyed
    // Key('activeBarCell_s1_0_0') to exist (section_instance_bar).
  });
}
```

(Write the full pump with the same scaffolding as existing sheet tests — see
`test/features/songwriter/` for prior art; reuse their project fixture.)

- [ ] **Step 2: Run — expect FAIL (key not found)**

- [ ] **Step 3: Implement highlight**

In `songwriter_screen_sheet.dart`:

1. `_BarRow.build`: watch the active position scoped to this row:

```dart
    final activeBar = ref.watch(
      songwriterActivePositionProvider.select(
        (p) => p != null &&
                p.sectionId == section.id &&
                p.instanceIndex == instanceIndex
            ? p.localBar
            : null,
      ),
    );
```

2. Pass `isActive` + a stable key into `_BarCell`. The row builds cells per
   bar index `i` (occupied cells span `owner.startBar..end`): a cell is active
   when `activeBar != null && activeBar >= startBar && activeBar < startBar + flex`
   where `startBar` is the bar index the cell starts at. Add fields to
   `_BarCell`: `required this.isActive`, and give the container, when active:

```dart
            color: isActive
                ? MuzicianTheme.violet.withValues(alpha: 0.34)
                : (block != null
                      ? MuzicianTheme.violet.withValues(alpha: 0.18)
                      : Colors.transparent),
```

   plus key on the cell when active: `Key('activeBarCell_${section.id}_${instanceIndex}_$startBar')`
   (pass section id / instance / startBar into `_BarCell` or wrap with a
   `KeyedSubtree` in `_BarRow` where all three are in scope — wrapper preferred,
   keeps `_BarCell` dumb).

3. Auto-scroll: in `_SectionInstance.build` add:

```dart
    ref.listen(
      songwriterActivePositionProvider.select(
        (p) => p != null &&
            p.sectionId == section.id &&
            p.instanceIndex == instanceIndex,
      ),
      (prev, next) {
        if (next && !(prev ?? false)) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.2,
          );
        }
      },
    );
```

- [ ] **Step 4: Run widget test + full suite — expect PASS**

Run: `flutter test`

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_sheet_playhead_test.dart
git commit -m "feat(songwriter): sheet playhead — active bar highlight + auto-scroll"
```

---

### Task 6: Phase gate

- [ ] **Step 1: Full verification**

Run: `flutter analyze && flutter test`
Expected: analyze clean, all tests pass.

- [ ] **Step 2: serve-sim verification**

Boot the app in the iOS simulator (serve-sim skill). In the Writer tab:
- Build a section with a couple of harmony chords + a drum lane.
- Press play: chords audibly stab per bar, drums hit, active bar highlights and
  sheet scrolls as playback advances. Stop works.

- [ ] **Step 3: Update docs**

`docs/songwriter.md`: replace the "blocks are silent visual guides" claims with
the new audible-playback behavior (chords/voicings per-bar stabs, drum lanes at
native resolution, metronome unchanged).

- [ ] **Step 4: Commit**

```bash
git add docs/songwriter.md
git commit -m "docs(songwriter): audible playback semantics"
```
