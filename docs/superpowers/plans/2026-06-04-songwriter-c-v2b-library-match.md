# Songwriter — Phase C v2-b: Library-Match Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Read `docs/superpowers/HANDOFF-songwriter.md` and `docs/superpowers/specs/2026-06-04-songwriter-c-v2b-library-match-design.md` first.**

**Goal:** Tap a harmony block → existing tabbed sheet gains a third tab **Library** that lists user saves whose `pendingChord.symbol` matches the block's chord OR whose `selectedNotes` all fit the project key's scale; one-tap accept inserts a save-lane block referencing the existing save (no duplication). The library is scoped to a **song-named top-level folder** introduced as a prerequisite: `SongwriterProjectSnapshot` gains a `name` field, the store maintains a top-level folder by exact name, and all previously-flat accept flows (C v1 voicings, C v2-a harmonies) are retroactively redirected into it.

**Architecture:** Add `name` to the project model with a JSON-back-compat default. Add `setProjectName` + project-folder helpers (`_findProjectFolderId` read-only; `_findOrCreateProjectFolderId` write) + `searchableSavesForLibraryMatch` (recursive subtree walk). Retroactively replace `_findOrCreateVoicingsFolder` (C v1) and `_findOrCreateHarmoniesFolder` (C v2-a) with the project-folder helper; delete the dropped consts. Add a pure rule `matchLibrary` that classifies each save as chord-match (`pendingChord.symbol == block.chordSymbol`) or scale-match (`selectedNotes ⊆ keyScalePcs`). Add `acceptLibraryMatch` (no SaveEntry creation — just `addSaveBlock`). Extend `showHarmonyBlockSheet` with a third Library tab rendering two labeled groups. Wire the tile to compute matches before opening the sheet. Add a project-name chip + rename dialog to the header.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses `SavePreviewThumbnail`, `saveSystemProvider`, `chromaticNotes`, `noteToPC`, `scaleIntervals`. No new external packages — `firstWhereOrNull` is open-coded to avoid a `package:collection` dependency.

**Spec:** `docs/superpowers/specs/2026-06-04-songwriter-c-v2b-library-match-design.md` (decisions C2B-1 through C2B-6).
**Depends on:** C v1 (done on branch `worktree-songwriter-ux-polish`) **+ C v2-a (assumed merged into the branch before v2-b execution).** The plan touches `acceptThirdAboveSuggestion`, `_findOrCreateHarmoniesFolder`, and `_harmoniesFolderName` introduced by v2-a; if v2-a has not landed, drop the v2-a-related steps from Task 3 and the related tests.

> **Read before starting:**
> - `lib/models/songwriter.dart` (`SongwriterProjectSnapshot` — constructor, `copyWith`, `toJson`, `fromJson` to be extended with `name`)
> - `lib/models/save_system.dart` (line 462: `SaveFolder` — `id`, `name`, `parentId`, `createdAt`, `order`; line 511: `SaveEntry` — `id`, `name`, `folderId`, `snapshot`, `createdAt`, `updatedAt`, `order`)
> - `lib/store/save_system_store.dart` (line 40: `createSaveFolder(name, parentId) → String?`; line 49: `renameFolder(id, name)`; line 83: `saveSnapshot(name, folderId, snapshot) → String?`; line 267: `saveSystemProvider`)
> - `lib/store/songwriter_store.dart` (existing C v1 `acceptVoicingSuggestion`, `_findOrCreateVoicingsFolder`, `_findOrCreateSaveLane`, top-level `_voicingsFolderName` const; post-v2-a `acceptThirdAboveSuggestion`, `_findOrCreateHarmoniesFolder`, `_harmoniesFolderName`)
> - `lib/features/songwriter/songwriter_block_preview.dart` (post-v2-a `showHarmonyBlockSheet(context, {block, voicings, thirdAbove, onAcceptVoicing, onAcceptThirdAbove})` with `DefaultTabController`)
> - `lib/features/songwriter/songwriter_block_tile.dart` (existing C v2-a `_onTap` harmony branch)
> - `lib/features/songwriter/songwriter_header.dart` (where the project-name chip goes — left side of the Row)
> - `lib/utils/note_utils.dart` (lines 24-156: `chromaticNotes`, `noteToPC`, `scaleIntervals`)
> - `test/store/songwriter_voicing_accept_test.dart` (folder-name assertion will move to project name)
> - `test/store/songwriter_third_above_accept_test.dart` (same)

Run `flutter test` for a green baseline (~445 tests after C v2-a).

---

### Task 1: Add `name` field to `SongwriterProjectSnapshot`

**Files:**
- Modify: `lib/models/songwriter.dart`
- Test: `test/models/songwriter_project_name_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/songwriter_project_name_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongwriterProjectSnapshot default name is "Untitled song"', () {
    const p = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );
    expect(p.name, 'Untitled song');
  });

  test('copyWith replaces name', () {
    const p = SongwriterProjectSnapshot(
      name: 'Old',
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );
    expect(p.copyWith(name: 'New').name, 'New');
    expect(p.copyWith().name, 'Old');
  });

  test('toJson includes name; fromJson round-trips it', () {
    const p = SongwriterProjectSnapshot(
      name: 'Song A',
      config: SongwriterConfig(tempo: 110, beatsPerBar: 3, beatUnit: 4),
      sections: [],
    );
    final j = jsonEncode(p.toJson());
    final back = SongwriterProjectSnapshot.fromJson(
      jsonDecode(j) as Map<String, dynamic>,
    );
    expect(back.name, 'Song A');
    expect(back.config.tempo, 110);
  });

  test('fromJson defaults missing name to "Untitled song"', () {
    final old = {
      'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
      'sections': <dynamic>[],
      // no 'name' field — simulating a saved session from before v2-b
    };
    final back = SongwriterProjectSnapshot.fromJson(old);
    expect(back.name, 'Untitled song');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/models/songwriter_project_name_test.dart`
Expected: FAIL — `name` field missing on the constructor.

