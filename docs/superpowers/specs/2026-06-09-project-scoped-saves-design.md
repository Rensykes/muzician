# Project-Scoped Save System — Design

**Status:** Approved (brainstorming). Implementation plan to follow.
**Date:** 2026-06-09
**Branch (suggested):** `project-scoped-saves`

---

## 1 Problem

Today the save system is a flat tree of folders + saves with no notion of a
"project". Songwriter has squatted on a fragile convention (a top-level folder
whose name matches `state.name`); Song has no project concept at all. The
shared `SaveBrowserPanel` shows the entire tree everywhere, so Song /
Songwriter can pick saves that belong to unrelated work. Key / tempo / time
signature drift freely across saves, with nothing tying them together.

We want:

1. **Projects.** Every project is represented by a dedicated top-level folder.
2. **Global selection.** The current project is an app-wide variable persisted
   across launches; visible in every tab.
3. **Project config.** Each project owns its key (root + scale), tempo, and
   time signature. Saves created inside a project inherit and stay locked to
   that config. Saves outside a project are free.
4. **Dump folder.** A single global spare bin. New saves on
   Fretboard / Piano / Roll can target it when no project is active. Song /
   Songwriter refuse to operate against Dump (they require a real project).
5. **Restricted browsing.** Song / Songwriter only see their own project; the
   instrument tabs see the current project (or Dump) plus a switcher.
6. **Nested folders.** Arbitrary subfolders inside a project (e.g.
   `Verse / Chorus`) purely for readability.

Deferred: copying a save from Dump → project; project export / import / share;
per-project audio asset isolation; project-level palette expansion.

---

## 2 Data Model (`lib/models/save_system.dart`)

```dart
enum SaveFolderKind { normal, project, dump }

class ProjectConfig {
  final String? keyRoot;        // 'C', 'C#', ... or null (no key set)
  final String? keyScaleName;   // 'major', 'minor', 'dorian', ... or null
  final int tempo;              // BPM, default 120
  final int beatsPerBar;        // numerator, default 4
  final int beatUnit;           // denominator (2, 4, 8, 16), default 4

  const ProjectConfig({
    this.keyRoot,
    this.keyScaleName,
    this.tempo = 120,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
  });

  ProjectConfig copyWith({...});
  Map<String, dynamic> toJson();
  factory ProjectConfig.fromJson(Map<String, dynamic> json);
}

class SaveFolder {
  // existing fields...
  final SaveFolderKind kind;          // default `normal`
  final ProjectConfig? projectConfig; // only meaningful when kind == project
  // copyWith now passes kind + projectConfig through.
}

class SaveSystemState {
  // existing fields...
  final String? selectedProjectId;    // id of folder with kind project|dump; null = no selection.
}
```

### Validation invariants

| Invariant | Enforced in |
|---|---|
| `kind != normal` ⇒ `parentId == null` | factory + store + `fromJson` assert |
| `kind == normal` ⇒ `projectConfig == null` | factory + store |
| At most one folder with `kind == dump` | store (`ensureDumpFolder` idempotent) |
| `selectedProjectId != null` ⇒ folder exists with that id AND kind in {project, dump} | store on every state mutation that affects folders; auto-clears otherwise |

### Persistence schema bump

Storage key: `@muzician/save_system/v2`. Blob fields:
`folders`, `saves`, `selectedProjectId`. Old `v1` blob is wiped on first launch
of v2 code (§7). No backward read.

---

## 3 Store API (`lib/store/save_system_store.dart`)

