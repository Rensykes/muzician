# Save System

The save system provides a hierarchical, folder-based persistence layer for progressions across all instruments (fretboard, piano, piano roll, song, songwriter). It is shared state — any screen can save to or load from the same tree.

---

## Architecture

```
lib/
  models/save_system.dart          ← data types (snapshots for all instruments)
  models/project_config.dart       ← ProjectConfig immutable value class
  schema/rules/save_system_rules.dart ← validation & UUID helpers
  store/save_system_store.dart     ← Riverpod NotifierProvider
  store/project_config_sync.dart   ← pushes config to instrument stores
  store/settings_store.dart        ← app-wide preferences provider
  ui/save_browser_panel.dart       ← reusable nested folder save browser
  features/save_system/
    save_system.dart               ← feature barrel export
```

---

## Data Model (`lib/models/save_system.dart`)

### Projects + Dump

Every top-level folder has a `kind`:

| Kind | Meaning |
|---|---|
| `normal` | Subfolder inside a project (Verse / Chorus) — readability only. |
| `project` | A user-facing project root. Carries a `ProjectConfig` (key, tempo, time signature). |
| `dump` | Single global spare folder (at most one). Holds ad-hoc saves until copied into a real project. |

`SaveSystemState.selectedProjectId` identifies the active project (`project` or `dump`). Persisted in the v3 blob. Song + Songwriter require `kind == project` (Dump is rejected). Fretboard / Piano / Roll accept either.

`ProjectConfig` (defined in `lib/models/project_config.dart`):

| Field | Type | Default |
|---|---|---|
| `keyRootPc` | `int?` (0-11) | null |
| `keyScaleName` | `String?` | null |
| `tempo` | `int` | 120 |
| `beatsPerBar` | `int` | 4 |
| `beatUnit` | `int` | 4 |

When a project is selected, tempo / key / time-signature controls on the instrument and arrangement headers are locked. Edit them through the project config sheet, which prompts before retrofitting every save in the project's subtree.

### Migration

Storage key bumped to `@muzician/save-system/v3`. On first launch of the v3 code, the legacy blobs (`@muzician/save-system/v2`, `@muzician/song_session/v1`, `@muzician/songwriter_session/v1`) and `appDocs/song_audio/` are wiped.

| Type | Description |
|---|---|
| `PendingChord` | Root + quality pending detection (`root`, `quality`, `symbol`) |
| `PendingScale` | Root + scale name pending detection |
| `InstrumentSnapshot` | Abstract class — `FretboardSnapshot`, `PianoSnapshot`, `PianoRollSnapshot`, `SongProjectSnapshot`, `SongwriterProjectSnapshot`, `DrumLoopSnapshot` |
| `FretboardSnapshot` | Fretboard save: tuning, capo, selected cells, notes, view mode, pending chord/scale |
| `PianoSnapshot` | Piano save: key range, selected keys, notes, view mode, pending chord/scale |
| `PianoRollSnapshot` | Piano roll session: tempo, time signature, notes, range, snap, highlights, derivable chord/scale |
| `SaveFolder` | Named folder node with optional parent ID, metadata, and ordering |
| `SaveEntry` | A saved progression: ID, name, folder ID, `InstrumentSnapshot`, timestamp, ordering |
| `ProgressionFolderMeta` | Metadata attached to a folder: source type, progression ID, key |
| `ProgressionChordMeta` | Metadata attached to a save: chord symbol, root, Roman numeral, chord notes |
| `ActiveSession` | Current navigation context: `saveId` + `folderId` |
| `AppSettings` | User preferences — `suppressOutOfKeyAlert`, `noteVolume`, `showNoteLabels`, `humSensitivity`, `metronomeEnabled`, `saveBrowserGrid` |
| `SaveSystemState` | Root state: `folders`, `saves`, `activeSession`, `hydrated`, `selectedProjectId` |

> Snapshots use an `abstract class InstrumentSnapshot` with `FretboardSnapshot`, `PianoSnapshot`, `PianoRollSnapshot`, `SongProjectSnapshot`, `SongwriterProjectSnapshot`, and `DrumLoopSnapshot` subtypes. (It was `sealed` until `SongwriterProjectSnapshot` was added from `lib/models/songwriter.dart`; Dart `sealed` restricts subtypes to the same library, and dispatch is done via `is`-checks + the `fromJson` factory rather than exhaustive `switch`, so the base was relaxed to `abstract`.) All types implement `toJson` / `fromJson` for `SharedPreferences` persistence.

