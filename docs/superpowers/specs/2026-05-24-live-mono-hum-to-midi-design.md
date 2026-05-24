# Live Mono Hum-to-MIDI Design

Date: 2026-05-24
Status: Draft approved in chat, written for repo review
Scope: First implementation spec for live mono humming capture into the piano roll

## Goal

Add a mobile-only feature that lets the user hum a monophonic melody into the microphone, see live note feedback while recording, and append the finalized melody to the piano roll as editable MIDI-style notes.

The first version should feel reliable and musical rather than expressive. Clean note segmentation is more important than preserving slides or vibrato.

## Locked Decisions

These product decisions were confirmed before writing this spec:

- Recording is live, not offline-only.
- Timing is captured live, then lightly quantized after stop.
- Pitch behavior is stable-note mode, not expressive split mode.
- Platform scope is mobile only for v1: Android and iOS.
- Architecture should use a shared detector engine, with piano roll as the first consumer.
- Imported notes append to existing piano roll content.
- Chords, polyphony, and pitch bends are out of scope for v1.

## User Experience

### Entry Point

The feature lives in the piano roll first. The piano roll gets a `Hum to MIDI` record control and a compact live monitor.

### Start Behavior

When the user starts recording:

- Request microphone permission if needed.
- Determine the insertion anchor:
  - use `selectedColumnTick` when present
  - otherwise use the first measure boundary after the latest existing note end tick
  - otherwise fall back to tick `0`
- Start microphone capture and live pitch analysis immediately.

### While Recording

The UI shows:

- recording timer
- current detected note name
- confidence or stability indicator
- current session state such as `Listening`, `Stable`, `Silence`, or `No pitch`

The detector does not emit a new piano roll note for every noisy frame. It tracks pitch continuously and only opens or closes note segments when the pitch is stable enough.

### Stop Behavior

When the user stops recording:

- finalize the open note if needed
- filter weak or too-short note segments
- convert timestamps to piano roll ticks
- apply light quantization
- ensure the piano roll has enough measure space
- append the new notes in one store update

If the take contains no stable notes, no notes are added and the user gets a small explanatory message instead of junk MIDI.

## Architecture

### 1. Shared Mic Session Layer

Add `lib/utils/mic_pitch_session.dart`.

Responsibilities:

- start and stop mobile microphone capture
- read live PCM16 mono audio frames from the recorder plugin
- run frame-level pitch estimation
- emit a stream of `PitchFrame` values to the store

Implementation choice:

- use the Flutter `record` package in stream mode with `pcm16bits`
- mobile only in v1
- initial capture format: mono PCM16 at 16 kHz

Rationale:

- `record` already supports live PCM16 stream capture on Android and iOS
- 16 kHz mono is sufficient for humming fundamentals and keeps CPU usage modest
- the mic session remains reusable for future fretboard or piano consumers

### 2. Shared Music Rules Layer

Add `lib/schema/rules/mono_pitch_rules.dart`.

This file contains pure Dart logic for:

- mapping detected frequency to nearest MIDI note
- confidence filtering
- silence detection
- stable-note segmentation
- short-gap merge rules
- minimum note duration rules
- timestamp-to-tick conversion
- light post-stop quantization

This is the most important test surface and should stay UI-free and platform-free.

### 3. Session Model and Store

Add:

- `lib/models/hum_to_midi.dart`
- `lib/store/hum_to_midi_store.dart`

The store owns transient recording state rather than mixing it into `pianoRollProvider`.

Suggested model shapes:

- `HumToMidiStatus`
  - `idle`
  - `requestingPermission`
  - `recording`
  - `processing`
  - `completed`
  - `error`
- `PitchFrame`
  - `timestampMs`
  - `frequencyHz`
  - `midiNote`
  - `centsOffset`
  - `amplitude`
  - `confidence`
  - `isSilence`
- `DetectedMonoNote`
  - `startMs`
  - `endMs`
  - `midiNote`
  - `confidence`

Store responsibilities:

- orchestrate permission, start, stop, and cancel
- expose the current detected note and session status to UI
- collect raw pitch frames during the take
- finalize the detected note list on stop
- hand the finalized note batch to the piano roll store

### 4. Piano Roll Integration

The piano roll remains the source of truth for note editing.

Required integration changes:

- add a piano roll UI control for start and stop recording
- add a compact live monitor in the piano roll UI
- add a piano roll notifier method for batch append import
- add a helper to extend `totalMeasures` when the imported take exceeds the current timeline, up to the existing maximum

