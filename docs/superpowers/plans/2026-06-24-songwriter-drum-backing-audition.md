# Drum Editor Backing Audition (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Songwriter drum-pattern editor audition the pattern *solo* (current behavior) or *with the section's harmony looping underneath*, so the beat is heard in musical context.

**Architecture:** A pure helper flattens one section's harmony/save chords into a tick-indexed map looping at the section length. The existing single-pattern audition transport (`DrumPatternPlaybackNotifier`) gains optional `backingNotes` + `loopTicks`; with backing, it loops over the section span (the drum pattern tiles within it) and fires chord notes through a new, self-contained backing sink. The shared editor body shows a **Backing** toggle only when a backing descriptor is supplied; the Songwriter sheet computes that descriptor from the section it was opened from. The Song feature is untouched (optional params, toggle hidden without backing).

**Tech Stack:** Dart, Flutter, Riverpod, `flutter_test`. No new packages. No model/persistence changes.

**Spec:** `docs/superpowers/specs/2026-06-23-songwriter-drum-loops-design.md` (Component 1).

**Depends on:** Phase 1 (drum fills) already merged on this branch — no overlap.

---

## File Structure

**Created:**
- `test/schema/rules/songwriter_playback_backing_test.dart` — unit tests for `sectionHarmonyLoop`.
- `test/features/songwriter/drum_backing_audition_test.dart` — widget tests for the backing toggle (body-level + sheet-level).

**Modified:**
- `lib/schema/rules/songwriter_playback_rules.dart` — add the pure `sectionHarmonyLoop` helper.
- `lib/store/drum_pattern_playback_store.dart` — add `drumPatternBackingSinkProvider`; extend `DrumPatternPlaybackNotifier.start` with optional `backingNotes` + `loopTicks`.
- `test/store/drum_pattern_playback_store_test.dart` — add backing-path tests.
- `lib/features/song/drum_machine_editor.dart` — add an optional `backing` param + a Backing toggle to `DrumMachineEditorBody`.
- `lib/features/songwriter/drum_pattern_sheet.dart` — add a `sectionId` param; compute the backing descriptor from the section.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — pass `sectionId` at the existing sheet-open site.

---

## Task 1: Pure `sectionHarmonyLoop` helper

Flattens one section's harmony + save chords into a `{tick → midiNotes}` map plus the section loop length. Mirrors the harmony/save branch of `flattenPlaybackEvents`, scoped to a single section and indexed from tick 0. Drum lanes are excluded.

**Files:**
- Modify: `lib/schema/rules/songwriter_playback_rules.dart` (append near the end; the file already imports `songwriter.dart`, `save_system.dart`, and `songwriter_rules.dart`, and already defines `chordMidiNotes`, `snapshotMidiNotes`; `tileLaneBlocks` + `resolveBlockSnapshot` come from `songwriter_rules.dart`).
- Test: `test/schema/rules/songwriter_playback_backing_test.dart`

- [ ] **Step 1: Write the failing test**

`test/schema/rules/songwriter_playback_backing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';

void main() {
  // measureTicks = ticksPerBeat(4) * beatsPerBar(4) = 16.
  const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);

  test('loopTicks spans the whole section; no harmony → empty map', () {
    const section = SongSection(id: 's1', lengthBars: 2, order: 0, lanes: []);
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.loopTicks, 32); // 2 bars × 16
    expect(loop.notesByTick, isEmpty);
  });

  test('harmony block fires its chord pitches at the bar tick', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 2,
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
      ],
    );
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.notesByTick[0], [60, 64, 67]); // C4 E4 G4
    expect(loop.notesByTick.keys.toSet(), {0});
  });

  test('multi-bar harmony block fires on each bar boundary', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 2,
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
              chordNotes: ['C', 'E', 'G'],
            ),
          ],
        ),
      ],
    );
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.notesByTick.keys.toSet(), {0, 16});
  });

  test('drum lanes are ignored', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 1,
      order: 0,
      lanes: [
        SongLane(
          id: 'd1',
          kind: SongLaneKind.drum,
          order: 0,
          blocks: [
            SongBlock(id: 'b1', startBar: 0, spanBars: 1, patternId: 'p1'),
          ],
        ),
      ],
    );
    final loop = sectionHarmonyLoop(section, cfg, const []);
    expect(loop.notesByTick, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_playback_backing_test.dart`
