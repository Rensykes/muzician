# Writer — Unsaved-state feedback & save/overwrite prompt

Date: 2026-06-22
Branch: `feature/writer-unsaved-feedback`

## Problem

In Writer (Songwriter), a project's named **save** (a `SaveEntry` in the save
system) and the live project state can diverge silently. Today:

- The live project auto-persists to a *session* draft (`songwriterSessionsProvider`),
  but there is no concept of "this project is bound to a named save".
- The Save/Load panel's "Save here" **always creates a new save** — there is no
  overwrite-the-one-I-loaded path.
- Nothing tells the user their edits are unsaved relative to a named save.

## Goal

1. **Unsaved indicator** — visible feedback when the live project differs from
   the named save it is bound to (or is unbound but has content).
2. **Save action with choice** — when saving a bound project, prompt the user to
   **overwrite** the existing save or **save as new**.
3. **"Don't ask again" per project** — the prompt offers an option to always
   overwrite for this project; once chosen, subsequent saves overwrite silently.

## Decisions (locked)

- "Save" means the **named save** (`SaveEntry`), not the auto-session draft.
- First-ever save and "Save as new" **reuse the existing Save/Load panel**
  (folder navigation + name dialog).
- "Always overwrite" stays in effect **until a different save is loaded or a new
  project is started** (rebinding resets the flag) — matches "same project".
- Indicator = **amber dot + "Unsaved" label** next to the project name in the
  header, **plus a dedicated Save button** enabled/highlighted only when dirty.

## Architecture

### 1. Save binding store (new)

`lib/store/writer_save_binding_store.dart`

```dart
class WriterSaveBinding {
  final String? activeSaveId;   // the SaveEntry this project is bound to
  final bool alwaysOverwrite;   // skip the prompt for this project
  const WriterSaveBinding({this.activeSaveId, this.alwaysOverwrite = false});
  // toJson / fromJson / copyWith
}
```

`WriterSaveBindingNotifier extends Notifier<Map<String, WriterSaveBinding>>`
keyed by **project id** (`selectedProjectId`). Mirrors
`songwriter_sessions_store.dart`:

- Persisted to SharedPreferences key `@muzician/writer_save_bindings/v1`,
  debounced (500 ms).
- `hydrate()` — called from `main.dart` next to the other hydrates.
- `get(projectId)` → `WriterSaveBinding?`.
- `bind(projectId, saveId)` — sets `activeSaveId = saveId`, **resets
  `alwaysOverwrite = false`**. Called on load and on save (new or overwrite).
- `setAlwaysOverwrite(projectId, bool)` — sets the flag, keeps `activeSaveId`.
- `clear(projectId)` — removes the binding (used by `newProject`).

`writerSaveBindingProvider = NotifierProvider<...>`.

### 2. Dirty computation (new derived provider)

`writerDirtyProvider = Provider<bool>` in the binding store file. Watches
`songwriterProvider`, `saveSystemProvider` (`selectedProjectId` + `saves`), and
`writerSaveBindingProvider`. Logic:

```
projectId = selectedProjectId
if projectId == null            -> false
binding = bindings[projectId]
id = binding?.activeSaveId
entry = saves.firstWhereOrNull(id)          // null if unbound or stale
if entry == null                -> hasContent(project)      // unbound/never-saved
else                            -> json(project) != json(entry.snapshot)
```

- `hasContent(project)` = `project.sections.isNotEmpty || project.drumPatterns.isNotEmpty`.
- `json(x)` = `jsonEncode(x.toJson())` — there is no `==` override on the
  snapshot model, so JSON comparison is the robust dirty check. Comparing the
  full snapshot (including `name`) is fine: save stores the current snapshot, so
  they match until edited.

### 3. SaveBrowserPanel — thread the save id (shared widget, additive)

`lib/ui/save_browser_panel.dart` is shared across instruments. Add two
**optional** callbacks (no behavior change for existing callers):

- `void Function(String saveId)? onSaved` — invoked in `_handleSaveHere` after
  `saveSnapshot(...)` returns a non-null id.
- `void Function(String saveId)? onLoadSaveId` — invoked in `_handleLoad` with
  `save.id` (alongside the existing `onLoad`).

### 4. SongwriterSavePanel — bind on load/save

`lib/features/songwriter/songwriter_save_panel.dart` wires the new callbacks to
`writerSaveBindingProvider.bind(selectedProjectId, saveId)` for both load and
save. (Loading a save binds it; saving a new save binds the new id.)