The hum store should not mutate raw piano roll state directly. It should finalize a take and pass plain note data into a dedicated piano roll importer method.

## Detection and Segmentation Rules

### Pitch Estimation

The first implementation should use a YIN-style monophonic pitch detector in Dart over short PCM windows. The output of each analysis frame is a `PitchFrame`.

Initial operating range:

- minimum frequency: 80 Hz
- maximum frequency: 1000 Hz

This range covers typical humming and light singing use without wasting work on irrelevant low or high frequencies.

### Stability Rules

The detector should prefer one clean held note over many jittery note changes.

Initial thresholds should be configurable constants in `mono_pitch_rules.dart`:

- note onset requires the same nearest MIDI note to remain stable for about 120 ms
- note change requires a different stable MIDI note for about 80 ms
- note end on silence requires about 120 ms of silence
- notes shorter than about 120 ms are discarded
- short silence gaps between the same MIDI note should be merged

These are starting defaults, not fixed UX promises. The code should keep them centralized so we can tune them after device testing.

### Vibrato and Small Wobble

Very small pitch fluctuation should not split a note. The segmentation rule should treat nearby frames as the same note when they still map to the same nearest MIDI pitch and meet confidence requirements.

## Timing and Quantization

### Time Base

Detected notes are recorded in milliseconds during capture. The conversion to piano roll timing happens only after stop.

### Tick Conversion

Convert note timestamps into float tick positions using the current:

- tempo
- time signature
- insertion anchor tick

### Light Quantization

The first version should quantize conservatively:

1. Convert raw note boundaries to float ticks.
2. Round to the nearest whole tick so the data fits the piano roll model.
3. If a boundary is within the limit in step 4 from the current `snapTicks` grid, move it to that grid line.
4. Do not move a boundary more than `max(1, snapTicks / 2)` ticks just to satisfy quantization.
5. Preserve note order and enforce a minimum duration of one tick.

This keeps the result musical without forcing an obviously human take into overly rigid timing.

## Data Flow

`record` mic stream -> `MicPitchSession` -> `PitchFrame` stream -> `hum_to_midi_store` -> `mono_pitch_rules` segmentation and finalize -> piano roll batch append

## Failure and Edge Cases

The first version must handle these safely:

- microphone permission denied
- recorder start failure
- microphone interruption during recording
- no stable pitch detected
- take longer than current piano roll measure count
- take longer than the piano roll maximum supported measure count

Expected behavior:

- denied or failed permission leaves the session in `error` with a clear message
- interruption stops or cancels safely without corrupting piano roll state
- empty or unstable takes add no notes
- long takes auto-expand the piano roll up to its current maximum limits
- notes beyond the hard maximum timeline are clamped, and the UI should surface that truncation

## Persistence

No save-system changes are required for v1.

The imported notes become ordinary piano roll notes once committed. We do not need to persist raw microphone frames, take metadata, or detector settings in the first version.

## Testing Strategy

### Unit Tests

Add focused tests for:

- frequency to MIDI conversion
- confidence and silence filtering
- stable-note onset and release behavior
- pitch-change segmentation
- gap merge behavior
- minimum-duration filtering
- timestamp-to-tick conversion
- light quantization limits

Suggested files:

- `test/schema/rules/mono_pitch_rules_test.dart`
- `test/store/hum_to_midi_store_test.dart`
- `test/store/piano_roll_store_test.dart` for batch import behavior

### Integration and Device Testing

Manual device verification is still needed for:

- permission flow on Android and iOS
- latency feel during live humming
- stability across quiet humming, louder humming, and vibrato
- behavior when pitch is noisy or weak

## Out of Scope

The first version does not include:

- polyphonic detection
- chord extraction
- pitch bend automation
- desktop or web capture
- background recording
- retrospective audio file import
- editable detector settings UI
- save metadata for takes

## Implementation Notes

The implementation should preserve existing repo boundaries:

- put musical conversion and segmentation in `lib/schema/rules/`
- keep transient mic session state in a dedicated Riverpod store
- keep `PianoRollState` focused on piano roll data, not mic lifecycle state
- append finalized notes through a single piano roll batch operation

## Open Assumptions

This spec assumes:

- the piano roll may auto-expand measures during import when needed
- the first insertion anchor should prefer the selected column, otherwise append after the latest content
- live UI preview is informational and does not create persistent notes until stop

If either insertion-anchor behavior or measure auto-expansion feels wrong during implementation, that should be revisited before shipping.
