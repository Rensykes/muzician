# Songwriter Audio Sampler — Plan 5: In-Clip Chord Segments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user annotate a recording's chords with **beat-quantized, silent** in-clip segments — each a harmony pick (chord wheel / manual) or a save reference — shown over the waveform and on the lane tile, with Roman numerals when diatonic. Segments are metadata only (no synth); they already feed `selectedNotes`/library-match via Plan 1.

**Architecture:** Reuse the existing `showHarmonyChordSheet` picker to author chords; lift its returned chord fields into a `ChordSegment` (Plan 1 model). Store ops add/edit/remove segments and clamp them when the clip's bar span shrinks (a pure rule). The clip editor (Plan 4) gains a beat-grid row over the waveform; the lane tile renders compact chord labels.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses `showHarmonyChordSheet`, `romanNumeralFor`.

**Depends on:** Plans 1–4. Spec: `docs/superpowers/specs/2026-06-25-songwriter-audio-sampler-design.md` (Decisions 3–4).

Reference files:
- `lib/features/songwriter/harmony_chord_sheet.dart` — `showHarmonyChordSheet(context, {startBar, spanBars, keyRoot, keyScaleName, ...}) → Future<SongBlock?>`; returned block carries `chordSymbol`/`chordQuality`/`chordRootPc`/`chordNotes`/`romanNumeral`.
- `lib/models/songwriter.dart` — `ChordSegment` (Plan 1).
- `lib/features/songwriter/songwriter_audio_clip_sheet.dart` (Plan 4) — editor to extend with the segment row.
- `lib/features/songwriter/songwriter_audio_lane_row.dart` (Plan 2) — tile to add chord labels to.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/schema/rules/songwriter_segment_rules.dart` | `clampedSegments`, `segmentAtTick`, clip-local tick helpers | Create |
| `lib/store/songwriter_store.dart` | `addChordSegment` / `removeChordSegment` / `clampClipSegments` | Modify |
| `lib/features/songwriter/songwriter_audio_clip_sheet.dart` | beat-grid segment row + picker wiring + span-shrink clamp | Modify |
| `lib/features/songwriter/songwriter_audio_lane_row.dart` | compact chord labels on the tile | Modify |
| `test/schema/rules/songwriter_segment_rules_test.dart` | clamp + lookup | Create |
| `test/store/songwriter_segment_store_test.dart` | add/remove/clamp store ops | Create |
| `test/features/songwriter/songwriter_segment_editor_test.dart` | segment renders + beat cell tappable | Create |

---

### Task 1: Segment rules

**Files:**
- Create: `lib/schema/rules/songwriter_segment_rules.dart`
- Test: `test/schema/rules/songwriter_segment_rules_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/songwriter_segment_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_segment_rules.dart';

void main() {
  const segs = [
    ChordSegment(id: 's1', startTick: 0, spanTicks: 480, chordSymbol: 'C'),
    ChordSegment(id: 's2', startTick: 960, spanTicks: 960, chordSymbol: 'G'),
  ];

  test('clampedSegments drops segments past the new span and clamps a straddler', () {
    // New span total = 1200 ticks. s1 fits. s2 starts at 960 < 1200 but ends at
    // 1920 → clamped to span 240. A segment starting >= 1200 is dropped.
    final out = clampedSegments([
      ...segs,
      const ChordSegment(id: 's3', startTick: 1300, spanTicks: 480, chordSymbol: 'F'),
    ], 1200);
    expect(out.map((s) => s.id), ['s1', 's2']);
    expect(out.firstWhere((s) => s.id == 's2').spanTicks, 240);
  });

  test('segmentAtTick finds the covering segment', () {
    expect(segmentAtTick(segs, 100)?.id, 's1');
    expect(segmentAtTick(segs, 500), isNull); // gap
    expect(segmentAtTick(segs, 1000)?.id, 's2');
  });
}
```

- [ ] **Step 2: Run + fail**

Run: `flutter test test/schema/rules/songwriter_segment_rules_test.dart` → FAIL.

- [ ] **Step 3: Implement**

Create `lib/schema/rules/songwriter_segment_rules.dart`:

```dart
/// Pure helpers for in-clip chord segments (clip-local tick space).
library;

import '../../models/songwriter.dart';

