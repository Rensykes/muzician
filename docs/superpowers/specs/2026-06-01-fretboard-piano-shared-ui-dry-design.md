# Fretboard / Piano Shared UI DRY Design

Date: 2026-06-01
Status: Draft, ready for repo review
Scope: UI + provider-plumbing duplication between Fretboard, Piano, and (scale picker only) Piano Roll

## Goal

Eliminate the large copy-paste duplication in the **UI and provider-plumbing layer** of the
Fretboard and Piano features by extracting shared, binding-parameterized widgets. As a direct
consequence, make the two pages behave and look identical, and fix the Piano scale-drawer
discrepancy where a scale selected in detection does not surface as a named chip + badge the way
it does on Fretboard.

This is a refactor. It must not change music-theory behavior — `lib/utils/note_utils.dart`
remains the single source of truth for chord/scale/detection logic and is already shared by both
features.

## Problem Statement

The harmonic-analysis layer is already shared, but the surrounding UI is duplicated three ways:

| Concern | Fretboard | Piano | Piano Roll | Sameness |
|---|---|---|---|---|
| Detection panel | `note_detection_panel.dart` (409L) | `piano_note_detection_panel.dart` (401L) | — | ~95% |
| Scale picker | `scale_picker.dart` (369L) | `piano_scale_picker.dart` (314L) | `piano_roll_scale_picker.dart` (418L) | ~90% |
| Chord picker | `chord_voicing_picker.dart` (492L) | `piano_chord_picker.dart` (526L) | — | ~80% |
| Screen scaffold | `_FretboardScreen` in `main.dart` | `_PianoScreen` in `main.dart` | — | ~95% |
| Store plumbing | `fretboard_store.dart` | `piano_store.dart` | `piano_roll_store.dart` | parallel Notifier + parallel StateProviders |

Concrete user-visible defect that falls out of the duplication:

- Fretboard `ScalePicker` header renders the active scale as a **named chip** (`C major ✕`).
- Piano `PianoScalePicker` header renders only a plain `Clear` text button — no named chip.
- Piano Roll `PianoRollScalePicker` has the **richest** behavior (named chip **plus**
  restore-from-active-state on open, plus a stale-highlight guard) that the other two lack.

Because the three pickers drifted independently, each has a slightly different feature set and a
slightly different look (e.g. chord chips: Fretboard purple/radius-10 vs Piano emerald/radius-16).

## Locked Decisions

These were agreed during brainstorming and should not be re-opened without a real blocker:

1. **Shared widgets, keep two stores.** Do **not** merge `FretboardNotifier` and `PianoNotifier`
   into one store. Share UI widgets, parameterized by a thin per-instrument **binding**.
2. **Fold in the third copy.** `piano_roll_scale_picker.dart` is replaced by the shared scale
   picker too.
3. **One look.** Standardize the divergent styling so the pages look as well as behave identically.
4. **No theory changes.** Detection, chord/scale note generation, and spelling stay in
   `note_utils.dart`, untouched.
5. **No save-format / state-shape changes.** Stores keep their current state classes and fields.

## Architecture

### Two-tier binding

Piano Roll only needs the scale picker, and its conflict source and feature surface differ from the
two instruments. So the binding is split into two tiers.

```dart
// lib/features/instrument_shared/instrument_binding.dart

/// The minimum a shared scale picker needs. Supplied by Fretboard, Piano, and Piano Roll.
class ScalePickerBinding {
  /// Current selected pitch classes used for out-of-key conflict detection.
  ///  - Fretboard / Piano: state.selectedNotes
  ///  - Piano Roll:        state.notes.map((n) => n.pitchClass)
  final ProviderListenable<List<String>> selectedPitchClasses;

  /// Currently highlighted scale pitch classes (drives the active/cleared sync).
  final ProviderListenable<List<String>> highlightedNotes;

  /// Action surface, resolved against a WidgetRef.
  final SelectionActions Function(WidgetRef) actions;

  /// Scale hand-off providers shared with the detection panel.
  final StateProvider<({String root, String scaleName})?> pendingScale;
  final StateProvider<({String root, String scaleName})?> activeScale;

  const ScalePickerBinding({...});
}

/// Adds everything the detection panel + chord picker need. Fretboard + Piano only.
class InstrumentBinding extends ScalePickerBinding {
  /// Exact-note list for detection (midiNote + pitchClass).
  ///  - Fretboard: built from selectedCells + current tuning
  ///  - Piano:     built from selectedKeys
  final ProviderListenable<List<ExactSelectionNote>> exactNotes;
  final ProviderListenable<List<String>> selectedNotes;   // chips in detection
  final ProviderListenable<Set<String>> focusedNotes;

  final StateProvider<({String root, String quality})?> pendingChord;
  final StateProvider<({String root, String quality})?> activeChord;
  final StateProvider<int> manualEdit;
  final StateProvider<bool> chordCommitted;

  /// Chord qualities this instrument's picker offers. Piano passes a subset.
  final List<String> chordQualitySymbols;

  const InstrumentBinding({...});
}
```

