# Songwriter v1 — Plan B2b: Playback + Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Read `docs/superpowers/HANDOFF-songwriter.md` first.**

**Goal:** Make the Songwriter tab playable and editable: a lightweight bar-clock transport with a metronome and a moving playhead that highlights blocks, drag-to-move/resize for blocks, and tap-a-block to open the referenced save (read-only preview) with Make-Unique / Re-link.

**Architecture:** A new `SongwriterPlaybackNotifier` (modeled on `PianoRollPlaybackNotifier`, but it only advances a bar/tick clock + fires a metronome — no note audio) drives a playhead read by an overlay widget. Block editing (drag/resize) flows through the existing `setBlockPlacement` store op; the lane row passes `barWidth` into the block tile so it can convert drag pixels to bars. Tap-into-save resolves a block's snapshot (`embedded ?? saved`) and shows a read-only preview. Store gains `relinkBlock` + `clearEmbedded`/`clearSaveId` on `SongBlock.copyWith`.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses `songwriter_rules.dart`, `NotePlayer.playClick`, `piano_roll_rules.durationForTickDelta`, `settingsProvider.metronomeEnabled`, `save_preview_thumbnail` painters.

**Spec:** `docs/superpowers/specs/2026-06-02-songwriter-v1-design.md` (§4.4 repeat semantics, §5 transport/tap-into-save) + this plan.
**Depends on:** B2a + **B2a polish merged to `main`** (bar ruler, value pills, undo, default C major).

> **Read before starting:** `lib/store/piano_roll_playback_store.dart` (transport template, tick loop L122-157; metronome sink provider L37-43), `lib/store/songwriter_store.dart`, `lib/schema/rules/songwriter_rules.dart`, `lib/models/songwriter.dart` (`SongBlock`, `SongLane`, `SongSection`), `lib/features/songwriter/songwriter_lane_row.dart` + `songwriter_block_tile.dart` + `songwriter_screen.dart` + `songwriter_header.dart`, `lib/utils/note_player.dart` (`playClick`), `lib/ui/save_previews/save_preview_thumbnail.dart`. Run `flutter test` for a green baseline.

> **Product decision (surface to the user before Task 7):** tap-into-save v1 = a **read-only preview sheet** (renders the snapshot via the existing preview painter). A full embedded, editable instrument view is heavier and deferred. If the user wants the editable version, re-scope Task 7.

---