### 5. Save-choice dialog (new)

`lib/features/songwriter/writer_save_choice_dialog.dart`

`Future<WriterSaveChoice?> showWriterSaveChoiceDialog(context, {required String saveName})`
returning `{ action: overwrite | saveAsNew, dontAskAgain: bool }` (null = cancel).
Layout: title "Save changes to '<name>'?", an "Always overwrite for this project"
checkbox, and buttons **Overwrite**, **Save as new…**, **Cancel**. Keys for tests:
`writerSaveOverwrite`, `writerSaveAsNew`, `writerSaveAlwaysCheckbox`.

### 6. Save flow (screen sheet)

`_SongwriterScreenSheetState._saveProject(context)`:

```
projectId = selectedProjectId; if null -> return
binding = bindings[projectId]; entry = saves[binding?.activeSaveId]
if entry != null:                                  // bound to an existing save
  if binding.alwaysOverwrite:
     updateSnapshot(entry.id, project); haptic; snackbar "Saved"
  else:
     choice = showWriterSaveChoiceDialog(name: entry.name)
     if choice == null: return
     if choice.dontAskAgain: setAlwaysOverwrite(projectId, true)
     if choice.action == overwrite:
        updateSnapshot(entry.id, project); haptic; snackbar "Saved"
     else: // saveAsNew
        _openSaveLoad(context)   // panel handles name+folder, binds new id
else:                                               // unbound / never saved
  _openSaveLoad(context)         // first save via panel, binds new id
```

### 7. Header indicator + Save button

`lib/features/songwriter/songwriter_header.dart` (already a `ConsumerWidget`):

- `final bool dirty = ref.watch(writerDirtyProvider);`
- Next to the project-name text: when `dirty`, an amber dot (8px,
  `MuzicianTheme` accent/warning color) + "Unsaved" caption. Key
  `writerUnsavedBadge`.
- A new `IconBtn` (`Icons.save_rounded`, key `writerSaveButton`) in the title
  row, calling a new `onSave` callback (wired from the screen sheet to
  `_saveProject`). Visually enabled/highlighted only when `dirty`; tapping when
  clean is a no-op (or hidden).
- Compact (landscape) layout: surface the Save action from the config-strip
  trailing button / overflow so it is still reachable.

## Binding lifecycle

| Event | Binding effect |
|-------|----------------|
| Load save X | `bind(projectId, X)` → activeSaveId=X, alwaysOverwrite=false |
| Save as new (id Y) | `bind(projectId, Y)` → activeSaveId=Y, alwaysOverwrite=false |
| Overwrite (checkbox on) | `setAlwaysOverwrite(true)`; activeSaveId unchanged |
| New project | `clear(projectId)` |
| Bound save deleted | dirty treats binding as stale → behaves as unbound |
| Switch project | binding read for the newly selected projectId |

## Testing (TDD)

Unit (`package:test` / Riverpod `ProviderContainer`):

- `writer_save_binding_store_test.dart` — bind sets id and resets
  alwaysOverwrite; setAlwaysOverwrite keeps id; clear removes; persist→hydrate
  round-trip.
- `writer_dirty_test.dart` — unbound+empty → not dirty; unbound+content →
  dirty; bound+equal → not dirty; bound+edited → dirty; bound+entry-deleted →
  dirty when content.

Widget:

- `writer_save_flow_test.dart` — bound + !alwaysOverwrite → dialog shows;
  Overwrite calls `updateSnapshot`; checkbox sets flag and next save is silent;
  Save-as-new + unbound first-save open the Save/Load panel.
- `writer_header_unsaved_test.dart` — badge visible when dirty, hidden when
  clean; Save button enabled only when dirty.

## Out of scope (YAGNI)

- Auto-save changes to the bound named save.
- A separate "reset always-overwrite" UI control (it resets on rebind/new).
- Conflict handling if the same save is edited elsewhere concurrently.
- Changes to non-songwriter instrument save panels (callbacks are optional).

## Files touched

- New: `lib/store/writer_save_binding_store.dart`,
  `lib/features/songwriter/writer_save_choice_dialog.dart`.
- Edit: `lib/ui/save_browser_panel.dart` (optional callbacks),
  `lib/features/songwriter/songwriter_save_panel.dart` (bind wiring),
  `lib/features/songwriter/songwriter_header.dart` (indicator + Save btn),
  `lib/features/songwriter/songwriter_screen_sheet.dart` (`_saveProject`, wire
  `onSave`), `lib/main.dart` (hydrate binding store).
