# Songwriter — Phase C v2-b: Library-Match Suggestions

**Date:** 2026-06-04
**Status:** Design spec — ready for `writing-plans` pass.
**Part of:** Songwriter C v2 slice 2 (sibling to C v2-a 3rd-above harmony).
**Depends on:** C v1 CAGED voicings (done on `worktree-songwriter-ux-polish`).
**Includes prerequisite:** Songwriter project naming + linked top-level folder (described in §4.1; affects C v1 + C v2-a retroactively).

## 1. Goal

Tap a harmony block in the Writer tab → see a third **Library** tab in the sheet (next to **Voicings** and the **Harmony** tab from v2-a) → list user's existing `SaveEntry`s that fit the chord or the project key → one-tap accept inserts a save-lane block pointing at the existing save (no duplication). The library is scoped to the **song-named top-level folder** (and its descendants), reflecting the convention "top-level folder = song, inner folders = sections."

## 2. Scope

### In scope (v1 of v2-b)

- **Project naming + folder linking prerequisite** (§4.1): Songwriter project gains a `name` field. The system maintains a top-level save folder with exactly that name. Voicings and harmonies created by C v1 and C v2-a are redirected into that folder.
- **Match rule**: union of two predicates per harmony block:
  - **Chord matches**: `save.snapshot.pendingChord?.symbol == block.chordSymbol`
  - **Scale matches**: every pitch class in `save.snapshot.selectedNotes` is in the project key's scale
- **Search scope**: the song-named folder + every descendant folder. Saves outside the song's folder are not considered.
- **Library tab UI**: two labeled groups — "Matches this chord" + "Fits this key". Within each group, sort by `save.updatedAt` descending. Cards reuse `SavePreviewThumbnail`.
- **Accept = insert save-lane block referencing the existing `saveId`** (no new SaveEntry). Bar alignment + auto save lane = same as v1 / v2-a.

### Out of scope (deferred)

- Per-section subfolders inside the song's folder (the user's model anticipates them, but v1 of v2-b only consumes them — auto-creating section subfolders is a separate slice).
- Manual folder linking via picker (auto-link by exact name only).
- Fuzzy name matching, alias mapping.
- Folder rename driven by external save-library renames (one-way: rename project → rename folder; reverse direction deferred).
- Ranking signals beyond `updatedAt` (most-used, recency-of-acceptance, instrument bias).
- Dedup against saves already inserted in the section.
- Cross-song match suggestions ("you have a similar chord in your other song").

## 3. Decisions (locked from brainstorm)

| ID | Decision |
|----|----------|
| C2B-1 | **Project ↔ folder binding by exact name**: `SongwriterProjectSnapshot` gets a `name` field. The store finds-or-creates a top-level folder with that name; if it exists, links to it. Renaming the project renames the folder. |
| C2B-2 | **Match union**: chord match OR scale match. Each save is tagged with its match kind so the UI can label it. |
| C2B-3 | **Search scope**: the song's folder and all descendants (per user's model "inner folder = section"). Saves elsewhere ignored. |
| C2B-4 | **Surface**: third tab in the harmony sheet — "Library" — alongside Voicings (v1) and Harmony (v2-a). |
| C2B-5 | **Accept** = save-lane block referencing existing `saveId`. No new SaveEntry. Bar alignment + auto save lane reuse the v1 helpers. |
| C2B-6 | **Retroactive change to C v1 and C v2-a**: the previously flat "Songwriter voicings" and "Songwriter harmonies" folders are dropped. Accepted voicings and harmonies are written into the song-named folder. (See §4.5 for migration notes.) |

## 4. Architecture

### 4.1 Prerequisite — project naming + folder linking

#### Model — `lib/models/songwriter.dart` (MODIFY)

Add a `name` field to `SongwriterProjectSnapshot`:

```dart
class SongwriterProjectSnapshot {
  final String name;             // NEW: human-readable project name
  final SongwriterConfig config;
  final List<SongSection> sections;
  // existing copyWith / toJson / fromJson updated to include `name`
}
```

