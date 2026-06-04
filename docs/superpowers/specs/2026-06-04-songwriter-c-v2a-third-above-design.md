# Songwriter — Phase C v2-a: 3rd-Above Harmony Suggestions

**Date:** 2026-06-04
**Status:** Design spec — ready for `writing-plans` pass.
**Part of:** Songwriter C v2 slice 1 (sibling to C v2-b library-match).
**Depends on:** C v1 CAGED voicings (done on `worktree-songwriter-ux-polish`).

## 1. Goal

Tap a harmony block in the Writer tab → see a **Harmony** tab in the sheet (next to the existing **Voicings** tab) → one card showing the **full chord shifted up a diatonic 3rd** as a piano highlight → one-tap accept persists a `PianoSnapshot` `SaveEntry` in a "Songwriter harmonies" folder and inserts a save-lane block aligned to the harmony block's bars.

The slice deliberately punts the arpeggio/sequence save type: a static `PianoSnapshot` is enough for a "shadow chord" guide. The dedicated arpeggio/sequence type is deferred until a slice actually needs ordered note motion (whole-section harmony lines, riffs).

## 2. Scope

### In scope (v1 of v2-a)

- One suggestion type: 3rd-above (full chord, diatonic).
- Granularity: per harmony block, one save per chord.
- Instrument: piano (`PianoSnapshot`).
- Surface: extend `showHarmonyBlockSheet` with a `TabBar` — Voicings tab keeps the existing CAGED strip, Harmony tab shows one 3rd-above card.
- Accept: 1-tap → `SaveEntry` in auto-created folder "Songwriter harmonies" + save-lane block aligned to the harmony block's `startBar` / `spanBars`. Save lane resolution: same logic as C v1 (first existing save lane by `order`, else auto-create).

### Out of scope (deferred)

- Arpeggio / ordered note-sequence save type (deferred until whole-section lines or riffs).
- 6th-above, 5th-below, octave-doubled, other harmony intervals.
- Whole-section harmony line (one save spanning the progression).
- Fretboard rendering of the harmony (piano-only for now).
- User-configurable octave / voice range (v1 uses a single middle-octave fallback).
- Dim / aug / non-diatonic chord support beyond what falls cleanly out of the rule.

## 3. Decisions (locked from brainstorm)

| ID | Decision |
|----|----------|
| C2A-1 | **Per-block granularity**: one chord → one save. No multi-block sequence. |
| C2A-2 | **Instrument: piano** (`PianoSnapshot`). Future v2-c may add a fretboard variant. |
| C2A-3 | **Content**: full chord shifted up by a **diatonic 3rd** in the project key. C major (C-E-G) in C major key → highlight (E-G-B). |
| C2A-4 | **Surface**: tabs in the existing `showHarmonyBlockSheet` — `Voicings` (existing CAGED) + `Harmony`. |
| C2A-5 | **Accept**: 1-tap → persisted `SaveEntry` in **new** auto-created folder "Songwriter harmonies" + save-lane block aligned to the harmony block's bars. Same lane resolution as v1. |

## 4. Architecture

### 4.1 Pure rules — `lib/schema/rules/songwriter_third_above_rules.dart` (NEW)

```dart
class ThirdAboveSuggestion {
  const ThirdAboveSuggestion({
    required this.rootPc,
    required this.quality,
    required this.sourcePcs,
    required this.targetPcs,
    required this.midiKeys,
    required this.label,
  });
  /// Original chord root pitch class.
  final int rootPc;
  /// Original chord quality string ('', 'm', etc.).
  final String quality;
  /// Pitch classes of the source chord (e.g. [0, 4, 7] for C major).
  final List<int> sourcePcs;
  /// Pitch classes of the diatonic 3rd-above of every source pc that lies
  /// in the key's scale. Source pcs not in the scale are dropped.
  final List<int> targetPcs;
  /// MIDI note numbers for the targetPcs in a single anchored octave
  /// (see §4.1 "Octave anchoring").
  final List<int> midiKeys;
  /// Human-readable label, e.g. "3rd above (E, G, B)".
  final String label;
}

/// Returns a single 3rd-above suggestion for the given chord in the given
/// key, or null when no key is set or no source pcs are in the key's scale.
ThirdAboveSuggestion? suggestThirdAbove({
  required int chordRootPc,
  required String chordQuality,
  required List<int> chordTonePcs,
  required int? keyRootPc,
  required String? keyScaleName,
});
```

