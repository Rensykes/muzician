# Songwriter — Phase C v1: CAGED Voicing Suggestions

**Date:** 2026-06-04
**Status:** Design spec — ready for `writing-plans` pass.
**Supersedes:** The "Phase C — Enrichment Design (SKETCH)" doc (`2026-06-03-songwriter-c-enrichment-design.md`) for the v1 slice. The sketch's other suggestion types (3rd-above lines, complementary scales, library-match) are deferred to future C slices.
**Depends on:** B2b (playback + tap-block preview sheet) and Chord Wheel — both done on branch `worktree-songwriter-ux-polish`, awaiting review.

## 1. Goal

Given a harmony block's chord in the Writer tab, surface up to 5 alternative **CAGED voicings** of that chord on the fretboard. One-tap acceptance creates a persisted fretboard save + a save-lane block aligned to the harmony block's bars. This is the thin vertical slice that wires up the suggestion → accept → save + block flow against the simplest possible engine; future slices reuse the surface and acceptance flow and only add new engines.

## 2. Scope

### In scope (v1)

- One suggestion type: CAGED voicings of a single harmony block's chord.
- Quality coverage: **major and minor triads only** (covers I, IV, V, ii, iii, vi from the chord wheel — ~98% of common songwriting).
- Trigger: tapping a harmony block opens a preview sheet that includes the chord header + a horizontal strip of voicing cards.
- Acceptance: one tap on a voicing card creates a `SaveEntry` (persisted in a "Songwriter voicings" folder) and inserts a save-lane block aligned to the harmony block's `startBar` / `spanBars`. Uses the section's existing save lane if present; otherwise auto-creates one.

### Out of scope (deferred to later C slices)