Default for new projects: `'Untitled song'` (or similar). `fromJson` falls back to that when `name` is missing (back-compat for existing saved sessions).

#### Store — `lib/store/songwriter_store.dart` (MODIFY)

```dart
/// Renames the project. Triggers folder rename via the save-system store.
void setProjectName(String name) {
  if (name.trim().isEmpty) return;
  final old = state.name;
  _set(state.copyWith(name: name.trim()));
  _renameProjectFolderIfExists(old, name.trim());
}

/// Returns the id of the song's top-level folder, creating it if missing.
String? _projectFolderId(SaveSystemNotifier saves) {
  final name = state.name.trim();
  if (name.isEmpty) return null;
  final existing = ref
      .read(saveSystemProvider)
      .folders
      .where((f) => f.parentId == null && f.name == name)
      .toList();
  if (existing.isNotEmpty) return existing.first.id;
  return saves.createSaveFolder(name, null);
}

void _renameProjectFolderIfExists(String oldName, String newName) {
  if (oldName.trim().isEmpty || oldName == newName) return;
  final saves = ref.read(saveSystemProvider);
  final folder = saves.folders
      .firstWhereOrNull((f) => f.parentId == null && f.name == oldName);
  if (folder == null) return;
  ref.read(saveSystemProvider.notifier).renameFolder(folder.id, newName);
}
```

> The store needs to import `package:collection/collection.dart` for `firstWhereOrNull`, or open-code it. Plan to pick one.

#### Header UI — `lib/features/songwriter/songwriter_header.dart` (MODIFY)

Add a tappable project-name chip on the left side of the header. Tap → text-field dialog → `setProjectName`. The chip displays the current name (or "Untitled song").

#### Retroactive update to v1 / v2-a accept flows

- `acceptVoicingSuggestion` (v1): replace `_findOrCreateVoicingsFolder` with `_projectFolderId(saves)`. Drop the `_voicingsFolderName` const.
- `acceptThirdAboveSuggestion` (v2-a): same — replace `_findOrCreateHarmoniesFolder` with `_projectFolderId(saves)`. Drop the `_harmoniesFolderName` const.

Both now write into the song's folder. Existing tests for v1 (and v2-a once landed) update their folder-name assertions to read `state.name`.

### 4.2 Pure rules — `lib/schema/rules/songwriter_library_match_rules.dart` (NEW)

```dart
enum LibraryMatchKind { chord, scale }

class LibraryMatch {
  const LibraryMatch({required this.entry, required this.kind});
  final SaveEntry entry;
  final LibraryMatchKind kind;
}

/// Splits all saves in [searchableSaves] into chord-matches and scale-matches
/// for the given harmony block + project key. A save can appear at most once
/// across both buckets (chord-match wins if it satisfies both).
({List<LibraryMatch> chordMatches, List<LibraryMatch> scaleMatches})
    matchLibrary({
  required SongBlock harmonyBlock,
  required List<SaveEntry> searchableSaves,
  required int? keyRootPc,
  required String? keyScaleName,
});
```

**Algorithm:**

1. Build `chordSymbol = harmonyBlock.chordSymbol`. If null, return empty buckets.
2. Build `scalePcs`:
   - If `keyRootPc == null` or `keyScaleName == null` → empty.
   - Else: `scaleIntervals[keyScaleName].map((i) => (keyRootPc + i) % 12).toSet()`.
3. For each `save` in `searchableSaves`:
   - Compute `chordHit = chordSymbol != null && save.snapshot.pendingChord?.symbol == chordSymbol`.
   - Compute `scaleHit = scalePcs.isNotEmpty && save.snapshot.selectedNotes.isNotEmpty && save.snapshot.selectedNotes.every((n) => scalePcs.contains(noteToPC[n]))`.
   - If `chordHit` → append to `chordMatches`. Else if `scaleHit` → append to `scaleMatches`.
4. Sort each list by `entry.updatedAt` descending.
5. Return both.

