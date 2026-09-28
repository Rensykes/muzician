# Save System

The save system provides project-scoped folders and canonical snapshots for
Fretboard, Piano, Piano Roll, Song, Writer, and reusable drum loops. Recoverable
Writer blocks link to these shared saves through managed section folders; a
shared save keeps one snapshot even when several Writer placements use it. A
block whose save and fallback content are both unavailable remains visible as
broken in Writer.

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
| `normal` | Ordinary project subfolder, or a Writer-managed section folder. |
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

When a project is selected, tempo / key / time-signature controls on the instrument and arrangement headers are locked. Edit them through the project config sheet, which prompts before retrofitting eligible saves in the project's subtree. Named Writer Song versions are immutable and are not retrofitted; the active Writer session follows the current project config.

### Migration

Storage key bumped to `@muzician/save-system/v3`. When no valid v3 state exists,
startup validates the known legacy save-system keys
(`@muzician/save-system/v2`, `@muzician/save_system`) and singular session keys
(`@muzician/song_session/v1`, `@muzician/songwriter_session/v1`) before the
existing migration clears them and `appDocs/song_audio/`. Valid legacy payloads
keep that migration policy. A malformed legacy string is kept in place and
shown in the startup recovery prompt until the user chooses **Start fresh**.

| Type | Description |
|---|---|
| `PendingChord` | Root + quality pending detection (`root`, `quality`, `symbol`) |
| `PendingScale` | Root + scale name pending detection |
| `InstrumentSnapshot` | Abstract class — `FretboardSnapshot`, `PianoSnapshot`, `PianoRollSnapshot`, `SongProjectSnapshot`, `SongwriterProjectSnapshot`, `WriterBlockSnapshot`, `DrumLoopSnapshot` |
| `FretboardSnapshot` | Fretboard save: tuning, capo, selected cells, notes, view mode, pending chord/scale |
| `PianoSnapshot` | Piano save: key range, selected keys, notes, view mode, pending chord/scale |
| `PianoRollSnapshot` | Piano roll session: tempo, time signature, notes, range, snap, highlights, derivable chord/scale |
| `WriterBlockSnapshot` | Writer-native content for a harmony, silent, drum, melody, strum, or audio block, including a default lyric seed for new placements; audio bytes stay in the audio repository |
| `SaveFolder` | Named folder node with optional parent ID, metadata, and ordering |
| `SaveEntry` | Canonical saved content: ID, name, physical folder ID, snapshot, origin (`manual` or `writer`), timestamp, and ordering |
| `WriterSaveLink` | Link from one Writer source block to its section folder and canonical save; holds no duplicate snapshot |
| `ProgressionFolderMeta` | Metadata attached to a folder: source type, progression ID, key |
| `ProgressionChordMeta` | Metadata attached to a save: chord symbol, root, Roman numeral, chord notes |
| `ActiveSession` | Current navigation context: `saveId` + `folderId` |
| `AppSettings` | User preferences — `suppressOutOfKeyAlert`, `noteVolume`, `showNoteLabels`, `humSensitivity`, `metronomeEnabled`, `saveBrowserGrid`, and the last content workspace |
| `SaveSystemState` | Root state: `folders`, `saves`, Writer links, `activeSession`, `hydrated`, and `selectedProjectId` |

> `SaveFolder.writerSectionId` marks a Writer-managed section folder; it is absent on ordinary folders and existing data. `SaveSystemState.writerLinks` is additive in v3 and defaults to an empty list for older payloads. Legacy saves default to origin `manual`. Snapshots implement `toJson` / `fromJson` for `SharedPreferences` persistence.

## Startup hydration and Data Recovery

The app keeps the content workspaces unmounted until saved settings, sessions,
Writer save links, and the save-system state have hydrated. A pending coordinated
Writer/save transaction is replayed before Writer is shown, so its canonical
saves, draft, and named-save binding recover together. A settings read
failure falls back to default settings. A session or save-system read failure
keeps the workspaces closed and offers **Retry**. Malformed persisted JSON is
shown with **Retry** and **Start fresh**; the original string stays in place
until the user chooses Start fresh.

