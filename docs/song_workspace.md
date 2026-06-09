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

- **Note clips** open a piano-roll editor mounting the full `PianoRollScreenV2` shell (stack builder, detection panel, hum recorder, tools, snap, pitch range, transport). The scale picker and save/load panels are hidden — scale is inherited from the song scale (see below), and load would smash the host pattern length. The editor uses an isolated `ProviderContainer` so edits never leak into the standalone `Roll` tab.
- **Drum clips** open a step sequencer with 8 lanes (kick, snare, hi-hats, clap, toms, crash).

### Song scale

The song carries an optional scale (`SongProjectConfig.scaleRoot` + `scaleName`).
- Set or clear it from the chip in the Song header.
- When set, every note-pattern editor seeds its `highlightedNotes` from the song scale; the per-pattern `highlightedNotes` field is preserved on save as a fallback for when the song scale is cleared later.
- Applying a song scale that conflicts with notes already placed in any pattern prompts a confirmation; on confirm the conflicting notes are removed from every pattern.
- When no song scale is set, the editor falls back to each pattern's own `highlightedNotes`.

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

### Session auto-save

In addition to the named save browser, the active Song workspace is
auto-persisted to a single `SharedPreferences` slot (`@muzician/song_session/v1`)
~500 ms after every mutation and restored on the next app launch.  This slot is
overwritten — not appended — so it is a "last session" snapshot, not a save
history.

Tap the **New Song** button in the Song header to wipe the current session and
start fresh.  A confirmation dialog protects against accidental overwrites; on
confirm, the persisted blob is removed, the project is reset to its default
empty state, and audio assets referenced only by the prior session are
reconciled out of `appDocs/song_audio/`.

## Audio Playback Sink

Audio clips on audio tracks are routed through `SongAudioClipSink`.  The
production implementation (`AudioPlayersClipSink`) holds one `AudioPlayer` per
asset id and is configured for simultaneous playback:

- On construction it installs a global `AudioContext` with the iOS
  `playback` category and the `mixWithOthers` option so internal players do
  not preempt each other when their sessions activate.
- `startPlayback` calls `audioSink.prepare(...)` once before the tick loop.
  This binds every scheduled clip's file source via `setSource`, paused.
  The tick loop's parallel `startClip` calls then only seek + resume — no
  concurrent `setSource` races where two clips fired at the same tick could
  leave one player silent.
- Sources stay loaded across clips via `ReleaseMode.stop` so re-triggering a
  clip is just a seek.

## Audio Tracks (v1.1)

Audio tracks host clips from microphone recordings or imported files.

- **Record**: tap an empty audio lane → `Record audio` → 1-measure count-in (metronome hi-hat) → song playback starts in the background while the mic captures → tap `Stop` and the clip is committed to the track immediately. There is no review step; remove the clip from the timeline if you do not want to keep the take. Tap `Cancel` during count-in or recording to abort without producing a clip.
- **Import**: tap-lane → `Import audio file` → choose WAV, MP3, or M4A (max 50 MB) via the system file picker.
- **Storage**: audio files live in `appDocs/song_audio/<assetId>.<ext>`. Save files reference assets by id; cross-device portability is not supported in v1.
- **Tempo**: clip length in ticks tracks the project tempo; the real audio duration never changes.
- **Limits**: no trim, no per-clip volume / pan / fade, no time-stretch, no live monitoring. Mute/solo applies at the track level only.
- **Web**: recording is disabled; import works via the standard file picker but files do not persist across reloads.
- **Broken clips**: if a referenced file is missing on load, the clip renders with a red diagonal stripe and stays silent during playback.
- **Auto-mute**: the target audio track is muted while you record so its prior clips do not bleed back through the mic.

## Project lock

When a project is selected, the Song workspace inherits its tempo and time
signature from `ProjectConfig` and the scale chip is disabled. Change the
values through the project config sheet from the project chip in the header.
Dump and "no project" leave controls free.

## Limitations (v1)

- No clip resize or time-stretching
- Same-track clip overlap not allowed
- No volume, pan, or mixer controls
- No undo/redo
