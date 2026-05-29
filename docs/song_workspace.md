# Song Workspace

The `Song` tab provides a pattern-based clip arranger with note and drum tracks.

## Overview

- **Tracks**: Note tracks, drum tracks, and audio tracks, each with mute, solo, rename, duplicate, and delete.
- **Clips**: Instances of reusable patterns (note/drum) or unique audio buffers placed on a track timeline.
- **Patterns**: Note patterns and drum patterns are shared across multiple clip instances; audio clip patterns are 1:1 with their underlying file.

## Pattern Reuse

- Editing a shared pattern updates every clip instance that references it.
- **Make Unique** clones a pattern and relinks only the active clip — other clips continue referencing the original.

## Editing

- **Note clips** open a piano-roll editor with the full note grid. This editor is isolated from the standalone `Roll` tab.
- **Drum clips** open a step sequencer with 8 lanes (kick, snare, hi-hats, clap, toms, crash).

## Import

Create clips from existing saves:
- `Piano Roll` save → exact note timings
- `Piano` save → stacked chord at tick 0
- `Fretboard` save → stacked chord at tick 0

New empty patterns default to 1 measure.

## Playback

Song-level transport plays all audible tracks. Muted tracks are silent unless soloed.
Solo takes priority over mute — if any track is soloed, only soloed tracks play.

## Save / Load

Song projects save as `SongProjectSnapshot` through the shared save browser.
A saved project contains:
- Global config (tempo, time signature, measures)
- All tracks, clips, note patterns, and drum patterns

## Audio Tracks (v1.1)

Audio tracks host clips from microphone recordings or imported files.

- **Record**: tap an empty audio lane → `Record audio` → 1-measure count-in (metronome hi-hat) → mic captures while the song plays → preview waveform → `Confirm` / `Retry` / `Discard`.
- **Import**: tap-lane → `Import audio file` → choose WAV, MP3, or M4A (max 50 MB) via the system file picker.
- **Storage**: audio files live in `appDocs/song_audio/<assetId>.<ext>`. Save files reference assets by id; cross-device portability is not supported in v1.
- **Tempo**: clip length in ticks tracks the project tempo; the real audio duration never changes.
- **Limits**: no trim, no per-clip volume / pan / fade, no time-stretch, no live monitoring. Mute/solo applies at the track level only.
- **Web**: recording is disabled; import works via the standard file picker but files do not persist across reloads.
- **Broken clips**: if a referenced file is missing on load, the clip renders with a red diagonal stripe and stays silent during playback.
- **Auto-mute**: the target audio track is muted while you record so its prior clips do not bleed back through the mic.

## Limitations (v1)

- No clip resize or time-stretching
- Same-track clip overlap not allowed
- No volume, pan, or mixer controls
- No undo/redo