---

## Snapshot Types

Each instrument produces a subtype of `InstrumentSnapshot`, stored inside a `SaveEntry`.

### FretboardSnapshot (`type: 'fretboard'`)

Captures the fretboard layout (tuning, capo, number of frets), selected fret coordinates, note names, and view mode. `pendingChord` and `pendingScale` are derived from the selected notes.

### PianoSnapshot (`type: 'piano'`)

Captures the piano range name, selected key coordinates, note names, and view mode. `pendingChord` and `pendingScale` are derived from the selected notes.

### PianoRollSnapshot (`type: 'piano_roll'`)

Full piano-roll session: tempo, key, time signature, total measures, notes, pitch window, snap, and highlighted scale notes.

- `selectedNotes` resolves pitch classes at the saved column tick (or all unique PCs if no tick is set).
- `pendingChord` and `pendingScale` are derived from those pitch classes.
- Save browser shows note chips for quick identification.

### SongProjectSnapshot (`type: 'song'`)

Entire Song project with tracks, clips, note patterns, and drum patterns.

- `selectedNotes` aggregates unique pitch classes across all note patterns.
- `pendingChord` and `pendingScale` return `null` — Song saves do not produce chord/scale summaries.
- Save browser shows track/clip/pattern counts instead of note chips.

### SongwriterProjectSnapshot (`type: 'songwriter'`)

Songwriter arrangement project — ordered `SongSection`s, each holding parallel `SongLane`s, each holding `SongBlock`s (live save references via `saveId`, or detached `embedded` snapshots). Defined in `lib/models/songwriter.dart`; see `docs/songwriter.md`.

- `selectedNotes` aggregates unique pitch classes across all harmony-block `chordNotes`.
- `pendingChord` and `pendingScale` return `null` — Songwriter saves do not produce chord/scale summaries.

### DrumLoopSnapshot (`type: 'drum_loop'`)

A single reusable drum loop (one `DrumPattern`) saved to the library so custom grooves persist and can be reused across projects. Defined in `lib/models/save_system.dart`.

