# Fretboard

An interactive guitar fretboard rendered entirely with `CustomPainter`. Supports multiple tunings, capo, chord voicing loading, scale highlighting, and a landscape modal view.

---

## Architecture

```
lib/
  models/fretboard.dart               ← data types
  schema/rules/fretboard_rules.dart   ← tunings, pitch helpers, validation
  store/fretboard_store.dart          ← Riverpod NotifierProvider
  features/fretboard/
    fretboard.dart                    ← CustomPainter grid (GuitarFretboard)
    capo_control.dart                 ← capo position stepper
    chord_diagram.dart                ← chord shape mini-diagram
    chord_voicing_picker.dart         ← chord root + quality → load to fretboard
    note_detection_panel.dart         ← detect chord/scale from selected cells
    scale_picker.dart                 ← scale root + type → highlight fretboard
    tuning_selector.dart              ← preset tuning picker
    landscape_fretboard_modal.dart    ← full-screen landscape view
```

---

## Data Model (`lib/models/fretboard.dart`)

| Type | Description |
|---|---|
| `TuningName` | Enum — 10 presets (standard, dropD, openG, openD, openE, DADGAD, halfStepDown, fullStepDown, openA, openC) |
| `TuningCategory` | Enum — standard / drop / open |
| `StringTuning` | MIDI note number for one string's open pitch |
| `Tuning` | Named tuple: `name`, `category`, `strings` (6 × `StringTuning`), `displayName` |
| `FretCell` | A cell on the grid: `stringIndex`, `fret`, `noteName`, `isSelected`, `isHighlighted`, `isRoot` |
| `FretCoordinate` | A selected position: `stringIndex`, `fret`, `noteName` |
| `ChordVoicing` | A named chord shape: `name`, list of `FretCoordinate` |
| `FretboardState` | Full state: `tuning`, `numFrets`, `capo`, `viewMode`, `inputMode`, `selectedCells`, `highlightedNotes` |
| `FretboardViewMode` | Enum — pitchClass / exact / focus / exactFocus |
| `FretboardInputMode` | Enum — free / chord |

---

## Schema / Rules (`lib/schema/rules/fretboard_rules.dart`)

| Export | Description |
|---|---|
| `tunings` | `Map<TuningName, Tuning>` — all 10 preset tunings |
| `chromaticSharp` / `chromaticFlat` | Chromatic note arrays |
| `positionMarkerFrets` | `{3, 5, 7, 9, 12, 15, 17, 19, 21}` — dot marker positions |
| `getPitchClassAtFret(tuning, string, fret)` | Returns pitch class string (e.g. `"C#"`) |
| `getNoteWithOctaveAtFret(tuning, string, fret)` | Returns note + octave (e.g. `"C#4"`) |
| `isNaturalNote(pitchClass)` | True for A B C D E F G |
| `isValidPitchClass(pc)` | Validates against chromatic arrays |
| `validateTuning(tuning)` | Returns `({bool valid, List<String> errors})` |
| `getDefaultFretboardState()` | Returns standard-tuned, 15-fret, no-capo state |

---

## Store (`lib/store/fretboard_store.dart`)

Provider: `fretboardProvider` (Riverpod `NotifierProvider<FretboardNotifier, FretboardState>`)

Auxiliary providers:
- `pendingChordProvider` — `StateProvider<({String root, String quality})?>` 
- `pendingScaleProvider` — `StateProvider<({String root, String scaleName})?>` 

### Key actions

| Method | Description |
|---|---|
| `toggleCell(stringIndex, fret)` | Select / deselect a fret cell; enforces one-per-string in chord mode |
| `setTuning(tuningName)` | Switch tuning preset, rebuild cells |
| `setNumFrets(n)` | Change visible fret count (1–24) |
| `setCapo(fret)` | Set capo position |
| `setViewMode(mode)` | Switch display mode |
| `setInputMode(mode)` | Switch input mode (free / chord) |
| `loadVoicing(voicing)` | Apply a `ChordVoicing` as selected cells |
| `clearSelectedNotes()` | Clear all cell selection |
| `reset()` | Restore defaults |
| `getCurrentTuning()` | Returns active `Tuning` |
| `getFretCells()` | Returns computed `List<FretCell>` grid |