- [ ] **Step 3: Implement**

Modify `lib/models/songwriter.dart`. Find the existing `class SongwriterProjectSnapshot` definition and apply these changes (preserve all other fields exactly as they are):

1. Add the field + named parameter:

```dart
class SongwriterProjectSnapshot {
  final String name;
  final SongwriterConfig config;
  final List<SongSection> sections;
  // ...existing fields stay...

  const SongwriterProjectSnapshot({
    this.name = 'Untitled song',
    required this.config,
    this.sections = const [],
    // ...existing required/optional params stay...
  });
  // ...
}
```

2. Update `copyWith`:

```dart
SongwriterProjectSnapshot copyWith({
  String? name,
  SongwriterConfig? config,
  List<SongSection>? sections,
  // ...existing nullable params stay...
}) => SongwriterProjectSnapshot(
      name: name ?? this.name,
      config: config ?? this.config,
      sections: sections ?? this.sections,
      // ...existing forwarding stays...
    );
```

3. Update `toJson` — add the `'name': name` entry to the existing map (alphabetical or wherever fits the existing order):

```dart
Map<String, dynamic> toJson() => {
  'name': name,
  // ...existing entries stay...
};
```

4. Update `fromJson` — read with a fallback:

```dart
factory SongwriterProjectSnapshot.fromJson(Map<String, dynamic> json) =>
    SongwriterProjectSnapshot(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Untitled song',
      config: SongwriterConfig.fromJson(
        json['config'] as Map<String, dynamic>,
      ),
      sections: (json['sections'] as List<dynamic>)
          .map((e) => SongSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      // ...existing forwarding stays...
    );
```

> The existing `SongwriterProjectSnapshot` may have additional fields (e.g. an embedded undo stack) — preserve them all. Only ADD `name`; do not remove or reorder anything else.

- [ ] **Step 4: Run it (PASS) + regression**

Run: `flutter test test/models/songwriter_project_name_test.dart`
Expected: PASS (4 tests).

Run: `flutter test test/store/`
Expected: existing store tests still pass (they call `SongwriterProjectSnapshot` constructors only via the store's defaults, which now include `name: 'Untitled song'`).

- [ ] **Step 5: Commit**

```bash
git add lib/models/songwriter.dart test/models/songwriter_project_name_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): SongwriterProjectSnapshot.name with JSON migration

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Project folder helpers + searchable-saves resolver

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_project_folder_test.dart`

Add `setProjectName`, the two project-folder helpers (read-only + write), `_renameProjectFolderIfExists`, and the public `searchableSavesForLibraryMatch` resolver. These are pure additions — no existing behavior changes yet.

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_project_folder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(saveSystemProvider.notifier);
    return c;
  }

  test('setProjectName updates the project name', () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    expect(c.read(songwriterProvider).name, 'Untitled song');
    sw.setProjectName('Song A');
    expect(c.read(songwriterProvider).name, 'Song A');
  });

  test('setProjectName rejects empty/whitespace', () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');
    sw.setProjectName('');
    sw.setProjectName('   ');
    expect(c.read(songwriterProvider).name, 'Song A');
  });

  test('setProjectName renames the project folder if it exists', () {
    final c = freshContainer();
    final saves = c.read(saveSystemProvider.notifier);
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');
    saves.createSaveFolder('Song A', null); // simulate the folder pre-existing
    sw.setProjectName('Song B');
    final folder = c
        .read(saveSystemProvider)
        .folders
        .singleWhere((f) => f.parentId == null);
    expect(folder.name, 'Song B');
  });

  test('searchableSavesForLibraryMatch is empty when project folder is missing',
      () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');
    expect(sw.searchableSavesForLibraryMatch(), isEmpty);
    // crucial: must NOT auto-create the project folder
    expect(c.read(saveSystemProvider).folders, isEmpty);
  });

  test('searchableSavesForLibraryMatch walks descendant folders', () {
    final c = freshContainer();
    final saves = c.read(saveSystemProvider.notifier);
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');

    final rootId = saves.createSaveFolder('Song A', null)!;
    final innerId = saves.createSaveFolder('Verse', rootId)!;
    final deeperId = saves.createSaveFolder('Chord palette', innerId)!;
    final unrelatedId = saves.createSaveFolder('Other song', null)!;

    // Saves in the project subtree
    saves.saveSnapshot('rootSave', rootId, _stubSnapshot());
    saves.saveSnapshot('innerSave', innerId, _stubSnapshot());
    saves.saveSnapshot('deeperSave', deeperId, _stubSnapshot());
    // Save outside the project subtree
    saves.saveSnapshot('outsideSave', unrelatedId, _stubSnapshot());

    final names = sw
        .searchableSavesForLibraryMatch()
        .map((s) => s.name)
        .toSet();
    expect(names, {'rootSave', 'innerSave', 'deeperSave'});
  });

  test('setProjectName with no prior folder does not error', () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    expect(() => sw.setProjectName('Song A'), returnsNormally);
    // No folders should be created by setProjectName itself
    expect(c.read(saveSystemProvider).folders, isEmpty);
  });
}

// Smallest valid InstrumentSnapshot for these tests (folder/search are the
// only things under test; snapshot content is irrelevant).
InstrumentSnapshot _stubSnapshot() => const _StubSnapshot();

