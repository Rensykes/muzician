# Songwriter Audio Clip Audition — Design

**Date:** 2026-06-27
**Branch:** `claude/modest-shirley-cb4811` (Songwriter audio sampler initiative)
**Status:** Approved design — ready for implementation plan

## Problem

The Songwriter audio lane lets you record/place a clip, but there is no way to
*audition* a recording in context. The only way to hear it with the rest of the
arrangement is the project-wide transport, which plays the whole song. There is
no focused "hear this recording by itself" or "hear it over just this section"
control.

The drum lane already solves the equivalent problem: the drum editor's **Backing**
toggle loops the section's harmony bed under the pattern so you can audition the
pattern alone or with backing. This feature brings the same affordance to audio
clips.

## Goal

Add a transport row to the **Audio Clip** sheet (`SongwriterAudioClipBody`) that
auditions the clip's recording two ways:

- **Alone** — the recording only, looping continuously until Stop.
- **With section** — the recording over a looping bed of the section's *other*
  lanes (harmony + save voicings + drum patterns), excluding this clip. Both the
  bed and the recording loop until Stop.

Mirrors the drum lane's audition feel and is isolated from the main project
transport.

## Non-goals (YAGNI)

- No play/solo button on the audio lane row — controls live in the clip sheet
  only.
- Other **audio** clips in the section are not part of the bed; the bed is
  harmony + saves + drums only.
- No per-mode volume / pan / fade.
- No new project-level playback behavior — the main transport is untouched.

## Approaches considered

| | Approach | Verdict |
|---|---|---|
| **A** | Dedicated looping audition transport (clone of `DrumPatternPlaybackNotifier`) + a pure `sectionAuditionBed` rule, driving the existing note/drum/audio sinks. | **Chosen** — parity with the drum lane, isolated from the main transport, fully testable via injected sinks. |
| B | Add an "audition scope/solo" mode to the main `songwriterPlaybackProvider`. | Rejected — pollutes the project transport, no clean single-section loop, regression risk. |
| C | Audio-only: alone = sink play; "with section" = start the main transport from this section. | Rejected — not a true section-loop bed; fails the "full section" intent. |

## Architecture (Approach A)

Four pieces, each independently testable.

### 1. Pure rule: `sectionAuditionBed`

Location: `lib/schema/rules/songwriter_playback_rules.dart` (next to
`sectionHarmonyLoop`).

```
({int loopTicks, Map<int, List<int>> notesByTick, Map<int, List<DrumLaneId>> drumByTick})
sectionAuditionBed(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves, {
  String? excludeAudioClipId,
})
```

- `loopTicks = section.lengthBars * measureTicks`.
- `notesByTick` — harmony + save voicing stabs per tick. Reuse the exact logic in
  `sectionHarmonyLoop` (harmony lanes → `chordMidiNotes`, save lanes →
  `snapshotMidiNotes`, tiled via `tileLaneBlocks`, clipped to the section).
- `drumByTick` — drum-lane hits per tick. Reuse the drum-flattening already used
  by `flattenPlaybackEvents` for drum lanes: for each drum block, resolve its
  `DrumPattern` and tile the lane hits across the block's bar span, clipped to the
  section.
- Audio lanes excluded entirely (the recording is the foreground). The
  `excludeAudioClipId` parameter is reserved for the (audio-lane) case and is a
  no-op for the bed today, but keeps the signature explicit and future-proof.
- Returns empty `notesByTick`/`drumByTick` when the section has no backing.

`sectionHarmonyLoop` stays as-is (still used by the drum editor). The shared
harmony/save tiling can be factored into a private helper both call, to avoid
duplication.

### 2. Audition transport: `SongwriterAudioAuditionNotifier`

Location: new `lib/store/songwriter_audio_audition_store.dart`. Modeled 1:1 on
`DrumPatternPlaybackNotifier` (`drum_pattern_playback_store.dart`): a `_version`
counter to cancel the loop, a `TickPacer` to anchor ticks to the wall clock, and
all audio routed through injected sink providers so tests capture events without
real audio.

State:

```
enum SongwriterAudioAuditionMode { alone, withSection }
enum SongwriterAudioAuditionStatus { idle, playing }
class SongwriterAudioAuditionState {
  final SongwriterAudioAuditionStatus status;
  final SongwriterAudioAuditionMode mode;
  final int? currentTick; // null when idle; drives no UI today but mirrors drum store
}
```