Expected: FAIL — `sectionHarmonyLoop` undefined.

- [ ] **Step 3: Implement the helper**

Append to `lib/schema/rules/songwriter_playback_rules.dart`:

```dart
/// One looping backing bed for a single section's harmony, for the drum
/// editor's "audition with backing" mode.
///
/// Returns the section's loop length in ticks and a `tick → midi pitches` map
/// of per-bar chord stabs, indexed from tick 0. Harmony lanes use
/// [chordMidiNotes]; save lanes use [snapshotMidiNotes]. Drum lanes are
/// excluded — the backing is the chord bed only. Blocks tile via
/// [tileLaneBlocks] and are clipped to the section.
({int loopTicks, Map<int, List<int>> notesByTick}) sectionHarmonyLoop(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves,
) {
  final beatTicks = config.ticksPerBeat;
  final measureTicks = beatTicks * config.beatsPerBar;
  final loopTicks = section.lengthBars * measureTicks;
  final notesAt = <int, List<int>>{};

  for (final lane in section.lanes) {
    if (lane.kind == SongLaneKind.drum) continue;
    final blocks = tileLaneBlocks(lane, sectionLengthBars: section.lengthBars);
    for (final block in blocks) {
      final clippedEnd = block.endBar > section.lengthBars
          ? section.lengthBars
          : block.endBar;
      final pitches = lane.kind == SongLaneKind.harmony
          ? chordMidiNotes(block)
          : snapshotMidiNotes(resolveBlockSnapshot(block, saves));
      if (pitches.isEmpty) continue;
      for (var bar = block.startBar; bar < clippedEnd; bar++) {
        final tick = bar * measureTicks;
        (notesAt[tick] ??= <int>[]).addAll(pitches);
      }
    }
  }

  return (loopTicks: loopTicks, notesByTick: notesAt);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_playback_backing_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Run the existing playback-rules suite for regressions**

Run: `flutter test test/schema/rules/songwriter_playback_rules_test.dart`
Expected: PASS (helper is additive).

- [ ] **Step 6: Commit**

```bash
git add lib/schema/rules/songwriter_playback_rules.dart test/schema/rules/songwriter_playback_backing_test.dart
git commit -m "feat(songwriter): sectionHarmonyLoop backing flattener"
```

---

## Task 2: Backing in the audition transport

Extend `DrumPatternPlaybackNotifier.start` with optional `backingNotes` (tick → midi) and a `loopTicks` override. With backing, the loop runs `loopTicks` ticks; the drum pattern tiles (`tick % length`) and backing notes fire through a new, self-contained backing sink. Without backing the behavior is byte-for-byte unchanged.

**Files:**
- Modify: `lib/store/drum_pattern_playback_store.dart`
- Test: `test/store/drum_pattern_playback_store_test.dart`

- [ ] **Step 1: Add failing tests**

Append these two tests inside the existing `group('DrumPatternPlaybackNotifier', ...)` in `test/store/drum_pattern_playback_store_test.dart` (after the last test, before the group's closing `});`):

```dart
test('backing notes fire through the backing sink when provided', () async {
  final backing = <List<int>>[];
  final c = ProviderContainer(
    overrides: [
      drumPatternPlaybackSinkProvider.overrideWithValue((lanes, vol) async {}),
      drumPatternBackingSinkProvider.overrideWithValue((notes) {
        backing.add(notes);
      }),
    ],
  );
  addTearDown(c.dispose);
  final notifier = c.read(drumPatternPlaybackProvider.notifier);

  // Pattern loops every 4 ticks; backing loop is 8 ticks (two bars).
  const p = DrumPattern(
    id: 'p',
    name: 'b',
    lengthTicks: 4,
    lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
  );
  unawaited(
    notifier.start(
      pattern: p,
      tempo: 6000,
      backingNotes: {
        0: [60, 64, 67],
        4: [62, 65, 69],
      },
      loopTicks: 8,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 60));
  notifier.stop();

  final fired = backing.expand((n) => n).toSet();
  expect(fired, containsAll(<int>[60, 64, 67, 62, 65, 69]));
});