```dart
class SaveSystemNotifier extends Notifier<SaveSystemState> {
  // Project CRUD
  String createProject(String name, ProjectConfig cfg);
  void   renameProject(String id, String name);
  void   deleteProject(String id);                  // refuses kind==dump; cascades
  void   updateProjectConfig(String id, ProjectConfig cfg); // raw setter; UI handles the migration prompt

  // Selection
  void   selectProject(String? projectId);          // null = clear; validates target kind ∈ {project, dump}
  void   _clearSelectionIfStale();                  // internal; invoked after destructive ops

  // Dump
  String ensureDumpFolder();                        // creates kind=dump root if missing; returns id

  // Project config retrofit (atomic)
  Future<void> applyProjectConfig(String projectId, ProjectConfig cfg, {required bool retrofit});
  // retrofit=false ⇒ same as updateProjectConfig.
  // retrofit=true  ⇒ rewrites every save in the subtree (see §5) and per-project sessions.

  // Hardened existing ops
  // deleteFolder refuses when folder.kind == dump.
  // deleteFolder of folder with kind == project clears selectedProjectId if it matched.
  // createSaveFolder refuses to create at root with kind != normal (root creation is via createProject/ensureDumpFolder).
}
```

### Rules (`lib/schema/rules/save_system_rules.dart`)

```dart
List<SaveFolder> getProjectFolders(List<SaveFolder> all);   // parentId==null && kind==project, ordered
SaveFolder?      getDumpFolder(List<SaveFolder> all);
Set<String>      getSubtreeFolderIds(List<SaveFolder> all, String rootId);
List<SaveEntry>  getSavesInSubtree(List<SaveFolder> all, List<SaveEntry> all2, String rootId);
bool             isProjectRoot(SaveFolder f);
bool             isDumpRoot(SaveFolder f);

SaveFolder createProjectFolder(String name, ProjectConfig cfg, int order);
SaveFolder createDumpFolder(int order);
SaveFolder createNormalFolder(String name, String? parentId, int order); // refactor today's helper
```

### Convenience providers

```dart
final selectedProjectProvider = Provider<SaveFolder?>(...);   // resolves selectedProjectId
final projectsListProvider    = Provider<List<SaveFolder>>(...);
final dumpFolderProvider      = Provider<SaveFolder?>(...);
```

---

## 4 Per-project sessions

Two new stores replace the existing single-blob session stores.

### `lib/store/song_sessions_store.dart`

```dart
class SongSessionsNotifier extends Notifier<Map<String, SongProject>> {
  Future<void> hydrate();           // reads @muzician/song_sessions/v2 → Map<projectId, SongProject>
  Future<void> _persist();           // debounced 500ms
  SongProject? get(String projectId);
  void put(String projectId, SongProject project);
  void remove(String projectId);     // called from SaveSystemNotifier.deleteProject
  Future<void> clearAll();           // wipe migration
}
final songSessionsProvider = NotifierProvider<SongSessionsNotifier, Map<String, SongProject>>(...);
```

### `lib/store/songwriter_sessions_store.dart`

Same shape, value type `SongwriterProjectSnapshot`. Key
`@muzician/songwriter_sessions/v2`.

### Wiring in `song_project_store.dart` + `songwriter_store.dart`

1. Remove direct SharedPreferences calls + the old `_sessionKey` constants.
2. On self-state-change: write through
   `songSessionsProvider.notifier.put(currentProjectId, state)`. Skipped while
   `_hydrating`.
3. `ref.listen(saveSystemProvider.select((s) => s.selectedProjectId))`:
   - Persist outgoing project immediately (no debounce).
   - If new id is null → load default empty state.
   - Else look up `songSessionsProvider.get(newId)`; if present use it; else
     synthesize a default seeded from the project's `ProjectConfig` (see §5
     defaults).
4. `deleteProject` triggers
   `songSessionsProvider.notifier.remove(projectId)` and same for Songwriter.

### App init order (`main.dart`)

```dart
await ref.read(saveSystemProvider.notifier).hydrate();
await ref.read(settingsProvider.notifier).hydrate();
await ref.read(songSessionsProvider.notifier).hydrate();
await ref.read(songwriterSessionsProvider.notifier).hydrate();
// derive initial in-memory Song + Songwriter from selectedProjectId
final selected = ref.read(saveSystemProvider).selectedProjectId;
if (selected != null) {
  ref.read(songProjectProvider.notifier).loadProject(
    ref.read(songSessionsProvider).get(selected) ?? defaultSongFor(selected, ref),
  );
  ref.read(songwriterProvider.notifier).loadProject(
    ref.read(songwriterSessionsProvider).get(selected) ?? defaultSongwriterFor(selected, ref),
  );
}
```