/// Total clip-local ticks for a span of [spanBars].
int clipSpanTicks(int spanBars, SongwriterConfig config) =>
    spanBars * config.beatsPerBar * config.ticksPerBeat;

/// Drops segments starting at/after [spanTotalTicks]; clamps a straddler's span
/// to end exactly at [spanTotalTicks].
List<ChordSegment> clampedSegments(
    List<ChordSegment> segments, int spanTotalTicks) {
  final out = <ChordSegment>[];
  for (final s in segments) {
    if (s.startTick >= spanTotalTicks) continue;
    final end = s.startTick + s.spanTicks;
    out.add(end > spanTotalTicks
        ? s.copyWith(spanTicks: spanTotalTicks - s.startTick)
        : s);
  }
  return out;
}

/// The segment whose half-open range covers [tick], or null.
ChordSegment? segmentAtTick(List<ChordSegment> segments, int tick) {
  for (final s in segments) {
    if (tick >= s.startTick && tick < s.startTick + s.spanTicks) return s;
  }
  return null;
}
```

- [ ] **Step 4: Run + pass, format, analyze, commit**

```bash
flutter test test/schema/rules/songwriter_segment_rules_test.dart
dart format lib/schema/rules/songwriter_segment_rules.dart test/schema/rules/songwriter_segment_rules_test.dart
flutter analyze lib/schema/rules/songwriter_segment_rules.dart
git add lib/schema/rules/songwriter_segment_rules.dart test/schema/rules/songwriter_segment_rules_test.dart
git commit -m "feat(songwriter): chord segment clamp + lookup rules"
```

---

### Task 2: Segment store ops

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_segment_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/store/songwriter_segment_store_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  String seedClip() {
    final s = c.read(songwriterProvider.notifier);
    s.addSection(label: 'A', lengthBars: 4);
    final secId = c.read(songwriterProvider).sections.single.id;
    s.addLane(sectionId: secId, kind: SongLaneKind.audio);
    return s.addAudioClip(assetId: 'a1', durationMs: 4000);
  }

  test('addChordSegment appends a harmony segment', () {
    final clipId = seedClip();
    final segId = c.read(songwriterProvider.notifier).addChordSegment(
        clipId: clipId, startTick: 0, spanTicks: 480,
        chordSymbol: 'C', chordQuality: 'maj', chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'], romanNumeral: 'I');
    final clip = c.read(songwriterProvider).audioClips.single;
    expect(clip.segments.single.id, segId);
    expect(clip.segments.single.chordSymbol, 'C');
  });

  test('removeChordSegment drops it', () {
    final clipId = seedClip();
    final segId = c.read(songwriterProvider.notifier)
        .addChordSegment(clipId: clipId, startTick: 0, spanTicks: 480, saveId: 'x');
    c.read(songwriterProvider.notifier)
        .removeChordSegment(clipId: clipId, segmentId: segId);
    expect(c.read(songwriterProvider).audioClips.single.segments, isEmpty);
  });

  test('clampClipSegments removes out-of-span segments', () {
    final clipId = seedClip();
    final n = c.read(songwriterProvider.notifier);
    n.addChordSegment(clipId: clipId, startTick: 0, spanTicks: 480, chordSymbol: 'C');
    n.addChordSegment(clipId: clipId, startTick: 1920, spanTicks: 480, chordSymbol: 'G');
    n.clampClipSegments(clipId: clipId, spanTotalTicks: 960);
    expect(c.read(songwriterProvider).audioClips.single.segments.length, 1);
  });
}
```

- [ ] **Step 2: Run + fail**

Run: `flutter test test/store/songwriter_segment_store_test.dart` → FAIL.

- [ ] **Step 3: Implement the store ops**

In `lib/store/songwriter_store.dart`, import the rule (`import '../schema/rules/songwriter_segment_rules.dart';`) and add beside the other clip helpers:

```dart
  String addChordSegment({
    required String clipId,
    required int startTick,
    required int spanTicks,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String> chordNotes = const [],
    String? romanNumeral,
    String? saveId,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return '';
    final seg = ChordSegment(
      id: generateId(),
      startTick: startTick,
      spanTicks: spanTicks,
      chordSymbol: chordSymbol,
      chordQuality: chordQuality,
      chordRootPc: chordRootPc,
      chordNotes: chordNotes,
      romanNumeral: romanNumeral,
      saveId: saveId,
    );
    updateAudioClip(clip.copyWith(segments: [...clip.segments, seg]));
    return seg.id;
  }

  void removeChordSegment({required String clipId, required String segmentId}) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(clip.copyWith(
        segments: clip.segments.where((s) => s.id != segmentId).toList()));
  }

  void clampClipSegments({required String clipId, required int spanTotalTicks}) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(
        clip.copyWith(segments: clampedSegments(clip.segments, spanTotalTicks)));
  }
```