`SelectionActions` is the shared action interface. Both notifiers already define every method, so
adopting it is a one-line `implements` with zero behavior change:

```dart
abstract interface class SelectionActions {
  void clearSelectedNotes();
  void toggleFocusedNote(String note);
  void setHighlightedNotes(List<String> notes);
  void removeNotesByPitchClass(List<String> notes);
}
```

`PianoRollNotifier` already exposes `setHighlightedNotes` and `removeNotesByPitchClass`; it does not
need `clearSelectedNotes` / `toggleFocusedNote` because the scale picker never calls them. To keep
the interface honest, Piano Roll's binding only requires the methods the scale picker uses — so
`SelectionActions` is the full interface for `InstrumentBinding`, and `ScalePickerBinding.actions`
is typed to a narrower `ScaleActions` interface (`setHighlightedNotes`, `removeNotesByPitchClass`)
that all three notifiers satisfy.

```dart
abstract interface class ScaleActions {
  void setHighlightedNotes(List<String> notes);
  void removeNotesByPitchClass(List<String> notes);
}
abstract interface class SelectionActions implements ScaleActions {
  void clearSelectedNotes();
  void toggleFocusedNote(String note);
}
```

### Derived providers per store

Each store file gains a few tiny derived providers so the binding can read reactive values without
the shared widget knowing the concrete state type:

```dart
// fretboard_store.dart
final fretboardSelectedNotesProvider =
    Provider((ref) => ref.watch(fretboardProvider.select((s) => s.selectedNotes)));
final fretboardFocusedNotesProvider =
    Provider((ref) => ref.watch(fretboardProvider.select((s) => s.focusedNotes)));
final fretboardHighlightedNotesProvider =
    Provider((ref) => ref.watch(fretboardProvider.select((s) => s.highlightedNotes)));
final fretboardExactNotesProvider = Provider<List<ExactSelectionNote>>((ref) {
  final state = ref.watch(fretboardProvider);
  final tuning = tunings[state.currentTuning]!;
  return state.selectedCells.map((cell) => ExactSelectionNote(
    midiNote: tuning.strings[cell.stringIndex].midiNote + cell.fret,
    pitchClass: cell.noteName,
  )).toList();
});
```

Piano supplies the equivalents (exact notes from `selectedKeys`); Piano Roll supplies
`pianoRollSelectedPitchClassesProvider` (from `state.notes`) and reuses its existing highlighted
provider.

Each store file then exports one `const`/`final` binding instance:
`fretboardBinding`, `pianoBinding` (both `InstrumentBinding`), and `pianoRollScaleBinding`
(`ScalePickerBinding`).

## Shared Widgets

New directory: `lib/features/instrument_shared/`.

### 1. `SharedScalePicker(binding: ScalePickerBinding)`

Replaces all three scale pickers. Adopts Piano Roll's superset behavior:

- Root pills, category tabs, scale pills (identical across all three today).
- Named active-scale **chip** in the header (`C major ✕`) — this fixes the Piano gap.
- Restore-from-active on open + stale-highlight guard (from Piano Roll).
- Conflict flow via `ScaleConflictDialog`, reading `binding.selectedPitchClasses` and calling
  `binding.actions(ref).removeNotesByPitchClass(...)`.
- Consumes `binding.pendingScale`, publishes `binding.activeScale`.

Fretboard and Piano inherit the restore-from-active behavior harmlessly: they only ever set
`activeScale` together with a highlight, so reopening the drawer simply re-affirms the current
state.

### 2. `SharedDetectionPanel(binding: InstrumentBinding, {onChordPanelRequested})`

Replaces both detection panels. Behavior is the union of the two (Fretboard's "no exact match"
hint is kept). Reads `binding.selectedNotes` / `binding.focusedNotes` / `binding.exactNotes`,
runs the shared detectors, and on chip tap writes `pendingChord`/`activeChord` (chord) or applies
the scale via the shared `_tryApplyScale` (scale).

### 3. `InstrumentScreen(...)`

Extracts the shared scaffold currently duplicated as `_FretboardScreen` / `_PianoScreen`:
`CompactAppBar` + optional mode segment + pinned board `SizedBox` + `Expanded` detection area with
the empty-state `_InsightHint` + `DockedToolbar` with Scale/Chord tabs.