class _StubSnapshot extends InstrumentSnapshot {
  const _StubSnapshot();
  @override
  String get instrument => 'stub';
  @override
  List<String> get selectedNotes => const [];
  @override
  PendingChord? get pendingChord => null;
  @override
  PendingScale? get pendingScale => null;
  @override
  Map<String, dynamic> toJson() => {'instrument': 'stub'};
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_project_folder_test.dart`
Expected: FAIL — `setProjectName` and `searchableSavesForLibraryMatch` don't exist; `_StubSnapshot` may not satisfy the existing `InstrumentSnapshot` abstract surface — if compilation fails on the stub, replace it with a real `FretboardSnapshot` with empty cells (see C v1 voicing tests for the constructor shape).

- [ ] **Step 3: Implement**

In `lib/store/songwriter_store.dart`:

1. Add the import for `save_system.dart` if it isn't already imported (the file imports it for `SaveEntry`):

```dart
import '../models/save_system.dart';
```

2. Inside the `SongwriterNotifier` class (place these methods next to the existing `acceptVoicingSuggestion` to keep folder logic co-located):

```dart
/// Updates the project's display name and renames its linked top-level
/// folder if one with the old name exists. Whitespace-only names are ignored.
void setProjectName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;
  final old = state.name;
  if (trimmed == old) return;
  _set(state.copyWith(name: trimmed));
  _renameProjectFolderIfExists(old, trimmed);
}

/// Returns the id of the project's top-level folder, or null when it does
/// not exist. Does NOT create the folder. Used by read-only callers like
/// the library-match resolver.
String? _findProjectFolderId() {
  final name = state.name.trim();
  if (name.isEmpty) return null;
  for (final f in ref.read(saveSystemProvider).folders) {
    if (f.parentId == null && f.name == name) return f.id;
  }
  return null;
}

/// Returns the id of the project's top-level folder, creating it if missing.
/// Used by accept flows that need to write a SaveEntry.
String? _findOrCreateProjectFolderId(SaveSystemNotifier saves) {
  final existing = _findProjectFolderId();
  if (existing != null) return existing;
  final name = state.name.trim();
  if (name.isEmpty) return null;
  return saves.createSaveFolder(name, null);
}

void _renameProjectFolderIfExists(String oldName, String newName) {
  final trimmedOld = oldName.trim();
  if (trimmedOld.isEmpty || trimmedOld == newName) return;
  for (final f in ref.read(saveSystemProvider).folders) {
    if (f.parentId == null && f.name == trimmedOld) {
      ref.read(saveSystemProvider.notifier).renameFolder(f.id, newName);
      return;
    }
  }
}

/// Returns the saves visible to library-match: the project's top-level
/// folder plus every descendant folder. Returns empty when the project
/// folder does not exist. Does NOT auto-create the folder.
List<SaveEntry> searchableSavesForLibraryMatch() {
  final rootId = _findProjectFolderId();
  if (rootId == null) return const [];
  final saves = ref.read(saveSystemProvider);
  final include = <String>{rootId};
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

> Open-coded `firstWhereOrNull` (the `for` loops above) avoids adding `package:collection`.

- [ ] **Step 4: Run it (PASS) + regression**

Run: `flutter test test/store/songwriter_project_folder_test.dart`
Expected: PASS (6 tests).

Run: `flutter test test/store/`
Expected: all existing store tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_project_folder_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): project name binding + searchable-saves resolver

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Retroactive — route v1 + v2-a accepts into the project folder

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Modify: `test/store/songwriter_voicing_accept_test.dart`
- Modify: `test/store/songwriter_third_above_accept_test.dart`

Delete the flat-folder helpers (`_findOrCreateVoicingsFolder`, `_findOrCreateHarmoniesFolder`) and consts (`_voicingsFolderName`, `_harmoniesFolderName`). Re-wire both accept flows to `_findOrCreateProjectFolderId`. Update the existing tests to assert against the project name ("Untitled song" by default).

- [ ] **Step 1: Run the existing tests (they FAIL after re-wiring — set the baseline first)**

Run: `flutter test test/store/songwriter_voicing_accept_test.dart test/store/songwriter_third_above_accept_test.dart`
Expected: PASS (they still target the flat folder names — baseline).

- [ ] **Step 2: Update the v1 voicing test for the project-folder behavior**

Open `test/store/songwriter_voicing_accept_test.dart`. The current tests assert:

```dart
expect(saves.folders.any((f) => f.name == 'Songwriter voicings'), isTrue);
final voicingsFolder =
    saves.folders.firstWhere((f) => f.name == 'Songwriter voicings');
```

Replace both with assertions against the project name:

```dart
expect(saves.folders.any((f) => f.name == 'Untitled song'), isTrue);
final projectFolder =
    saves.folders.firstWhere((f) => f.name == 'Untitled song');
```

Rename the local `voicingsFolder` variable to `projectFolder` throughout the test for clarity. The "second accept reuses the same folder" test similarly switches `Songwriter voicings` → `Untitled song`.

- [ ] **Step 3: Update the v2-a 3rd-above test for the project-folder behavior**

Open `test/store/songwriter_third_above_accept_test.dart`. The current tests assert:

```dart
final folder = saves.folders
    .where((f) => f.name == 'Songwriter harmonies')
    .toList();
```

Replace with `'Untitled song'`. The "harmonies and voicings folders coexist" test no longer makes sense — both flows now write into the same project folder. Replace that test with:

```dart
test('voicing accept + 3rd-above accept both land in the project folder',
    () async {
  final c = freshContainer();
  final ids = seedSongWithHarmonyBlock(c);

  await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
        sectionId: ids.sectionId,
        harmonyBlockId: ids.harmonyBlockId,
        suggestion: firstVoicingForC(),
      );
  // Move first block out of the way to avoid the second accept overlapping.
  final saveLaneId = c
      .read(songwriterProvider)
      .sections
      .firstWhere((s) => s.id == ids.sectionId)
      .lanes
      .firstWhere((l) => l.kind == SongLaneKind.save)
      .id;
  final firstBlockId = c
      .read(songwriterProvider)
      .sections
      .firstWhere((s) => s.id == ids.sectionId)
      .lanes
      .firstWhere((l) => l.kind == SongLaneKind.save)
      .blocks
      .single
      .id;
  c.read(songwriterProvider.notifier).setBlockPlacement(
        sectionId: ids.sectionId,
        laneId: saveLaneId,
        blockId: firstBlockId,
        startBar: 4,
        spanBars: 2,
      );
  await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
        sectionId: ids.sectionId,
        harmonyBlockId: ids.harmonyBlockId,
        suggestion: freshSuggestion(),
      );

  final folders = c
      .read(saveSystemProvider)
      .folders
      .where((f) => f.name == 'Untitled song')
      .toList();
  expect(folders.length, 1,
      reason: 'project folder must be a single folder');
  final saveCount = c
      .read(saveSystemProvider)
      .saves
      .where((s) => s.folderId == folders.single.id)
      .length;
  expect(saveCount, 2, reason: 'one voicing + one 3rd-above in the folder');
});
```

