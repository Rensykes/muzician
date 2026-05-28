# Song Workspace

The `Song` tab provides a pattern-based clip arranger with note and drum tracks.

## Overview

- **Tracks**: Note tracks and drum tracks, each with mute, solo, rename, duplicate, and delete.
- **Clips**: Instances of reusable patterns placed on a track timeline.
- **Patterns**: Note patterns and drum patterns, shared across multiple clip instances.

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

## Limitations (v1)

- No clip resize or time-stretching
- Same-track clip overlap not allowed
- No volume, pan, or mixer controls
- No undo/redo
