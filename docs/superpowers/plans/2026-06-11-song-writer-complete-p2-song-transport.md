# Phase 2 — Song Transport Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Loop region, practice tempo, auto-follow, count-in + metronome, and per-track volume on the Song transport.

**Architecture:** `SongPlaybackState` gains loop/multiplier/count-in fields; `SongPlaybackNotifier`'s tick loop wraps at the loop boundary and fires a metronome click per beat. `SongTrack` gains a `volume` field that `buildPlaybackEvents` carries through to per-volume sink calls. UI: transport strip chips (tempo multiplier, metronome, count-in), ruler drag = loop region, timeline auto-follows the playhead, track menu gains a volume slider.

**Tech Stack:** Flutter, Riverpod, flutter_test. Spec §3 of `docs/superpowers/specs/2026-06-11-song-writer-complete-design.md`.

**Verified facts:**
- Transport: `lib/store/song_playback_store.dart` (`SongPlaybackNotifier.startPlayback` tick loop ~L138-204, `seek`, `stopPlayback`); state in `lib/models/song_playback.dart`.
- Events: `lib/schema/rules/song_playback_rules.dart` `buildPlaybackEvents` — tickMap of midi/drum sets; `SongPlaybackEvent {tick, midiNotes, drumLanes}`.
- `SongTrack` (`lib/models/song_project.dart:78`): no volume field yet. Store actions in `lib/store/song_project_store.dart` (`renameTrack` L171, `toggleMute` L187 patterns).
- Audio: `schedulableAudioClips` (`song_audio_rules.dart:58`) → `ScheduledAudioClip`; sink interface `SongAudioClipSink.startClip({asset, offsetMs})`; production `AudioPlayersClipSink` in `lib/store/song_audio_player_sink.dart`.
- Transport UI: `_SongTransportStrip` (`lib/features/song/song_screen.dart:307`) wraps shared `TransportStrip` (`lib/ui/transport_strip.dart:41`).
- Ruler: `_MeasureRuler` (`song_arranger_timeline.dart:145`) — `GestureDetector.onTapDown → onSeekToDx`.
- Metronome click: `NotePlayer.instance.playClick(accent:)`; settings flag `settingsProvider.metronomeEnabled`.
- Tick = 16th: `beatTicks = beatUnit == 8 ? 2 : 4`.

---

### Task 1: `SongTrack.volume` + store action

**Files:** `lib/models/song_project.dart`, `lib/store/song_project_store.dart`, `test/store/song_project_store_test.dart`

- [ ] Test: `setTrackVolume clamps and persists` — create default project, add track, `setTrackVolume(id, 0.5)` → track.volume 0.5; `setTrackVolume(id, 1.4)` → 1.0; `fromJson` of a track JSON without `volume` → 1.0.
- [ ] Run (fail) → implement: `volume` field (default 1.0) + copyWith + toJson + fromJson (`(json['volume'] as num?)?.toDouble() ?? 1.0`); store action:

```dart
  void setTrackVolume(String trackId, double volume) {
    final v = volume.clamp(0.0, 1.0);
    state = state.copyWith(
      tracks: state.tracks
          .map((t) => t.id == trackId ? t.copyWith(volume: v) : t)
          .toList(),
    );
    _scheduleSave();
  }
```

(match the existing mutation/save pattern in `toggleMute`).
- [ ] Run (pass) → commit `feat(song): per-track volume field + setTrackVolume`.

### Task 2: volume-aware playback events

**Files:** `lib/models/song_playback.dart`, `lib/schema/rules/song_playback_rules.dart`, `lib/schema/rules/song_audio_rules.dart`, `test/schema/rules/song_playback_rules_test.dart`

- [ ] Test: two note tracks volumes 1.0 / 0.5 with same-tick notes → event exposes `noteGroups` `[ (volume: 1.0, midiNotes: [..]), (volume: 0.5, midiNotes: [..]) ]`; drum equivalent; default volume tracks behave as one group.
- [ ] Implement: `SongPlaybackEvent` gains

```dart
  final List<({double volume, List<int> midiNotes})> noteGroups;
  final List<({double volume, List<DrumLaneId> drumLanes})> drumGroups;
```

  keeping `midiNotes`/`drumLanes` as flattened getters for back-compat with existing tests/UI. `buildPlaybackEvents` buckets per (tick, trackVolume). `ScheduledAudioClip` gains `volume` (from its track).
- [ ] Run all rule tests (pass) → commit `feat(song): volume-aware playback events`.

### Task 3: notifier honors volumes + audio sink volume

**Files:** `lib/store/song_playback_store.dart`, `lib/store/song_audio_player_sink.dart`, `test/store/song_playback_store_test.dart`

- [ ] Test: override sinks, track volume 0.5 → `noteSink` called with volume 0.5.
- [ ] Implement: tick loop fires one sink call per group (`noteSink(group.midiNotes, 0.8 * group.volume)`); `SongAudioClipSink.startClip` gains `double volume` param (no-op sink + `AudioPlayersClipSink` → `player.setVolume(volume)` before resume; callers pass `clip.volume`).
- [ ] Run (pass) → commit `feat(song): playback sinks honor per-track volume`.

### Task 4: loop region + practice tempo + count-in + metronome in transport

**Files:** `lib/models/song_playback.dart`, `lib/store/song_playback_store.dart`, `test/store/song_playback_store_test.dart`