test('backing sink is never called when no backing is provided', () async {
  final backing = <List<int>>[];
  final c = ProviderContainer(
    overrides: [
      drumPatternPlaybackSinkProvider.overrideWithValue((lanes, vol) async {}),
      drumPatternBackingSinkProvider.overrideWithValue((notes) {
        backing.add(notes);
      }),
    ],
  );
  addTearDown(c.dispose);
  final notifier = c.read(drumPatternPlaybackProvider.notifier);
  const p = DrumPattern(
    id: 'p',
    name: 'b',
    lengthTicks: 4,
    lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
  );
  unawaited(notifier.start(pattern: p, tempo: 6000));
  await Future<void>.delayed(const Duration(milliseconds: 40));
  notifier.stop();
  expect(backing, isEmpty);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/store/drum_pattern_playback_store_test.dart`
Expected: FAIL — `drumPatternBackingSinkProvider` undefined and `start` has no `backingNotes`/`loopTicks` params.

- [ ] **Step 3: Add the backing sink provider**

In `lib/store/drum_pattern_playback_store.dart`, directly below the existing `drumPatternPlaybackSinkProvider` definition, add:

```dart
/// Signature for a function that sounds a chord/voicing backing stab.
typedef DrumPatternBackingSink = void Function(List<int> midiNotes);

/// Injected backing sink backed by [NotePlayer].  Override in tests to capture
/// the chord stabs that play under the pattern during "audition with backing".
final drumPatternBackingSinkProvider = Provider<DrumPatternBackingSink>((ref) {
  return (midiNotes) {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6);
    }
  };
});
```

(`NotePlayer` is already imported in this file.)

- [ ] **Step 4: Extend `start`**

Replace the entire existing `start` method with this version (the only changes: two new optional params, a `loop` modulus, `tick % length` for drum hits + the grid highlight, and the backing-sink call):

```dart
/// Starts looping [pattern] at [tempo] BPM.  No-op if already playing or the
/// pattern is empty.
///
/// Solo (default): the loop wraps after [DrumPattern.lengthTicks]. When
/// [backingNotes] + [loopTicks] are given (the drum editor's "audition with
/// backing"), the loop wraps after [loopTicks] instead; the drum pattern tiles
/// within it (`tick % length`) and the chord stabs in [backingNotes] fire via
/// [drumPatternBackingSinkProvider]. Runs until [stop] is called.
Future<void> start({
  required DrumPattern pattern,
  required int tempo,
  Map<int, List<int>>? backingNotes,
  int? loopTicks,
}) async {
  if (state.status == DrumPatternPlaybackStatus.playing) return;
  final length = pattern.lengthTicks;
  if (length <= 0) return;
  final loop = (loopTicks != null && loopTicks > 0) ? loopTicks : length;

  final sink = ref.read(drumPatternPlaybackSinkProvider);
  final backingSink = ref.read(drumPatternBackingSinkProvider);

  final lanesByTick = <int, List<DrumLaneId>>{};
  for (final lane in pattern.lanes) {
    for (final tick in lane.activeTicks) {
      (lanesByTick[tick] ??= <DrumLaneId>[]).add(lane.laneId);
    }
  }

  // Sixteenth-grid tick: a quarter note spans 4 ticks, so one tick is a
  // sixteenth.
  final tickDuration = rules.tickDuration(tempo);

  final version = ++_version;
  state = const DrumPatternPlaybackState(
    status: DrumPatternPlaybackStatus.playing,
    currentTick: 0,
  );

  // [TickPacer] anchors each tick to the wall clock so per-tick body work
  // (state mutation → rebuilds, the sinks) cannot accumulate into drift.
  final pacer = TickPacer(tickDuration);
  var tick = 0;
  var elapsedTicks = 0;
  while (_version == version) {
    final drumTick = tick % length;
    // Keep the grid highlight inside the pattern even when the backing loop is
    // longer than the pattern.
    state = state.copyWith(currentTick: () => drumTick);
    final lanes = lanesByTick[drumTick];
    if (lanes != null && lanes.isNotEmpty) {
      unawaited(sink(lanes, 0.8));
    }
    if (backingNotes != null) {
      final notes = backingNotes[tick];
      if (notes != null && notes.isNotEmpty) backingSink(notes);
    }
    await pacer.awaitBoundary(++elapsedTicks);
    if (_version != version) return;
    tick = (tick + 1) % loop;
  }
}
```

- [ ] **Step 5: Run the store tests**

Run: `flutter test test/store/drum_pattern_playback_store_test.dart`
Expected: PASS — both new tests plus all existing ones (the solo path is unchanged: `loop == length`, `drumTick == tick`, no backing).

- [ ] **Step 6: Commit**

```bash
git add lib/store/drum_pattern_playback_store.dart test/store/drum_pattern_playback_store_test.dart
git commit -m "feat(drum): optional backing notes + loop length in audition transport"
```

---

## Task 3: Backing toggle in `DrumMachineEditorBody`

Add an optional `backing` descriptor and a **Backing** toggle to the shared editor body. The toggle appears only when `backing != null` (Songwriter); the Song feature passes nothing and sees no toggle. When the toggle is on, Play starts the audition with the backing; otherwise solo.

**Files:**
- Modify: `lib/features/song/drum_machine_editor.dart`
- Test: `test/features/songwriter/drum_backing_audition_test.dart` (body-level cases; sheet-level cases added in Task 4)

- [ ] **Step 1: Write the failing widget test**

`test/features/songwriter/drum_backing_audition_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';

