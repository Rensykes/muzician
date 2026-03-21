# Save System

The save system provides a hierarchical, folder-based persistence layer for progressions across all instruments (fretboard, piano, piano roll). It is shared state — any screen can save to or load from the same tree.

---

## Architecture

```
lib/
  models/save_system.dart          ← data types
  schema/rules/save_system_rules.dart ← validation & UUID helpers
  store/save_system_store.dart     ← Riverpod NotifierProvider
  features/save_system/
    progression_save_button.dart   ← inline name-entry + save trigger
    save_manager_modal.dart        ← full folder/save browser modal
    save_navigation_bar.dart       ← breadcrumb path bar
    load_feedback_toast.dart       ← success / warning overlay toast
```

---

## Data Model (`lib/models/save_system.dart`)

| Type | Description |
|---|---|
| `PendingChord` | Root + quality pending detection (`root`, `quality`) |
| `PendingScale` | Root + scale name pending detection |
| `InstrumentSnapshot` | Sealed class — either `FretboardSnapshot` (selected cells + notes) or `PianoSnapshot` (selected keys + notes) |
| `SaveFolder` | Named folder node with optional parent ID and list of child save IDs |
| `SaveEntry` | A saved progression: ID, name, folder ID, `InstrumentSnapshot`, timestamp |
| `ActiveSession` | Current navigation context: `currentFolderId`, `currentSaveId`, breadcrumb path |
| `AppSettings` | User preferences — `fretboardFavouriteViewMode`, `pianoFavouriteViewMode` |
| `SaveSystemState` | Root state: `folders`, `saves`, `session`, `settings` |

> Snapshots use `sealed class` with `FretboardSnapshot` and `PianoSnapshot` subtypes. All types implement `toJson` / `fromJson` for `SharedPreferences` persistence.

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
| `navigateTo(folderId)` | Set `currentFolderId`, append to breadcrumb |
| `navigateBack()` | Pop breadcrumb to parent |
| `setCurrentSave(id)` | Mark a save as the active session entry |

---

## Widgets

### `ProgressionSaveButton`
An inline button that expands to a text field on tap. The user types a progression name and confirms to call `onSaveToFolder(name)`. Shows a "saved" indicator when `savedPath` is non-null and an "unsaved changes" dot when `isDirty` is true.

**Props:**
| Prop | Type | Description |
|---|---|---|
| `onSaveToFolder` | `Function(String)` | Called with the entered name |
| `savedPath` | `List<String>?` | Current breadcrumb path (shows saved state) |
| `isDirty` | `bool` | Shows unsaved-changes indicator |
| `onUpdate` | `VoidCallback?` | Called to overwrite an existing save |

---

### `SaveManagerModal`
A full-screen bottom sheet modal (triggered via `showModalBottomSheet`) with two modes:

| Mode | `SaveManagerMode` | Behaviour |
|---|---|---|
| Browse | `.browse` | Navigate folders, open / delete saves |
| Save | `.save` | Browse + inline save-to-current-folder action |

The modal renders:
- A `SaveNavigationBar` breadcrumb at the top
- A list of child folders (tap to navigate in, swipe to delete)
- A list of saves in the current folder (tap to load, swipe to delete)
- A create-folder button
- In `.save` mode: a name-entry row at the bottom

---

### `SaveNavigationBar`
A horizontal breadcrumb row showing the current folder path. Each segment is tappable to jump back to that ancestor. Displays a home icon at the root. Reads from `saveSystemProvider`.

---

### `LoadFeedbackToast`
A `Positioned` overlay widget for temporary feedback messages. Use inside a `Stack` — shown/hidden by the parent via conditional rendering.

| Prop | Default | Description |
|---|---|---|
| `message` | — | Text to display |
| `isWarning` | `false` | Orange border + bg on true, green on false |

Usage pattern:
```dart
Stack(
  children: [
    // ... main content
    if (_showToast)
      LoadFeedbackToast(message: 'Loaded!'),
  ],
)
```

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
