# Songwriter — record-time monitoring (backing + metronome)

**Status:** design
**Date:** 2026-06-29
**Branch:** feature/songwriter-audio-daw (continued on claude/modest-shirley-cb4811)

## Problem

When recording an audio clip into a Songwriter section/lane, nothing audible
plays. The performer has no backing or click to record against. We want optional
monitoring: while the mic is capturing, play back the section's existing material
and/or a metronome so the take lands in time.

This is opt-in and primarily useful on headphones — on speakers the mic captures
the monitor output (bleed/feedback). Defaults are OFF.

## Decisions (from brainstorming)

- **Backing scope:** full section playback — chord/save voicing bed **+** drum
  lanes **+** other audio clips in the section. Loops the recording's section.
- **Controls:** two independent toggles on the recorder sheet — **Backing** and
  **Metronome** — both default OFF, plus an optional **Count-in** affordance.
- **Count-in:** optional; when on, play one bar of clicks before the mic arms,
  then start recording and monitoring together.

## Approach (selected: dedicated record-monitor loop, recorder store orchestrates)

The recorder store already owns the count-in → record → ready state machine and
is the only place that knows exactly when the mic arms. It orchestrates the
monitor so backing/metronome start in lockstep with `driver.start()` and stop
exactly on stop/cancel. The store stays **data-driven**: the caller builds a
plain-data monitor descriptor from project state and passes it in; the store
reads no project state itself (project-agnostic contract preserved).

Rejected alternatives: a separate monitor Notifier coordinated by the sheet
(looser lockstep, awkward count-in ownership); extending the main
`SongwriterPlaybackNotifier` (overloads the project transport, reshapes
whole-song playback into section-loop, regression risk).

### Data flow

```
recorder sheet (toggles: backing / metronome / count-in)
   │  builds, only if backing on:
   │    bed   = sectionAuditionBed(section, config, saves, drumPatterns)
   │    clips = songwriterSectionSchedulableClips(section, config)   ← new rule
   ▼
showSongwriterAudioPicker → SongwriterAudioRecorderSheet(monitor: …, countInMs: …)
   ▼
SongwriterAudioRecorderNotifier.start({countInMs, monitor})
   ├─ enter playAndRecord session  (clip sink)        ← only if monitor != null
   ├─ count-in clicks (playClick, accent on beat 1)   ← only if countInMs > 0
   ├─ driver.start()                                   (mic arms)
   └─ monitor loop (TickPacer, section-looped):
        • bed notes  → noteSink
        • bed drums  → drumSink
        • section clips by section-relative ms → clip sink
        • click per beat (accent on downbeat)  → metronome sink   (if metronome on)
   stop()/cancel():
   ├─ cancel loop (_version bump)
   ├─ clip sink stopAll
   └─ restore playback session
```

## Components

### 1. New pure rule — `songwriterSectionSchedulableClips`

`lib/schema/rules/songwriter_audio_rules.dart`

A section-scoped, section-relative sibling of `songwriterSchedulableAudioClips`.
Reuses `SongwriterScheduledClip`. Returns clips whose `startMs`/`endMs` are
relative to the section's local bar 0 (not the flattened song), plus the section
loop length in ms.

```dart
({int loopMs, List<SongwriterScheduledClip> clips})
songwriterSectionSchedulableClips(SongSection section, SongwriterConfig config);
```

- Iterates the section's `audio` lanes, tiles blocks (`tileLaneBlocks`), resolves
  stretched vs source asset and trim/loop exactly as the existing rule does.
- `startMs`/`endMs` computed from `block.startBar`/`clippedEnd` **without**
  `exp.globalStartBar` (section-local).
