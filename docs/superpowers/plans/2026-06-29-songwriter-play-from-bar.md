# Songwriter Play-From-Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user start Songwriter playback from a chosen bar mid-section via a "Play from here" bar-menu action, continuing through the rest of the song.

**Architecture:** Add a `startTick` parameter to the songwriter transport (mirroring the Song transport's seek: filter events to `tick >= start`, start the loop at `start`, pace off a 0-based `elapsedTicks` counter; the existing `fireAudio` already seeks into clips spanning the start). A pure rule maps `(section instance, localBar) → global tick`. The bar action sheet gets a "Play from here" row.

**Tech Stack:** Dart / Flutter, Riverpod `Notifier`, `package:flutter_test`.

---

## File Structure

- `lib/schema/rules/songwriter_playback_rules.dart` — **modify**: add pure `sectionBarGlobalTick`.
- `lib/store/songwriter_playback_store.dart` — **modify**: `startPlayback({startTick})`.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — **modify**: "Play from here" bar action + `_playFromBar` helper.
- `test/store/songwriter_playback_test.dart` — **modify**: rule tests + transport startTick tests.

---

## Task 1: `sectionBarGlobalTick` rule

**Files:**
- Modify: `lib/schema/rules/songwriter_playback_rules.dart`
- Test: `test/store/songwriter_playback_test.dart`

Context: `expandSections(List<SongSection>)` (in `songwriter_rules.dart`, already imported by `songwriter_playback_rules.dart`) returns `List<ExpandedSection>` where each has `sectionId`, `repeatIndex`, `globalStartBar`, `lengthBars`. Occurrences of a given section id appear in `repeatIndex` order, so the Nth occurrence in the filtered list is `repeatIndex == N`.

- [ ] **Step 1: Write the failing tests**

Add to the end of `main()` in `test/store/songwriter_playback_test.dart`:

```dart
  group('sectionBarGlobalTick', () {
    const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;

    test('localBar within a later section maps to its global tick', () {
      final sections = [
        const SongSection(id: 's1', lengthBars: 2, order: 0),
        const SongSection(id: 's2', lengthBars: 4, order: 1),
      ];
      // s2 starts at global bar 2; bar 1 of s2 → global bar 3.
      expect(sectionBarGlobalTick(sections, cfg, 's2', 1), 3 * measureTicks);
      expect(sectionBarGlobalTick(sections, cfg, 's1', 0), 0);
    });

    test('repeated section uses the requested instance', () {
      final sections = [
        const SongSection(id: 's1', lengthBars: 2, order: 0, repeat: 2),
      ];
      // instance 0 starts at bar 0; instance 1 at bar 2.
      expect(sectionBarGlobalTick(sections, cfg, 's1', 1), 1 * measureTicks);
      expect(
        sectionBarGlobalTick(sections, cfg, 's1', 1, instanceIndex: 1),
        3 * measureTicks,
      );
    });

    test('unknown section id → 0', () {
      expect(sectionBarGlobalTick(const [], cfg, 'nope', 3), 0);
    });

    test('localBar is clamped into the section length', () {
      final sections = [const SongSection(id: 's1', lengthBars: 2, order: 0)];
      // bar 5 in a 2-bar section clamps to bar 1.
      expect(sectionBarGlobalTick(sections, cfg, 's1', 5), 1 * measureTicks);
    });
  });
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: FAIL — `sectionBarGlobalTick` undefined.

- [ ] **Step 3: Implement the rule**

Append to `lib/schema/rules/songwriter_playback_rules.dart` (before the final newline):

```dart
/// Global transport tick for [localBar] within the [instanceIndex]-th occurrence
/// of [sectionId] on the flattened timeline. [localBar] is clamped to the
/// section's bar range; an out-of-range [instanceIndex] or unknown section falls
/// back to the first occurrence / tick 0. Used by the "Play from here" action.
int sectionBarGlobalTick(
  List<SongSection> sections,
  SongwriterConfig config,
  String sectionId,
  int localBar, {
  int instanceIndex = 0,
}) {
  final measureTicks = config.ticksPerBeat * config.beatsPerBar;
  final occurrences = expandSections(
    sections,
  ).where((e) => e.sectionId == sectionId).toList();
  if (occurrences.isEmpty) return 0;
  final occ = (instanceIndex >= 0 && instanceIndex < occurrences.length)
      ? occurrences[instanceIndex]
      : occurrences.first;
  final maxLocal = occ.lengthBars - 1;
  final clamped = localBar < 0
      ? 0
      : (localBar > maxLocal ? maxLocal : localBar);
  return (occ.globalStartBar + clamped) * measureTicks;
}
```

Confirm `songwriter_playback_rules.dart` already imports `songwriter_rules.dart` (for `expandSections`) and `song_project.dart` / `songwriter.dart` (for `SongSection` / `SongwriterConfig`). It does (existing rules use `expandSections` and these types); no new imports needed.

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: PASS (new group + all pre-existing tests).

- [ ] **Step 5: Format + commit**

```bash
dart format lib/schema/rules/songwriter_playback_rules.dart test/store/songwriter_playback_test.dart
git add lib/schema/rules/songwriter_playback_rules.dart test/store/songwriter_playback_test.dart
git commit -m "feat(songwriter): sectionBarGlobalTick rule for play-from-bar"
```

---

## Task 2: Transport `startPlayback({startTick})`

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_playback_test.dart`

Context: current `startPlayback({Duration? tickDurationOverride})` loops `for (var tick = 0; tick < endTick; tick++)` with `if (tick > 0) await pacer.awaitBoundary(tick)`. Starting at `tick = start` with `awaitBoundary(start)` would wait `tickDuration * start` before the first tick (the wall clock is ~0), so pacing must key off a separate 0-based `elapsedTicks` counter (as the Song transport does).

- [ ] **Step 1: Write the failing tests**

Add to `test/store/songwriter_playback_test.dart` `main()`:

```dart
  test('startPlayback(startTick:) skips bars before the start', () async {
    final accents = <bool>[];
    final container = ProviderContainer(
      overrides: [
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async => accents.add(accent),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 1);
    sw.addSection(label: 'B', lengthBars: 1);
    final cfg = container.read(songwriterProvider).config;
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;

    await container
        .read(songwriterPlaybackProvider.notifier)
        .startPlayback(
          startTick: measureTicks,
          tickDurationOverride: Duration.zero,
        );

    // Bar 0's downbeat accent is skipped; only bar 1's fires.
    expect(accents.where((a) => a).length, 1);
    expect(
      container.read(songwriterPlaybackProvider).status,
      SongwriterPlaybackStatus.completed,
    );
  });

  test('startPlayback(startTick:) past the end completes without firing', () async {
    final accents = <bool>[];
    final container = ProviderContainer(
      overrides: [
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async => accents.add(accent),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(
          label: 'A',
          lengthBars: 1,
        );

    await container
        .read(songwriterPlaybackProvider.notifier)
        .startPlayback(startTick: 100000, tickDurationOverride: Duration.zero);

    expect(accents, isEmpty);
    expect(
      container.read(songwriterPlaybackProvider).status,
      SongwriterPlaybackStatus.completed,
    );
  });
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: FAIL — `startPlayback` has no `startTick` parameter.

- [ ] **Step 3: Add the `startTick` parameter**

In `lib/store/songwriter_playback_store.dart`, change the signature:

```dart
  Future<void> startPlayback({Duration? tickDurationOverride}) async {
```
to:
```dart
  Future<void> startPlayback({
    int startTick = 0,
    Duration? tickDurationOverride,
  }) async {
```

- [ ] **Step 4: Start the loop at `start`, pace off `elapsedTicks`**

Replace this block (the state init through the end of the tick loop):

```dart
    state = SongwriterPlaybackState(
      status: SongwriterPlaybackStatus.playing,
      currentTick: 0,
      totalTicks: endTick,
      measureTicks: measureTicks,
    );

    // [TickPacer] anchors each tick to the wall clock so the body's work
    // (state mutation → rebuilds, sinks, the active-position provider) cannot
    // accumulate into drift and make playback run progressively late.
    final pacer = TickPacer(tickDuration);
    var eventIndex = 0;
    for (var tick = 0; tick < endTick; tick++) {
      if (_version != version) return;
      if (tick > 0) await pacer.awaitBoundary(tick);
      if (_version != version) return;
      state = state.copyWith(currentTick: () => tick);
      if (metronomeOn && tick % beatTicks == 0) {
        unawaited(metronomeSink(accent: tick % measureTicks == 0));
      }
      while (eventIndex < events.length && events[eventIndex].tick == tick) {
        final event = events[eventIndex];
        eventIndex++;
        if (event.midiNotes.isNotEmpty) noteSink(event.midiNotes);
        if (event.drumLanes.isNotEmpty) {
          unawaited(drumSink(event.drumLanes, 0.8));
        }
      }
      fireAudio(tick);
    }
```

with:

```dart
    final start = startTick < 0
        ? 0
        : (startTick > endTick ? endTick : startTick);
    if (start >= endTick) {
      state = state.copyWith(status: SongwriterPlaybackStatus.completed);
      return;
    }

    state = SongwriterPlaybackState(
      status: SongwriterPlaybackStatus.playing,
      currentTick: start,
      totalTicks: endTick,
      measureTicks: measureTicks,
    );

    // [TickPacer] anchors each tick to the wall clock so the body's work
    // (state mutation → rebuilds, sinks, the active-position provider) cannot
    // accumulate into drift. Pace off a 0-based [elapsedTicks] counter, not the
    // absolute tick — otherwise a mid-song start would wait tickDuration*start
    // before the first tick.
    final pacer = TickPacer(tickDuration);
    var eventIndex = 0;
    // Skip events before the start tick so a mid-song start doesn't replay them.
    while (eventIndex < events.length && events[eventIndex].tick < start) {
      eventIndex++;
    }
    var elapsedTicks = 0;
    for (var tick = start; tick < endTick; tick++) {
      if (_version != version) return;
      if (elapsedTicks > 0) await pacer.awaitBoundary(elapsedTicks);
      if (_version != version) return;
      state = state.copyWith(currentTick: () => tick);
      if (metronomeOn && tick % beatTicks == 0) {
        unawaited(metronomeSink(accent: tick % measureTicks == 0));
      }
      while (eventIndex < events.length && events[eventIndex].tick == tick) {
        final event = events[eventIndex];
        eventIndex++;
        if (event.midiNotes.isNotEmpty) noteSink(event.midiNotes);
        if (event.drumLanes.isNotEmpty) {
          unawaited(drumSink(event.drumLanes, 0.8));
        }
      }
      fireAudio(tick);
      elapsedTicks++;
    }
```

The trailing block after the loop (the `pendingAudioStops` flush + `completed` state) is unchanged.

- [ ] **Step 5: Run tests, verify they pass**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: PASS (new startTick tests + all pre-existing, including the start=0 metronome/chord/drift tests as a regression guard).

- [ ] **Step 6: Analyze + format + commit**

Run: `flutter analyze lib/store/songwriter_playback_store.dart` → No issues.

```bash
dart format lib/store/songwriter_playback_store.dart test/store/songwriter_playback_test.dart
git add lib/store/songwriter_playback_store.dart test/store/songwriter_playback_test.dart
git commit -m "feat(songwriter): startPlayback(startTick) for mid-song start"
```

---

## Task 3: "Play from here" bar action

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`

Context: tapping a bar opens `showBarActionSheet(context:, title:, actions: [BarAction(...)])`. Two builders: `_onTapEmpty(context, ref, int bar)` and `_onTapBlock(context, ref, SongBlock block)` (use `block.startBar`). The enclosing widget exposes `final SongSection section;` and `final int instanceIndex;`. `BarAction` fields: `key`, `label`, `icon`, `onTap`, optional `destructive`.

- [ ] **Step 1: Add the `_playFromBar` helper**

In `lib/features/songwriter/songwriter_screen_sheet.dart`, add this method to the same widget class that defines `_onTapEmpty`/`_onTapBlock` (it has `section` and `instanceIndex` in scope):

```dart
  void _playFromBar(WidgetRef ref, int bar) {
    final project = ref.read(songwriterProvider);
    final tick = sectionBarGlobalTick(
      project.sections,
      project.config,
      section.id,
      bar,
      instanceIndex: instanceIndex,
    );
    final pb = ref.read(songwriterPlaybackProvider.notifier);
    pb.stopPlayback();
    unawaited(pb.startPlayback(startTick: tick));
  }
```

- [ ] **Step 2: Add the action to the empty-bar sheet**

In `_onTapEmpty`, add as the first entry of the `actions:` list:

```dart
        BarAction(
          key: const Key('barActionPlayFromHere'),
          label: 'Play from here',
          icon: Icons.play_arrow,
          onTap: () => _playFromBar(ref, bar),
        ),
```

- [ ] **Step 3: Add the action to the block sheet**

In `_onTapBlock`, add as the first entry of the `actions:` list (uses the block's start bar):

```dart
        BarAction(
          key: const Key('barActionPlayFromHere'),
          label: 'Play from here',
          icon: Icons.play_arrow,
          onTap: () => _playFromBar(ref, block.startBar),
        ),
```

- [ ] **Step 4: Ensure imports**

Confirm the file imports (add any missing):
- `dart:async` (for `unawaited`).
- `../../schema/rules/songwriter_playback_rules.dart` (for `sectionBarGlobalTick`) — likely already present via existing playback usage; add the `show`/import if `flutter analyze` reports `sectionBarGlobalTick` undefined.
- `../../store/songwriter_playback_store.dart` (for `songwriterPlaybackProvider`) — likely already imported (the header uses it); add if missing.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/songwriter/songwriter_screen_sheet.dart`
Expected: No issues (resolve any missing import from Step 4).

- [ ] **Step 6: Commit**

```bash
dart format lib/features/songwriter/songwriter_screen_sheet.dart
git add lib/features/songwriter/songwriter_screen_sheet.dart
git commit -m "feat(songwriter): Play from here bar action starts mid-section"
```

---

## Task 4: Full suite + analyze

**Files:** none (verification only)

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: PASS (no regressions).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: No new issues. (A pre-existing `info` in `test/store/songwriter_scatter_test.dart` is unrelated to this work.)

- [ ] **Step 3: Manual device check (not automated)**

Open a multi-bar section, tap a middle bar → "Play from here" → playback starts at that bar and continues through the song. Tap "Play from here" while playing → it re-seeks to the new bar.

---

## Self-Review (completed during planning)

- **Spec coverage:** "Play from here" trigger → Task 3. Continue-through-song seek → Task 2. `sectionBarGlobalTick` rule → Task 1. Pacer fix → Task 2 Step 4. Edge cases (start≤0, start≥end, repeated section, clip spanning start) → Task 1 (clamp/instance) + Task 2 (clamp + reused `fireAudio`). Testing → Tasks 1, 2, 4.
- **Refinement vs spec:** the spec said "first occurrence"; the plan uses the **viewed `instanceIndex`** (defaults to 0 = first occurrence, so a strict superset) because the bar widget already carries `instanceIndex` — "Play from here" should start at the instance the user is looking at.
- **Placeholder scan:** none — all steps have concrete code/commands.
- **Type consistency:** `sectionBarGlobalTick(List<SongSection>, SongwriterConfig, String, int, {int instanceIndex})` is defined in Task 1 and called identically in Task 3; `startPlayback({int startTick, Duration? tickDurationOverride})` defined in Task 2 and called in Task 3; `ExpandedSection` fields (`sectionId`, `repeatIndex`, `globalStartBar`, `lengthBars`) match the source.