**Algorithm:**

1. If `keyRootPc == null` or `keyScaleName == null` or `scaleIntervals[keyScaleName] == null` → return `null`.
2. Resolve `intervals = scaleIntervals[keyScaleName]` (list of 7 semitone offsets from the key root).
3. Build `scalePcs = intervals.map((i) => (keyRootPc + i) % 12).toSet()`.
4. For each source pitch class `sourcePc` in `chordTonePcs`:
   - Compute `offset = ((sourcePc - keyRootPc) % 12 + 12) % 12`.
   - `degree = intervals.indexOf(offset)`. If `< 0`, source pc isn't in scale — skip.
   - `targetDegree = (degree + 2) % 7` (diatonic 3rd up).
   - `targetPc = (keyRootPc + intervals[targetDegree]) % 12`.
   - Append `targetPc` to `targetPcs` (preserving source order, deduping if already present).
5. If `targetPcs.isEmpty` → return `null` (the source chord is fully non-diatonic).
6. Octave anchoring (see below) → compute `midiKeys`.
7. Build label `"3rd above (${targetPcs.map(chromaticNotes).join(', ')})"`.

**Octave anchoring:**

- For each `targetPc`, compute `midi = 60 + targetPc` so notes sit in the C4..B4 window (MIDI 60..71).
- This keeps highlighted keys clustered in one octave for clean visual reading. v1 punts cleverer voicing.

### 4.2 Save factory

Add to the same rules file:

```dart
PianoSnapshot thirdAboveToSnapshot(ThirdAboveSuggestion s) {
  // key49: startMidi = 36 (C2). keyIndex = midi - startMidi.
  const startMidi = 36;
  return PianoSnapshot(
    currentRange: PianoRangeName.key49,
    selectedKeys: [
      for (final m in s.midiKeys)
        PianoCoordinate(
          keyIndex: m - startMidi,
          midiNote: m,
          noteName: chromaticNotes[m % 12],
        ),
    ],
    selectedNotes: [for (final pc in s.targetPcs) chromaticNotes[pc]],
    viewMode: PianoViewMode.exact,
  );
}
```