- [ ] **Step 4: Run the updated tests (FAIL)**

Run: `flutter test test/store/songwriter_voicing_accept_test.dart test/store/songwriter_third_above_accept_test.dart`
Expected: FAIL — the store still writes to "Songwriter voicings" / "Songwriter harmonies".

- [ ] **Step 5: Implement the store re-wiring**

In `lib/store/songwriter_store.dart`:

1. Delete the two top-level consts:

```dart
// DELETE
const _voicingsFolderName = 'Songwriter voicings';
const _harmoniesFolderName = 'Songwriter harmonies';
```

2. Delete the two helper methods:

```dart
// DELETE
String? _findOrCreateVoicingsFolder(SaveSystemNotifier saves) { ... }
String? _findOrCreateHarmoniesFolder(SaveSystemNotifier saves) { ... }
```

3. In `acceptVoicingSuggestion`, replace the helper call:

```dart
// before
final folderId = _findOrCreateVoicingsFolder(saves);
// after
final folderId = _findOrCreateProjectFolderId(saves);
```

4. In `acceptThirdAboveSuggestion`, replace the helper call:

```dart
// before
final folderId = _findOrCreateHarmoniesFolder(saves);
// after
final folderId = _findOrCreateProjectFolderId(saves);
```

- [ ] **Step 6: Run the tests (PASS)**

Run: `flutter test test/store/songwriter_voicing_accept_test.dart test/store/songwriter_third_above_accept_test.dart test/store/songwriter_project_folder_test.dart`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_voicing_accept_test.dart test/store/songwriter_third_above_accept_test.dart
git commit -m "$(cat <<'EOF'
refactor(songwriter): route voicing + 3rd-above accepts into project folder

Drops the flat 'Songwriter voicings' / 'Songwriter harmonies' folders.
Both C v1 and C v2-a accept flows now persist into the project-named
top-level folder created/linked via _findOrCreateProjectFolderId.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Pure rule — `matchLibrary`

**Files:**
- Create: `lib/schema/rules/songwriter_library_match_rules.dart`
- Test: `test/schema/rules/songwriter_library_match_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_library_match_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_library_match_rules.dart';

SaveEntry _save({
  required String id,
  required String name,
  required List<String> selectedNotes,
  PendingChord? pendingChord,
  required int updatedAt,
}) {
  final snap = FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: const [],
    selectedNotes: selectedNotes,
    viewMode: FretboardViewMode.exact,
    pendingChord: pendingChord,
  );
  return SaveEntry(
    id: id,
    name: name,
    folderId: 'f',
    snapshot: snap,
    createdAt: 0,
    updatedAt: updatedAt,
    order: 0,
  );
}

void main() {
  const cMajorBlock = SongBlock(
    id: 'hb1', startBar: 0, spanBars: 2,
    chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
    chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
  );

  test('chord match: save.pendingChord.symbol == block.chordSymbol', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'C voicing', selectedNotes: ['C', 'E', 'G'],
          pendingChord: const PendingChord(symbol: 'C', root: 'C'),
          updatedAt: 100,
        ),
        _save(
          id: 's2', name: 'Random', selectedNotes: ['D', 'F#'],
          pendingChord: const PendingChord(symbol: 'D', root: 'D'),
          updatedAt: 200,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.length, 1);
    expect(m.chordMatches.single.entry.id, 's1');
    expect(m.chordMatches.single.kind, LibraryMatchKind.chord);
  });

  test('scale match: every selectedNote is in the key scale', () {
    // C major scale = {C,D,E,F,G,A,B}
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'CMaj scale highlight',
          selectedNotes: ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
          updatedAt: 100,
        ),
        _save(
          id: 's2', name: 'Has F#', selectedNotes: ['F#', 'G'],
          updatedAt: 200,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches, isEmpty);
    expect(m.scaleMatches.length, 1);
    expect(m.scaleMatches.single.entry.id, 's1');
    expect(m.scaleMatches.single.kind, LibraryMatchKind.scale);
  });

  test('save that matches both chord and scale only appears in chord bucket',
      () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'C voicing', selectedNotes: ['C', 'E', 'G'],
          pendingChord: const PendingChord(symbol: 'C', root: 'C'),
          updatedAt: 100,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.length, 1);
    expect(m.scaleMatches, isEmpty);
  });

  test('no key and no chordSymbol → empty buckets', () {
    const block = SongBlock(id: 'hb', startBar: 0, spanBars: 1);
    final m = matchLibrary(
      harmonyBlock: block,
      searchableSaves: [
        _save(
          id: 's1', name: 'C voicing', selectedNotes: ['C', 'E', 'G'],
          pendingChord: const PendingChord(symbol: 'C', root: 'C'),
          updatedAt: 100,
        ),
      ],
      keyRootPc: null,
      keyScaleName: null,
    );
    expect(m.chordMatches, isEmpty);
    expect(m.scaleMatches, isEmpty);
  });

  test('save with empty selectedNotes is not scale-matched', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(id: 's1', name: 'empty', selectedNotes: const [], updatedAt: 100),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.scaleMatches, isEmpty);
  });

  test('chord bucket sorted by updatedAt desc', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 'old', name: 'C old', selectedNotes: ['C', 'E', 'G'],
          pendingChord: const PendingChord(symbol: 'C', root: 'C'),
          updatedAt: 100,
        ),
        _save(
          id: 'new', name: 'C new', selectedNotes: ['C', 'E', 'G'],
          pendingChord: const PendingChord(symbol: 'C', root: 'C'),
          updatedAt: 500,
        ),
        _save(
          id: 'mid', name: 'C mid', selectedNotes: ['C', 'E', 'G'],
          pendingChord: const PendingChord(symbol: 'C', root: 'C'),
          updatedAt: 300,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.map((x) => x.entry.id).toList(),
        ['new', 'mid', 'old']);
  });
}
```

