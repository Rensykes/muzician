# Piano Roll Latest Import Navigation Design

Date: 2026-05-24
Status: Draft written from brainstorming, ready for repo review
Scope: Piano Roll hum-import navigation and monophonic import behavior only

## Goal

Add a reliable way to return the piano roll view to the most recent hum-imported notes, while also ensuring hum recording imports only one note at a time and never creates stacked notes after quantization.

This work is intentionally narrow. It improves the post-import navigation experience and tightens hum-import behavior without redesigning the general piano roll editor, playback transport, or manual note workflows.

## Problem Statement

The current Piano Roll hum flow has two usability gaps:

1. After a hum take is imported, there is no durable UI action that lets the user jump back to the imported notes later.
2. Quantized hum notes are segmented monophonically at the audio level, but neighboring imported notes can still collapse into overlaps or same-tick stacks after snapping and quantization.

These issues make hum import feel fragile. Users can lose the imported region in a larger roll, and recorded takes can visually read like chord stacks even though the source input was monophonic humming.

## Locked Decisions

These decisions are part of this design and should not be re-opened during implementation unless a real blocker appears:

- `Jump to latest` is scoped to hum/import results only. It does not track general manual note creation.
- The control lives in the `Hum to MIDI` card, not in the playback card, top control row, or grid overlay.
- The latest-import target stays available after a successful hum import until a later non-import note-add action occurs.
- Manual selection changes, scrolling, playback, and note movement do not clear the latest-import target.
- Any later non-import note creation hides the button by clearing the remembered import target.
- A later successful hum import replaces the earlier remembered import target.
- The jump action is navigation only. It does not change `selectedColumnTick`, selected notes, or playback state.
- Hum recording must remain visually monophonic after import. If quantization would create overlaps or same-tick stacks, the earlier note is trimmed to end at the later note's start, and dropped if trimming would reduce it to zero length.

## User Experience

### 1. Jump back to the latest imported region

After a successful hum import that creates notes, the `Hum to MIDI` card shows a `Jump to latest` action.

The action should:

- remain available while the remembered latest-import target still exists
- scroll the piano roll horizontally to the start of the imported region
- leave current playback start, selection, and note focus untouched

This gives the user a clear way to return to the imported material without coupling navigation to edit selection.

### 2. Predictable visibility rules

The button should be visible only when there is a remembered latest-import target from hum/import.

The button stays visible after:

- playback
- manual scrolling
- selecting columns
- selecting notes
- moving or resizing notes

The button disappears after:

- manual cell note creation
- manual note stack creation
- any other non-import note-add action
- clearing all notes
- full piano roll reset

### 3. Monophonic hum import

Hum recording should never create visual stacks or overlapping imported notes.

If two neighboring imported hum notes would overlap after quantization:

- the earlier note is shortened so it ends exactly where the later note begins
- if the earlier note would become zero-length, it is dropped

This preserves the "one note at a time" feel of the humming workflow.

## Architecture

### 1. Remembered latest-import range in piano roll state

Add a small value object to represent the latest remembered hum-import region:

- `startTick`
- `endTickExclusive`

Store it in `PianoRollState` as a nullable field such as `latestImportedRange`.

This state belongs in the piano roll store because the feature is about editor navigation and visibility rules, not microphone session state.

### 2. Hum import owns creation of the remembered target

`HumToMidiNotifier.stopRecording()` remains the entry point that:

- segments hum frames
- quantizes them into ticks
- normalizes them into a monophonic imported sequence
- appends them into the piano roll
- stores the remembered latest-import range when notes were actually created

The remembered range must be based on the actual created imported notes after normalization, clamping, and truncation, not just the raw pre-import note list.

### 3. Navigation uses the existing piano roll scroll signal

The implementation should reuse the existing horizontal scroll signal consumed by the grid, rather than inventing a second scroll mechanism.

Tapping `Jump to latest` should emit the remembered `startTick` through the existing piano roll scroll-to-tick path.

The action should not:

- select the column
- select imported notes again
- affect transport playback state

### 4. Clearing rules live in piano roll note-add paths

Any non-import note creation path should clear `latestImportedRange`.

This includes:

- manual cell toggles when they create a new note
- `addNote`
- `addNoteStack`
- any equivalent editor-side add flow introduced during implementation

Non-add edit actions such as move, resize, selection changes, and note deletion do not clear the remembered latest-import target unless they already clear the entire piano roll state.

### 5. Hum import normalization step

Add a pure rule-layer normalization step for imported hum notes after quantization and before store append.

Responsibilities:

- sort imported notes by start tick
- enforce non-overlap between consecutive imported notes
- trim earlier notes to the next note's start tick when needed
- drop any earlier note that would become zero-length

This step should live in the hum rule layer, not inside widget code or UI stores.

## Data Flow

1. User records a hum take.
2. `HumToMidiNotifier.stopRecording()` segments stable monophonic notes.
3. Quantized imported notes are normalized into a strictly one-note-at-a-time sequence.
4. The piano roll appends the normalized imported notes.
5. If created notes exist:
   - the piano roll remembers the created import range
   - the existing scroll-to-tick signal can still be emitted immediately after import, as it is today
   - the `Hum to MIDI` card shows `Jump to latest`
6. If the user later manually adds notes, the remembered import range is cleared and the button disappears.
7. If the user taps `Jump to latest` before that happens, the grid scrolls back to the remembered region start.

## UI Rules

### Hum To MIDI card

The `Hum to MIDI` card is the only location for the new action in this scope.

Required behavior:

- show `Jump to latest` only when `latestImportedRange` exists
- place it within the Hum card, visually associated with hum feedback
- keep it secondary to the `Record` action

The button does not need to be shown in any other piano roll surface.

### Button copy

Use the label `Jump to latest`.

No additional helper copy is required unless implementation reveals discoverability issues.

## Edge Cases

- If hum import produces no created notes, no remembered import range is stored and no button is shown.
- If a later hum import succeeds, it replaces the older remembered range.
- If clamping/truncation changes the imported notes at the timeline edge, the remembered range should reflect the final created notes.
- If all earlier overlapping notes are dropped during monophonic normalization, the remembered range should still reflect the surviving imported notes.
- If the user manually adds notes after import, the remembered range is cleared even if the imported notes still exist on the roll.
- Playback availability and playback progress are out of scope except for ensuring the jump action does not disturb them.

## Testing Strategy

### Rule tests

Add coverage in `test/schema/rules/mono_pitch_rules_test.dart` for:

- overlapping or snapped imported hum notes being normalized into a strictly monophonic sequence
- earlier notes being trimmed to the next note start
- earlier notes being dropped when trimming would make them zero-length

### Store tests

Add coverage in `test/store/hum_to_midi_store_test.dart` for:

- successful hum import storing the remembered latest-import range
- a later successful hum import replacing the previous remembered range

Add coverage in `test/store/piano_roll_store_test.dart` for:

- manual non-import note creation clearing the remembered import range
- `clearNotes()` clearing the remembered import range
- reset clearing the remembered import range

### Widget tests

Add widget coverage near the Hum to MIDI / toolbar surface for:

- `Jump to latest` appearing after a successful hum import
- tapping it emitting the scroll target without changing selection
- the button disappearing after a later manual note-add action

## Out Of Scope

- General-purpose "jump to selected notes" navigation
- Automatic viewport movement for all note creation flows
- Reworking playback start-point selection
- Changing manual note editing semantics
- Expanding hum import into polyphonic detection