- New `InstrumentSnapshot` subtype (arpeggio/ordered sequence) — v1 uses existing `FretboardSnapshot`.
- Diminished, augmented, 7th, sus, extended chord voicings.
- 3rd-above / 6th-above harmony lines.
- Complementary scale highlights.
- Library-match engine (find user's saves whose notes fit the chord/key).
- Per-section "Suggest" panel, batch acceptance.
- Piano voicings (fretboard only for v1).
- Voicing dedup in the library, ranking by "diversity" vs already-accepted voicings.

## 3. Decisions (locked)

| ID | Decision |
|----|----------|
| C-1 | v1 slice uses **existing `FretboardSnapshot`**. No new save type is introduced. The arpeggio/sequence save-type decision is deferred to the v2 slice (harmony lines) where it actually drives behavior. |
| C-2 | Trigger surface: extend the existing tap-block preview sheet (built in B2b Task 7). For harmony blocks, the sheet shows chord info + a "Suggested voicings" horizontal strip. For save blocks the sheet behaves exactly as before. |
| C-3 | Engine: pure rule-based CAGED. No library-match in v1. |
| C-4 | "Complementary voicing" = a CAGED shape at a different neck position. v1 returns up to 5 shapes for major (C, A, G, E, D) and up to 3 for minor (Am, Em, Dm); the other minor shapes are not idiomatic in CAGED and are skipped. |
| C-5 | Accept = create `SaveEntry` (persisted to library, in a "Songwriter voicings" folder, auto-created on first accept) + insert save-lane block. Save lane: auto-uses the section's existing save lane if any, else auto-creates one. Block bars: same `startBar` and `spanBars` as the triggering harmony block. |

## 4. Architecture

### 4.1 Pure rules — `lib/schema/rules/songwriter_voicing_rules.dart` (NEW)

```dart
enum CagedShape { c, a, g, e, d }

class VoicingTemplate {
  final CagedShape shape;
  final String quality;          // '' (major) or 'm' (minor)
  final int anchorPc;            // pitch class of the chord root in the template
  final int anchorStringIndex;   // 6 = low E ... 1 = high e
  /// Frets per string, index 0 = low E (string 6), index 5 = high e (string 1).
  /// null = muted/unplayed.
  final List<int?> openShape;
}

class VoicingSuggestion {
  final CagedShape shape;
  final int rootPc;
  final String quality;
  final List<FretCoordinate> cells;
  final int lowestFret;
  final String label;            // e.g. "C-shape (open)" or "A-shape (3rd fret)"
}

/// Returns up to 5 CAGED voicings for the given chord, sorted by lowest fret
/// ascending. Returns empty when quality is not in {'', 'm'} or no shape fits
/// the 12-fret neck.
List<VoicingSuggestion> suggestVoicings({
  required int chordRootPc,
  required String quality,
});

/// Wraps a voicing's cells into a FretboardSnapshot (standard tuning, 12 frets,
/// capo 0, exact view, selectedNotes derived from cells).
FretboardSnapshot voicingToSnapshot(VoicingSuggestion v);
```

#### CAGED templates

Standard EADGBe tuning, string indexing: 6 = low E, 1 = high e. `null` = muted/unplayed.

**Major:**

| Shape | Anchor PC | Anchor string | openShape (strings 6→1) |
|-------|-----------|---------------|--------------------------|
| C | 0 (C) | 5 (A) | `[null, 3, 2, 0, 1, 0]` |
| A | 9 (A) | 5 (A) | `[null, 0, 2, 2, 2, 0]` |
| G | 7 (G) | 6 (E) | `[3, 2, 0, 0, 0, 3]` |
| E | 4 (E) | 6 (E) | `[0, 2, 2, 1, 0, 0]` |
| D | 2 (D) | 4 (D) | `[null, null, 0, 2, 3, 2]` |

**Minor:**

| Shape | Anchor PC | Anchor string | openShape (strings 6→1) |
|-------|-----------|---------------|--------------------------|
| A | 9 (A) | 5 (A) | `[null, 0, 2, 2, 1, 0]` |
| E | 4 (E) | 6 (E) | `[0, 2, 2, 0, 0, 0]` |
| D | 2 (D) | 4 (D) | `[null, null, 0, 2, 3, 1]` |

#### Transposition

For each template:
1. `shift = (chordRootPc - template.anchorPc + 12) % 12`
2. For every fretted string `s` (non-null fret `f`): new fret = `f + shift`.
3. If any new fret > 12 → skip this shape entirely (don't truncate).
4. `lowestFret` = min of all non-null new frets.
5. Convert to `List<FretCoordinate>` (each cell is `FretCoordinate(stringIndex: s, fret: newFret)`).
6. `label`: `"${shape.name.toUpperCase()}-shape (${lowestFret == 0 ? 'open' : '${_ordinal(lowestFret)} fret'})"`.

Sort the resulting list by `lowestFret` ascending.

### 4.2 Store — `lib/store/songwriter_store.dart` (MODIFY)

Add:

```dart
Future<void> acceptVoicingSuggestion({
  required String sectionId,
  required String harmonyBlockId,
  required VoicingSuggestion suggestion,
}) async {
  // 1. Read harmony block to capture startBar / spanBars.
  // 2. Resolve folder: _findOrCreateVoicingsFolder() returns the id of a
  //    "Songwriter voicings" folder at the save library root, creating it via
  //    saveSystemNotifier.createSaveFolder(name, parentId: null) on first call.
  // 3. Persist the voicing: saveSystemNotifier.saveSnapshot(
  //      name: '${rootName}${quality} — ${suggestion.label}',
  //      folderId: voicingsFolderId,
  //      snapshot: voicingToSnapshot(suggestion),
  //    ) → returns the new save id.
  // 4. Find-or-create save lane in the section:
  //      - existing lane with kind == SongLaneKind.save → use it
  //      - else addLane(sectionId, kind: SongLaneKind.save)
  // 5. addSaveBlock(sectionId, laneId, saveId, startBar, spanBars).
}
```

Helpers (private):

- `String _findOrCreateVoicingsFolder()` — returns the id of a folder named "Songwriter voicings" in the save library root. Creates it on first call. Idempotent.
- `String _findOrCreateSaveLane(SongSection section)` — returns lane id, creating a new save lane when none exists.

### 4.3 Preview sheet — `lib/features/songwriter/songwriter_block_preview.dart` (MODIFY)

Currently exports `showBlockPreviewSheet(context, snapshot)` for save blocks and `showBrokenReferenceSheet` for missing-save blocks. Add a third entry point:

```dart
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> suggestions,
  required void Function(VoicingSuggestion) onAccept,
});
```

Sheet body (top → bottom):

1. **Header row**: chord symbol + roman numeral (e.g. "C   I") in `titleMedium`, plus instrument icon (guitar).
2. **Chord notes row**: small chips of pitch classes (reuse the chip style from `showBlockPreviewSheet`).
3. **Empty / unsupported state**:
   - If `block.chordRootPc == null` → "Set a chord to see voicings."
   - Else if `suggestions.isEmpty` → "No voicings available for this chord (v1: major/minor triads only)."
4. **Suggested voicings strip**: horizontal `ListView` of voicing cards. Each card:
   - Small fretboard thumbnail rendered with the existing `_FretboardMiniPainter` (in `lib/ui/save_previews/save_preview_thumbnail.dart`). The painter is currently private; either promote it to public or expose a `SavePreviewThumbnail.fromSnapshot(snapshot)` wrapper (decide in the plan).
   - Label underneath: `suggestion.label`.
   - Tap → `onAccept(suggestion)` → sheet closes immediately. Suggestion handler in the tile awaits the store call.

### 4.4 Tile wiring — `lib/features/songwriter/songwriter_block_tile.dart` (MODIFY)

In `_onTap`:

```dart
if (block.chordRootPc != null && block.chordQuality != null) {
  // Harmony block: show the harmony sheet with voicing suggestions.
  final suggestions = suggestVoicings(
    chordRootPc: block.chordRootPc!,
    quality: block.chordQuality!,
  );
  showHarmonyBlockSheet(
    context,
    block: block,
    suggestions: suggestions,
    onAccept: (v) async {
      await ref.read(songwriterProvider.notifier).acceptVoicingSuggestion(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            suggestion: v,
          );
    },
  );
  return;
}
// Existing save-block flow (resolve snapshot → preview or broken-ref).
```

### 4.5 Data flow

```
tap harmony block
  → _onTap detects chordRootPc != null
  → suggestVoicings(chordRootPc, quality)
  → showHarmonyBlockSheet(suggestions)
  → user taps a voicing card
  → onAccept fires
  → store.acceptVoicingSuggestion
    → saveSystemProvider.createSave(folder, name, FretboardSnapshot)
    → find-or-create save lane in section
    → addSaveBlock(sectionId, laneId, saveId, startBar, spanBars)
  → sheet closes
  → save-lane block appears under the harmony block
```

## 5. Edge cases

| Case | Behavior |
|------|----------|
| Quality not in `{'', 'm'}` | `suggestVoicings` returns empty → sheet shows "No voicings available for this chord (v1: major/minor only)" |
| Shape's transposed top fret > 12 | Skip that shape (don't truncate) |
| Block has `chordRootPc == null` (degenerate harmony block) | Sheet shows "Set a chord to see voicings" — no list, no error |
| User taps the same voicing twice for the same chord | Allowed — creates two `SaveEntry`s. Library dedup deferred to v2. |
| Save lane creation fails (storage error) | Snackbar "Could not save voicing" — leave UI untouched, no partial state |
| User has no folders yet | "Songwriter voicings" folder is auto-created at the save library root on first accept |
| Section already has multiple save lanes | Use the **first** save lane in `lane.order` (deterministic) |
| Multiple harmony lanes in the section | Suggestion is keyed by the tapped harmony block; voicing goes into a save lane in the same section regardless of which harmony lane the chord came from |

## 6. Tests

| Layer | File | Coverage |
|-------|------|----------|
| Pure rules | `test/schema/rules/songwriter_voicing_test.dart` | `suggestVoicings` for `(0, '')` returns 5 shapes sorted, first is C-shape at fret 0; `(9, '')` includes A-shape at fret 0; `(0, 'm')` returns 3 shapes (Am at fret 3, Em at fret 8, Dm at fret 10); `(0, 'dim')` returns empty; transpose past fret 12 is dropped; `voicingToSnapshot` produces a `FretboardSnapshot` whose `selectedNotes` is exactly the chord's pitch classes |
| Store | `test/store/songwriter_voicing_accept_test.dart` | `acceptVoicingSuggestion`: creates `SaveEntry` in a "Songwriter voicings" folder (auto-created); creates a save lane if the section has none; reuses existing save lane otherwise; inserts the block at the harmony block's `startBar` / `spanBars`; second accept on the same section reuses the same folder + same save lane |
| Widget | `test/features/songwriter/songwriter_voicing_sheet_test.dart` | Tap harmony block → sheet opens, shows N voicing cards (N = suggestion count); tap card → store mutation fires + sheet closes (use the 500 ms debounce drain pattern); degenerate `chordRootPc == null` → "Set a chord" message; unsupported quality → "No voicings" message |

Test gotchas reminded from B2b/Chord Wheel:
- Drain the songwriter store 500 ms debounce with `await tester.pump(const Duration(milliseconds: 600))` after any block/lane/section mutation in widget tests.
- Override `saveSystemProvider` (or its storage backend) in store tests to capture writes without SharedPreferences round-tripping.

## 7. Risks / future slices (NOT v1)

- **Arpeggio / sequence save type** — the v2 "3rd-above harmony line" slice forces this design decision. v1 deliberately punts because static fretboard voicings don't need it.
- **Diversity ranking** — v1 sorts purely by lowest fret. If the user accepts the C-shape they then see the A-shape next time too. A "haven't-used-yet" boost is a v2 nicety.
- **Library-match engine** — find existing user saves whose pitch classes match the chord/key. Pure search, no new rules. Deferred to v2.
- **Piano voicings** — introduces instrument-pick UI on the sheet. Deferred.
- **7th, sus, dim, aug, extended qualities** — each adds template rows; not blocking but expands the rule table.

## 8. Out-of-scope decisions deliberately left to the implementation plan

- Exact label format ("C-shape (open)" vs "C-shape (fret 0)" vs "C-shape (open position)") — pick in plan.
- Voicing card visual style (thumbnail size, card border, accent-on-root). Defaults: ~80×60 thumbnail in a Material card, no special accent for v1.
- Whether `_FretboardMiniPainter` is promoted to public or wrapped behind a new factory on `SavePreviewThumbnail`. Either way it must be reachable from the new sheet — decide in the plan.
- Exact name of the auto-created folder — "Songwriter voicings" is the recommended default.

## 9. File map (new + modified)

| File | Status | Responsibility |
|------|--------|----------------|
| `lib/schema/rules/songwriter_voicing_rules.dart` | NEW | `CagedShape`, `VoicingTemplate`, `VoicingSuggestion`, `suggestVoicings`, `voicingToSnapshot` |
| `lib/store/songwriter_store.dart` | MODIFY | add `acceptVoicingSuggestion`, `_findOrCreateVoicingsFolder`, `_findOrCreateSaveLane` |
| `lib/features/songwriter/songwriter_block_preview.dart` | MODIFY | add `showHarmonyBlockSheet` |
| `lib/features/songwriter/songwriter_block_tile.dart` | MODIFY | `_onTap` branches harmony vs save block |
| `test/schema/rules/songwriter_voicing_test.dart` | NEW | pure rule tests |
| `test/store/songwriter_voicing_accept_test.dart` | NEW | store tests |
| `test/features/songwriter/songwriter_voicing_sheet_test.dart` | NEW | widget tests |

No model changes. No migration. Existing saves untouched.