> The `PendingChord` constructor surface varies by codebase — verify with `grep -n "class PendingChord" lib/models/save_system.dart` before running. If the test fails to compile because `PendingChord` requires more fields, fill them in with sensible defaults (e.g. `notes: const [], quality: ''`).

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/schema/rules/songwriter_library_match_test.dart`
Expected: FAIL — file/symbols missing.

- [ ] **Step 3: Implement**

Create `lib/schema/rules/songwriter_library_match_rules.dart`:

```dart
/// Library-match rule for Songwriter Phase C v2-b.
///
/// Classifies user `SaveEntry`s as either a chord-match (the save's detected
/// `pendingChord.symbol` equals the harmony block's `chordSymbol`) or a
/// scale-match (every note in the save's `selectedNotes` is in the project
/// key's scale). Chord-match takes precedence — a save that satisfies both
/// only appears in the chord bucket.
library;

import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';

enum LibraryMatchKind { chord, scale }

class LibraryMatch {
  const LibraryMatch({required this.entry, required this.kind});
  final SaveEntry entry;
  final LibraryMatchKind kind;
}

({List<LibraryMatch> chordMatches, List<LibraryMatch> scaleMatches})
    matchLibrary({
  required SongBlock harmonyBlock,
  required List<SaveEntry> searchableSaves,
  required int? keyRootPc,
  required String? keyScaleName,
}) {
  final chordSymbol = harmonyBlock.chordSymbol;
  final scalePcs = <int>{};
  if (keyRootPc != null && keyScaleName != null) {
    final intervals = scaleIntervals[keyScaleName];
    if (intervals != null) {
      for (final i in intervals) {
        scalePcs.add((keyRootPc + i) % 12);
      }
    }
  }

  final chord = <LibraryMatch>[];
  final scale = <LibraryMatch>[];
  for (final save in searchableSaves) {
    final snap = save.snapshot;
    final chordHit =
        chordSymbol != null && snap.pendingChord?.symbol == chordSymbol;
    if (chordHit) {
      chord.add(LibraryMatch(entry: save, kind: LibraryMatchKind.chord));
      continue;
    }
    if (scalePcs.isEmpty) continue;
    final notes = snap.selectedNotes;
    if (notes.isEmpty) continue;
    var allInScale = true;
    for (final n in notes) {
      final pc = noteToPC[n];
      if (pc == null || !scalePcs.contains(pc)) {
        allInScale = false;
        break;
      }
    }
    if (allInScale) {
      scale.add(LibraryMatch(entry: save, kind: LibraryMatchKind.scale));
    }
  }

  chord.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  scale.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  return (chordMatches: chord, scaleMatches: scale);
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/schema/rules/songwriter_library_match_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_library_match_rules.dart test/schema/rules/songwriter_library_match_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): library-match rule

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Store action — `acceptLibraryMatch`

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_library_accept_test.dart`

The action inserts a save-lane block referencing an existing `saveId`. No new `SaveEntry` is created. Reuses `_findOrCreateSaveLane(sectionId)` and `addSaveBlock`.

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_library_accept_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(saveSystemProvider.notifier);
    return c;
  }

  ({String sectionId, String harmonyLaneId, String harmonyBlockId})
      seedSong(ProviderContainer c) {
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );
    return (sectionId: s, harmonyLaneId: l, harmonyBlockId: 'hb1');
  }

  String _seedExistingSave(ProviderContainer c) {
    final saves = c.read(saveSystemProvider.notifier);
    final folderId = saves.createSaveFolder('Other folder', null)!;
    return saves.saveSnapshot(
      'Existing C voicing',
      folderId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    )!;
  }

  test('accept inserts a save-lane block referencing the existing saveId; '
      'no new SaveEntry created', () {
    final c = freshContainer();
    final ids = seedSong(c);
    final existingSaveId = _seedExistingSave(c);
    final saveCountBefore = c.read(saveSystemProvider).saves.length;

    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          saveId: existingSaveId,
        );

    final saveCountAfter = c.read(saveSystemProvider).saves.length;
    expect(saveCountAfter, saveCountBefore,
        reason: 'acceptLibraryMatch must NOT create a new SaveEntry');

    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLane = section.lanes.firstWhere(
      (l) => l.kind == SongLaneKind.save,
    );
    expect(saveLane.blocks.single.saveId, existingSaveId);
    expect(saveLane.blocks.single.startBar, 0);
    expect(saveLane.blocks.single.spanBars, 2);
  });

  test('second accept at overlapping bars is silently rejected by '
      'blocksOverlap; no second block created', () {
    final c = freshContainer();
    final ids = seedSong(c);
    final existingSaveId = _seedExistingSave(c);

    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          saveId: existingSaveId,
        );
    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          saveId: existingSaveId,
        );

    final saveLane = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save);
    expect(saveLane.blocks.length, 1,
        reason: 'overlap rejection is silent; only the first block lands');
  });

  test('missing harmony block: silent no-op', () {
    final c = freshContainer();
    final ids = seedSong(c);
    final existingSaveId = _seedExistingSave(c);
    final initialSnapshot = c.read(songwriterProvider);

    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: 'nope',
          saveId: existingSaveId,
        );

    expect(c.read(songwriterProvider), initialSnapshot,
        reason: 'missing block must leave songwriter state untouched');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_library_accept_test.dart`
Expected: FAIL — `acceptLibraryMatch` missing.

- [ ] **Step 3: Implement**

Append to `SongwriterNotifier` in `lib/store/songwriter_store.dart`, near `acceptVoicingSuggestion`:

