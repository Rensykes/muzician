# Writer Melody Pattern Length and Naming Design

## Intent

Let songwriters author melody patterns longer than one bar, keep every pattern nameable, and make Writer placements behave as bar-aligned windows over the melody instead of looping it. The melody remains the source content; shortening or moving a placement clips its playback without deleting notes.

## Goals

- Extend a melody's editing canvas in whole bars so notes can be written across multiple bars.
- Derive the melody's length from its last note, rounded up to a complete bar, with a one-bar minimum.
- Keep pattern names editable and shared by every linked placement.
- Limit placements to the melody's last bar and stop playback at the melody's end; no looping past it.
- Preserve existing pattern, placement, Save and history contracts.

## Non-goals

- No looping a melody beyond its authored end.
- No arbitrary trailing empty bars after the last note.
- No new melody schema beyond the existing name and length fields.
- No changes to Guitar Strum, Drums, Harmony, Song tracks or audio lanes.
- No destructive cleanup of old projects.

## Approaches considered

1. **Chosen: editor controls.** Add a Bars stepper that extends the existing Piano Roll canvas and make the editor title renameable. Pattern length is recalculated from the notes when saved. This uses the existing multi-bar Piano Roll support and keeps authoring in one place.
2. **Setup dialog first.** Ask for name and bars before opening the editor. Clearer upfront, but the editor still needs both controls for later changes, so it duplicates UI.
3. **Auto-grow on drawing.** Extend the grid when notes approach its right edge. Discoverable only by drawing at the boundary and offers no deliberate way to prepare empty space.

## Behavior

### Melody content and length

- A new melody starts at one bar and is named `Melody`.
- The melody editor exposes a Bars stepper from 1 to 32. Increasing it extends the Piano Roll canvas; decreasing it may not go below the bar containing the last note.
- On save, melody length is `max(1, ceil(last note end / measure ticks))` bars. Empty melodies remain one bar. A melody ending early inside a bar occupies that whole bar, with silence after the last note.
- Pattern length is quantized to whole bars. Notes are never deleted by changing the editing canvas or by shortening a Writer placement.
- The name is edited in the melody editor. Saving applies both name and notes. Renaming a shared melody updates every linked placement's label. Cancelling leaves the prior name and content.
- Existing non-bar-aligned pattern lengths are treated as `ceil(length / measure)` bars for placement limits; the stored length is normalized on the next save.

### Writer placements

- A placement may be shortened to any whole bar. Shortening clips playback at the placement edge while all melody notes remain stored.
- A placement may not extend beyond the melody's last-note bar. Resize, Adjust placement, creation from an existing pattern, and Repeat / reuse all enforce this limit and show why the limit was reached when relevant.
- Playback plays the melody once from the placement's start. If the placement is shorter than the melody, later notes are clipped. If a stored placement is longer than the melody, it keeps its full occupied span, sounds silence after the melody ends, and shows a clear silent-tail cue with no implied loop.
- Editing a melody's length never resizes existing placements; they keep the bar span they were placed with. Shorter placements clip; longer placements keep their occupied bars and display the silent tail. An over-long placement may still move without changing its span, but any resize must end within the melody's last-note bar and may shrink directly from the over-long span.
- A newly created melody starts with a one-bar placement. On the first save, that initial placement expands to the melody's full bar count when the complete span fits the section and lane. Adding a Melody lane creates a one-bar pattern and a one-bar placement; later authoring expands it through the first-save rule.
- Automatic lane repeats continue to repeat the lane's bar arrangement, not the melody content.

### Visual and interaction consistency

- The Bars and Name controls follow Studio styling, the 44px target rule, both Studio themes and compact/wide layouts.
- The note preview and labels reflect the effective melody length and existing placement windows.
- No looping indication appears for placements that reach or exceed the melody end.
- The existing Save, back/cancel, Piano Roll tools, linked reuse and Make Unique behavior remain intact.

## Compatibility and safety

- No schema migration is required: `NotePattern.name` and `lengthTicks` already exist.
- Existing placements are not deleted or rewritten. A placement longer than its melody keeps its occupied span, shows the silent tail, and does not loop; it normalizes only when the user resizes it. Move-only edits may retain the over-long span.
- Save System canonical content remains authoritative; rename and length follow the existing melody save path.
- Undo/redo groups a melody save as one edit, and linked placements update from the shared pattern.

## Verification

- Unit tests for length quantization, one-bar minimum, last-note bar limits, no-loop playback and clipping.
- Store tests for save/rename propagation, placement limits across resize, Adjust placement, creation and Repeat / reuse, and unchanged existing placement spans.
- Widget tests for Bars stepper bounds, rename flow, compact/wide layouts, large text, both themes and unchanged editing gestures.
- Runtime inspection of a populated multi-bar melody and its placements at compact and wide sizes.

## Builder decisions

The implementer may choose the exact Bars control layout, rename dialog presentation and messaging for the last-note limit, provided the rules above and the repository's accessibility and theme contracts are met.