Parameters: the binding, the instrument board widget, titles/labels, help-tab index, the save panel
widget, the settings sheet builder, the chord picker builder, and any extra mode segment
(Fretboard's Free/Chord input mode is Fretboard-only and passed in as an optional slot).

### 4. Chord pickers — partial extraction

Voicing generation genuinely differs (guitar fret-window search vs piano inversions), so the two
chord pickers remain as separate widgets, but their shared ~60% is extracted:

- `ChordPickerHeader` — title + active-chord badge.
- `RootPillRow` and `QualityPillRow` — shared pill widgets (also reused by `SharedScalePicker`).
- `ChordPickerSync` helper (a mixin or small controller) — the identical block that listens to
  `selectedNotes` (live-sync while not committed), `manualEdit` (drop commit), consumes
  `pendingChord`, and publishes `activeChord` via post-frame callback.

Each chord picker keeps only its own voicing list builder + apply logic.

## Visual Standardization (one look)

Source of truth: the `DockedToolbar` tabs already use the same colors in both screens —
**Scale = emerald, Chord = violet**. Standardize every harmonic surface to match:

- Scale chips / pills / active badges → emerald.
- Chord chips / pills / active badges → violet.
- One chip corner radius, one header text style, one pill style across both pages (removes the
  radius-10-purple vs radius-16-emerald split).
- Category tabs keep their per-category accent color (informative), unchanged.

## Out of Scope

- Merging the stores or changing any state class / save format.
- Piano Roll's chord flow or detection (Piano Roll has none; only its scale picker is folded in).
- Re-spelling rendered instrument cells (covered by the separate shared-foundation initiative).
- Any change to `note_utils.dart` theory logic.

## Files

**Added**
- `lib/features/instrument_shared/instrument_binding.dart` — bindings + interfaces.
- `lib/features/instrument_shared/shared_scale_picker.dart`
- `lib/features/instrument_shared/shared_detection_panel.dart`
- `lib/features/instrument_shared/instrument_screen.dart`
- `lib/features/instrument_shared/chord_picker_parts.dart` — header, pill rows, sync helper.

**Deleted**
- `lib/features/fretboard/note_detection_panel.dart`
- `lib/features/piano/piano_note_detection_panel.dart`
- `lib/features/fretboard/scale_picker.dart`
- `lib/features/piano/piano_scale_picker.dart`
- `lib/features/piano_roll/piano_roll_scale_picker.dart`

**Edited**
- `lib/store/fretboard_store.dart`, `lib/store/piano_store.dart`, `lib/store/piano_roll_store.dart`
  — `implements` interfaces, derived providers, binding export.
- `lib/main.dart` — both screens call `InstrumentScreen`.
- `lib/features/fretboard/chord_voicing_picker.dart`,
  `lib/features/piano/piano_chord_picker.dart` — use shared header/pills/sync.
- `lib/features/fretboard/fretboard_feature.dart` and any barrels / call sites referencing deleted
  files (e.g. `piano_roll_screen_v2.dart`, `song_screen.dart`, `_mockup_shell.dart`).

Net: ~5 duplicate files removed; an estimated ~1500 duplicated lines collapse to ~600 shared.

## Implementation Order (incremental, each step compiles + tests green)

1. Add `instrument_binding.dart` (interfaces + binding classes), make the three notifiers
   `implements` the relevant interface, add derived providers + binding exports. No UI change yet.
2. Extract `SharedScalePicker`; switch Fretboard, Piano, then Piano Roll to it; delete the three
   old pickers. (This step alone fixes the Piano chip defect.)
3. Extract `SharedDetectionPanel`; switch both screens; delete the two old panels.
4. Extract `chord_picker_parts.dart`; refactor both chord pickers onto it.
5. Extract `InstrumentScreen`; collapse `_FretboardScreen`/`_PianoScreen` in `main.dart`.
6. Apply the visual-standardization pass inside the shared widgets.

## Testing

- Run the existing widget/unit suite after each step (`flutter test`).
- Add a binding-parameterized widget test for `SharedScalePicker` exercised with both
  `fretboardBinding` and `pianoBinding`: selecting a scale shows the named chip, the conflict
  dialog appears on an out-of-key note, and `Clear`/`✕` removes the highlight and active badge.
- Add a widget test asserting the dock Scale/Chord badge lights when the corresponding active
  provider is set on both instruments.

## Risks

- **Provider read-vs-listen ergonomics.** Shared widgets need `ProviderListenable` objects (for
  `ref.listen`) plus the action surface. The binding holds the provider objects directly and a
  `SelectionActions Function(WidgetRef)`, so both reactive reads and imperative actions work.
- **Piano Roll behavior superset.** Folding Piano Roll in means Fretboard/Piano adopt its
  restore-from-active + stale-guard logic. Verified harmless for them; covered by step-2 manual
  check + tests.
- **Call sites of deleted files.** `piano_roll_screen_v2.dart`, `song_screen.dart`,
  `_mockup_shell.dart`, and the feature barrels reference the old widgets; all must be repointed in
  the same step that deletes each file to keep the tree compiling.