### Task 1: Expanded-section mapping (playhead maths)

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart`
- Test: `test/schema/rules/songwriter_expand_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_expand_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('expandSections lays out repeats on a global bar axis', () {
    const sections = [
      SongSection(id: 'a', lengthBars: 4, order: 0, repeat: 2), // bars 0-4, 4-8
      SongSection(id: 'b', lengthBars: 8, order: 1, repeat: 1), // bars 8-16
    ];
    final ex = expandSections(sections);
    expect(ex.map((e) => e.sectionId).toList(), ['a', 'a', 'b']);
    expect(ex.map((e) => e.globalStartBar).toList(), [0, 4, 8]);
    expect(ex.map((e) => e.repeatIndex).toList(), [0, 1, 0]);
  });

  test('sectionAtGlobalBar returns the containing instance + local bar', () {
    const sections = [
      SongSection(id: 'a', lengthBars: 4, order: 0, repeat: 2),
    ];
    final ex = expandSections(sections);
    final hit = sectionAtGlobalBar(ex, 5);
    expect(hit, isNotNull);
    expect(hit!.section.sectionId, 'a');
    expect(hit.localBar, 1); // bar 5 is local bar 1 of the 2nd instance (4-8)
    expect(sectionAtGlobalBar(ex, 99), isNull);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/schema/rules/songwriter_expand_test.dart`
Expected: FAIL — symbols missing.

- [ ] **Step 3: Implement**

Add to `lib/schema/rules/songwriter_rules.dart`:

```dart
class ExpandedSection {
  const ExpandedSection({
    required this.sectionId,
    required this.repeatIndex,
    required this.globalStartBar,
    required this.lengthBars,
  });
  final String sectionId;
  final int repeatIndex;
  final int globalStartBar;
  final int lengthBars;
  int get globalEndBar => globalStartBar + lengthBars;
}

class SectionHit {
  const SectionHit({required this.section, required this.localBar});
  final ExpandedSection section;
  final int localBar;
}

/// Lays sections (expanded by their repeat count) onto a global bar axis.
List<ExpandedSection> expandSections(List<SongSection> sections) {
  final out = <ExpandedSection>[];
  var bar = 0;
  for (final s in sections) {
    final reps = s.repeat < 1 ? 1 : s.repeat;
    for (var r = 0; r < reps; r++) {
      out.add(ExpandedSection(
        sectionId: s.id,
        repeatIndex: r,
        globalStartBar: bar,
        lengthBars: s.lengthBars,
      ));
      bar += s.lengthBars;
    }
  }
  return out;
}

/// Finds the expanded section instance containing [globalBar] and the local
/// bar offset within it, or null if past the end.
SectionHit? sectionAtGlobalBar(List<ExpandedSection> expanded, int globalBar) {
  for (final e in expanded) {
    if (globalBar >= e.globalStartBar && globalBar < e.globalEndBar) {
      return SectionHit(section: e, localBar: globalBar - e.globalStartBar);
    }
  }
  return null;
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/schema/rules/songwriter_expand_test.dart`
Expected: PASS (2).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_expand_test.dart
git commit -m "feat(songwriter): expanded-section bar mapping for playhead"
```

---

### Task 2: Songwriter metronome sink provider

**Files:**
- Create: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_metronome_sink_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_metronome_sink_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  test('metronome sink provider is overridable for tests', () {
    final hits = <bool>[];
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider.overrideWithValue(
        ({required bool accent}) async => hits.add(accent),
      ),
    ]);
    addTearDown(container.dispose);
    final sink = container.read(songwriterMetronomeSinkProvider);
    sink(accent: true);
    sink(accent: false);
    expect(hits, [true, false]);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_metronome_sink_test.dart`
Expected: FAIL — file/provider missing.

- [ ] **Step 3: Implement the sink (start the new store file)**

```dart
// lib/store/songwriter_playback_store.dart
/// Songwriter transport: a bar/tick clock that drives a playhead and a
/// metronome. v1 produces no block audio — blocks are silent visual guides.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/note_player.dart';

/// Plays a metronome click. [accent] is true on the downbeat (beat 1).
typedef SongwriterMetronomeSink = Future<void> Function({required bool accent});

/// Injected metronome sink. Defaults to the synthesised click in [NotePlayer];
/// overridable in tests.
final songwriterMetronomeSinkProvider = Provider<SongwriterMetronomeSink>((ref) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_metronome_sink_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_playback_store.dart test/store/songwriter_metronome_sink_test.dart
git commit -m "feat(songwriter): metronome sink provider"
```

---

### Task 3: Transport notifier (bar clock + metronome)

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_playback_test.dart`

The clock advances ticks. ticksPerQuarter = 4; `beatTicks = beatUnit == 8 ? 2 : 4`; `measureTicks = beatTicks * beatsPerBar`; total ticks = `flattenedBarCount(sections) * measureTicks`. Metronome fires on beat boundaries (`tick % beatTicks == 0`), accent on measure boundaries (`tick % measureTicks == 0`). `currentTick` is exposed for the playhead. Gate the click on `settingsProvider.metronomeEnabled`. Use a `_playbackVersion` guard for stop (copy the pattern in `piano_roll_playback_store.dart`).

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_playback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playback fires a metronome accent on each bar downbeat', () async {
    final accents = <bool>[];
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider.overrideWithValue(
        ({required bool accent}) async => accents.add(accent),
      ),
    ]);
    addTearDown(container.dispose);

    // Two 1-bar sections (4/4) -> 2 bars -> 2 downbeats, 8 beats total.
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 1);
    sw.addSection(label: 'B', lengthBars: 1);

    final transport = container.read(songwriterPlaybackProvider.notifier);
    await transport.startPlayback(tickDurationOverride: Duration.zero);

    // 4/4: beatTicks 4, measureTicks 4 -> beats at ticks 0,4 (2 bars).
    expect(accents.length, 2);
    expect(accents, [true, true]); // each bar's first beat is the downbeat
    expect(container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.completed);
  });

  test('stopPlayback halts the clock', () async {
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider
          .overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 4);
    final transport = container.read(songwriterPlaybackProvider.notifier);
    transport.stopPlayback();
    expect(container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.idle);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement state + notifier**

Append to `lib/store/songwriter_playback_store.dart` (add imports `songwriter_store.dart`, `settings_store.dart`, `../schema/rules/songwriter_rules.dart`, and `../schema/rules/piano_roll_rules.dart as pr_rules`):

```dart
enum SongwriterPlaybackStatus { idle, playing, completed }

class SongwriterPlaybackState {
  const SongwriterPlaybackState({
    this.status = SongwriterPlaybackStatus.idle,
    this.currentTick,
    this.totalTicks = 0,
    this.measureTicks = 4,
  });
  final SongwriterPlaybackStatus status;
  final int? currentTick;
  final int totalTicks;
  final int measureTicks;

  /// Current global bar (0-based) derived from the tick, or null when idle.
  int? get currentBar =>
      currentTick == null ? null : currentTick! ~/ measureTicks;

  SongwriterPlaybackState copyWith({
    SongwriterPlaybackStatus? status,
    int? Function()? currentTick,
    int? totalTicks,
    int? measureTicks,
  }) =>
      SongwriterPlaybackState(
        status: status ?? this.status,
        currentTick: currentTick != null ? currentTick() : this.currentTick,
        totalTicks: totalTicks ?? this.totalTicks,
        measureTicks: measureTicks ?? this.measureTicks,
      );
}

class SongwriterPlaybackNotifier extends Notifier<SongwriterPlaybackState> {
  int _version = 0;

  @override
  SongwriterPlaybackState build() => const SongwriterPlaybackState();

  Future<void> startPlayback({Duration? tickDurationOverride}) async {
    if (state.status == SongwriterPlaybackStatus.playing) return;

    final project = ref.read(songwriterProvider);
    final settings = ref.read(settingsProvider);
    final metronomeSink = ref.read(songwriterMetronomeSinkProvider);

    final cfg = project.config;
    final beatTicks = cfg.beatUnit == 8 ? 2 : 4;
    final measureTicks = beatTicks * cfg.beatsPerBar;
    final totalBars = flattenedBarCount(project.sections);
    final endTick = totalBars * measureTicks;
    final metronomeOn = settings.metronomeEnabled;
    final tickDuration =
        tickDurationOverride ?? pr_rules.durationForTickDelta(1, cfg.tempo);

    if (endTick <= 0) {
      state = state.copyWith(status: SongwriterPlaybackStatus.completed);
      return;
    }

    final version = ++_version;
    state = state.copyWith(
      status: SongwriterPlaybackStatus.playing,
      currentTick: () => 0,
      totalTicks: endTick,
      measureTicks: measureTicks,
    );

    for (var tick = 0; tick < endTick; tick++) {
      if (_version != version) return;
      if (tick > 0) await Future<void>.delayed(tickDuration);
      if (_version != version) return;
      state = state.copyWith(currentTick: () => tick);
      if (metronomeOn && tick % beatTicks == 0) {
        unawaited(metronomeSink(accent: tick % measureTicks == 0));
      }
    }
    if (_version != version) return;
    state = state.copyWith(
      status: SongwriterPlaybackStatus.completed,
      currentTick: () => endTick,
    );
  }

  void stopPlayback() {
    _version++;
    state = state.copyWith(
      status: SongwriterPlaybackStatus.idle,
      currentTick: () => null,
    );
  }
}

final songwriterPlaybackProvider =
    NotifierProvider<SongwriterPlaybackNotifier, SongwriterPlaybackState>(
  SongwriterPlaybackNotifier.new,
);
```

> Confirm `pr_rules.durationForTickDelta(int, int)` signature in `lib/schema/rules/piano_roll_rules.dart`; adapt the call if it differs. Confirm `settingsProvider` import path.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: PASS (2).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_playback_store.dart test/store/songwriter_playback_test.dart
git commit -m "feat(songwriter): bar-clock transport with metronome"
```

---

### Task 4: Transport controls in the header

**Files:**
- Modify: `lib/features/songwriter/songwriter_header.dart`
- Test: `test/features/songwriter/songwriter_transport_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_transport_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('play button starts the transport', (tester) async {
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider
          .overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(label: 'A', lengthBars: 1);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('songwriterPlay')));
    await tester.pump(); // enter playing
    expect(
      container.read(songwriterPlaybackProvider).status,
      isNot(SongwriterPlaybackStatus.idle),
    );
    container.read(songwriterPlaybackProvider.notifier).stopPlayback();
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_transport_test.dart`
Expected: FAIL — no `songwriterPlay` key.

- [ ] **Step 3: Add a play/stop button (and metronome toggle) to the header**

In `SongwriterHeader.build`, after the `Spacer()` (before the chips) add a play/stop `IconButton` keyed `songwriterPlay` that reads `songwriterPlaybackProvider.status` and calls `startPlayback()` / `stopPlayback()`:

```dart
Consumer(builder: (context, ref, _) {
  final playing = ref.watch(songwriterPlaybackProvider
      .select((s) => s.status == SongwriterPlaybackStatus.playing));
  final t = ref.read(songwriterPlaybackProvider.notifier);
  return IconButton(
    key: const Key('songwriterPlay'),
    icon: Icon(playing ? Icons.stop : Icons.play_arrow),
    onPressed: () => playing ? t.stopPlayback() : t.startPlayback(),
  );
}),
```
Add a metronome toggle `IconButton` bound to `settingsProvider.metronomeEnabled` / `setMetronomeEnabled` (the setter exists). Imports: `songwriter_playback_store.dart`, `settings_store.dart`.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/songwriter_transport_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_header.dart test/features/songwriter/songwriter_transport_test.dart
git commit -m "feat(songwriter): transport play/stop + metronome toggle in header"
```

---

### Task 5: Playhead + block highlight

**Files:**
- Modify: `lib/features/songwriter/songwriter_lane_row.dart` (highlight blocks under the playhead)
- Modify: `lib/features/songwriter/songwriter_section_card.dart` (playhead line over the active section)
- Modify: `lib/features/songwriter/songwriter_grid.dart` (add a `PlayheadPainter`)
- Test: `test/features/songwriter/songwriter_grid_test.dart` (extend) — paint smoke test

The active section + local bar comes from `songwriterPlaybackProvider.currentBar` mapped through `expandSections` / `sectionAtGlobalBar`. The section card watches the transport; when the current bar falls in this section's range (any repeat instance), it overlays a vertical playhead at `localBar * barWidth` and tells lanes which `localBar` is active so blocks containing it highlight.

- [ ] **Step 1: Add a `PlayheadPainter` (test it renders)**

Add to `songwriter_grid.dart`:

```dart
/// Vertical playhead line at [bar] (0-based) within a [lengthBars]-wide body.
class PlayheadPainter extends CustomPainter {
  PlayheadPainter({
    required this.bar,
    required this.lengthBars,
    required this.color,
  });
  final double bar;
  final int lengthBars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = lengthBars < 1 ? 1 : lengthBars;
    final x = (bar / bars) * size.width;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        Paint()..color = color ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(PlayheadPainter old) =>
      old.bar != bar || old.lengthBars != lengthBars || old.color != color;
}
```

Add to `test/features/songwriter/songwriter_grid_test.dart`:

```dart
  testWidgets('playhead painter renders without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomPaint(
          size: const Size(200, 40),
          painter: PlayheadPainter(bar: 2, lengthBars: 8, color: Colors.cyan),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
```
Run: `flutter test test/features/songwriter/songwriter_grid_test.dart` → PASS.

- [ ] **Step 2: Wire the playhead into the section card**

In `SongwriterSectionCard`, watch the transport and compute whether this section is active:

```dart
final tick = ref.watch(songwriterPlaybackProvider.select((s) => s.currentBar));
// expand once from the whole project:
final expanded = expandSections(ref.watch(songwriterProvider).sections);
final hit = tick == null ? null : sectionAtGlobalBar(expanded, tick);
final activeLocalBar =
    (hit != null && hit.section.sectionId == sectionId) ? hit.localBar : null;
```
Wrap the lanes area in a `Stack`; when `activeLocalBar != null`, overlay a `Positioned.fill` `CustomPaint(PlayheadPainter(bar: activeLocalBar.toDouble()+0.0, lengthBars: section.lengthBars, color: theme.colorScheme.primary))` aligned to the lane body (offset by the 72 gutter — reuse the ruler's gutter approach). Pass `activeLocalBar` to each `SongwriterLaneRow`.

- [ ] **Step 3: Highlight blocks under the playhead in the lane row**

`SongwriterLaneRow` takes a new `int? activeBar`. A block whose `startBar <= activeBar < endBar` renders highlighted (brighter fill / border). Pass `activeBar` down to `SongwriterBlockTile` (new `bool highlighted` param) or compute the highlight in the lane and tint the tile.

- [ ] **Step 4: Run the grid + lane tests + analyze**

Run: `flutter test test/features/songwriter/songwriter_grid_test.dart test/features/songwriter/songwriter_lane_row_test.dart`
Run: `flutter analyze lib/features/songwriter/`
Expected: PASS / clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_grid_test.dart
git commit -m "feat(songwriter): playhead overlay + block highlight"
```

---

### Task 6: Drag-move + resize blocks

**Files:**
- Modify: `lib/features/songwriter/songwriter_lane_row.dart` (pass `barWidth` to the tile)
- Modify: `lib/features/songwriter/songwriter_block_tile.dart` (drag handlers)
- Test: `test/features/songwriter/songwriter_block_drag_test.dart`

Move = horizontal drag on the body → `setBlockPlacement(startBar + round(dx/barWidth), spanBars)`. Resize = drag on a right-edge handle → `setBlockPlacement(startBar, spanBars + round(dx/barWidth))`. The store already clamps + rejects overlaps. The lane row computes `barWidth` (`constraints.maxWidth / lengthBars`) — pass it into the tile.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_block_drag_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_block_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('horizontal drag moves the block by whole bars', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final bId =
        container.read(songwriterProvider).sections.single.lanes.single.blocks.single.id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SongwriterBlockTile(
            sectionId: s, laneId: l, blockId: bId, barWidth: 40,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    // Drag right by ~2 bars (80px at 40px/bar).
    await tester.drag(find.byKey(Key('block_$bId')), const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(songwriterProvider)
        .sections.single.lanes.single.blocks.single.startBar, 2);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_block_drag_test.dart`
Expected: FAIL — `SongwriterBlockTile` has no `barWidth` param.

- [ ] **Step 3: Implement drag**

Add `required this.barWidth` (`double`) to `SongwriterBlockTile`. Wrap the tile in a `GestureDetector` with a drag accumulator:

```dart
double _dragDx = 0;
// onHorizontalDragStart: _dragDx = 0;
// onHorizontalDragUpdate: _dragDx += details.delta.dx;
// onHorizontalDragEnd:
//   final deltaBars = (_dragDx / barWidth).round();
//   if (deltaBars != 0) ref.read(songwriterProvider.notifier).setBlockPlacement(
//     sectionId: sectionId, laneId: laneId, blockId: blockId,
//     startBar: block.startBar + deltaBars, spanBars: block.spanBars);
```
Because `SongwriterBlockTile` is a `ConsumerWidget`, convert it to `ConsumerStatefulWidget` to hold `_dragDx` (or use a `StatefulBuilder` inside). Add a right-edge resize handle (`GestureDetector` on a thin trailing `Container`) that adjusts `spanBars` the same way. Keep the existing long-press menu. In `SongwriterLaneRow`, pass `barWidth: barWidth` (already computed in the `LayoutBuilder`) into each `SongwriterBlockTile`.

> Update any other `SongwriterBlockTile(...)` call sites (and tests from B2a) to pass `barWidth` (the lane row is the only production caller; tests can pass `barWidth: 40`).

- [ ] **Step 4: Run it (PASS) + regression**

Run: `flutter test test/features/songwriter/songwriter_block_drag_test.dart test/features/songwriter/songwriter_lane_row_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_block_drag_test.dart
git commit -m "feat(songwriter): drag to move + resize blocks"
```

---

### Task 7: Resolve snapshot + tap-block read-only preview

> **Confirm the product decision** (read-only preview vs editable) with the user before building.

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart` (add `resolveBlockSnapshot`)
- Create: `lib/features/songwriter/songwriter_block_preview.dart`
- Modify: `lib/features/songwriter/songwriter_block_tile.dart` (tap → preview)
- Test: `test/schema/rules/songwriter_resolve_test.dart`

- [ ] **Step 1: Write the failing resolve test**

```dart
// test/schema/rules/songwriter_resolve_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  FretboardSnapshot snap(List<String> notes) => FretboardSnapshot(
        tuning: TuningName.standard, numFrets: 12, capo: 0,
        selectedCells: const [], selectedNotes: notes,
        viewMode: FretboardViewMode.exact,
      );

  test('embedded wins; else looked up by saveId; else null', () {
    final saves = [
      SaveEntry(id: 's1', name: 'A', folderId: 'f', snapshot: snap(['C']),
          createdAt: 0, updatedAt: 0, order: 0),
    ];
    expect(resolveBlockSnapshot(
        const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1'), saves)!
        .selectedNotes, ['C']);
    final embedded = snap(['E']);
    expect(resolveBlockSnapshot(
        SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1', embedded: embedded),
        saves), embedded);
    expect(resolveBlockSnapshot(
        const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 'missing'),
        saves), isNull);
  });
}
```

> Verify the real `SaveEntry` constructor signature in `lib/models/save_system.dart` and adjust the test's `SaveEntry(...)` accordingly (field names/order).

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/schema/rules/songwriter_resolve_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `resolveBlockSnapshot`**

Add to `songwriter_rules.dart` (import `../../models/save_system.dart`):

```dart
/// Resolves the snapshot a block points at: the detached [SongBlock.embedded]
/// copy if present, else the live save by id, else null (broken reference).
InstrumentSnapshot? resolveBlockSnapshot(SongBlock block, List<SaveEntry> saves) {
  if (block.embedded != null) return block.embedded;
  final id = block.saveId;
  if (id == null) return null;
  for (final e in saves) {
    if (e.id == id) return e.snapshot;
  }
  return null;
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/schema/rules/songwriter_resolve_test.dart`
Expected: PASS.

- [ ] **Step 5: Build the preview sheet + wire the tap**

Create `lib/features/songwriter/songwriter_block_preview.dart` — a `showModalBottomSheet` that renders the resolved snapshot read-only. Reuse the painter chooser in `lib/ui/save_previews/save_preview_thumbnail.dart` (`_painterFor` / the public preview widget if exported; otherwise render `snapshot.selectedNotes` as chips + the derived chord/scale label via `saveCardLabel` from `lib/ui/save_card_label.dart`). Keep it minimal — a titled sheet showing instrument icon, chord/scale label, note chips, and (if a painter is available) the thumbnail.

In `SongwriterBlockTile`, add `onTap` (distinct from the long-press menu) that resolves the snapshot via `resolveBlockSnapshot(block, ref.read(saveSystemProvider).saves)` and opens the preview sheet; if null, show a "broken reference" sheet offering Re-link/Delete.

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/songwriter/ lib/schema/rules/songwriter_rules.dart`
```bash
git add lib/features/songwriter/ lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_resolve_test.dart
git commit -m "feat(songwriter): tap block to preview the referenced save"
```

---

### Task 8: Make-Unique + Re-link

**Files:**
- Modify: `lib/models/songwriter.dart` (`SongBlock.copyWith` gains `clearEmbedded`/`clearSaveId`)
- Modify: `lib/store/songwriter_store.dart` (`relinkBlock`; `makeBlockUnique` already exists)
- Modify: `lib/features/songwriter/songwriter_block_tile.dart` (menu actions)
- Test: `test/store/songwriter_relink_test.dart`, `test/models/song_block_clear_test.dart`

- [ ] **Step 1: Write the failing model test**

```dart
// test/models/song_block_clear_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('copyWith can clear embedded and saveId', () {
    final b = const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1')
        .copyWith(clearSaveId: true);
    expect(b.saveId, isNull);
  });
}
```

- [ ] **Step 2: Run it (FAIL)** → `flutter test test/models/song_block_clear_test.dart`

- [ ] **Step 3: Add clear flags to `SongBlock.copyWith`**

In `SongBlock.copyWith`, add `bool clearEmbedded = false` and `bool clearSaveId = false`; compute:
```dart
saveId: clearSaveId ? null : (saveId ?? this.saveId),
embedded: clearEmbedded ? null : (embedded ?? this.embedded),
```

- [ ] **Step 4: Run it (PASS)** → `flutter test test/models/song_block_clear_test.dart`

- [ ] **Step 5: Write the relink store test**

```dart
// test/store/songwriter_relink_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('relinkBlock points the block at a new save and clears embedded', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'old', startBar: 0, spanBars: 2);
    final bId = c.read(songwriterProvider).sections.single.lanes.single.blocks.single.id;

    n.relinkBlock(sectionId: s, laneId: l, blockId: bId, saveId: 'new');
    final b = c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    expect(b.saveId, 'new');
    expect(b.embedded, isNull);
  });
}
```

- [ ] **Step 6: Run it (FAIL), implement `relinkBlock`, run (PASS)**

In `SongwriterNotifier`:
```dart
void relinkBlock({
  required String sectionId,
  required String laneId,
  required String blockId,
  required String saveId,
}) {
  _replaceLane(sectionId, laneId, (l) => l.copyWith(
        blocks: l.blocks
            .map((b) => b.id == blockId
                ? b.copyWith(saveId: saveId, clearEmbedded: true)
                : b)
            .toList(),
      ));
}
```
Run: `flutter test test/store/songwriter_relink_test.dart` → PASS.

- [ ] **Step 7: Wire menu actions**

In `SongwriterBlockTile._openMenu`, add **Make Unique** (resolve the snapshot, call `makeBlockUnique(... snapshot: resolved)`) and **Re-link** (open the `SaveBrowserPanel` palette → `relinkBlock(... saveId: picked.id)`). Make-Unique is hidden when already embedded; Re-link is offered always (esp. on broken blocks).

- [ ] **Step 8: Analyze + commit**

Run: `flutter analyze lib/ lib/features/songwriter/`
```bash
git add lib/models/songwriter.dart lib/store/songwriter_store.dart lib/features/songwriter/ test/models/song_block_clear_test.dart test/store/songwriter_relink_test.dart
git commit -m "feat(songwriter): make-unique + re-link block actions"
```

---

### Task 9: Verify + serve-sim

**Files:** none (verification only)

- [ ] **Step 1: Format + analyze**

Run: `dart format lib/features/songwriter/ lib/store/songwriter_playback_store.dart lib/schema/rules/songwriter_rules.dart lib/models/songwriter.dart`
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 2: Full sweep**

Run: `flutter test`
Expected: all PASS (≈390 baseline + new B2b tests).

- [ ] **Step 3: Simulator check**

Launch (`flutter run -d <iPhone sim udid>`), open **Writer**. New project → add a 4-bar section + harmony lane + a few chords. Press **play**: confirm the playhead sweeps across bars, the metronome clicks (accent on bar 1), and blocks highlight under the playhead. Drag a block to move it; drag its right edge to resize. Tap a block → preview sheet of the referenced save. Long-press → Make Unique / Re-link / Delete. Toggle the metronome off and replay. Check compact + wide widths.

- [ ] **Step 4: Commit any formatting**

```bash
git add -A
git commit -m "chore(songwriter): format + verify B2b" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** transport+metronome (T2-T4), playhead+highlight (T5, uses T1 mapping), drag move/resize (T6), tap-into-save preview + resolve (T7), make-unique/re-link + broken-ref (T8). Repeat semantics honored via `flattenedBarCount`/`expandSections`. ✓
- **Deferred (note for the user):** block *audio* (still silent in v1), audio-track lanes, full editable instrument view on tap (preview only), per-lane instrument for the save palette.
- **Type/name consistency:** `expandSections`→`List<ExpandedSection>`, `sectionAtGlobalBar`→`SectionHit?`; `songwriterPlaybackProvider` / `SongwriterPlaybackStatus{idle,playing,completed}` / `state.currentBar`; `songwriterMetronomeSinkProvider`; `resolveBlockSnapshot(block, saves)`; `relinkBlock(...)`; `SongBlock.copyWith(clearEmbedded/clearSaveId)`; `SongwriterBlockTile(... barWidth)`.
- **Test gotchas:** drain the 500 ms store debounce with `pump(600ms)`; pass `tickDurationOverride: Duration.zero` to transport tests so they run instantly; override `songwriterMetronomeSinkProvider` to capture accents.

## Next plans
- **Chord wheel:** `docs/superpowers/specs/2026-06-03-songwriter-chord-wheel-design.md` (needs a writing-plans pass).
- **C — enrichment:** `docs/superpowers/specs/2026-06-03-songwriter-c-enrichment-design.md` (needs a brainstorm pass first).