Start fresh copies each malformed original string to a separate
`@muzician/data-recovery/v1/` preference and verifies the copy before removing
the source key. Settings then exposes preserved entries under **Data Recovery**
as read-only raw text. Each entry offers **Copy**, **Export**, and confirmed
**Delete backup**; deletion removes only that entry. Recovery backups remain
until explicitly deleted.

Export preserves the stored string's UTF-8 bytes without decoding or
re-encoding JSON. Filenames include a sanitized source key and a unique backup
ID. Android and iOS use the native share sheet, with the initiating Export
control anchoring the iPadOS share popover; macOS, Windows, and Linux use a save
dialog and then write those bytes. Web uses the browser Share API when available
and `share_plus`'s download fallback otherwise. Web feedback reflects that the
file was shared or downloaded; dismissing the share UI produces no success
message.

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

Named Song version — ordered `SongSection`s, parallel `SongLane`s, and
`SongBlock`s with materialized fallback content for recoverable musical state.
The active Writer session resolves current content through each block's
canonical save first; fallback content lets a named version restore the content
as it was when saved. Defined in `lib/models/songwriter.dart`; see
[`docs/songwriter.md`](songwriter.md).

- `selectedNotes` aggregates unique pitch classes across all harmony-block `chordNotes`.
- `pendingChord` and `pendingScale` return `null` — Songwriter saves do not produce chord/scale summaries.

### WriterBlockSnapshot

One placement-free Writer block's canonical musical content. Harmony and silent
blocks carry their chord or silent-block data; drum, melody, and strum blocks
carry pattern contents; audio blocks carry clip and source/derived asset
metadata. `defaultLyrics` is copied into a new placement once and later lyric
edits remain local to that placement. Source audio bytes remain in
`SongAudioRepository`. Save-lane voicings continue to use `FretboardSnapshot`
or `PianoSnapshot`.

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
| `deleteFolder(id)` | Remove an ordinary folder and descendants if none contain linked Writer saves; project roots use the project-wide delete path |
| `createProject(name, cfg)` | Create a new top-level project folder with config |
| `renameProject(id, name)` | Rename a project folder |
| `deleteProject(id)` | Delete a project and its subtree, Writer draft, and named-save binding in one recoverable transaction |
| `updateProjectConfig(id, cfg)` | Update a project's `ProjectConfig` |
| `ensureDumpFolder()` | Returns dump folder ID, creating it if needed |
| `selectProject(id)` | Set the active project selection (project or dump kind) |
| `applyProjectConfig(projectId, cfg, {retrofit})` | Update config and optionally retrofit eligible subtree saves |
| `moveFolderUp(id)` | Swap folder order with the sibling above it |
| `moveFolderDown(id)` | Swap folder order with the sibling below it |
| `saveSnapshot(name, folderId, snapshot)` | Create a new save entry in the given folder |
| `updateSnapshot(id, snapshot)` | Overwrite the snapshot of an existing save |
| `renameSave(id, name)` | Rename a save entry |
| `deleteSave(id)` | Remove a save entry |
| `buildWriterStructure(projectId, next)` | Validate and prepare the Save System side of a Writer reconciliation without changing state or writing storage |
| `commitWriterStructure(projectId, next, {persist = true})` | Validate and publish the candidate Writer structure; set `persist: false` when the shared Writer transaction queue owns the write |
| `moveSaveUp(id)` | Swap save order with the sibling above it |
| `moveSaveDown(id)` | Swap save order with the sibling below it |
| `setActiveSession(session)` | Set the navigation active session |
| `loadSave(saveId, apply)` | Load a save's snapshot into an instrument via callback |
| `navigatePrev(apply)` | Load the previous save in the current folder |
| `navigateNext(apply)` | Load the next save in the current folder |