Old keys (`@muzician/song_session/v1`, `@muzician/songwriter_session/v1`)
deleted in the v2 wipe (§7).

---

## 5 Project config propagation

### Read flow

When a tab is entered or a save is loaded, the active `ProjectConfig` is
applied as follows:

| Tab | With project selected | With Dump selected | Nothing selected |
|---|---|---|---|
| Fretboard | `highlightedNotes` seeded from `keyRoot + keyScaleName` (empty when key is null) | from save / empty | Gate (§6) |
| Piano | same | same | Gate |
| Piano Roll | `key`, `tempo`, `numerator`, `denominator`, `highlightedNotes` from config | from save / defaults | Gate |
| Song | `SongProjectConfig.tempo / timeSignature / scaleRoot / scaleName` from config | n/a (Dump disallowed) | Gate (Dump NOT offered) |
| Songwriter | `SongwriterConfig.tempo / beatsPerBar / beatUnit / keyRoot / keyScaleName` from config | n/a | Gate (Dump NOT offered) |

### Write flow (project config edited)

Editing the project's config opens a sheet (key, tempo, time sig). On submit:

```
1. Compute diff vs current ProjectConfig.
2. Collect impact (subtree saves + Song + Songwriter sessions for this project id).
3. Show confirm dialog:
     "Change <project>: key C major → A minor, tempo 120 → 100.
      N saves will be retuned/retimed:
        • 3 fretboard, 2 piano, 4 piano roll
        • Song arrangement updated
        • Songwriter arrangement updated
      Notes outside new key will be flagged red in piano roll. Continue?"
4. On confirm: SaveSystemNotifier.applyProjectConfig(projectId, cfg, retrofit: true)
   a. updateProjectConfig on the folder.
   b. For each save in subtree:
        - Fretboard / Piano: rebuild `highlightedNotes` from new key (selectedNotes preserved).
        - PianoRoll:        rebuild `highlightedNotes`; set `key`, `tempo`, `numerator`, `denominator`.
                            Notes outside scale kept (existing out-of-scale render handles them).
        - Song:             config.tempo / timeSignature / scaleRoot / scaleName overwritten.
        - Songwriter:       config overwritten; recompute Roman numerals.
   c. If selectedProjectId == this id, refresh in-memory Song + Songwriter stores from sessions
      (re-applying the overwritten config to the live workspace).
5. Single persist at end of step 4.
```

### Lock UI

When `selectedProject?.kind == project`:

| Control | State |
|---|---|
| Songwriter header tempo chip | disabled w/ toast "Set in project config" |
| Songwriter header key chip | disabled, same toast |
| Song header tempo + scale chip | disabled |
| Piano Roll header tempo / key / scale / timesig | disabled |
| Fretboard / Piano scale picker | disabled |
| Songwriter project-name field | editable; setProjectName routes to `renameProject(selectedProjectId, ...)` |