```dart
/// Inserts a save-lane block in [sectionId] aligned to the harmony block's
/// bars, referencing the existing [saveId]. Does NOT create a new SaveEntry.
/// Silently no-ops when the section or harmony block is missing.
void acceptLibraryMatch({
  required String sectionId,
  required String harmonyBlockId,
  required String saveId,
}) {
  final section = state.sections.firstWhere(
    (s) => s.id == sectionId,
    orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
  );
  if (section.id.isEmpty) return;
  SongBlock? harmonyBlock;
  for (final lane in section.lanes) {
    for (final b in lane.blocks) {
      if (b.id == harmonyBlockId) {
        harmonyBlock = b;
        break;
      }
    }
    if (harmonyBlock != null) break;
  }
  if (harmonyBlock == null) return;

  final laneId = _findOrCreateSaveLane(sectionId);
  if (laneId == null) return;

  addSaveBlock(
    sectionId: sectionId,
    laneId: laneId,
    saveId: saveId,
    startBar: harmonyBlock.startBar,
    spanBars: harmonyBlock.spanBars,
  );
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_library_accept_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_library_accept_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): acceptLibraryMatch store action

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Library tab in the harmony sheet

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_preview.dart`
- Test: `test/features/songwriter/songwriter_library_tab_test.dart`

Extend `showHarmonyBlockSheet` with a third tab `Library`. The tab content renders two labeled groups: "Matches this chord" + "Fits this key" (horizontal strips of `_LibraryMatchCard`s, mirroring the v1/v2-a strip style). Default selected tab stays Voicings.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_library_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_library_match_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

SaveEntry _save(String id, String name) => SaveEntry(
      id: id,
      name: name,
      folderId: 'f',
      snapshot: FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
      createdAt: 0,
      updatedAt: 0,
      order: 0,
    );