- `loopMs = section.lengthBars * measureTicks → ms`.
- Includes all section audio clips, including any already in the target lane
  (the new recording's clip does not exist yet). Documented limitation; no
  per-lane exclusion in v1.

### 2. Monitor descriptor — plain data

`lib/store/songwriter_audio_recorder_store.dart` (or a small sibling file)

```dart
class SongwriterRecordMonitor {
  final bool backing;          // play bed + section clips
  final bool metronome;        // click per beat
  final int tempo;
  final int beatTicks;         // ticksPerBeat
  final int measureTicks;      // ticksPerBeat * beatsPerBar
  final SongwriterAuditionBed bed;            // chords/saves + drums, tick-indexed (bed.loopTicks = section loop)
  final List<SongwriterScheduledClip> clips;  // section-relative
  final int loopMs;                           // section loop length in ms
}
```

Built by the caller only when `backing || metronome`. When `backing` is false,
`bed`/`clips` are empty and only the click fires.

### 3. Recorder store — orchestration

`SongwriterAudioRecorderNotifier.start({int countInMs = 0, SongwriterRecordMonitor? monitor})`

- `monitor == null` → current behaviour unchanged (no session switch, no loop).
- Count-in unified to `NotePlayer.playClick(accent: i == 0)` (today uses the
  hi-hat lane; switch to the click voice for consistency with the metronome).
- After `driver.start()`, if `monitor != null && (backing || metronome)`, spawn
  `_runMonitor(version, monitor)` (unawaited), a `TickPacer`-anchored loop
  mirroring the audition transport:
  - per tick: emit `bed.notesByTick[tick]` → noteSink, `bed.drumByTick[tick]` →
    drumSink (when `backing`); on `tick % beatTicks == 0` emit click with
    `accent: tick % measureTicks == 0` (when `metronome`);
  - section audio clips fired by section-relative ms via the clip sink, mirroring
    `fireAudio` in the main transport (start at `startMs`, stop at `endMs`),
    re-armed each loop pass;
  - `tick = (tick + 1) % loopTicks`; cancel when `_version` changes.
- `stop()`/`cancel()` already bump cancellation; add: clip sink `stopAll()` and
  restore the playback session. Loop exits on the next `_version` check.

The store reads sinks via `ref.read` (note/drum/metronome/clip providers) — same
pattern as the audition and playback stores. It still reads **no** project state.

### 4. Audio session switch (the main technical risk)

The whole monitor stack is `audioplayers` (NotePlayer + clip sink). The global
iOS session is set once to `AVAudioSessionCategory.playback`
(`song_audio_player_sink.dart`), which **forbids recording**. Simultaneous
play+record on iOS needs `playAndRecord`.

Add to the songwriter clip-sink interface:

```dart
Future<void> enterRecordSession();  // playAndRecord + mixWithOthers + defaultToSpeaker (+ allowBluetooth)
Future<void> exitRecordSession();   // restore playback + mixWithOthers
```

- No-op default sink → no-ops (tests unaffected).
- Production sink flips `AudioPlayer.global.setAudioContext(...)`. The global
  context is process-wide for audioplayers, so one flip covers the bed clicks,
  the metronome, and the clips.
- Recorder store calls `enterRecordSession()` before `driver.start()` and
  `exitRecordSession()` on stop/cancel (only when monitoring).

Android: `AudioContextAndroid` with `audioFocus: gain` generally coexists with
the `record` package; verify it does not duck/stop capture.

### 5. UI — recorder sheet

`SongwriterAudioRecorderSheet` gains, shown only in the idle/error (pre-record)
state:

- **Backing** switch, **Metronome** switch, **Count-in** switch — all default
  OFF, persisted in `settingsProvider` (new bool fields:
  `recordMonitorBacking`, `recordMonitorMetronome`, `recordCountIn`).
- A one-line hint: "Use headphones — speaker playback bleeds into the mic."
- On Record: read the three toggles; build the `SongwriterRecordMonitor` (caller
  side, in `songwriter_audio_actions.dart`, which has section + config + saves +
  drum patterns); pass `monitor` and `countInMs` (one bar when count-in on, else
  0) into `start()`.

`songwriter_audio_actions.dart::showSongwriterAudioPicker` already receives
`sectionId`/`laneId`/`startBar`/`sectionLengthBars`; it resolves the
`SongSection`, `config`, `saves`, and drum patterns to build the bed + clips.

## Error handling / edge cases

- **No headphones / bleed:** mitigated by defaults OFF + the hint. Not blocked.
- **Empty section** (no chords/drums/clips) with backing on: bed/clips empty;
  metronome still works if on; loop is harmless.
- **Same-lane existing clips:** played (no exclusion in v1).
- **Cancel during count-in:** existing `_cancelled`/status guards abort before
  `driver.start()`; ensure `exitRecordSession()` runs on that path.
- **Stop during clip-sink prepare:** mirror the audition guard — re-check
  `_version` after the awaited `prepare` before starting the loop.
- **Session restore on error:** `exitRecordSession()` in the `stop()` catch and
  `cancel()` so the global context never stays stuck on `playAndRecord`.

## Testing

Unit (pure rule):
- `songwriterSectionSchedulableClips`: section-relative startMs/endMs, loopMs,
  stretch/loop/trim parity with the flattened rule, multi-lane, empty section.

Store (fake sinks + injected/fake clock, as audition/playback tests do):
- `monitor == null` → no session switch, no sink calls beyond today; behaviour
  unchanged.
- backing on → bed notes/drums + section clips emitted on the right ticks; loops.
- metronome on → click on every beat, accent on downbeats; no bed when backing
  off.
- count-in on → N clicks before `driver.start()`; mic not armed until after.
- stop()/cancel() → loop stops, clip sink `stopAll`, `exitRecordSession` called.
- `enterRecordSession` called before `driver.start()` when monitoring.

Manual (device — sim mic/routing unreliable):
- iOS device on headphones: backing + metronome audible while recording; the
  recording captures only the voice/instrument, not the monitor.
- iOS: session restores to `playback` after recording (subsequent audition/
  project playback still works).
- Android device: capture not ducked/stopped by playback.

## Out of scope (v1)

- Per-lane / per-clip mute of the backing.
- Live input monitoring (hearing the mic through the app).
- Latency compensation / aligning the captured take to the grid.
- Whole-song play-through (monitor loops the single section only).