DrumPattern _pattern() => const DrumPattern(
  id: 'p1',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.closedHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.openHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.clap, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.lowTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.highTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.crash, activeTicks: []),
  ],
);

void main() {
  testWidgets('backing toggle is shown when a backing descriptor is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: _pattern(),
              tempo: 120,
              onChanged: (_) {},
              backing: (loopTicks: 16, notesByTick: {0: [60, 64, 67]}),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('backingToggle')), findsOneWidget);
  });

  testWidgets('no backing toggle when backing is null', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: _pattern(),
              tempo: 120,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('backingToggle')), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/drum_backing_audition_test.dart`
Expected: FAIL — `backing` is not a parameter of `DrumMachineEditorBody`.

- [ ] **Step 3: Add the `backing` field**

In `DrumMachineEditorBody` (the widget class), add the field + constructor param (keep the existing ones):

```dart
class DrumMachineEditorBody extends ConsumerStatefulWidget {
  const DrumMachineEditorBody({
    super.key,
    required this.pattern,
    required this.tempo,
    required this.onChanged,
    this.beatUnit = 4,
    this.backing,
  });

  final DrumPattern pattern;
  final int tempo;
  final int beatUnit;
  final void Function(DrumPattern updated) onChanged;

  /// Optional looping chord bed for "audition with backing". When non-null the
  /// editor shows a Backing toggle; when the toggle is on, Play loops over
  /// [backing.loopTicks] with the chord stabs in [backing.notesByTick].
  final ({int loopTicks, Map<int, List<int>> notesByTick})? backing;