> `generateId()` is already imported in this file (used by the existing factories via `songwriter_rules.dart`); if not directly visible, import `save_system_rules.dart show generateId` as `harmony_chord_sheet.dart` does.

- [ ] **Step 4: Run + pass, format, analyze, commit**

```bash
flutter test test/store/songwriter_segment_store_test.dart
dart format lib/store/songwriter_store.dart test/store/songwriter_segment_store_test.dart
flutter analyze lib/store/songwriter_store.dart
git add lib/store/songwriter_store.dart test/store/songwriter_segment_store_test.dart
git commit -m "feat(songwriter): chord segment store ops"
```

---

### Task 3: Segment row in the clip editor

**Files:**
- Modify: `lib/features/songwriter/songwriter_audio_clip_sheet.dart`
- Test: `test/features/songwriter/songwriter_segment_editor_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/songwriter/songwriter_segment_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_clip_sheet.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  testWidgets('renders a chord label for an existing segment', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(songwriterProvider.notifier);
    s.addSection(label: 'A', lengthBars: 4);
    final secId = c.read(songwriterProvider).sections.single.id;
    s.addLane(sectionId: secId, kind: SongLaneKind.audio);
    final laneId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).id;
    s.loadProject(c.read(songwriterProvider).copyWith(audioAssets: const [
      AudioAsset(id: 'a1', durationMs: 4000, sampleRate: 44100, channels: 1,
          format: 'wav', peaks: [10, 20], sourceLabel: 'r'),
    ]));
    final clipId = s.addAudioClip(assetId: 'a1', durationMs: 4000);
    s.addAudioBlock(sectionId: secId, laneId: laneId, audioClipId: clipId,
        startBar: 0, spanBars: 2);
    s.addChordSegment(clipId: clipId, startTick: 0, spanTicks: 480,
        chordSymbol: 'C', romanNumeral: 'I');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: SongwriterAudioClipBody(
            sectionId: secId, laneId: laneId, clipId: clipId)))),
    ));
    expect(find.text('C'), findsWidgets);
    expect(find.byKey(const Key('segBeat_0')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run + fail**

Run: `flutter test test/features/songwriter/songwriter_segment_editor_test.dart`
Expected: FAIL — no `segBeat_0` cell / no 'C' label (segment row not built yet).

- [ ] **Step 3: Add the segment row to the editor**

In `lib/features/songwriter/songwriter_audio_clip_sheet.dart`, add imports:

```dart
import '../../schema/rules/songwriter_segment_rules.dart';
import 'harmony_chord_sheet.dart';
```

Inside `SongwriterAudioClipBody.build`, after the waveform `SizedBox`, insert a beat-grid row. It has `block.spanBars * config.beatsPerBar` cells; each cell shows the covering segment's `chordSymbol` (+ Roman numeral) or is empty-and-tappable:

```dart
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final cfg = project.config;
          final beats = block.spanBars * cfg.beatsPerBar;
          final tpb = cfg.ticksPerBeat;
          return Row(
            children: [
              for (var beat = 0; beat < beats; beat++)
                Expanded(
                  child: GestureDetector(
                    key: Key('segBeat_$beat'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final tick = beat * tpb;
                      final existing = segmentAtTick(clip.segments, tick);
                      if (existing != null) {
                        store.removeChordSegment(
                            clipId: clipId, segmentId: existing.id);
                        return;
                      }
                      final picked = await showHarmonyChordSheet(
                        context,
                        startBar: 0,
                        spanBars: 1,
                        keyRoot: cfg.keyRoot,
                        keyScaleName: cfg.keyScaleName,
                      );
                      if (picked == null || picked.isSilent) return;
                      store.addChordSegment(
                        clipId: clipId,
                        startTick: tick,
                        spanTicks: tpb,
                        chordSymbol: picked.chordSymbol,
                        chordQuality: picked.chordQuality,
                        chordRootPc: picked.chordRootPc,
                        chordNotes: picked.chordNotes,
                        romanNumeral: picked.romanNumeral,
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 34,
                      decoration: BoxDecoration(
                        color: segmentAtTick(clip.segments, beat * tpb) != null
                            ? MuzicianTheme.sky.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.03),
                        border: Border.all(color: MuzicianTheme.glassBorder),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Builder(builder: (_) {
                        final seg = segmentAtTick(clip.segments, beat * tpb);
                        if (seg == null) return const SizedBox.shrink();
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(seg.chordSymbol ?? '·',
                                style: const TextStyle(
                                    color: MuzicianTheme.textPrimary,
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            if (seg.romanNumeral != null)
                              Text(seg.romanNumeral!,
                                  style: const TextStyle(
                                      color: MuzicianTheme.textMuted, fontSize: 9)),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
            ],
          );
        }),
```

> Tapping a filled cell removes that segment (simple toggle). The harmony picker already computes `romanNumeral` from the project key. For save-reference segments, see Task 4.

- [ ] **Step 4: Run + pass**

Run: `flutter test test/features/songwriter/songwriter_segment_editor_test.dart`
Expected: PASS — `segBeat_0` present and 'C' rendered.

- [ ] **Step 5: Wire span-shrink clamp**

In the same file, in the two span-stepper `onPressed` handlers (Plan 4), after the `setBlockPlacement(...)` call add a clamp so segments outside the new span are dropped:

```dart
              final newSpan = (block.spanBars - 1).clamp(1, maxSpan); // or +1 variant
              store.setBlockPlacement(
                  sectionId: sectionId, laneId: laneId, blockId: block.id,
                  startBar: block.startBar, spanBars: newSpan);
              store.clampClipSegments(
                  clipId: clipId,
                  spanTotalTicks: clipSpanTicks(newSpan, project.config));
              rerenderIfStretch();
```

Apply to both the minus and plus handlers (the plus variant only grows, so the clamp is a no-op there but harmless and keeps the two paths identical).

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/features/songwriter/songwriter_audio_clip_sheet.dart test/features/songwriter/songwriter_segment_editor_test.dart
flutter analyze lib/features/songwriter/songwriter_audio_clip_sheet.dart
git add lib/features/songwriter/songwriter_audio_clip_sheet.dart test/features/songwriter/songwriter_segment_editor_test.dart
git commit -m "feat(songwriter): in-clip chord segment editor (beat grid)"
```

---

### Task 4: Save-reference segments + tile labels

**Files:**
- Modify: `lib/features/songwriter/songwriter_audio_clip_sheet.dart` (save picker option)
- Modify: `lib/features/songwriter/songwriter_audio_lane_row.dart` (compact labels)

- [ ] **Step 1: Add a "save reference" path to the segment cell**

The empty-cell tap currently opens the harmony picker directly. Wrap it in a tiny chooser so the user can pick a chord **or** a save. Replace the empty-cell `onTap` body's picker call with:

```dart
                      final choice = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: MuzicianTheme.surface,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(
                              key: const ValueKey('segAddChord'),
                              leading: const Icon(Icons.piano),
                              title: const Text('Chord'),
                              onTap: () => Navigator.pop(ctx, 'chord'),
                            ),
                            ListTile(
                              key: const ValueKey('segAddSave'),
                              leading: const Icon(Icons.library_music_outlined),
                              title: const Text('From a save'),
                              onTap: () => Navigator.pop(ctx, 'save'),
                            ),
                          ]),
                        ),
                      );
                      if (choice == 'chord') {
                        // ...existing showHarmonyChordSheet flow...
                      } else if (choice == 'save') {
                        final saveId = await _pickSaveId(context, ref);
                        if (saveId != null) {
                          store.addChordSegment(
                              clipId: clipId, startTick: tick, spanTicks: tpb,
                              saveId: saveId);
                        }
                      }
```

Add a minimal save chooser that lists the project's saves (scoped like the rest of the songwriter UI). Reuse the existing save-browser scope used by `addLibraryBlockAt` in `songwriter_store.dart` — read that method to find the provider that yields in-scope saves (`getSavesInSubtree(...)`), and present them in a simple list returning the chosen `SaveEntry.id`:

```dart
Future<String?> _pickSaveId(BuildContext context, WidgetRef ref) async {
  final saves = ref.read(songwriterInScopeSavesProvider); // confirm the real provider name
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: MuzicianTheme.surface,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        for (final s in saves)
          ListTile(
            title: Text(s.name,
                style: const TextStyle(color: MuzicianTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx, s.id),
          ),
      ]),
    ),
  );
}
```

> The in-scope saves provider name is a placeholder — read `songwriter_store.dart`'s `addLibraryBlockAt` / library-match section and `songwriter_library_match_rules.dart` to find the actual provider/helper (the spec notes scope is `getSavesInSubtree(folders, saves, selectedProjectId)`). Use the real one. Display the save's chord (via `saveBlockRomanNumeral`) is optional polish.

- [ ] **Step 2: Compact chord labels on the lane tile**

In `lib/features/songwriter/songwriter_audio_lane_row.dart`, in the clip tile `Stack`, add a bottom strip of segment symbols when present:

```dart
                if (clip != null && clip.segments.isNotEmpty)
                  Positioned(
                    left: 4, right: 4, bottom: 2,
                    child: Text(
                      clip.segments
                          .map((s) => s.chordSymbol ?? '◆')
                          .join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: MuzicianTheme.textPrimary, fontSize: 9),
                    ),
                  ),
```

(`◆` marks a save-reference segment, which has no `chordSymbol`.)

- [ ] **Step 3: Run songwriter widget tests, format, analyze, commit**

```bash
flutter test test/features/songwriter/
dart format lib/features/songwriter/songwriter_audio_clip_sheet.dart lib/features/songwriter/songwriter_audio_lane_row.dart
flutter analyze lib/features/songwriter
git add lib/features/songwriter/songwriter_audio_clip_sheet.dart lib/features/songwriter/songwriter_audio_lane_row.dart
git commit -m "feat(songwriter): save-reference segments + tile chord labels"
```

---

### Task 5: Verification gate + full-suite pass

- [ ] **Step 1: Full segment test set**

Run:
```bash
flutter test \
  test/schema/rules/songwriter_segment_rules_test.dart \
  test/store/songwriter_segment_store_test.dart \
  test/features/songwriter/
```
Expected: all PASS.

- [ ] **Step 2: Whole-project analyze + test (the feature is now complete end to end)**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues; full suite green. Fix any regressions before finishing.

- [ ] **Step 3: Device smoke — full loop**

Record a 4-bar chord progression → trim → fit = stretch to 4 bars (chords stay in tune) → open the editor → tap beats to mark `C G Am F` (Roman numerals show in key) → mark one beat as a save reference → labels appear on the tile → press play: the recording sounds, segments stay silent, chords/Roman numerals display. Save the project, reload, confirm clips + segments persist.

- [ ] **Step 4: Confirm `selectedNotes` feeds library-match**

Verify (manually or via a quick test) that a clip with harmony segments contributes its `chordNotes` to `SongwriterProjectSnapshot.selectedNotes` (Plan 1 wired this) — i.e. library-match/analysis sees the recording's harmony.

---

## Self-Review

**Spec coverage (P5 = M7 segments):** beat-quantized silent segments ✓ (model from P1; rules T1); harmony pick via reused `showHarmonyChordSheet` ✓ (T3); save reference ✓ (T4); Roman numerals when diatonic (from the picker) ✓ (T3); span-shrink clamp ✓ (T1 rule + T3 wiring); display on editor + tile ✓ (T3/T4); `selectedNotes`/library-match feed ✓ (P1 + T5 S4). Free-ms placement and segment-synth-doubling remain out of scope per spec Non-Goals.

**Placeholder scan:** No "TBD"/"implement later". The save-scope provider name in T4 is explicitly flagged as needing confirmation against `songwriter_store.dart`, with the concrete helper (`getSavesInSubtree`) named — a verification instruction, not a blank.

**Type consistency:** `clampedSegments`/`segmentAtTick`/`clipSpanTicks` (T1) match store + editor usage (T2/T3). Store ops `addChordSegment`/`removeChordSegment`/`clampClipSegments` signatures match between T2 implementation, its test, and the T3 editor calls. `ChordSegment` fields match Plan 1. The harmony picker's returned `SongBlock` fields (`chordSymbol`/`chordQuality`/`chordRootPc`/`chordNotes`/`romanNumeral`) are exactly those lifted into `addChordSegment` (T3).