> `noteToPC` from `lib/utils/note_utils.dart` maps note names to pitch classes. `scaleIntervals` likewise.

### 4.3 Searchable-saves resolver — `lib/store/songwriter_store.dart` (MODIFY)

Add a public helper (reused by the tile):

```dart
/// Returns saves in the song's folder and all descendant folders.
List<SaveEntry> searchableSavesForLibraryMatch() {
  final saves = ref.read(saveSystemProvider);
  final rootId = _projectFolderId(ref.read(saveSystemProvider.notifier));
  if (rootId == null) return const [];
  final include = <String>{rootId};
  // Walk descendants iteratively.
  final queue = [rootId];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    for (final f in saves.folders) {
      if (f.parentId == id) {
        include.add(f.id);
        queue.add(f.id);
      }
    }
  }
  return saves.saves.where((s) => include.contains(s.folderId)).toList();
}
```

> Watch for accidental folder creation: `_projectFolderId` will create the folder if missing. Plan should add a `createIfMissing: false` variant so reading "what's searchable" doesn't auto-create the folder. Suggest extracting `_findProjectFolderId` (read-only) vs `_findOrCreateProjectFolderId`.

### 4.4 Store action — `acceptLibraryMatch`

```dart
void acceptLibraryMatch({
  required String sectionId,
  required String harmonyBlockId,
  required String saveId,
}) {
  // 1. Locate harmony block (return silently if missing).
  // 2. final laneId = _findOrCreateSaveLane(sectionId);
  // 3. addSaveBlock(sectionId, laneId, saveId, harmonyBlock.startBar,
  //    harmonyBlock.spanBars).
}
```

No SaveEntry creation. Bar alignment + auto save lane reuse C v1's helpers.

### 4.5 Library tab — `lib/features/songwriter/songwriter_block_preview.dart` (MODIFY)

Extend the v2-a tabbed `showHarmonyBlockSheet` with a third tab `Library`. Tab content:

- If `keyRootPc == null && chordSymbol == null` → "Library matches need a key or a chord."
- Else if `chordMatches.isEmpty && scaleMatches.isEmpty` → "No matching saves in this song's folder yet."
- Else: two labeled sections rendered as vertical lists (or horizontal strips, mirroring v1/v2-a):
  - "Matches this chord" — one card per `LibraryMatch.chord`
  - "Fits this key" — one card per `LibraryMatch.scale`
  - Each card: `SavePreviewThumbnail(snapshot: entry.snapshot, ...)` + entry name + match badge ("chord" or "scale"). Tap → `onAcceptLibrary(entry.id)` + sheet closes.

Sheet signature is updated again:

```dart
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> voicings,
  required ThirdAboveSuggestion? thirdAbove,
  required List<LibraryMatch> chordMatches,
  required List<LibraryMatch> scaleMatches,
  required void Function(VoicingSuggestion) onAcceptVoicing,
  required void Function(ThirdAboveSuggestion) onAcceptThirdAbove,
  required void Function(String saveId) onAcceptLibrary,
});
```

### 4.6 Tile wiring — `lib/features/songwriter/songwriter_block_tile.dart` (MODIFY)

`_onTap`'s harmony branch now resolves the library matches before showing the sheet:

```dart
final searchable = ref.read(songwriterProvider.notifier)
    .searchableSavesForLibraryMatch();
final matches = matchLibrary(
  harmonyBlock: block,
  searchableSaves: searchable,
  keyRootPc: cfg.keyRoot,
  keyScaleName: cfg.keyScaleName,
);
showHarmonyBlockSheet(
  context,
  block: block,
  voicings: voicings,
  thirdAbove: thirdAbove,
  chordMatches: matches.chordMatches,
  scaleMatches: matches.scaleMatches,
  onAcceptVoicing: ...,
  onAcceptThirdAbove: ...,
  onAcceptLibrary: (saveId) => ref.read(songwriterProvider.notifier)
      .acceptLibraryMatch(
        sectionId: widget.sectionId,
        harmonyBlockId: widget.blockId,
        saveId: saveId,
      ),
);
```