### Writer links and removal safeguards

Section folders are direct children of the project and are owned by Writer.
Renaming, reordering, removing, undoing, redoing, or loading a named Writer
version reconciles those folders and their links by section ID. A Writer-origin
save is placed in its earliest linked section folder and returns to the project
root after its final Writer link is removed. A manual save linked from the root
keeps its original folder. Linking a manual root save does not duplicate or
move it.

The Writer store prepares block content, canonical saves, and links, then uses
`buildWriterStructure` and `commitWriterStructure` to validate and publish the
Save System state. `WriterSaveSyncNotifier.commitWriterTransaction` coordinates
that state with the Writer draft and named-save binding through the journal.

The Save System store rejects direct deletion of a linked save or managed
section folder, and rejects ordinary creation or rename/move operations inside
a managed section folder. The Writer Section blocks view can rename a linked
save; removing or repositioning its Writer block is managed in Writer. Deleting
an ordinary ancestor folder is also rejected when its descendants contain
linked saves. Deleting a project removes its Writer draft and named-save
binding along with the project tree. The shared journal makes all three
persisted payloads recover together after an interrupted write.

Save System writes, Writer drafts, and named-save bindings use a shared serial
queue for coordinated Writer changes. Each compound change records a pending
journal before writing the three payloads; startup replays an incomplete
journal before exposing workspaces.

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
A reusable nested folder browser used by instrument save panels. Renders folder navigation with breadcrumbs, create/rename/delete for ordinary folders and saves, and instrument-specific save/load actions. Writer section folders are managed by Writer. Linked saves appear in each linked section folder; one canonical save can therefore be visible through more than one link.

When Writer reconciliation preserves two different versions of a save, the
recovered entry is labeled **Recovered · “original name”** and the original
entry is labeled **Original · “recovered name”**. These names let the user
identify both versions from the Writer recovery review without needing to
interpret internal save IDs. Save Browser header controls provide 44×44px
targets and button semantics while keeping their compact visual style. Edit-mode
save delete and reorder controls use the same target size and expose action names.
The header, breadcrumbs, folders, and saves share one vertical scroll area at
bounded heights; in content-sized instrument sheets, the panel can still grow
with its contents.

| Prop | Type | Description |
|---|---|---|
| `instrumentFilter` | `String?` | Filters saves to a single instrument type (`'fretboard'`, `'piano'`, `'piano_roll'`, `'song'`, `'songwriter'`, `'writer_block'`, `'drum_loop'`); Writer's Section blocks view can show mixed Writer and instrument save types |
| `allowedInstruments` | `Set<String>?` | Allowlist of snapshot types; when combined with `instrumentFilter`, a save must satisfy both filters |
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

The Writer panel separates whole-project **Song versions** from individual
**Section blocks**. A Writer-native block save can be browsed, renamed, or used
in Writer, but is never loaded as a whole Song version. Fretboard and Piano
ideas in a project root have an explicit **Use in Writer** action; Dump-root
ideas stay in Dump. Opening a linked voicing for editing offers **Update linked
save** only while that save still has a Writer link.

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
  ├─ hydrate settings
  ├─ replay pending Writer/save journal    ← finish a coordinated write first
  ├─ hydrate Song, Writer draft, and binding stores
  ├─ saveSystemProvider.hydrate()          ← load from SharedPreferences
  │
  ├─ restore selected project or create Dump
  ├─ reconcile Writer if a real project is selected ← restore section folders / saves
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

`ProjectConfigSheet` (project config editing UI) calls `applyProjectConfig()`
which can retrofit eligible saves in the project's subtree. Named
`SongwriterProjectSnapshot` versions are immutable and skipped. The active
Writer session still follows the project config; loading a version whose tempo,
meter, or key differs shows the difference before applying the current config.
Subfolder saves under a project are locked to the parent project's config;
key/tempo/time-signature controls in instrument toolbars are disabled when
`isProjectLockedProvider` is true.