---

## Widgets

### `GuitarFretboard`
The main fretboard widget. Rendered entirely with `CustomPainter` + `RepaintBoundary`.

**Controls (top bars):**
1. **Input Mode Bar** — `Free` vs `Chord` toggle (see [Input Modes](#input-modes) below).
2. **View Mode Bar** — `All` / `Exact` / `Focus` / `Solo` selector.

**Painter logic:**
- String lines spaced vertically, fret lines spaced horizontally
- Nut drawn as thick line at fret 0
- Position dot markers at standard fret positions (3, 5, 7, 9, 12…)
- Capo shown as a coloured bar across all strings
- Selected cells drawn as filled circles with note name label
- Highlighted (scale) cells drawn as outlined circles
- Root note cells use accent colour (`sky`)

**Interaction:**
- `GestureDetector.onTapUp` → `toggleCell(string, fret)` with `lightImpact` haptic

**Layout:**
- `LayoutBuilder` ensures the fretboard fills available width
- `RepaintBoundary` isolates paint from surrounding rebuilds

---

### `CapoControl`
A row with `−` / `+` buttons to step the capo position between 0 and 11. Calls `fretboardProvider.notifier.setCapo()`. Shows `"No capo"` at 0.

---

### `TuningSelector`
A horizontal `Wrap` of pill buttons, one per `TuningName`. Active tuning is highlighted. Tapping calls `setTuning()` with `lightImpact`. Groups displayed by `TuningCategory` via a section label above each group.

---

### `ChordVoicingPicker`
Lets the user pick a chord root (12 chromatic notes) and quality (major, minor, 7, maj7, m7, dim, aug, sus2, sus4). Tapping "Load" calls `fretboardProvider.notifier.loadVoicing(voicing)`, which places the chord shape directly on the fretboard.

Chord tones are computed from a semitone-interval map (`_chordIntervals`) rather than the `music_notes` package, to ensure correct cross-string placement.

---

### `NoteDetectionPanel`
Reads `pendingChordProvider` and `pendingScaleProvider`. Displays:
- The detected chord name (e.g. `"Cmaj7"`)
- The detected scale name (e.g. `"C major"`)
- A "Clear" button that resets both providers

Chord/scale detection is triggered by the fretboard store whenever `selectedCells` changes, writing results into the pending providers.

---

### `ScalePicker`
Root + scale type selector (major, natural minor, major pentatonic, minor pentatonic, dorian, mixolydian, etc.). Tapping "Highlight" writes `pendingScaleProvider` and calls the store to populate `highlightedCells` and mark the `rootNote`.

---

### `ChordDiagram`
A compact `CustomPainter` rendering of a 5-fret chord box diagram. Draws:
- 6 vertical string lines
- 5 horizontal fret lines
- Filled dots for each fret position in the voicing
- Open / muted string indicators at the top
- Fret number label if the diagram doesn't start at fret 1

Used as a preview inside `ChordVoicingPicker`.

---

### `LandscapeFretboardModal`
A full-screen modal (pushed via `Navigator.push`) that renders `GuitarFretboard` in landscape orientation using `SystemChrome.setPreferredOrientations`. Includes a close button that restores the original orientation on pop.

---

## State Flow

```
TuningSelector → fretboardProvider.setTuning()
                          │
                 GuitarFretboard repaints
                          │
              User taps cell → toggleCell()
                          │
        NoteDetectionPanel reads pendingChordProvider
```

## Behaviour Notes

- Input modes: The fretboard supports two input modes selected via the `_InputModeBar`. In **free** mode any number of notes may be placed on any string, subject to the existing scale-highlight guard. In **chord** mode only one note per string is allowed; tapping a new fret on an already-occupied string replaces the existing note on that string, making it straightforward to build chord voicings. The active mode is stored as `FretboardState.inputMode` and toggled via `FretboardNotifier.setInputMode()`.

- Out-of-key confirmation: If a scale highlight is active and the user attempts to add a note outside that scale, the app shows an out-of-key confirmation dialog. The dialog offers a "Don't show again" option which persists to settings. See implementation: [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart).

- View-mode initialization & local override: The fretboard initializes its view mode from app settings but exposes a small view-mode control on the page allowing a local override. Tools such as chord/scale pickers do not force the view mode. Relevant code: [lib/main.dart](lib/main.dart) and [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart).

- Scroll guard: To prevent accidental note insertion while scrolling horizontally, the fretboard uses a pointer-down/ up movement threshold and ignores taps that exceed the threshold distance. See: [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart).

- Scale highlight & conflicts: Applying a scale highlights pitch classes across the board and will warn if the selected scale conflicts with already-selected notes (offers to remove conflicting notes). See: [lib/features/fretboard/scale_picker.dart](lib/features/fretboard/scale_picker.dart).

---

## Recent Changes — 2026-03-23

- **Capo behavior:** Setting the capo now animates the fretboard to the capo position and transposes currently selected notes by the capo delta so their pitches remain correct.
- **Chord picker / voicings:** Selecting a chord voicing animates the fretboard to the voicing's base fret (the nearest physical occurrence) and loads the voicing as selected cells.
- **Detection vs committed voicing:** The picker shows detected chords by default. When a user explicitly commits a voicing (taps to load), it overrides detection until the user makes a manual fretboard edit; unfocusing without selection reverts to detection.
- **Manual-edit signal:** Manual fretboard edits now clear any committed voicing so detection regains control.
- **Implementation notes:** Added two inter-widget signals in the store — `scrollToFretProvider` (one-shot int?) and `fretboardManualEditProvider` (counter). Voicing generation and `loadVoicing()` were adjusted to operate on physical frets (capo handled separately) to avoid double-applying the capo offset.
- **Bugfixes & diagnostics:** Fixed a bug where the capo was being applied twice in pitch calculations. Static checks ran locally; modified files compile cleanly. One minor unused helper (`_toSharp`) remains for cleanup.
- **Next steps:** Remove the unused helper or integrate it into parsing, and verify the piano page for analogous capo/selection issues.

---

## Recent Changes — 2026-03-23 (input modes)

- **Free mode / Chord mode:** Added `FretboardInputMode` enum (`free`, `chord`) to the data model and `FretboardState`. Default is `free`.
- **Chord mode constraint:** In chord mode `toggleCell` enforces one note per string: tapping a new fret on an occupied string replaces the existing note; tapping the selected fret deselects it. All other input-mode behaviour (scale guard, view mode, capo) is unchanged.
- **Free mode:** Existing multi-note-per-string behaviour is preserved, including the out-of-key scale guard.
- **`_InputModeBar` widget:** A two-button bar (`Free` / `Chord`) is rendered above the existing view-mode bar inside `GuitarFretboard`. Tapping a button calls `FretboardNotifier.setInputMode()` with a light haptic.
- **`setInputMode()`:** New method on `FretboardNotifier`. Persists `inputMode` in `FretboardState` via `copyWith`.


---

## Info Panel

File: `lib/ui/core/app_info_panel.dart`

A shared, dismissible help overlay. Opened by tapping the **?** button in the top-right corner of the Fretboard screen header (opens the info sheet pre-selected on the Fretboard tab).

### Entry point

```dart
showAppInfoPanel(context, initialTab: 0); // 0 = Fretboard, 1 = Piano, 2 = Piano Roll
```

### Fretboard tab sections

| Section | Content |
|---|---|
| **Gestures** | Tap fret cell to select / deselect |
| **Input & View Modes** | Free mode, Chord mode, All / Exact / Focus / Solo views |
| **Panels & Tools** | Tuning (10 presets), Capo (0–11), Chord voicing picker, Scale picker, Detection panel, Saves |
