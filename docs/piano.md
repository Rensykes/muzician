# Piano

An interactive piano keyboard rendered with `CustomPainter`. Supports three range sizes (49 / 61 / 88 keys), chord and scale highlighting, note detection, and a landscape modal view.

---

## Architecture

```
lib/
  models/piano.dart               ← data types
  schema/rules/piano_rules.dart   ← ranges, MIDI helpers, key generation
  store/piano_store.dart          ← Riverpod NotifierProvider
  features/piano/
    piano_keyboard.dart           ← CustomPainter keyboard (PianoKeyboard)
    piano_chord_picker.dart       ← chord root + quality → highlight keys
    piano_scale_picker.dart       ← scale root + type → highlight keys
    piano_note_detection_panel.dart ← detect chord/scale from selected keys
    piano_range_selector.dart     ← 49 / 61 / 88 range pill picker
    landscape_piano_modal.dart    ← full-screen landscape view
```

---

## Data Model (`lib/models/piano.dart`)

| Type | Description |
|---|---|
| `PianoRangeName` | Enum — `key49`, `key61`, `key88` |
| `PianoRange` | Named range: `name`, `startMidi`, `endMidi`, `displayName` |
| `PianoKeyCell` | One key: `midiNote`, `pitchClass`, `octave`, `isBlack`, `isSelected`, `isHighlighted`, `isRoot` |
| `PianoCoordinate` | A selected key: `midiNote`, `pitchClass`, `octave` |
| `PianoState` | Full state: `currentRange`, `keys`, `selectedKeys`, `highlightedKeys`, `rootNote`, `viewMode` |
| `PianoViewMode` | Enum — standard / chords / scales / intervals |

---

## Schema / Rules (`lib/schema/rules/piano_rules.dart`)

| Export | Description |
|---|---|
| `pianoRanges` | `Map<PianoRangeName, PianoRange>` — 49 (C3–C7), 61 (C2–C7), 88 (A0–C8) |
| `midiToPitchClass(midi)` | Returns pitch class string (e.g. `"C#"`) |
| `midiToNoteWithOctave(midi)` | Returns note + octave (e.g. `"C#4"`) |
| `generateKeys(range)` | Builds `List<PianoKeyCell>` for the given range |
| `getDefaultPianoState()` | Returns 49-key state, no selection |

---

## Store (`lib/store/piano_store.dart`)

Provider: `pianoProvider` (Riverpod `NotifierProvider<PianoNotifier, PianoState>`)

Auxiliary providers:
- `pianoPendingChordProvider` — `StateProvider<({String root, String quality})?>` 
- `pianoPendingScaleProvider` — `StateProvider<({String root, String scaleName})?>` 

### Key actions

| Method | Description |
|---|---|
| `toggleKey(midiNote)` | Select / deselect a piano key |
| `setRange(rangeName)` | Switch to 49 / 61 / 88 key layout |
| `setViewMode(mode)` | Switch display mode |
| `setPianoFavouriteViewMode(mode)` | Persist favourite view mode to settings |
| `highlightChord(root, quality)` | Mark chord tones as highlighted, set root note |
| `highlightScale(root, scaleName)` | Mark scale tones as highlighted, set root note |
| `clearHighlights()` | Remove all highlights and root marker |
| `clearSelectedNotes()` | Deselect all keys |
| `reset()` | Restore defaults |

---

## Widgets

### `PianoKeyboard`
The main keyboard widget. Rendered with `CustomPainter` + `RepaintBoundary` inside a horizontal `SingleChildScrollView` (scrollable for 61 / 88 key ranges).

**Painter logic:**
- White keys drawn first as filled rectangles with black borders
- Black keys drawn on top — narrower, shorter
- Selected keys fill with `sky` accent colour and show note name
- Highlighted keys use `teal` fill (scale) or `violet` (chord)
- Root note key uses `emerald` fill
- Note labels drawn on wide-enough keys only

**Interaction:**
- `GestureDetector.onTapUp` and `onPanUpdate` → `toggleKey(midi)` with `lightImpact` haptic
- Horizontal pan scrolls when no key is directly tapped

**Layout:**
- White key width computed from available width ÷ number of white keys in range
- `LayoutBuilder` keeps proportions correct at any screen size

---

### `PianoRangeSelector`
A `Wrap` of pill buttons for the three range presets (49-key, 61-key, 88-key). Active range is highlighted in `sky`. Tapping calls `pianoProvider.notifier.setRange()`.

---

### `PianoChordPicker`
Root (12 chromatic notes) + chord quality selector. Same chord qualities as the fretboard picker (major, minor, 7, maj7, m7, dim, aug, sus2, sus4). Tapping "Highlight" calls `highlightChord()` and writes to `pianoPendingChordProvider`.

Chord tones computed from a semitone-interval map (`_chordIntervals`).

---

### `PianoScalePicker`
Root + scale type selector. Tapping "Highlight" calls `highlightScale()` and writes to `pianoPendingScaleProvider`.

---

### `PianoNoteDetectionPanel`
Reading `pianoPendingChordProvider` and `pianoPendingScaleProvider`, displays the detected chord and scale for active selected keys. Includes a "Clear" button that resets both providers and clears highlights.

---

### `LandscapePianoModal`
A full-screen modal that forces landscape orientation (`SystemChrome.setPreferredOrientations`) and renders `PianoKeyboard`. Restores orientation on pop.

---

## State Flow

```
PianoRangeSelector → pianoProvider.setRange()
                            │
                  PianoKeyboard repaints
                            │
            User taps key → toggleKey(midi)
                            │
    PianoNoteDetectionPanel reads pianoPendingChordProvider
```

## Behaviour Notes

- Out-of-key confirmation: When a scale highlight is active and the user tries to add a key outside that scale, the app shows an out-of-key confirmation dialog with a "Don't show again" option persisted to settings. See implementation: [lib/features/piano/piano_keyboard.dart](lib/features/piano/piano_keyboard.dart).

- View-mode initialization & local override: The piano initializes its view mode from app settings and provides an in-page view-mode control for local overrides; chord/scale tools do not force the view mode. Relevant files: [lib/main.dart](lib/main.dart) and [lib/features/piano/piano_keyboard.dart](lib/features/piano/piano_keyboard.dart).

- Scale highlight & conflicts: Applying a scale highlights pitch classes and will prompt to remove conflicting selected keys if necessary. See: [lib/features/piano/piano_scale_picker.dart](lib/features/piano/piano_scale_picker.dart).