- `selectedNotes` is empty; `pendingChord` / `pendingScale` return `null`.
- Saved + browsed via `DrumLoopSavePanel` (`lib/features/song/drum_loop_save_panel.dart`), a `SaveBrowserPanel` filtered to `'drum_loop'`. Loading applies the loop into the drum pattern currently being edited (`onLoad` → the editor's `_applyLoadedPattern`, keeping the pattern id so the referencing block stays linked). Built-in (non-saved) presets are code-defined in `lib/schema/rules/drum_presets.dart`.

---

## Schema / Validation (`lib/schema/rules/save_system_rules.dart`)

Storage keys: `saveSystemStorageKey` (`@muzician/save-system/v3`), `legacySaveSystemStorageKeys`, `legacySessionKeys`.

| Helper | Purpose |
|---|---|
| `generateId()` | UUID v4 via `package:uuid` |
| `getDefaultSaveSystemState()` | Default empty state |
| `isValidFolderName(name)` | Non-empty, ≤ 60 chars |
| `isValidSaveName(name)` | Non-empty, ≤ 80 chars |
| `createFolder(name, parentId, siblingCount, [meta])` | Factory — new `SaveFolder` with UUID |
| `createSaveEntry(name, folderId, snapshot, siblingCount, [meta])` | Factory — new `SaveEntry` with UUID + timestamp |
| `getSavesInFolder(saves, folderId)` | All `SaveEntry`s in a folder (sorted) |
| `getChildFolders(folders, parentId)` | Direct child folders of a node (sorted) |
| `getDescendantFolderIds(folders, folderId)` | All descendant IDs (for safe delete) |
| `buildFolderBreadcrumb(folders, folderId)` | Breadcrumb list for navigation UI |
| `getAdjacentSaves(saves, session)` | Previous/next save IDs for prev/next navigation |
| `serialiseState({folders, saves, selectedProjectId})` | Encode full state to JSON string |
| `deserialiseState(raw)` | Parse JSON → `({folders, saves, selectedProjectId})?` |
| `getProjectFolders(folders)` | Top-level project folders (sorted) |
| `getDumpFolder(folders)` | The single dump folder or null |
| `getSubtreeFolderIds(folders, rootId)` | Set of all folder IDs in a subtree |
| `getSavesInSubtree(folders, saves, rootId)` | All saves under a subtree root |
| `isProjectRoot(f)` | True when folder is a top-level project |
| `isDumpRoot(f)` | True when folder is a top-level dump |
| `createProjectFolder(name, cfg, siblingCount)` | Factory — new project root `SaveFolder` |
| `createDumpFolder(siblingCount)` | Factory — new dump root `SaveFolder` |

---

## Store (`lib/store/save_system_store.dart`)

Provider: `saveSystemProvider` (Riverpod `NotifierProvider<SaveSystemNotifier, SaveSystemState>`)

### Key actions

| Method | Description |
|---|---|
| `hydrate()` | Load persisted state from `SharedPreferences` on app start |
| `persist()` | Serialize and save to `SharedPreferences` |
| `createSaveFolder(name, parentId)` | Add new folder, persist, return folder ID |
| `renameFolder(id, name)` | Update folder name |
| `deleteFolder(id)` | Remove folder + all descendants + their saves |
| `createProject(name, cfg)` | Create a new top-level project folder with config |
| `renameProject(id, name)` | Rename a project folder |
| `deleteProject(id)` | Delete a project and all its subtree |
| `updateProjectConfig(id, cfg)` | Update a project's `ProjectConfig` |
| `ensureDumpFolder()` | Returns dump folder ID, creating it if needed |
| `selectProject(id)` | Set the active project selection (project or dump kind) |
| `applyProjectConfig(projectId, cfg, {retrofit})` | Update config and optionally retrofit all subtree saves |
| `moveFolderUp(id)` | Swap folder order with the sibling above it |
| `moveFolderDown(id)` | Swap folder order with the sibling below it |
| `saveSnapshot(name, folderId, snapshot)` | Create a new save entry in the given folder |
| `updateSnapshot(id, snapshot)` | Overwrite the snapshot of an existing save |
| `renameSave(id, name)` | Rename a save entry |
| `deleteSave(id)` | Remove a save entry |
| `moveSaveUp(id)` | Swap save order with the sibling above it |
| `moveSaveDown(id)` | Swap save order with the sibling below it |
| `setActiveSession(session)` | Set the navigation active session |
| `loadSave(saveId, apply)` | Load a save's snapshot into an instrument via callback |
| `navigatePrev(apply)` | Load the previous save in the current folder |
| `navigateNext(apply)` | Load the next save in the current folder |

---

### Top-level providers

| Provider | Type | Description |
|---|---|---|
| `selectedProjectProvider` | `Provider<SaveFolder?>` | Currently selected project or dump folder |
| `projectsListProvider` | `Provider<List<SaveFolder>>` | All top-level project folders |
| `dumpFolderProvider` | `Provider<SaveFolder?>` | The single dump folder (or null) |
| `isProjectLockedProvider` | `Provider<bool>` | True when a real project (not dump) is selected |
| `activeProjectKeyProvider` | `Provider<({String root, String scaleName})?>` | Active project's key as a readable pair, or null |

---

## Widgets

### `SaveBrowserPanel` (`lib/ui/save_browser_panel.dart`)
A reusable nested folder browser used by all instrument save panels. Renders folder navigation with breadcrumbs, create/rename/delete for folders and saves, and instrument-specific save/load actions.

| Prop | Type | Description |
|---|---|---|
| `instrumentFilter` | `String?` | Filters saves to a single instrument type (`'fretboard'`, `'piano'`, `'piano_roll'`, `'song'`, `'songwriter'`, `'drum_loop'`) |
| `allowedInstruments` | `List<String>?` | Allowlist of snapshot types; overrides `instrumentFilter` when set |
| `captureSnapshot` | `InstrumentSnapshot Function()?` | Captures a snapshot from the current instrument state for saving |
| `onLoad` | `void Function(InstrumentSnapshot)?` | Applies a loaded snapshot to the current instrument |
| `onPick` | `void Function(SaveEntry)?` | Callback for picking a save entry (alternative to onLoad) |
| `rootFolderId` | `String?` | Virtual root — navigation stops at this folder and Back cannot escape it; `null` = full tree |

### Instrument save panels
Each instrument has a thin save panel widget that wraps `SaveBrowserPanel` with the appropriate filter and capture/load callbacks:

| Panel | File | Filter |
|---|---|---|
| `FretboardSavePanel` | `lib/features/fretboard/fretboard_save_panel.dart` | `'fretboard'` |
| `PianoSavePanel` | `lib/features/piano/piano_save_panel.dart` | `'piano'` |
| `PianoRollSavePanel` | `lib/features/piano_roll/piano_roll_save_panel.dart` | `'piano_roll'` |
| `SongSavePanel` | `lib/features/song/song_save_panel.dart` | `'song'` |
| `SongwriterSavePanel` | `lib/features/songwriter/songwriter_save_panel.dart` | `'songwriter'` |

### `PianoRollSaveStackLoader` (`lib/features/piano_roll/piano_roll_save_stack_loader.dart`)
A separate importer that lets the piano roll browse saved fretboard/piano snapshots and place their note stacks onto the timeline. Contrasts with `PianoRollSavePanel` which saves/loads the full piano roll session.

---

## Settings Store (`lib/store/settings_store.dart`)

Provider: `settingsProvider` (Riverpod `NotifierProvider<SettingsNotifier, AppSettings>`)

Stores app-wide preferences persisted to `SharedPreferences`:

| Field | Default | Description |
|---|---|---|
| `suppressOutOfKeyAlert` | `false` | Suppress the out-of-key confirmation dialog |
| `noteVolume` | `0.8` | Playback volume (0.0–1.0) |
| `showNoteLabels` | `true` | Render note-name text on instrument canvases |
| `humSensitivity` | `balanced` | Hum-to-MIDI pitch sensitivity preset |
| `metronomeEnabled` | `true` | Piano roll metronome toggle |

---

## State Flow

```
App start
  │
  ├─ saveSystemProvider.hydrate()          ← load from SharedPreferences
  │
  ├─ ensureDumpFolder()                    ← create dump if missing
  │
  ├─ selectProject(selectedProjectId)      ← restore active project
  │
  ├─ hydrate song / songwriter sessions    ← restore Song/Songwriter states
  │
  └─ read projectConfigSyncProvider        ← push key/tempo/signature
                                               into all instrument stores
                         │
               User opens SaveBrowserPanel
                         │
             Navigates folders / creates saves
                         │
          saveSystemProvider.saveSnapshot(...)
                         │
                 _persist() → SharedPreferences (JSON)
```

---

## Project Config Sync (`lib/store/project_config_sync.dart`)

Provider: `projectConfigSyncProvider` (mounted once in `main.dart`).

Watches `selectedProjectProvider` and, when the active project changes (or is set on startup), pushes the project's `ProjectConfig` — key, tempo, time signature — into all five instrument stores:

| Instrument | Fields pushed |
|---|---|
| Fretboard | `setHighlightedNotes(scaleNotes)` |
| Piano | `setHighlightedNotes(scaleNotes)` |
| Piano Roll | `setTempo`, `setTimeSignature`, `setKey`, `setHighlightedNotes` |
| Song | `setTempo`, `setTimeSignature`, `setScale` |
| Songwriter | `setTempo`, `setKey` |

`activeProjectKeyProvider` exposes the active project's key as a `({String root, String scaleName})?` record for use in instrument headers and other UI.

---

## Project Config (`lib/models/project_config.dart`)

`ProjectConfig` is an immutable value class carried by every `SaveFolder` with `kind == project`:

| Field | Type | Default |
|---|---|---|
| `keyRootPc` | `int?` (0-11) | null |
| `keyScaleName` | `String?` | null |
| `tempo` | `int` | 120 |
| `beatsPerBar` | `int` | 4 |
| `beatUnit` | `int` | 4 |

`ProjectConfigSheet` (project config editing UI) calls `applyProjectConfig()` which optionally retrofits config into every save in the project's subtree. Subfolder saves under a project are locked to the parent project's config; key/tempo/time-signature controls in instrument toolbars are disabled when `isProjectLockedProvider` is true.