### 4.7 Data flow

```
tap harmony block
  → _onTap (existing branch)
  → suggestVoicings + suggestThirdAbove + matchLibrary(searchableSaves)
  → showHarmonyBlockSheet (Voicings | Harmony | Library tabs)
  → user picks Library tab + taps a card
  → onAcceptLibrary(saveId)
  → store.acceptLibraryMatch → addSaveBlock (no new SaveEntry)
  → sheet closes
```

## 5. Edge cases

| Case | Behavior |
|------|----------|
| Project's folder doesn't exist yet (no saves accepted before) | `searchableSavesForLibraryMatch` returns empty → Library tab shows "No matching saves in this song's folder yet." |
| Project `name` is empty / whitespace | `setProjectName` rejects it. `_projectFolderId` returns null → searchable empty. |
| Two saves match both chord AND scale criteria | Chord match wins (deduped — appears only in chord-matches list) |
| Save has `selectedNotes == []` (e.g. blank highlight) | Skipped — not scale-matched (requires non-empty notes) |
| Save name unchanged but its pendingChord changes (e.g. user edited a fretboard save) | Re-evaluated on next sheet open — no caching |
| User renames the project while a folder with the new name already exists | `renameFolder` is called against the OLD folder id; collision with the existing same-named folder is up to the save store (current behaviour: rename succeeds, two same-named folders coexist; v1 of v2-b accepts this). Future slice: collision resolution. |
| `block.chordRootPc == null` | Library tab still renders — searches by chord symbol only (which is also null → no chord matches). Scale matches still run if a key is set and `selectedNotes` are diatonic. |
| Existing v1 voicings folder "Songwriter voicings" already exists | Left in place. The retroactive change only affects new accepts; old saves stay where they are. No migration script. Document for the user that they can move them manually if desired. |
| Block bars already occupied by an existing save block in the lane | `addSaveBlock` silently rejects via `blocksOverlap` (existing v1 behaviour). UI does not error; sheet still closes. |

## 6. Tests

| Layer | File | Coverage |
|-------|------|----------|
| Model | `test/models/songwriter_project_name_test.dart` | `SongwriterProjectSnapshot.copyWith(name: ...)`, `toJson/fromJson` round-trip preserves name, `fromJson` defaults missing name to 'Untitled song' |
| Pure rules | `test/schema/rules/songwriter_library_match_test.dart` | C major chord block + 'Cmaj' save → chord match; scale-only fit (E minor pentatonic over A minor key, all in scale) → scale match; save that matches both → only chord-match bucket; empty buckets when no key + no chord; sort order is `updatedAt` desc |
| Store — folder linking | `test/store/songwriter_project_folder_test.dart` | `setProjectName` triggers folder rename when the named folder already exists; project rename twice → folder rename twice; `_projectFolderId` returns null when name is empty; `searchableSavesForLibraryMatch` walks descendant folders; does NOT auto-create the project folder (verify via `read-only` variant) |
| Store — accept | `test/store/songwriter_library_accept_test.dart` | `acceptLibraryMatch` inserts a save-lane block at the harmony block's bars; second accept on the same lane respects overlaps; no new SaveEntry created (saves count unchanged) |
| Store — retroactive | `test/store/songwriter_voicing_accept_test.dart` (UPDATE) and `test/store/songwriter_third_above_accept_test.dart` (UPDATE if v2-a landed) | Folder name in assertion = project name (default 'Untitled song'), not "Songwriter voicings" / "Songwriter harmonies" |
| Widget | `test/features/songwriter/songwriter_library_tab_test.dart` | Library tab present alongside Voicings + Harmony; renders chord-matches + scale-matches groups; tap card fires `onAcceptLibrary` with the right saveId + closes sheet; empty state messages |
| Widget — header | `test/features/songwriter/songwriter_project_name_test.dart` | Header chip renders the project name; tap → text-field dialog → `setProjectName` |

Test gotchas: 500 ms debounce drain after store mutations; override `saveSystemProvider`'s storage to keep folder/save state in-memory.