API:

```
Future<void> start({
  required AudioAsset asset,
  required int trimStartMs,
  required SongwriterAudioAuditionMode mode,
  required int tempo,
  ({int loopTicks, Map<int,List<int>> notesByTick, Map<int,List<DrumLaneId>> drumByTick})? bed,
});
void stop();
```

Behavior:

- **Alone:** `audioSink.prepare([asset])` → `startClip(asset, offsetMs: trimStartMs,
  loop: true)`. No bed loop required; the sink loops the recording. `stop()` →
  `audioSink.stopAll()`.
- **With section:** start the recording exactly as above (`loop: true`), *and* run
  a `TickPacer` loop over `bed.loopTicks`:
  - fire `bed.notesByTick[tick]` via `songwriterNoteSinkProvider`,
  - fire `bed.drumByTick[tick]` via `drumPatternPlaybackSinkProvider` (volume `0.8`),
  - wrap at `loopTicks`; the recording continues looping via the sink (no re-arm
    needed because `loop: true`).
  - `stop()` → cancel the loop (version bump) + `audioSink.stopAll()`.
- No-op `start` when already playing or when `mode == withSection` and the bed is
  empty.

Sinks reused (all already injectable):
`songwriterAudioClipSinkProvider`, `songwriterNoteSinkProvider`,
`drumPatternPlaybackSinkProvider`.

Provider: `songwriterAudioAuditionProvider =
NotifierProvider<SongwriterAudioAuditionNotifier, SongwriterAudioAuditionState>`.

### 3. UI: transport row in `SongwriterAudioClipBody`

`lib/features/songwriter/songwriter_audio_clip_sheet.dart`. Add a row below the
existing span controls:

- A **Play / Stop** `IconButton` toggling the audition (reads
  `songwriterAudioAuditionProvider` status).
- A two-chip **mode toggle** (`Alone` / `With section`) styled like the drum
  editor's Backing `ChoiceChip`. `With section` is **disabled** when
  `sectionAuditionBed(...)` returns empty maps. Changing mode while playing
  restarts the audition in the new mode.
- On Play: read the clip's `asset` + `trimStartMs`, compute the bed via
  `sectionAuditionBed(section, config, saves, excludeAudioClipId: clipId)`, and
  call `start(...)`.
- Stop the audition when the sheet closes — call `stop()` in `dispose()` (convert
  `SongwriterAudioClipBody` to a `ConsumerStatefulWidget`, or wrap the transport
  row in a small stateful widget), mirroring `drum_machine_editor.dart`'s
  `dispose`/`deactivate` stop.

### 4. Wiring

The production audio sink is already wired for the songwriter transport
(`songwriterAudioClipSinkProvider` overridden to
`productionSongwriterAudioClipSinkProvider` in `main.dart`). The audition store
reads the same provider, so no new `main.dart` wiring is required beyond
confirming the override scope covers the audition store. Verify during
implementation.

## Testing

- **`sectionAuditionBed` (pure):** harmony+save stabs land on the right ticks;
  drum hits tiled and clipped correctly; audio lanes excluded; empty section →
  empty maps. New `test/schema/rules/songwriter_audition_bed_test.dart`.
- **`SongwriterAudioAuditionNotifier` (store):** override the three sink providers
  to capture events; assert Alone fires only `startClip` (no note/drum events),
  With-section fires the expected note + drum events per loop and starts the clip;
  `stop()` calls `stopAll` and halts the loop. New
  `test/store/songwriter_audio_audition_store_test.dart`. Mirror the existing
  `songwriter_audio_playback_test.dart` and `drum_pattern_playback` test setup.
- **Widget (optional):** the clip sheet shows the transport row; `With section`
  disabled when the section is empty.

## Risks / notes

- **Loop phrasing:** as in the drum audition, the recording and the bed loop
  independently; they only line up at the wrap when the recording length divides
  the section loop. Accepted — same trade-off the drum editor documents.
- **Sink contention with the main transport:** the audition and the project
  transport share `AudioPlayersClipSink`. Auditioning and project playback are
  mutually exclusive: **starting an audition stops the main transport**
  (`songwriterPlaybackProvider.notifier.stopPlayback()`), and **starting project
  playback stops any running audition** (`songwriterAudioAuditionProvider.notifier
  .stop()`, called at the top of `SongwriterPlaybackNotifier.startPlayback`). This
  keeps one owner of the audio sink at a time.