> `keyIndex` is **range-relative** in this codebase (verified in `lib/schema/rules/piano_rules.dart` `getKeysForRange` — `keyIndex: keys.length` iterates from the range's `startMidi`). For `PianoRangeName.key49` the range is C2..C6 → `startMidi = 36`. Anchored notes (MIDI 60..71) land at `keyIndex` 24..35 within the 49-key range.

### 4.3 Store action — `lib/store/songwriter_store.dart` (MODIFY)

Add `acceptThirdAboveSuggestion`, mirroring `acceptVoicingSuggestion`:

```dart
Future<void> acceptThirdAboveSuggestion({
  required String sectionId,
  required String harmonyBlockId,
  required ThirdAboveSuggestion suggestion,
}) async {
  // Same shape as acceptVoicingSuggestion:
  // 1. Locate harmony block (return silently if missing).
  // 2. _findOrCreateHarmoniesFolder() — root-level "Songwriter harmonies".
  // 3. saveSnapshot(name, folderId, thirdAboveToSnapshot(suggestion)).
  //    Name format: '${rootName}${quality} — ${suggestion.label}'.
  // 4. _findOrCreateSaveLane(sectionId).
  // 5. addSaveBlock(sectionId, laneId, saveId, harmonyBlock.startBar,
  //    harmonyBlock.spanBars).
}
```

New private helper:

```dart
String? _findOrCreateHarmoniesFolder(SaveSystemNotifier saves) {
  // Mirror _findOrCreateVoicingsFolder but with `_harmoniesFolderName`.
}
```

And a top-level const:

```dart
const _harmoniesFolderName = 'Songwriter harmonies';
```

`_findOrCreateSaveLane` is reused unchanged (already in store from C v1).

### 4.4 Harmony sheet — `lib/features/songwriter/songwriter_block_preview.dart` (MODIFY)

Convert the body of `showHarmonyBlockSheet` to use a `DefaultTabController` + `TabBar` + `TabBarView`. Chord header + chord-note chips stay above the tabs. Tabs:

- **Voicings** (existing): the CAGED card strip.
- **Harmony**: a single column with one `_ThirdAboveCard` (or a "Set a key" / "No 3rd-above available" empty state).

```dart
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> voicings,
  required ThirdAboveSuggestion? thirdAbove,
  required void Function(VoicingSuggestion) onAcceptVoicing,
  required void Function(ThirdAboveSuggestion) onAcceptThirdAbove,
}) { ... }
```

Note the parameter rename `suggestions → voicings` and the added `thirdAbove + onAcceptThirdAbove`. Tile call site updates accordingly (see §4.5).

`_ThirdAboveCard` mirrors `_VoicingCard` (same width, same `SavePreviewThumbnail` + label pattern, but rendering the `PianoSnapshot` produced by `thirdAboveToSnapshot`).

Tab labels can be plain `'Voicings'` / `'Harmony'`. Default selected tab: Voicings (matches existing behaviour).

### 4.5 Tile wiring — `lib/features/songwriter/songwriter_block_tile.dart` (MODIFY)

`_onTap` already branches harmony blocks (C v1 Task 4). The harmony branch now also computes the 3rd-above suggestion and passes both `voicings` + `thirdAbove` into the sheet, plus both `onAccept*` callbacks routing to the matching store actions.

```dart
if (block.chordRootPc != null && block.chordQuality != null) {
  final cfg = ref.read(songwriterProvider).config;
  final voicings = suggestVoicings(
    chordRootPc: block.chordRootPc!,
    quality: block.chordQuality!,
  );
  final thirdAbove = suggestThirdAbove(
    chordRootPc: block.chordRootPc!,
    chordQuality: block.chordQuality!,
    chordTonePcs: _chordPcs(block), // helper: derive ints from block.chordNotes
    keyRootPc: cfg.keyRoot,
    keyScaleName: cfg.keyScaleName,
  );
  showHarmonyBlockSheet(
    context,
    block: block,
    voicings: voicings,
    thirdAbove: thirdAbove,
    onAcceptVoicing: (v) => ref.read(songwriterProvider.notifier)
        .acceptVoicingSuggestion(...),
    onAcceptThirdAbove: (s) => ref.read(songwriterProvider.notifier)
        .acceptThirdAboveSuggestion(...),
  );
  return;
}
```

`_chordPcs(block)` converts `block.chordNotes` (`List<String>` like `['C', 'E', 'G']`) to `List<int>` via `noteToPC`.

### 4.6 Data flow

```
tap harmony block
  → _onTap (existing branch)
  → suggestVoicings(...) + suggestThirdAbove(...)
  → showHarmonyBlockSheet (Voicings | Harmony tabs)
  → user picks tab + taps a card
  → onAcceptVoicing OR onAcceptThirdAbove
  → store action persists SaveEntry in folder + inserts save-lane block
  → sheet closes
```

## 5. Edge cases

| Case | Behavior |
|------|----------|
| No key set in project (`keyRoot == null` or `keyScaleName == null`) | Harmony tab shows "Set a key to see harmony suggestions" |
| Source chord fully non-diatonic (no source pc in scale) | Harmony tab shows "No 3rd-above available for this chord" |
| Source chord partially non-diatonic | Skip non-diatonic source pcs; produce a possibly-shorter `targetPcs`. Card renders with however many target notes resulted. |
| Block has `chordRootPc == null` (degenerate harmony block) | Tabs hidden — sheet shows "Set a chord to see voicings" (existing v1 behaviour, unchanged) |
| User accepts the same 3rd-above twice | Two `SaveEntry`s created. Library dedup is out of scope. |
| User has no "Songwriter harmonies" folder | Auto-created on first accept |
| `acceptThirdAboveSuggestion` block alignment overlaps existing save lane block | Existing `addSaveBlock` silently rejects (current C v1 behaviour). UI does not error; sheet still closes. |

## 6. Tests

| Layer | File | Coverage |
|-------|------|----------|
| Pure rules | `test/schema/rules/songwriter_third_above_test.dart` | C major in C major → targets E, G, B; A minor in C major → targets C, E, G; Bdim (B, D, F) in C major → targets D, F, A (vii° works because all chord tones are in scale); G major in F major → drops F♯ if non-diatonic (only some target pcs survive); no key → null; key with unknown scale → null; chord with no diatonic tones → null |
| Save factory | (same file) | `thirdAboveToSnapshot` round-trip: `selectedNotes` matches `targetPcs` mapped to names, `selectedKeys` length matches |
| Store | `test/store/songwriter_third_above_accept_test.dart` | `acceptThirdAboveSuggestion`: creates SaveEntry in auto-created "Songwriter harmonies" folder, inserts save-lane block at harmony block's bars; second accept reuses both folder + save lane (no duplication); harmonies folder and voicings folder coexist (separate names) |
| Widget | `test/features/songwriter/songwriter_third_above_sheet_test.dart` | Tab bar shows Voicings + Harmony; switching to Harmony shows the card; tapping card fires `onAcceptThirdAbove` + closes sheet; "Set a key" message when no key in project; "No 3rd-above available" when `thirdAbove == null` and key is set |

Test gotchas from v1: 500 ms debounce drain (`await tester.pump(const Duration(milliseconds: 600))`) after store mutations in widget tests.

## 7. File map (new + modified)

| File | Status | Responsibility |
|------|--------|----------------|
| `lib/schema/rules/songwriter_third_above_rules.dart` | NEW | `ThirdAboveSuggestion`, `suggestThirdAbove`, `thirdAboveToSnapshot` |
| `lib/store/songwriter_store.dart` | MODIFY | add `acceptThirdAboveSuggestion`, `_findOrCreateHarmoniesFolder`, top-level `_harmoniesFolderName` const |
| `lib/features/songwriter/songwriter_block_preview.dart` | MODIFY | refactor `showHarmonyBlockSheet` to `DefaultTabController`; rename `suggestions` param to `voicings`; add `thirdAbove` param + `onAcceptThirdAbove`; add `_ThirdAboveCard` |
| `lib/features/songwriter/songwriter_block_tile.dart` | MODIFY | `_onTap` harmony branch computes both suggestions, passes both onAccept callbacks; new private helper `_chordPcs(block)` |
| `test/schema/rules/songwriter_third_above_test.dart` | NEW | pure rule tests |
| `test/store/songwriter_third_above_accept_test.dart` | NEW | store tests |
| `test/features/songwriter/songwriter_third_above_sheet_test.dart` | NEW | widget tests |

No model changes. No migration. Existing saves and existing "Songwriter voicings" folder untouched.

## 8. Risks / future slices (NOT v1 of v2-a)

- **Arpeggio / sequence save type** — deferred again. The slice that forces it is a true multi-note moving line (e.g. a riff that arpeggiates each chord's 3rds across beats). Static piano highlights cover the v2-a use case.
- **Voice range / octave clustering** — v1 jams everything into C4..B4 which can sound thin. v2-c could expose an octave chip in the sheet.
- **6th-above, 5th-below, etc.** — same rule shape, different `+ degree` offset. Future iterations multiply cards on the Harmony tab.
- **Fretboard 3rd-above variant** — recompute on the fretboard for guitar players. Optional v2-d.

## 9. Out-of-scope decisions deliberately left to the implementation plan

- Whether the Harmony tab card uses the same width as voicing cards (default: yes) or grows to fill the tab body.
- Exact label format ("3rd above" vs "Harmony (3rd above)" vs note list).
- Whether the Voicings tab is the default selection on every open (default: yes).
- Whether the PianoSnapshot `currentRange` should be `key49` or `key61` (default: `key49` for compact preview thumbnails).
