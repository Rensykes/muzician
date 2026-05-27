# Save System

The save system provides a hierarchical, folder-based persistence layer for progressions across all instruments (fretboard, piano, piano roll). It is shared state — any screen can save to or load from the same tree.

---

## Architecture

```
lib/
  models/save_system.dart          ← data types (snapshots for all instruments)
  schema/rules/save_system_rules.dart ← validation & UUID helpers
  store/save_system_store.dart     ← Riverpod NotifierProvider
  store/settings_store.dart        ← app-wide preferences provider
  ui/save_browser_panel.dart       ← reusable nested folder save browser
  features/save_system/
    save_system.dart               ← feature barrel export
```

---

## Data Model (`lib/models/save_system.dart`)

| Type | Description |
|---|---|
| `PendingChord` | Root + quality pending detection (`root`, `quality`, `symbol`) |
| `PendingScale` | Root + scale name pending detection |
| `InstrumentSnapshot` | Sealed class — `FretboardSnapshot`, `PianoSnapshot`, or `PianoRollSnapshot` |
| `FretboardSnapshot` | Fretboard save: tuning, capo, selected cells, notes, view mode, pending chord/scale |
| `PianoSnapshot` | Piano save: key range, selected keys, notes, view mode, pending chord/scale |
| `PianoRollSnapshot` | Piano roll session: tempo, time signature, notes, range, snap, highlights, derivable chord/scale |
| `SaveFolder` | Named folder node with optional parent ID, metadata, and ordering |
| `SaveEntry` | A saved progression: ID, name, folder ID, `InstrumentSnapshot`, timestamp, ordering |
| `ProgressionFolderMeta` | Metadata attached to a folder: source type, progression ID, key |
| `ProgressionChordMeta` | Metadata attached to a save: chord symbol, root, Roman numeral, chord notes |
| `ActiveSession` | Current navigation context: `saveId` + `folderId` |
| `AppSettings` | User preferences — `suppressOutOfKeyAlert`, `noteVolume`, `showNoteLabels`, `humSensitivity`, `metronomeEnabled` |
| `SaveSystemState` | Root state: `folders`, `saves`, `activeSession`, `hydrated` |

> Snapshots use `sealed class` with `FretboardSnapshot`, `PianoSnapshot`, and `PianoRollSnapshot` subtypes. All types implement `toJson` / `fromJson` for `SharedPreferences` persistence.

---

## Schema / Validation (`lib/schema/rules/save_system_rules.dart`)

| Helper | Purpose |
|---|---|
| `generateId()` | UUID v4 via `package:uuid` |
| `validateFolderName(name)` | Non-empty, ≤ 64 chars |
| `validateSaveName(name)` | Non-empty, ≤ 128 chars |
| `getChildFolders(state, folderId)` | Direct child folders of a node |
| `getDescendantFolderIds(state, folderId)` | All descendant IDs (for safe delete) |
| `getSavesInFolder(state, folderId)` | All `SaveEntry`s in a folder |
| `makeFolder(name, parentId)` | Factory — new `SaveFolder` with UUID |
| `makeSave(name, folderId, snapshot)` | Factory — new `SaveEntry` with UUID + timestamp |

---

## Store (`lib/store/save_system_store.dart`)

Provider: `saveSystemProvider` (Riverpod `NotifierProvider<SaveSystemNotifier, SaveSystemState>`)

### Key actions

| Method | Description |
|---|---|
| `hydrate()` | Load persisted state from `SharedPreferences` on app start |
| `persist()` | Serialize and save to `SharedPreferences` |
| `createFolder(name, parentId)` | Add new folder, navigate into it |
| `renameFolder(id, name)` | Update folder name |
| `deleteFolder(id)` | Remove folder + all descendants + their saves |
| `createSave(name, snapshot)` | Create a new save entry in the current folder |
| `updateSave(id, snapshot)` | Overwrite the snapshot of an existing save |
| `deleteSave(id)` | Remove a save entry |
| `navigateTo(folderId)` | Set `currentFolderId` |
| `navigateBack()` | Pop to parent folder |
| `setCurrentSave(id)` | Mark a save as the active session entry |

---

## Widgets

### `SaveBrowserPanel` (`lib/ui/save_browser_panel.dart`)
A reusable nested folder browser used by all three instrument save panels. Renders folder navigation with breadcrumbs, create/rename/delete for folders and saves, and instrument-specific save/load actions.

| Prop | Type | Description |
|---|---|---|
| `instrumentFilter` | `String?` | Filters saves to a single instrument type (`'fretboard'`, `'piano'`, `'piano_roll'`) |
| `captureSnapshot` | `InstrumentSnapshot Function()?` | Captures a snapshot from the current instrument state for saving |
| `loadSnapshot` | `void Function(InstrumentSnapshot)?` | Applies a loaded snapshot to the current instrument |
| `onRenameRequest` | — | Handles rename dialog presentation |

### Instrument save panels
Each instrument has a thin save panel widget that wraps `SaveBrowserPanel` with the appropriate filter and capture/load callbacks:

| Panel | File | Filter |
|---|---|---|
| `FretboardSavePanel` | `lib/features/fretboard/fretboard_save_panel.dart` | `'fretboard'` |
| `PianoSavePanel` | `lib/features/piano/piano_save_panel.dart` | `'piano'` |
| `PianoRollSavePanel` | `lib/features/piano_roll/piano_roll_save_panel.dart` | `'piano_roll'` |

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
App start → saveSystemProvider.hydrate()
                      │
              User opens SaveManagerModal
                      │
          Navigates folders / creates saves
                      │
       saveSystemProvider.createSave(name, snapshot)
                      │
              saveSystemProvider.persist()
                      │
              SharedPreferences (JSON)
```