Under Dump or no selection, controls remain unlocked (today's behavior).

### Defaults

`ProjectConfig(keyRoot: null, keyScaleName: null, tempo: 120, beatsPerBar: 4,
beatUnit: 4)`. Empty key = no highlight. New-project dialog prefills with
these.

Defaults for synthesized sessions on first project entry:

- Song: `getDefaultSongProject()` then patch `config` from `ProjectConfig`.
- Songwriter: empty `SongwriterProjectSnapshot` with `config` from `ProjectConfig`.

---

## 6 Save Browser scoping (`lib/ui/save_browser_panel.dart`)

New prop on `SaveBrowserPanel`: `final String? rootFolderId;`

- `rootFolderId == null` → today's behavior (full tree). Kept for tests /
  future "all projects" view; no production caller after this plan.
- `rootFolderId != null` → virtual root mode:
  - `_breadcrumb` stops walking when it reaches `rootFolderId`.
  - `_childFolders` at the virtual root = direct children of `rootFolderId`.
  - `_savesHere` at virtual root = saves whose `folderId == rootFolderId`;
    deeper navigation unchanged.
  - Initial `_currentFolderId = rootFolderId` (user lands inside the project).
  - "Save here" works at the virtual-root level (saves can attach directly to
    the project root — unlike today where root requires a subfolder first).

Per-tab wiring:

| Panel | `rootFolderId` |
|---|---|
| `FretboardSavePanel`, `PianoSavePanel`, `PianoRollSavePanel` | `selectedProjectId` (project OR dump) |
| `SongSavePanel` | `selectedProjectId` — guarded so it is never Dump |
| `SongwriterSavePanel` | same — never Dump |

If `selectedProjectId == null`, the panel renders a gating placeholder
("Pick a project to save / load") with a button opening the project picker.

`SongSavePanel` migrates from `SaveTreeBrowser` to `SaveBrowserPanel` so all
tabs share one browser. `SaveTreeBrowser` deleted unless still required by
other callers (audit during implementation).

Library-match scope
(`songwriterProvider.searchableSavesForLibraryMatch`) switches from
project-name matching to
`getSavesInSubtree(folders, saves, selectedProjectId)`.

---

## 7 Project picker + global chip + gate modal

### `ProjectChip` (`lib/ui/project_chip.dart`)

Rendered in every tab header (Fretboard / Piano / Roll / Song / Songwriter;
Settings excluded).

States:

| Selection | Visual |
|---|---|
| `null` | orange "No project" pill |
| project | green pill — `🎵 <name> · <key> · <tempo>` (key part hidden if null) |
| dump | grey pill — `📦 Dump` |

Tap → opens project picker sheet.

### Project picker sheet (`lib/ui/project_picker_sheet.dart`)

Bottom sheet layout:

```
PROJECTS
  ▸ My Song          A minor · 100 · 4/4   [3 saves]      ☆ active
  ▸ Untitled 2       — · 120 · 4/4         [0 saves]
  + New project
─────────
SPARE
  ▸ Dump             [12 saves]
─────────
  ⚙ Edit project config         (visible only when a project is active)
```

Actions:

- Tap project / Dump → `selectProject(id)`, close sheet. Triggers session swap
  (§4).
- "+ New project" → name + initial config dialog → `createProject(name, cfg)`
  → auto-select.
- "Edit project config" → opens the §5 write-flow sheet.
- Long-press project → rename / delete (delete confirms; if last project, no
  auto-fallback).

### Gate modal (`lib/ui/project_gate_modal.dart`)

Triggered:

- Opening Song or Songwriter tab when `selectedProjectId == null` OR
  `selectedProject.kind == dump` → Dump suppressed; "Cancel" disabled.
- Opening a save panel on Fretboard / Piano / Roll when
  `selectedProjectId == null` → Dump offered; "Cancel" closes the panel and
  leaves user in the instrument workspace.

Non-dismissible by scrim tap in the Song / Songwriter variant.

On app launch: if `selectedProjectId` was persisted but the folder is gone,
clear silently. No auto-select if any projects exist — user picks on the next
gate trigger.

---

## 8 Locking semantics (concrete UI changes)

| File | Change |
|---|---|
| `songwriter_header.dart` | Tempo + key chips disabled when active selection is a project; tap shows "Set in project config" toast. Project-name field continues to call `setProjectName`, which now routes to `renameProject(selectedProjectId, ...)`. |
| `song_screen.dart` (header) | Tempo control + scale chip disabled. |
| `piano_roll_*` (header) | Tempo + key root + scale + time signature controls disabled. |
| `fretboard.dart` / `piano.dart` (scale picker) | Disabled when project has a `keyScaleName != null`. |
| All disabled controls | Use existing `glass_snackbar.dart` toast. |

Under Dump or no selection, every control remains unlocked.

---

## 9 Migration / wipe (v1 → v2)

One-shot inside `SaveSystemNotifier.hydrate`:

```
1. Check for @muzician/save_system/v2 → if present, normal v2 hydrate, skip rest.
2. Read & delete legacy keys:
     @muzician/save_system          (v1 blob)
     @muzician/song_session/v1
     @muzician/songwriter_session/v1
3. Reset session blobs:
     @muzician/song_sessions/v2          → empty
     @muzician/songwriter_sessions/v2    → empty
4. Wipe appDocs/song_audio/ recursively (best-effort; swallow IO errors).
5. Initialise empty SaveSystemState with selectedProjectId = null.
6. Persist v2 blob.
```

Confirmed "Full clean slate" — no backup, no prompt.

---

## 10 Tests

New test files:

```
test/models/save_system_project_test.dart
  – SaveFolderKind + ProjectConfig fromJson / toJson roundtrip
  – fromJson rejects kind != normal at non-root

test/schema/rules/save_system_project_rules_test.dart
  – getProjectFolders, getDumpFolder, getSubtreeFolderIds, getSavesInSubtree

test/store/save_system_store_project_test.dart
  – createProject, ensureDumpFolder (idempotent), selectProject (validates kind),
    deleteProject (cascades, clears selection), deleteFolder refuses dump

test/store/save_system_store_migration_test.dart
  – v1 blob present → wiped, v2 created empty, audio dir wiped (mock IO)

test/store/song_sessions_store_test.dart                   – hydrate empty, put/get/remove, persist+rehydrate
test/store/songwriter_sessions_store_test.dart             – same shape

test/store/song_project_store_session_swap_test.dart       – switch project mid-edit: outgoing persisted, incoming loaded
test/store/songwriter_store_session_swap_test.dart         – same

test/store/save_system_project_config_apply_test.dart
  – applyProjectConfig(retrofit: true) rewrites subtree saves + sessions atomically

test/ui/project_picker_sheet_test.dart                     – projects + dump rows, new-project flow, active marker
test/ui/project_gate_modal_test.dart                       – Song/Writer entry blocked; Dump suppressed there; allowed on instrument tabs

test/ui/save_browser_panel_rooted_test.dart                – rootFolderId restricts navigation; cannot breadcrumb past root

test/features/songwriter/songwriter_library_match_project_scope_test.dart
  – library-match honors selectedProjectId
```

Updated:

- `test/store/save_system_store_test.dart` — state shape (selectedProjectId).
- `test/features/songwriter/songwriter_save_panel_test.dart` — root-scoped browser.
- `test/features/song/song_save_panel_test.dart` — root-scoped browser; Dump invisible.
- Any test that referenced v1 session keys → update to v2.

---

## 11 Documentation updates

| Doc | Change |
|---|---|
| `docs/save_system.md` | Add §Projects + Dump; document `SaveFolderKind`, `ProjectConfig`, `selectedProjectId`; lock semantics; v1 wipe note. |
| `docs/song_workspace.md` | Replace single-slot session description with per-project sessions; document Dump prohibition; document tempo / timesig / scale lock. |
| `docs/songwriter.md` | Replace project-name folder convention with `selectedProjectId`; document config lock; library-match scope source. |
| `docs/piano.md`, `docs/piano_roll.md`, `docs/fretboard.md` | Brief note: scale / tempo / key controlled by project when one is active; otherwise free. |
| `AGENTS.md` | Quick audit; align if mentions save_system. |

---

## 12 Out-of-scope (deferred)

- Copying a save from Dump → project (planned follow-up).
- Project export / import / share.
- Per-project namespacing of `appDocs/song_audio/`.
- Project-level chord palette / library-match scope expansion beyond
  current subtree.
- Multiple Song / Songwriter arrangements per project.

---

## 13 Implementation order (sketch — full plan in writing-plans)

1. Data model + rules + persistence schema bump (§2, §3 partial, §9 wipe).
2. Per-project session stores (§4) + main.dart wiring.
3. `SaveBrowserPanel.rootFolderId` (§6).
4. Project chip + picker sheet + gate modal (§7).
5. Project config sheet + retrofit (`applyProjectConfig`, §5 write flow).
6. Lock UI on all instrument / arrangement headers (§8).
7. Songwriter library-match repointed (§6 tail).
8. Tests + docs (§10, §11).

Each step lands as its own commit; tests at every layer; manual UI verification
before any "done" claim.