void main() {
  const block = SongBlock(
    id: 'hb', startBar: 0, spanBars: 2,
    chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
    chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
  );

  testWidgets('sheet has Voicings + Harmony + Library tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: block,
              voicings: const [],
              thirdAbove: null,
              chordMatches: const [],
              scaleMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('Library tab shows empty state when no matches', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: block,
              voicings: const [],
              thirdAbove: null,
              chordMatches: const [],
              scaleMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching saves'), findsOneWidget);
  });

  testWidgets('Library tab renders chord + scale groups; tap fires '
      'onAcceptLibrary with the right saveId and closes sheet', (tester) async {
    String? pickedId;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: block,
              voicings: const [],
              thirdAbove: null,
              chordMatches: [
                LibraryMatch(entry: _save('chord1', 'Chord A'),
                    kind: LibraryMatchKind.chord),
              ],
              scaleMatches: [
                LibraryMatch(entry: _save('scale1', 'Scale A'),
                    kind: LibraryMatchKind.scale),
              ],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (id) => pickedId = id,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('Matches this chord'), findsOneWidget);
    expect(find.text('Fits this key'), findsOneWidget);

    await tester.tap(find.byKey(const Key('libraryCard_chord1')));
    await tester.pumpAndSettle();

    expect(pickedId, 'chord1');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_library_tab_test.dart`
Expected: FAIL — sheet signature doesn't accept `chordMatches` / `scaleMatches` / `onAcceptLibrary` yet.

- [ ] **Step 3: Implement**

In `lib/features/songwriter/songwriter_block_preview.dart`:

1. Add the import:

```dart
import '../../schema/rules/songwriter_library_match_rules.dart';
```

2. Update the `showHarmonyBlockSheet` signature and `DefaultTabController` length, and add a third entry in the `TabBar.tabs` and `TabBarView.children`:

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
}) {
  // ...header + chord chips unchanged...
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTabController(
          length: 3, // was 2
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ...header Row + chord chips unchanged...
              const SizedBox(height: 12),
              const TabBar(
                tabs: [
                  Tab(text: 'Voicings'),
                  Tab(text: 'Harmony'),
                  Tab(text: 'Library'),
                ],
              ),
              SizedBox(
                height: 230, // was 170: extra room for the labeled groups
                child: TabBarView(
                  children: [
                    _VoicingsTab(
                      hasChord: hasChord,
                      voicings: voicings,
                      onAccept: (v) {
                        Navigator.pop(sheetCtx);
                        onAcceptVoicing(v);
                      },
                    ),
                    _HarmonyTab(
                      hasChord: hasChord,
                      thirdAbove: thirdAbove,
                      onAccept: (s) {
                        Navigator.pop(sheetCtx);
                        onAcceptThirdAbove(s);
                      },
                    ),
                    _LibraryTab(
                      chordMatches: chordMatches,
                      scaleMatches: scaleMatches,
                      onAccept: (id) {
                        Navigator.pop(sheetCtx);
                        onAcceptLibrary(id);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
```

3. Add `_LibraryTab` and `_LibraryMatchCard` at the bottom of the file:

```dart
class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.chordMatches,
    required this.scaleMatches,
    required this.onAccept,
  });
  final List<LibraryMatch> chordMatches;
  final List<LibraryMatch> scaleMatches;
  final void Function(String saveId) onAccept;

  @override
  Widget build(BuildContext context) {
    if (chordMatches.isEmpty && scaleMatches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text("No matching saves in this song's folder yet."),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chordMatches.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Matches this chord',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chordMatches.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = chordMatches[i];
                  return _LibraryMatchCard(
                    key: Key('libraryCard_${m.entry.id}'),
                    match: m,
                    onTap: () => onAccept(m.entry.id),
                  );
                },
              ),
            ),
          ],
          if (scaleMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Fits this key',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: scaleMatches.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = scaleMatches[i];
                  return _LibraryMatchCard(
                    key: Key('libraryCard_${m.entry.id}'),
                    match: m,
                    onTap: () => onAccept(m.entry.id),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryMatchCard extends StatelessWidget {
  const _LibraryMatchCard({
    super.key,
    required this.match,
    required this.onTap,
  });
  final LibraryMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SavePreviewThumbnail(
              snapshot: match.entry.snapshot,
              width: 84,
              height: 60,
            ),
            const SizedBox(height: 4),
            Text(
              match.entry.name,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Update the existing v2-a sheet test for the new signature**

Open `test/features/songwriter/songwriter_third_above_sheet_test.dart`. Every call to `showHarmonyBlockSheet` must add three new required parameters: `chordMatches: const []`, `scaleMatches: const []`, `onAcceptLibrary: (_) {}`. Open `test/features/songwriter/songwriter_voicing_sheet_test.dart` and do the same.

- [ ] **Step 5: Run the new test + the updated existing tests (PASS)**

Run: `flutter test test/features/songwriter/songwriter_library_tab_test.dart test/features/songwriter/songwriter_third_above_sheet_test.dart test/features/songwriter/songwriter_voicing_sheet_test.dart`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/songwriter_block_preview.dart test/features/songwriter/songwriter_library_tab_test.dart test/features/songwriter/songwriter_third_above_sheet_test.dart test/features/songwriter/songwriter_voicing_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): Library tab in harmony sheet

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Tile harmony branch — resolve matches and pass them through

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_tile.dart`
- Test: `test/features/songwriter/songwriter_library_tile_test.dart`

`_onTap`'s harmony branch (introduced by C v1, extended by C v2-a) now resolves the library matches before opening the sheet.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_library_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_block_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tap → Library tab → card → save-lane block inserted; '
      'no new SaveEntry', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    final saves = container.read(saveSystemProvider.notifier);

    n.setProjectName('Song A');
    n.setKey(0, 'major');
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l = container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );

    // Seed an existing save inside the project folder so library-match finds it.
    final projectFolderId = saves.createSaveFolder('Song A', null)!;
    final existingSaveId = saves.saveSnapshot(
      'Existing C voicing',
      projectFolderId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
        pendingChord: const PendingChord(symbol: 'C', root: 'C'),
      ),
    )!;
    final savesCountBefore = container.read(saveSystemProvider).saves.length;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320, height: 44,
            child: SongwriterBlockTile(
              sectionId: s,
              laneId: l,
              blockId: 'hb1',
              barWidth: 40,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('block_hb1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('libraryCard_$existingSaveId')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(saveSystemProvider).saves.length, savesCountBefore,
        reason: 'no new SaveEntry created');

    final section = container
        .read(songwriterProvider)
        .sections
        .firstWhere((sec) => sec.id == s);
    final saveLane = section.lanes.firstWhere(
      (la) => la.kind == SongLaneKind.save,
    );
    expect(saveLane.blocks.single.saveId, existingSaveId);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_library_tile_test.dart`
Expected: FAIL — tile doesn't pass library matches or `onAcceptLibrary` yet.

- [ ] **Step 3: Implement**

In `lib/features/songwriter/songwriter_block_tile.dart`:

1. Add the new import:

```dart
import '../../schema/rules/songwriter_library_match_rules.dart';
```

2. Inside the harmony branch in `_onTap`, before calling `showHarmonyBlockSheet`, compute the library matches:

```dart
final swNotifier = ref.read(songwriterProvider.notifier);
final searchable = swNotifier.searchableSavesForLibraryMatch();
final matches = matchLibrary(
  harmonyBlock: block,
  searchableSaves: searchable,
  keyRootPc: cfg.keyRoot,
  keyScaleName: cfg.keyScaleName,
);
```

3. Replace the `showHarmonyBlockSheet` call so it receives the new arguments and routes `onAcceptLibrary` to the store:

```dart
showHarmonyBlockSheet(
  context,
  block: block,
  voicings: voicings,
  thirdAbove: thirdAbove,
  chordMatches: matches.chordMatches,
  scaleMatches: matches.scaleMatches,
  onAcceptVoicing: (v) {
    swNotifier.acceptVoicingSuggestion(
      sectionId: widget.sectionId,
      harmonyBlockId: widget.blockId,
      suggestion: v,
    );
  },
  onAcceptThirdAbove: (s) {
    swNotifier.acceptThirdAboveSuggestion(
      sectionId: widget.sectionId,
      harmonyBlockId: widget.blockId,
      suggestion: s,
    );
  },
  onAcceptLibrary: (saveId) {
    swNotifier.acceptLibraryMatch(
      sectionId: widget.sectionId,
      harmonyBlockId: widget.blockId,
      saveId: saveId,
    );
  },
);
```

- [ ] **Step 4: Run the new test + regression**

Run: `flutter test test/features/songwriter/songwriter_library_tile_test.dart test/features/songwriter/songwriter_third_above_tile_test.dart test/features/songwriter/songwriter_block_drag_test.dart test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_block_tile.dart test/features/songwriter/songwriter_library_tile_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): tile resolves library matches before opening sheet

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Header project-name chip + rename dialog

**Files:**
- Modify: `lib/features/songwriter/songwriter_header.dart`
- Test: `test/features/songwriter/songwriter_project_name_test.dart`