## 7. File map (new + modified)

| File | Status | Responsibility |
|------|--------|----------------|
| `lib/models/songwriter.dart` | MODIFY | add `name` field + copyWith/toJson/fromJson |
| `lib/schema/rules/songwriter_library_match_rules.dart` | NEW | `LibraryMatchKind`, `LibraryMatch`, `matchLibrary` |
| `lib/store/songwriter_store.dart` | MODIFY | `setProjectName`, `_findProjectFolderId` + `_findOrCreateProjectFolderId`, `_renameProjectFolderIfExists`, `searchableSavesForLibraryMatch`, `acceptLibraryMatch`; UPDATE existing `acceptVoicingSuggestion` (and `acceptThirdAboveSuggestion` if v2-a landed) to use the project folder; drop `_voicingsFolderName` const (and `_harmoniesFolderName` if landed) |
| `lib/features/songwriter/songwriter_header.dart` | MODIFY | project-name chip + rename dialog |
| `lib/features/songwriter/songwriter_block_preview.dart` | MODIFY | extend tabs to Voicings / Harmony / Library; add `_LibraryMatchCard`; add `chordMatches`, `scaleMatches`, `onAcceptLibrary` params |
| `lib/features/songwriter/songwriter_block_tile.dart` | MODIFY | resolve library matches and pass them through to the sheet |
| `test/models/songwriter_project_name_test.dart` | NEW | model name tests |
| `test/schema/rules/songwriter_library_match_test.dart` | NEW | rule tests |
| `test/store/songwriter_project_folder_test.dart` | NEW | folder linking + scope tests |
| `test/store/songwriter_library_accept_test.dart` | NEW | acceptLibraryMatch tests |
| `test/store/songwriter_voicing_accept_test.dart` | UPDATE | folder name assertion → project name |
| `test/store/songwriter_third_above_accept_test.dart` | UPDATE (if v2-a landed) | folder name assertion → project name |
| `test/features/songwriter/songwriter_library_tab_test.dart` | NEW | Library tab widget tests |
| `test/features/songwriter/songwriter_project_name_test.dart` | NEW | header chip + rename dialog tests |

## 8. Risks / future slices (NOT v1 of v2-b)

- **Per-section subfolders**: the user's model implies each section maps to an inner folder. v2-b only consumes them; auto-creating + binding them on section CRUD is a separate slice.
- **Folder-rename collisions**: renaming the project to an existing folder's name produces two same-named folders. Resolution (merge, prompt, refuse) is future work.
- **Migration of old voicings/harmonies folders**: existing accepted saves in the flat "Songwriter voicings" / "Songwriter harmonies" folders stay there. Optional v2-c slice: a one-tap "move into song folder" migration.
- **Ranking by use frequency**: v1 sorts by `updatedAt` only. A "most-recently-accepted in this song" tier is a v2-d nicety.
- **Cross-song matches**: explicitly out — but a "from your other songs" sub-list could land in v3.

## 9. Implementation ordering

Within v2-b's plan, tasks must run in this order to avoid breaking existing tests:

1. Model: add `name` field with safe default + JSON migration.
2. Store: add `setProjectName`, `_projectFolderId` helpers, `searchableSavesForLibraryMatch`.
3. Update `acceptVoicingSuggestion` (and v2-a's `acceptThirdAboveSuggestion` if present) to write to the project folder; update existing tests.
4. Add `matchLibrary` rule + tests.
5. Add `acceptLibraryMatch` store action + tests.
6. Extend the harmony sheet with Library tab + tests.
7. Update tile wiring.
8. Header project-name chip + rename dialog.
9. Verify + serve-sim.

## 10. Out-of-scope decisions deliberately left to the implementation plan

- Default project name string ("Untitled song" vs "New song" vs blank).
- Project-name chip visual style + dialog layout.
- Whether the Library tab is the default selection (default: keep Voicings as default).
- Card layout in the Library tab (horizontal strip per group vs vertical list per group).