  @override
  ConsumerState<DrumMachineEditorBody> createState() =>
      _DrumMachineEditorBodyState();
}
```

- [ ] **Step 4: Track the toggle state + use it in `togglePlayback`**

In `_DrumMachineEditorBodyState`, add a field near `_pattern`:

```dart
bool _backingOn = false;
```

In `build`, replace the existing `togglePlayback` closure with:

```dart
void togglePlayback() {
  final notifier = ref.read(drumPatternPlaybackProvider.notifier);
  if (playing) {
    notifier.stop();
  } else {
    final backing = widget.backing;
    if (_backingOn && backing != null) {
      notifier.start(
        pattern: _pattern,
        tempo: widget.tempo,
        backingNotes: backing.notesByTick,
        loopTicks: backing.loopTicks,
      );
    } else {
      notifier.start(pattern: _pattern, tempo: widget.tempo);
    }
  }
  HapticFeedback.lightImpact();
}
```

- [ ] **Step 5: Render the toggle in the transport row**

In the transport `Row` (currently `IconButton` play/stop, then `Spacer`, then the BPM `Text`), insert the toggle between the play button and the `Spacer`:

```dart
Row(
  children: [
    IconButton(
      tooltip: playing ? 'Stop' : 'Play',
      icon: Icon(playing ? Icons.stop : Icons.play_arrow),
      color: MuzicianTheme.orange,
      onPressed: togglePlayback,
    ),
    if (widget.backing != null) ...[
      const SizedBox(width: 4),
      FilterChip(
        key: const Key('backingToggle'),
        label: const Text('Backing'),
        selected: _backingOn,
        showCheckmark: false,
        onSelected: (v) => setState(() => _backingOn = v),
        backgroundColor: MuzicianTheme.violet.withValues(alpha: 0.12),
        selectedColor: MuzicianTheme.violet.withValues(alpha: 0.30),
        side: BorderSide(color: MuzicianTheme.violet.withValues(alpha: 0.5)),
        labelStyle: const TextStyle(
          color: MuzicianTheme.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
    const Spacer(),
    Text(
      '${widget.tempo} BPM',
      style: const TextStyle(
        color: MuzicianTheme.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
),
```

- [ ] **Step 6: Run the widget test**

Run: `flutter test test/features/songwriter/drum_backing_audition_test.dart`
Expected: PASS (2/2).

- [ ] **Step 7: Run the drum-editor regression suite**

Run: `flutter test test/features/song/`
Expected: PASS — the `backing` param is optional; the Song feature's `DrumMachineEditor` constructs `DrumMachineEditorBody` without it, so no toggle appears and behavior is unchanged.

- [ ] **Step 8: Commit**

```bash
git add lib/features/song/drum_machine_editor.dart test/features/songwriter/drum_backing_audition_test.dart
git commit -m "feat(drum): backing toggle in the shared editor body"
```

---

## Task 4: Thread section context into the Songwriter drum sheet

Give `showSongwriterDrumPatternSheet` an optional `sectionId`; the sheet computes the backing descriptor from that section and passes it to the body. Wire the existing open site to pass the section it is in.

**Files:**
- Modify: `lib/features/songwriter/drum_pattern_sheet.dart`
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (the sheet-open call near line 1616)
- Test: extend `test/features/songwriter/drum_backing_audition_test.dart`

- [ ] **Step 1: Add failing sheet-level tests**

Append to `test/features/songwriter/drum_backing_audition_test.dart` (add the imports at the top, then the new tests inside `main`):

Add these imports at the top of the file:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/drum_pattern_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';
```

Add inside `main()`:

```dart
SongwriterProjectSnapshot _projectWithHarmony() => const SongwriterProjectSnapshot(
  name: 'demo',
  config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
  drumPatterns: [
    DrumPattern(
      id: 'p1',
      name: 'Beat',
      lengthTicks: 16,
      lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
    ),
  ],
  sections: [
    SongSection(
      id: 's1',
      lengthBars: 2,
      order: 0,
      lanes: [
        SongLane(
          id: 'h1',
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
          id: 'd1',
          kind: SongLaneKind.drum,
          order: 1,
          blocks: [
            SongBlock(id: 'db1', startBar: 0, spanBars: 2, patternId: 'p1'),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _openSheet(
  WidgetTester tester,
  ProviderContainer container,
  String? sectionId,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSongwriterDrumPatternSheet(
                context: context,
                patternId: 'p1',
                sectionId: sectionId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

testWidgets('sheet shows the backing toggle when opened from a harmony section',
    (tester) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(songwriterProvider.notifier).loadProject(_projectWithHarmony());

  await _openSheet(tester, container, 's1');

  expect(find.byKey(const Key('backingToggle')), findsOneWidget);
});

testWidgets('sheet shows no backing toggle when opened without a section', (
  tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(songwriterProvider.notifier).loadProject(_projectWithHarmony());

  await _openSheet(tester, container, null);

  expect(find.byKey(const Key('backingToggle')), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/drum_backing_audition_test.dart`
Expected: FAIL — `showSongwriterDrumPatternSheet` has no `sectionId` parameter.

- [ ] **Step 3: Add `sectionId` + backing computation to the sheet**

Replace the entire contents of `lib/features/songwriter/drum_pattern_sheet.dart` with:

```dart
/// Bottom-sheet host that edits a single Songwriter [DrumPattern] using the
/// generalized [DrumMachineEditorBody].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../schema/rules/songwriter_playback_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../song/drum_machine_editor.dart';
import '../_mockup_shell.dart';

Future<void> showSongwriterDrumPatternSheet({
  required BuildContext context,
  required String patternId,
  String? sectionId,
}) {
  return showWidgetSheet(
    context: context,
    title: 'Drum Pattern',
    child: _Body(patternId: patternId, sectionId: sectionId),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.patternId, this.sectionId});
  final String patternId;
  final String? sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final pattern = project.drumPatterns.firstWhere(
      (p) => p.id == patternId,
      orElse: () => const DrumPattern(
        id: '',
        name: '',
        lengthTicks: 16,
        lanes: [],
      ),
    );
    if (pattern.id.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Pattern not found.'),
      );
    }

    // Compute the looping harmony bed from the section this sheet was opened
    // from. Null when there is no section context or the section has no chords.
    final backing = _backingFor(ref, project);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: DrumMachineEditorBody(
        key: Key('drumPatternBody_$patternId'),
        pattern: pattern,
        tempo: project.config.tempo,
        backing: backing,
        onChanged: (updated) {
          ref.read(songwriterProvider.notifier).updateDrumPattern(updated);
        },
      ),
    );
  }

  ({int loopTicks, Map<int, List<int>> notesByTick})? _backingFor(
    WidgetRef ref,
    SongwriterProjectSnapshot project,
  ) {
    final id = sectionId;
    if (id == null) return null;
    SongSection? section;
    for (final s in project.sections) {
      if (s.id == id) {
        section = s;
        break;
      }
    }
    if (section == null) return null;
    final saves = ref.watch(saveSystemProvider).saves;
    final loop = sectionHarmonyLoop(section, project.config, saves);
    if (loop.notesByTick.isEmpty) return null;
    return loop;
  }
}
```

> `SongSection`, `SongwriterProjectSnapshot`, `SongLaneKind` come transitively from `songwriter_store.dart` (which exports the model via its imports). If the analyzer reports any of these as undefined, add `import '../../models/songwriter.dart';` to the sheet file.

- [ ] **Step 4: Pass `sectionId` at the open site**

In `lib/features/songwriter/songwriter_screen_sheet.dart`, find the drum-tile `onTap` near line 1616 that calls `showSongwriterDrumPatternSheet`. It is inside a per-section widget where a `section` variable is in scope (the same widget reads `section.lengthBars`). Update the call to pass the section id:

```dart
onTap: () {
  if (owner.patternId == null) return;
  showSongwriterDrumPatternSheet(
    context: context,
    patternId: owner.patternId!,
    sectionId: section.id,
  );
},
```

> Verify `section` (a `SongSection`) is the in-scope variable at this call site before editing — if the local is named differently (e.g. `widget.section`), use that. Do not invent a new lookup.

- [ ] **Step 5: Run the backing test file**

Run: `flutter test test/features/songwriter/drum_backing_audition_test.dart`
Expected: PASS (4/4 — two body-level + two sheet-level).

- [ ] **Step 6: Run the songwriter sheet regression suite**

Run: `flutter test test/features/songwriter/`
Expected: PASS — the sheet still opens for drum tiles; `sectionId` is optional and the existing `drumPatternBody_<id>` key is unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/drum_pattern_sheet.dart lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/drum_backing_audition_test.dart
git commit -m "feat(songwriter): audition drum lane with section harmony backing"
```

---

## Task 5: Full-suite regression + analyze + manual smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the affected suites**

Run: `flutter test test/schema/rules/ test/store/ test/features/song/ test/features/songwriter/`
Expected: PASS.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/schema/rules/songwriter_playback_rules.dart lib/store/drum_pattern_playback_store.dart lib/features/song/drum_machine_editor.dart lib/features/songwriter/drum_pattern_sheet.dart lib/features/songwriter/songwriter_screen_sheet.dart`
Expected: No new issues.

- [ ] **Step 3: Manual smoke check**

Run: `flutter run -d <preferred-device>`
- Open a Songwriter project that has a section with a harmony lane (chords) and a drum lane.
- Tap the drum tile → the editor sheet opens and shows a **Backing** chip next to Play.
- Press Play with Backing OFF → drums only loop.
- Enable Backing, press Play → the section's chords loop under the drums; the grid highlight still tracks the pattern.
- Open the drum editor from the Song feature (a drum clip) → no Backing chip appears (Song path unaffected).

- [ ] **Step 4: Final commit (only if the smoke check required a fix)**

```bash
git add -A
git commit -m "fix(drum): address backing-audition smoke-test findings"
```

---

## Self-Review Notes

- **Spec coverage (Component 1):** backing toggle in the editor (Task 3), section-harmony loop source (Task 1), section length loop with pattern tiling (Task 2 `loop`/`drumTick`), chord bed via a self-contained sink (Task 2), sheet threading of `sectionId` (Task 4), Song feature untouched (optional `backing`, toggle hidden). Live edits are audible because edits flow through `onChanged` → `updateDrumPattern` → the watched `songwriterProvider`, which re-runs the sheet `build` and re-supplies `_pattern`/`backing` before the next Play.
- **Backwards compatibility:** `start` with no backing keeps `loop == length`, `drumTick == tick`, and never calls the backing sink — verified by the "never called" test and the unchanged existing tests. The grid highlight now uses `tick % length`, identical to the old `tick` for the solo path.
- **Decoupling:** the drum store gains its own `drumPatternBackingSinkProvider` (default `NotePlayer.previewNote`) instead of importing the songwriter note sink, so no store-to-store coupling and the Song feature path is unaffected.
- **Type consistency:** the backing descriptor `({int loopTicks, Map<int, List<int>> notesByTick})` is identical across `sectionHarmonyLoop` (return), `DrumMachineEditorBody.backing` (field), and the sheet's `_backingFor` (return). `start({..., Map<int, List<int>>? backingNotes, int? loopTicks})` matches the call in `togglePlayback`.
- **Backing excludes other drum lanes** (only harmony/save) — matches the spec's "chord bed only".
- **No placeholders:** every step has complete code; the only verification-time judgment is confirming the `section` variable name at the open site (Task 4 Step 4) and the transitive model import (Task 4 Step 3 note).

---

## Out-of-scope reminders (do NOT do here)

- No presets/library (Phases 3–4).
- No Song-feature backing (Song has a different model).
- No new model fields or persistence changes.
- No mixing of other drum lanes into the backing bed.
- No mid-playback restart when the toggle flips — the mode is read at Play (documented behavior).
- Do not pass `beatUnit` from the sheet in this phase (pre-existing default of 4; out of scope).