Add a tappable chip on the left side of the header row that shows the project name. Tap → text-field dialog → `setProjectName`. The chip key is `projectNameChip` and the dialog text field is `projectNameField`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_project_name_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('chip renders the project name', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).setProjectName('Song A');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Song A'), findsOneWidget);
  });

  testWidgets('tap chip → dialog → submit → setProjectName fires',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('projectNameChip')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('projectNameField')), 'Song B');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(songwriterProvider).name, 'Song B');
  });

  testWidgets('whitespace-only name is rejected', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).setProjectName('Song A');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('projectNameChip')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('projectNameField')), '   ');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(songwriterProvider).name, 'Song A');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_project_name_test.dart`
Expected: FAIL — chip not in the header yet.

- [ ] **Step 3: Implement**

Modify `lib/features/songwriter/songwriter_header.dart`. The header is a Riverpod `ConsumerWidget` (or `Consumer`-wrapping `StatelessWidget`) — adapt to whichever pattern the file uses. The chip goes at the leftmost position of the main Row:

```dart
// inside the build/Row, as the first child
Consumer(builder: (context, ref, _) {
  final name = ref.watch(songwriterProvider.select((p) => p.name));
  return ActionChip(
    key: const Key('projectNameChip'),
    label: Text(name),
    onPressed: () => _editProjectName(context, ref, name),
  );
}),
```

Add the dialog helper at the bottom of the file (or as a private top-level function):

```dart
void _editProjectName(BuildContext context, WidgetRef ref, String current) {
  final controller = TextEditingController(text: current);
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Project name'),
      content: TextField(
        key: const Key('projectNameField'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            ref.read(songwriterProvider.notifier)
                .setProjectName(controller.text);
            Navigator.pop(dialogCtx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
```

> If `SongwriterHeader` is a `ConsumerStatefulWidget` (the dialog approach above takes `WidgetRef` from a `Consumer` builder anyway, but adapt the import/scope). Use whatever pattern matches the existing header; the chip just needs the key and the dialog text-field needs `Key('projectNameField')`.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/songwriter_project_name_test.dart`
Expected: PASS (3 tests).

Run the header-overflow regression too:

Run: `flutter test test/features/songwriter/songwriter_header_overflow_test.dart`
Expected: PASS. If the new chip pushes the header into overflow on narrow widths, wrap it in a `Flexible` and apply `overflow: TextOverflow.ellipsis` to the `Text(name)`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_header.dart test/features/songwriter/songwriter_project_name_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): header project-name chip + rename dialog

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Verify + serve-sim

**Files:** none (verification only)

- [ ] **Step 1: Format + analyze**

Run:
```bash
dart format \
  lib/models/songwriter.dart \
  lib/schema/rules/songwriter_library_match_rules.dart \
  lib/store/songwriter_store.dart \
  lib/features/songwriter/songwriter_header.dart \
  lib/features/songwriter/songwriter_block_preview.dart \
  lib/features/songwriter/songwriter_block_tile.dart
flutter analyze
```
Expected: clean.

- [ ] **Step 2: Full sweep**

Run: `flutter test`
Expected: all PASS (~445 baseline after v2-a + 4 model + 6 folder + 3 retroactive + 6 rule + 3 accept + 3 library tab + 1 library tile + 3 project name = ~474).

- [ ] **Step 3: Simulator check**

```bash
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted io.francescolacriola.muzician
```

Navigate to Writer. The header shows a chip labeled "Untitled song". Tap it → dialog → enter "My Song" → Save. The chip updates.

Set key to C major. Add a section, harmony lane, and a C(I) chord via the wheel. Tap the C block: the sheet has three tabs (Voicings / Harmony / Library).

- **Voicings** (default) → 4 CAGED cards.
- **Harmony** → 3rd-above card showing piano highlight (E, G, B).
- **Library** → "No matching saves in this song's folder yet."

Accept a voicing (tap C-shape card). A save lane appears with a save block; a top-level folder "My Song" exists in the save library containing one save.

Tap the C block again → Library tab. Now "Matches this chord" shows the previously-accepted voicing. Tap it → a second save block lands in the next free bar of the save lane.

Tap the project name chip → rename to "My Song v2". The library folder renames too (visible in the save library tab).

- [ ] **Step 4: Commit any formatting drift**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(songwriter): format + verify C v2-b library-match

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** decisions C2B-1 through C2B-6 each map to tasks. C2B-1 (project↔folder name binding) → Task 1 (model name) + Task 2 (helpers) + Task 8 (header UI). C2B-2 (match union with chord-precedence) → Task 4. C2B-3 (search scope = song folder + descendants) → Task 2's `searchableSavesForLibraryMatch`. C2B-4 (third tab) → Task 6. C2B-5 (accept = block-only, no new SaveEntry) → Task 5. C2B-6 (retroactive change to v1 + v2-a) → Task 3.
- **Deferred:** per-section subfolders, manual folder picker, fuzzy matching, ranking beyond `updatedAt`, dedup against already-inserted saves, cross-song matches, folder-rename collision handling. None in this plan.
- **Type / signature consistency:** `LibraryMatch` + `LibraryMatchKind` (Task 4) consumed in Task 6 sheet + Task 7 tile. `_findOrCreateProjectFolderId` (Task 2) used by Task 3's re-wired v1/v2-a accepts. `searchableSavesForLibraryMatch()` (Task 2) consumed in Task 7. `matchLibrary` record fields `chordMatches` + `scaleMatches` consistent across Tasks 4-7. `setProjectName` (Task 2) consumed in Task 8 dialog. `'Untitled song'` default in Task 1 referenced by Task 3 test updates.
- **Test gotchas:** Task 3 must run AFTER Task 2 because the new helper `_findOrCreateProjectFolderId` is what the v1/v2-a accepts now call. Widget tests in Tasks 6, 7, 8 use the 600 ms pump pattern to drain the 500 ms persistence debounce after any store mutation.
- **Risk:** Task 1's `fromJson` migration assumes old sessions are deserialised at hydrate time. If the existing `hydrate` path uses a `try/catch` that swallows JSON shape errors, an old session without `name` will quietly fall through to `_emptyProject()` — the migration test (Task 1 step 1) covers the synchronous `fromJson` path explicitly to catch this.
- **Risk:** Task 8 may bump into header-row overflow. The existing `songwriter_header_overflow_test.dart` is the canary; if it fails, wrap the chip in `Flexible` and apply `Text overflow: TextOverflow.ellipsis`.

## Next slices (NOT in this plan)

- v2-c: Per-section subfolders inside the song's folder + section↔folder linking on section CRUD.
- v2-d: Folder-rename collision resolution (merge / prompt / refuse).
- v3: Arpeggio / sequence save type (the slice that finally forces a new InstrumentSnapshot subtype), 6th-above / 5th-below variants, fretboard 3rd-above.