State additions (all preserved by `copyWith`):

```dart
  final int? loopStartTick;
  final int? loopEndTickExclusive;   // half-open; both null = no loop
  final double tempoMultiplier;      // 0.5 | 0.75 | 1.0, default 1.0
  final bool countInEnabled;         // default false
```

Notifier methods: `setLoopRegion(int startTick, int endTickExclusive)` (normalized/clamped; ignores empty), `clearLoopRegion()`, `cycleTempoMultiplier()` (1.0 → 0.75 → 0.5 → 1.0), `toggleCountIn()`.

`startPlayback` changes:
- `tickDuration = base ~/ multiplier` → `Duration(microseconds: (base.inMicroseconds / m).round())`.
- Optional `tickDurationOverride` param (test hook, mirrors songwriter transport).
- Count-in: before the main loop, if `countInEnabled && metronomeOn`, play one measure of clicks (`beatsPerMeasure` clicks at `beatTicks * tickDuration` intervals, first accented) while `status == playing` and `currentTick` stays at start.
- Metronome: inside the tick loop, `if (metronomeOn && (tick % beatTicks) == 0) playClick(accent: tick % measureTicks == 0)` via an injectable `songMetronomeSinkProvider` (same shape as `songwriterMetronomeSinkProvider`).
- Loop wrap: restructure the unified loop (merge the empty/non-empty event branches — they only differ by event firing):

```dart
      var tick = start;
      var eventIndex = lowerBound(rangeEvents, tick);
      while (tick < end && _playbackVersion == version) {
        ... delay, state update, metronome, events, audio ...
        tick++;
        final loopEnd = state.loopEndTickExclusive;
        final loopStart = state.loopStartTick;
        if (loopEnd != null && loopStart != null && tick == loopEnd) {
          tick = loopStart;
          eventIndex = indexOfFirstEventAtOrAfter(rangeEvents, tick);
          await audioSink.stopAll();
          scheduled
            ..clear()
            ..addAll(allScheduled.where((c) => c.startMs >= audioTickToMs(tick, ...)));
          pendingStops.clear();
        }
      }
```

  (`allScheduled` = immutable snapshot taken before the loop; audio clips overlapping the wrap restart from their offset — acceptable v1: only clips starting at/after loopStart are re-armed.)

- [ ] Tests (with `tickDurationOverride: Duration.zero`): loop wraps (events at tick 0 fire twice when loop 0..N runs two passes — stop via `stopPlayback` after counting, or run with a loop region then `clearLoopRegion` mid-run via sink callback); tempo multiplier changes tick duration (assert on state field + duration maths helper); count-in fires `beatsPerMeasure` clicks before tick 0 event.
- [ ] Commit `feat(song): loop region, practice tempo, count-in, metronome in transport`.

### Task 5: transport + ruler UI

**Files:** `lib/features/song/song_screen.dart`, `lib/ui/transport_strip.dart`, `lib/features/song/song_arranger_timeline.dart`, widget tests `test/features/song/song_transport_controls_test.dart`

- [ ] `TransportStrip` gains optional `extras: List<Widget>` slot rendered after the readout.
- [ ] `_SongTransportStrip` passes chips: tempo multiplier (`1×`/`¾×`/`½×`, key `tempoMultiplierChip`, cycles), metronome toggle (key `songMetronomeToggle`, icon `Icons.music_note`/accent color when on — writes `settingsProvider`), count-in toggle (key `countInToggle`), loop indicator chip (visible when loop set, key `loopChip`, tap clears).
- [ ] Ruler: horizontal drag on `_MeasureRuler` selects a measure-snapped range → `setLoopRegion`; painted as translucent accent band in `_RulerPainter`; plain tap still seeks (drag distance < half a measure ⇒ treat as tap/seek).
- [ ] Widget tests: tapping multiplier chip cycles state; loop chip appears when region set and clears on tap.
- [ ] Commit `feat(song): transport controls — tempo multiplier, metronome, count-in, loop UI`.

### Task 6: auto-follow playhead

**Files:** `lib/features/song/song_arranger_timeline.dart`

- [ ] Timeline listens to `songPlaybackProvider.currentTick` while playing; if the playhead x (tick → dx) leaves the visible horizontal window (with 80 px margin), `jumpTo`/`animateTo` keeps it at ~30% of viewport. A `NotificationListener<UserScrollNotification>` sets a `_userScrubbing` flag that pauses follow until playback restarts.
- [ ] Manual sim verification (scroll math is gesture-driven; no widget test).
- [ ] Commit `feat(song): timeline auto-follows playhead during playback`.

### Task 7: track volume slider

**Files:** `lib/features/song/song_track_header.dart`, widget test `test/features/song/song_track_volume_test.dart`

- [ ] Track header menu (where rename/mute/solo live) gains a `Slider` row (key `trackVolumeSlider_<id>`) bound to `track.volume` → `setTrackVolume`.
- [ ] Widget test: dragging slider updates store value.
- [ ] Commit `feat(song): per-track volume slider`.

### Task 8: phase gate

- [ ] `flutter analyze` clean; full `flutter test` green.
- [ ] serve-sim: loop region drag + wrap audible/visible, tempo chip slows playhead, metronome clicks, volume slider lowers a track, auto-follow scrolls.
- [ ] Update `docs/song_workspace.md` Playback section.
- [ ] Commit docs.
