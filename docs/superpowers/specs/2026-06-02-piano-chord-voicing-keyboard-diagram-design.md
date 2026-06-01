# Piano Chord Voicing — Mini-Keyboard Diagram

**Date:** 2026-06-02
**Status:** Approved

## Problem

The piano chord picker ([lib/features/piano/piano_chord_picker.dart](../../../lib/features/piano/piano_chord_picker.dart))
shows each voicing/inversion as a plain text card (label + comma-joined note
names). The fretboard chord picker shows a visual mini-neck diagram per voicing
via [ChordDiagram](../../../lib/features/fretboard/chord_diagram.dart). The piano
picker should reach parity: each voicing card renders a mini piano keyboard with
the chord's keys highlighted, so a distinct keyboard appears per voicing/inversion.

## Decisions

- **Card content:** mini-keyboard **plus** the note-name text row (e.g. `C E G`)
  below it. Voicing label (`Root` / `1 inv`) on top.
- **Range:** fixed **2 octaves**, window start = octave containing the lowest
  voicing midi (`(minMidi ~/ 12) * 12`).
- **Root highlight:** root pitch class in **sky**; other chord tones in
  **violet** — mirrors the fretboard diagram's color scheme.

## Design

### New widget — `lib/features/piano/piano_chord_diagram.dart`

Mirrors `chord_diagram.dart` structure (StatelessWidget + private CustomPainter).

```
PianoChordDiagram({
  required List<int> midis,      // voicing midi notes (already filtered to keys)
  required int? rootPc,          // root pitch class (noteToPC[root]); null hides root tint
  required String label,         // "Root" / "1 inv" / "2 inv"
  required List<String> noteLabels, // ["C","E","G"] for the text row
  required bool isSelected,
  required VoidCallback onPress,
})
```

- `GestureDetector` → `Container` (selected = violet glow + brighter border,
  reuse current card decoration values) → `Column`:
  1. `label` text (top)
  2. `CustomPaint` mini-keyboard
  3. note-name text row (`noteLabels.join(' ')`)

### `_PianoChordPainter`

- Constants: 2 octaves → 14 white keys; black-key positions per octave at white
  indices `{0,1,3,4,5}` (C#,D#,F#,G#,A#), reusing the `_blackKeysAt` pattern from
  `_PianoMiniPainter` in
  [save_preview_thumbnail.dart](../../../lib/ui/save_previews/save_preview_thumbnail.dart).
- `windowStart = (midis.reduce(min) ~/ 12) * 12`.
- Draw 14 white keys (default dark fill). For each white key whose midi ∈ `midis`:
  fill sky if `midi % 12 == rootPc`, else violet.
- Draw black keys on top. Same highlight rule.
- Keys with midi outside the window are not drawn; the note-name text row still
  lists every chord tone, so overflow (rare: 9th chords) stays legible.

### Integration — `piano_chord_picker.dart`

- Replace the text-only voicing `Container` (currently
  [lines ~242-304](../../../lib/features/piano/piano_chord_picker.dart)) inside the
  `ListView.separated` itemBuilder with `PianoChordDiagram`.
- Pass: `midis: v.midis`, `rootPc: noteToPC[_selectedRoot]`,
  `label: v.label`, `noteLabels: chordNotes`, `isSelected: _selectedVoicingIdx == i`.
- `onPress` keeps the existing tap logic verbatim (haptic, set committed,
  `loadExactMidis(v.midis)`, scroll-to-min-midi provider).
- Bump carousel `SizedBox(height: 70)` → `~108` to fit keyboard + two text rows
  (match fretboard carousel height).

### Out of scope / non-changes

- No store / provider / state changes — voicing midis already computed in `build`.
- Voicing generation (`_buildVoicingMidis`), octave selector, root/quality pills
  unchanged.

## Testing

- Widget test: render `PianoChordDiagram` with a known voicing (C major,
  midis [60,64,67], rootPc 0), assert it paints without error and the note text
  row shows `C E G`.
- Extend existing piano chord picker test
  ([test/features/piano](../../../test/features/piano)) to confirm voicing cards
  render the new diagram and tapping still commits + loads midis.
- `dart analyze` clean; `dart format`.
