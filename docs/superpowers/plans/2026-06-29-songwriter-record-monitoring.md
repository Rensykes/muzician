# Songwriter Record-Time Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While recording an audio clip into a Songwriter section, optionally play the section's backing (chord/save bed + drums + other audio clips, looped) and/or a metronome, with an optional count-in.

**Architecture:** The recorder store (`SongwriterAudioRecorderNotifier`) orchestrates a section-looped monitor loop (`TickPacer`) in lockstep with the mic. The store stays data-driven: the recorder sheet's caller builds a plain-data `SongwriterRecordMonitor` (bed + section-relative clips + tick fields) from project state and passes it into `start()`. A new pure rule produces section-relative audio-clip schedules. The Song feature already plays back during record without an audio-session flip (shipped precedent), so the iOS `playAndRecord` switch is a verification-gated follow-up (Task 6), not core.

**Tech Stack:** Dart / Flutter, Riverpod `Notifier`, `audioplayers` (playback) + `record` (capture), `package:flutter_test`.

---

## File Structure

- `lib/schema/rules/songwriter_audio_rules.dart` — **modify**: add pure `songwriterSectionSchedulableClips`.
- `test/schema/rules/songwriter_audio_rules_test.dart` — **modify**: tests for the new rule.
- `lib/models/save_system.dart` — **modify**: add 3 persisted bool fields to `AppSettings`.
- `lib/store/settings_store.dart` — **modify**: add 3 setters.
- `test/models/app_settings_test.dart` — **create** (or extend if present): json round-trip for the new fields.
- `lib/store/songwriter_audio_recorder_store.dart` — **modify**: `SongwriterRecordMonitor` struct + monitor loop + count-in unify + teardown.
- `test/store/songwriter_audio_recorder_store_test.dart` — **modify**: monitor-loop tests.
- `lib/features/songwriter/songwriter_audio_recorder_sheet.dart` — **modify**: toggles (Backing / Metronome / Count-in) + hint; assemble final monitor.
- `lib/features/songwriter/songwriter_audio_actions.dart` — **modify**: build the monitor template + count-in params; pass to the sheet.

---

## Task 1: Section-relative audio-clip scheduling rule

**Files:**
- Modify: `lib/schema/rules/songwriter_audio_rules.dart`
- Test: `test/schema/rules/songwriter_audio_rules_test.dart`

Context: `songwriterSchedulableAudioClips` (same file) flattens clips to **absolute** ms across all section repeats using `exp.globalStartBar`. The monitor loops a single section, so it needs **section-local** ms (based at the section's bar 0) plus the section loop length. Reuse `SongwriterScheduledClip`, `tileLaneBlocks`, `songwriterAudioTickToMs`, and the exact stretch/trim/loop resolution from the existing rule.

- [ ] **Step 1: Write the failing tests**

Append to `test/schema/rules/songwriter_audio_rules_test.dart` (the file already defines `_asset` and `_project(AudioFitMode)`; reuse them):

```dart
  test('section clips are section-local (no globalStartBar offset)', () {
    final res = songwriterSectionSchedulableClips(_project(AudioFitMode.loop), 's1');
    final c = res.clips.single;
    expect(c.startMs, 0);
    expect(c.endMs, 4000); // 2-bar span @120 4/4
    expect(c.loop, isTrue);
  });

  test('section loopMs is the section length, not the clip span', () {
    final res = songwriterSectionSchedulableClips(_project(AudioFitMode.loop), 's1');
    expect(res.loopMs, 8000); // 4 bars @120 4/4
  });

  test('section repeat does NOT add extra placements (single section view)', () {
    final base = _project(AudioFitMode.loop);
    final repeated = base.copyWith(
      sections: [base.sections.single.copyWith(repeat: 2)],
    );
    final res = songwriterSectionSchedulableClips(repeated, 's1');
    expect(res.clips.length, 1);
    expect(res.loopMs, 8000);
  });

  test('unknown section id yields no clips and zero loopMs', () {
    final res = songwriterSectionSchedulableClips(_project(AudioFitMode.loop), 'nope');
    expect(res.clips, isEmpty);
    expect(res.loopMs, 0);
  });
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/schema/rules/songwriter_audio_rules_test.dart`
Expected: FAIL — `songwriterSectionSchedulableClips` undefined.

- [ ] **Step 3: Implement the rule**

Append to `lib/schema/rules/songwriter_audio_rules.dart` (before the final newline):

```dart
/// Section-local sibling of [songwriterSchedulableAudioClips] for the
/// record-time monitor. Returns the section's audio-lane clips with
/// `startMs`/`endMs` relative to the section's own bar 0 (no flattened
/// `globalStartBar` offset, no per-repeat duplication), plus [loopMs] — the
/// section length in ms, used to wrap the monitor loop. Stretch/trim/loop
/// resolution matches the flattened rule. Includes every audio clip in the
/// section (the in-progress recording's clip does not exist yet).
({int loopMs, List<SongwriterScheduledClip> clips}) songwriterSectionSchedulableClips(
  SongwriterProjectSnapshot project,
  String sectionId,
) {
  final cfg = project.config;
  final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
  final section = project.sections.where((s) => s.id == sectionId).firstOrNull;
  if (section == null) return (loopMs: 0, clips: const []);

  final assetsById = {for (final a in project.audioAssets) a.id: a};
  final clipsById = {for (final c in project.audioClips) c.id: c};
  final out = <SongwriterScheduledClip>[];

  for (final lane in section.lanes) {
    if (lane.kind != SongLaneKind.audio) continue;
    for (final block in tileLaneBlocks(
      lane,
      sectionLengthBars: section.lengthBars,
    )) {
      final clip = clipsById[block.audioClipId];
      if (clip == null) continue;
      final usesStretched = clip.fitMode == AudioFitMode.stretch &&
          clip.stretchedAssetId != null;
      final playAsset = usesStretched
          ? assetsById[clip.stretchedAssetId]
          : assetsById[clip.assetId];
      if (playAsset == null) continue;

      final clippedEnd = block.endBar > section.lengthBars
          ? section.lengthBars
          : block.endBar;
      final startTick = block.startBar * measureTicks; // section-local
      final spanEndTick = clippedEnd * measureTicks;
      final startMs = songwriterAudioTickToMs(startTick, cfg);
      final spanMs = songwriterAudioTickToMs(spanEndTick, cfg) - startMs;
      final trimEnd =
          clip.trimEndMs == 0 ? playAsset.durationMs : clip.trimEndMs;
      final regionMs = (trimEnd - clip.trimStartMs).clamp(0, playAsset.durationMs);
      final loop = clip.fitMode == AudioFitMode.loop;
      final endMs = loop || usesStretched
          ? startMs + spanMs
          : startMs + (regionMs < spanMs ? regionMs : spanMs);

      out.add(SongwriterScheduledClip(
        asset: playAsset,
        startMs: startMs,
        endMs: endMs,
        trimStartMs: usesStretched ? 0 : clip.trimStartMs,
        loop: loop,
      ));
    }
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return (loopMs: songwriterAudioTickToMs(section.lengthBars * measureTicks, cfg), clips: out);
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/schema/rules/songwriter_audio_rules_test.dart`
Expected: PASS (all, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_audio_rules.dart test/schema/rules/songwriter_audio_rules_test.dart
git commit -m "feat(songwriter): section-relative audio-clip schedule rule for record monitor"
```

---

## Task 2: Persist the three monitor toggles in AppSettings

**Files:**
- Modify: `lib/models/save_system.dart:689-754` (the `AppSettings` class)
- Modify: `lib/store/settings_store.dart`
- Test: `test/models/app_settings_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/models/app_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';

void main() {
  test('record-monitor fields default OFF', () {
    const s = AppSettings();
    expect(s.recordMonitorBacking, isFalse);
    expect(s.recordMonitorMetronome, isFalse);
    expect(s.recordCountIn, isFalse);
  });

  test('record-monitor fields survive json round-trip', () {
    const s = AppSettings(
      recordMonitorBacking: true,
      recordMonitorMetronome: true,
      recordCountIn: true,
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.recordMonitorBacking, isTrue);
    expect(back.recordMonitorMetronome, isTrue);
    expect(back.recordCountIn, isTrue);
  });

  test('legacy json without the fields defaults them OFF', () {
    final back = AppSettings.fromJson(const {'metronomeEnabled': true});
    expect(back.recordMonitorBacking, isFalse);
    expect(back.recordMonitorMetronome, isFalse);
    expect(back.recordCountIn, isFalse);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/models/app_settings_test.dart`
Expected: FAIL — `recordMonitorBacking` getter undefined.

- [ ] **Step 3: Add the fields**

In `lib/models/save_system.dart`, inside `class AppSettings`:

After the `saveBrowserGrid` field declaration (line ~710) add:

```dart
  /// Record-time monitoring (Songwriter audio lane). All default OFF — playback
  /// bleeds into the mic on speakers; intended for headphones.
  final bool recordMonitorBacking;   // loop the section bed + other audio clips
  final bool recordMonitorMetronome; // click per beat while recording
  final bool recordCountIn;          // one bar of clicks before the mic arms
```

In the const constructor, after `this.saveBrowserGrid = false,` add:

```dart
    this.recordMonitorBacking = false,
    this.recordMonitorMetronome = false,
    this.recordCountIn = false,
```

In `copyWith`, after the `bool? saveBrowserGrid,` parameter add:

```dart
    bool? recordMonitorBacking,
    bool? recordMonitorMetronome,
    bool? recordCountIn,
```

and after `saveBrowserGrid: saveBrowserGrid ?? this.saveBrowserGrid,` add:

```dart
    recordMonitorBacking: recordMonitorBacking ?? this.recordMonitorBacking,
    recordMonitorMetronome: recordMonitorMetronome ?? this.recordMonitorMetronome,
    recordCountIn: recordCountIn ?? this.recordCountIn,
```

In `toJson`, after `'saveBrowserGrid': saveBrowserGrid,` add:

```dart
    'recordMonitorBacking': recordMonitorBacking,
    'recordMonitorMetronome': recordMonitorMetronome,
    'recordCountIn': recordCountIn,
```

In `fromJson`, after `saveBrowserGrid: json['saveBrowserGrid'] as bool? ?? false,` add:

```dart
    recordMonitorBacking: json['recordMonitorBacking'] as bool? ?? false,
    recordMonitorMetronome: json['recordMonitorMetronome'] as bool? ?? false,
    recordCountIn: json['recordCountIn'] as bool? ?? false,
```

- [ ] **Step 4: Add setters**

In `lib/store/settings_store.dart`, inside `SettingsNotifier`, after `setSaveBrowserGrid` add:

```dart
  Future<void> setRecordMonitorBacking(bool on) async {
    state = state.copyWith(recordMonitorBacking: on);
    await _persist();
  }

  Future<void> setRecordMonitorMetronome(bool on) async {
    state = state.copyWith(recordMonitorMetronome: on);
    await _persist();
  }

  Future<void> setRecordCountIn(bool on) async {
    state = state.copyWith(recordCountIn: on);
    await _persist();
  }
```

- [ ] **Step 5: Run test, verify it passes**

Run: `flutter test test/models/app_settings_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/save_system.dart lib/store/settings_store.dart test/models/app_settings_test.dart
git commit -m "feat(settings): persist record-monitor backing/metronome/count-in toggles"
```

---

## Task 3: Monitor descriptor + recorder-store loop

**Files:**
- Modify: `lib/store/songwriter_audio_recorder_store.dart`
- Test: `test/store/songwriter_audio_recorder_store_test.dart`

Context: `SongwriterAudioRecorderNotifier.start({countInMs})` does count-in (4 hi-hat blips) then `driver.start()`. We add a `monitor` param + `countInBeats`, unify the count-in to `playClick`, and after `driver.start()` spawn a section-looped monitor loop (mirrors the audition transport). Cancellation uses a new generation counter so `stop()`/`cancel()` kill the loop. The store reads sinks via providers but still reads no project state.

- [ ] **Step 1: Write the failing tests**

In `test/store/songwriter_audio_recorder_store_test.dart`, add imports at the top:

```dart
import 'dart:async';
import 'package:muzician/models/song_project.dart' show DrumLaneId;
import 'package:muzician/store/song_playback_store.dart' show SongAudioClipSink;
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart' show SongwriterAuditionBed;
```

Add a fake clip sink near `_FakeDriver`:

```dart
class _FakeClipSink implements SongAudioClipSink {
  int startCount = 0;
  int stopAllCount = 0;
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async => startCount++;
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async => stopAllCount++;
}
```

Add tests inside `main()`:

```dart
  SongwriterRecordMonitor _monitor({
    required bool backing,
    required bool metronome,
  }) => SongwriterRecordMonitor(
        backing: backing,
        metronome: metronome,
        tempo: 6000, // fast: many ticks per 200ms window
        beatTicks: 4,
        measureTicks: 16,
        loopTicks: 16,
        loopMs: 1000,
        bed: const (
          loopTicks: 16,
          notesByTick: {0: [60, 64, 67]},
          drumByTick: {0: [DrumLaneId.kick]},
        ),
        clips: const [],
      );

  test('monitor backing fires bed notes + drums while recording', () async {
    final notes = <List<int>>[];
    final drums = <List<DrumLaneId>>[];
    final clip = _FakeClipSink();
    final c = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
      songwriterAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp, subdir: 'songwriter_audio'),
      ),
      songwriterAudioClipSinkProvider.overrideWithValue(clip),
      songwriterNoteSinkProvider.overrideWithValue((n) => notes.add(n)),
      drumPatternPlaybackSinkProvider.overrideWithValue((l, v) async => drums.add(l)),
      songwriterMetronomeSinkProvider.overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(monitor: _monitor(backing: true, metronome: false));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(notes, isNotEmpty);
    expect(notes.first, containsAll(<int>[60, 64, 67]));
    expect(drums, isNotEmpty);
    await n.cancel();
  });

  test('monitor metronome-only clicks without bed notes', () async {
    var clicks = 0;
    final notes = <List<int>>[];
    final c = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
      songwriterAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp, subdir: 'songwriter_audio'),
      ),
      songwriterAudioClipSinkProvider.overrideWithValue(_FakeClipSink()),
      songwriterNoteSinkProvider.overrideWithValue((n) => notes.add(n)),
      drumPatternPlaybackSinkProvider.overrideWithValue((l, v) async {}),
      songwriterMetronomeSinkProvider.overrideWithValue(({required bool accent}) async => clicks++),
    ]);
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(monitor: _monitor(backing: false, metronome: true));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(clicks, greaterThan(0));
    expect(notes, isEmpty);
    await n.cancel();
  });

  test('stop tears the monitor down (clip stopAll, loop ends)', () async {
    final clip = _FakeClipSink();
    final c = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
      songwriterAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp, subdir: 'songwriter_audio'),
      ),
      songwriterAudioClipSinkProvider.overrideWithValue(clip),
      songwriterNoteSinkProvider.overrideWithValue((_) {}),
      drumPatternPlaybackSinkProvider.overrideWithValue((l, v) async {}),
      songwriterMetronomeSinkProvider.overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(monitor: _monitor(backing: true, metronome: true));
    await n.stop();
    expect(clip.stopAllCount, greaterThanOrEqualTo(1));
    expect(c.read(songwriterAudioRecorderProvider).status, SongAudioRecorderStatus.ready);
  });

  test('no monitor keeps current behaviour (no clip sink calls)', () async {
    final clip = _FakeClipSink();
    final c = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
      songwriterAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp, subdir: 'songwriter_audio'),
      ),
      songwriterAudioClipSinkProvider.overrideWithValue(clip),
    ]);
    addTearDown(c.dispose);
    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start();
    expect(c.read(songwriterAudioRecorderProvider).status, SongAudioRecorderStatus.recording);
    expect(clip.startCount, 0);
    await n.cancel();
  });
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/store/songwriter_audio_recorder_store_test.dart`
Expected: FAIL — `SongwriterRecordMonitor` undefined and `start` has no `monitor` param.

- [ ] **Step 3: Add the descriptor + imports**

In `lib/store/songwriter_audio_recorder_store.dart`, replace the import block (lines 5-11) with:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart' show AudioAsset, DrumLaneId;
import '../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../schema/rules/songwriter_audio_rules.dart' show SongwriterScheduledClip;
import '../schema/rules/songwriter_playback_rules.dart' show SongwriterAuditionBed;
import '../utils/note_player.dart';
import '../utils/tick_pacer.dart';
import 'drum_pattern_playback_store.dart';
import 'song_audio_recorder_store.dart'
    show SongAudioRecorderStatus, songAudioRecorderDriverProvider;
import 'song_audio_repository.dart';
import 'songwriter_audio_sink.dart';
import 'songwriter_playback_store.dart';
```

Above `class SongwriterAudioRecorderState`, add:

```dart
/// Plain-data descriptor for record-time monitoring. Built by the caller from
/// project state and passed into [SongwriterAudioRecorderNotifier.start]; the
/// store reads no project state itself. [bed]/[clips] are ignored when
/// [backing] is false (only the metronome fires).
class SongwriterRecordMonitor {
  final bool backing;
  final bool metronome;
  final int tempo;
  final int beatTicks; // ticksPerBeat
  final int measureTicks; // ticksPerBeat * beatsPerBar
  final int loopTicks; // section length in ticks (wraps the loop)
  final int loopMs; // section length in ms (positions clips)
  final SongwriterAuditionBed bed;
  final List<SongwriterScheduledClip> clips;
  const SongwriterRecordMonitor({
    required this.backing,
    required this.metronome,
    required this.tempo,
    required this.beatTicks,
    required this.measureTicks,
    required this.loopTicks,
    required this.loopMs,
    required this.bed,
    required this.clips,
  });

  SongwriterRecordMonitor copyWith({bool? backing, bool? metronome}) =>
      SongwriterRecordMonitor(
        backing: backing ?? this.backing,
        metronome: metronome ?? this.metronome,
        tempo: tempo,
        beatTicks: beatTicks,
        measureTicks: measureTicks,
        loopTicks: loopTicks,
        loopMs: loopMs,
        bed: bed,
        clips: clips,
      );
}
```

- [ ] **Step 4: Add the generation counter + rewrite `start`**

In `SongwriterAudioRecorderNotifier`, add a field beside `_cancelled`:

```dart
  int _monitorGen = 0;
```

Replace the whole `start` method with:

```dart
  Future<void> start({
    int countInMs = 0,
    int countInBeats = 4,
    SongwriterRecordMonitor? monitor,
  }) async {
    final st = state.status;
    if (st != SongAudioRecorderStatus.idle &&
        st != SongAudioRecorderStatus.error) {
      return;
    }
    _cancelled = false;
    final driver = ref.read(songAudioRecorderDriverProvider);
    if (!await driver.ensurePermission()) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }
    state = const SongwriterAudioRecorderState(
      status: SongAudioRecorderStatus.countIn,
    );
    if (countInMs > 0 && countInBeats > 0) {
      final beat = Duration(milliseconds: (countInMs / countInBeats).round());
      for (var i = 0; i < countInBeats; i++) {
        if (state.status != SongAudioRecorderStatus.countIn) return;
        NotePlayer.instance.playClick(accent: i == 0);
        await Future<void>.delayed(beat);
      }
    }
    if (state.status != SongAudioRecorderStatus.countIn) return;
    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    await driver.start();
    if (monitor != null && (monitor.backing || monitor.metronome)) {
      unawaited(_runMonitor(++_monitorGen, monitor));
    }
  }
```

- [ ] **Step 5: Add the monitor loop**

Add this method to `SongwriterAudioRecorderNotifier` (e.g. after `start`):

```dart
  /// Section-looped backing + metronome under the live recording. Mirrors the
  /// audition transport: a [TickPacer] anchors ticks; bed notes/drums fire by
  /// section-local tick; section audio clips fire by section-local ms and
  /// re-arm each loop pass. Cancelled when [_monitorGen] moves past [gen]
  /// (stop/cancel).
  Future<void> _runMonitor(int gen, SongwriterRecordMonitor m) async {
    final clipSink = ref.read(songwriterAudioClipSinkProvider);
    final noteSink = ref.read(songwriterNoteSinkProvider);
    final drumSink = ref.read(drumPatternPlaybackSinkProvider);
    final metroSink = ref.read(songwriterMetronomeSinkProvider);

    if (m.backing && m.clips.isNotEmpty) {
      await clipSink.prepare(m.clips.map((c) => c.asset));
      if (_monitorGen != gen) return; // stop during prepare
    }

    final loopTicks = m.loopTicks > 0 ? m.loopTicks : m.measureTicks;
    final pacer = TickPacer(pr_rules.tickDuration(m.tempo));
    final pendingStops = <(AudioAsset, int)>[];
    var tick = 0;
    var elapsed = 0;
    var nextClip = 0;

    void fireClips(int nowMs) {
      while (nextClip < m.clips.length && m.clips[nextClip].startMs <= nowMs) {
        final clip = m.clips[nextClip++];
        unawaited(clipSink.startClip(
          asset: clip.asset,
          offsetMs: clip.offsetIntoAsset(nowMs).clamp(0, clip.asset.durationMs),
          volume: clip.volume,
          loop: clip.loop,
        ));
        pendingStops.add((clip.asset, clip.endMs));
      }
      pendingStops.removeWhere((p) {
        if (p.$2 <= nowMs) {
          unawaited(clipSink.stopClip(asset: p.$1));
          return true;
        }
        return false;
      });
    }

    while (_monitorGen == gen) {
      if (m.metronome && tick % m.beatTicks == 0) {
        unawaited(metroSink(accent: tick % m.measureTicks == 0));
      }
      if (m.backing) {
        final notes = m.bed.notesByTick[tick];
        if (notes != null && notes.isNotEmpty) noteSink(notes);
        final drums = m.bed.drumByTick[tick];
        if (drums != null && drums.isNotEmpty) unawaited(drumSink(drums, 0.8));
        if (m.clips.isNotEmpty && loopTicks > 0) {
          fireClips((tick * m.loopMs / loopTicks).round());
        }
      }
      await pacer.awaitBoundary(++elapsed);
      if (_monitorGen != gen) break;
      final prev = tick;
      tick = (tick + 1) % loopTicks;
      if (tick <= prev) {
        // Loop wrapped: re-arm clips for the next pass.
        nextClip = 0;
        for (final p in pendingStops) {
          unawaited(clipSink.stopClip(asset: p.$1));
        }
        pendingStops.clear();
      }
    }
  }

  void _stopMonitor() {
    _monitorGen++;
    unawaited(ref.read(songwriterAudioClipSinkProvider).stopAll());
  }
```

- [ ] **Step 6: Tear the monitor down in `stop` and `cancel`**

In `stop()`, immediately after the `state = state.copyWith(status: SongAudioRecorderStatus.finalising);` line, add:

```dart
    _stopMonitor();
```

In `cancel()`, immediately after `_cancelled = true;`, add:

```dart
    _stopMonitor();
```

- [ ] **Step 7: Run tests, verify they pass**

Run: `flutter test test/store/songwriter_audio_recorder_store_test.dart`
Expected: PASS (new + the pre-existing record→ready test).

- [ ] **Step 8: Commit**

```bash
git add lib/store/songwriter_audio_recorder_store.dart test/store/songwriter_audio_recorder_store_test.dart
git commit -m "feat(songwriter): record-time monitor loop (backing + metronome) in recorder store"
```

---

## Task 4: Recorder sheet toggles + monitor assembly

**Files:**
- Modify: `lib/features/songwriter/songwriter_audio_recorder_sheet.dart`
- Modify: `lib/features/songwriter/songwriter_audio_actions.dart`
- Test: `test/features/songwriter/songwriter_audio_recorder_sheet_test.dart` (create)

Context: the sheet currently calls `n.start(countInMs: countInMs)`. It becomes stateful: three toggles seeded from `settingsProvider`, persisted on change, shown only in the pre-record (idle/error) state. The caller (`showSongwriterAudioPicker`) builds a `monitorTemplate` (backing+metronome both true) plus `countInBarMs`/`countInBeats`, and passes them to the sheet. On Record the sheet flips the template flags and decides `countInMs`.

- [ ] **Step 1: Build the monitor template in the caller**

In `lib/features/songwriter/songwriter_audio_actions.dart`, add imports:

```dart
import '../../schema/rules/songwriter_audio_rules.dart';
import '../../schema/rules/songwriter_playback_rules.dart' show sectionAuditionBed;
import '../../store/save_system_store.dart';
import '../../store/songwriter_audio_recorder_store.dart' show SongwriterRecordMonitor;
```

Replace the `onRecord` body (the `showModalBottomSheet<AudioAsset?>` call) with:

```dart
      onRecord: () async {
        Navigator.of(sheetCtx).pop();
        final project = ref.read(songwriterProvider);
        final cfg = project.config;
        final section =
            project.sections.where((s) => s.id == sectionId).firstOrNull;
        final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
        SongwriterRecordMonitor? template;
        if (section != null) {
          final sectionClips = songwriterSectionSchedulableClips(project, sectionId);
          template = SongwriterRecordMonitor(
            backing: true,
            metronome: true,
            tempo: cfg.tempo,
            beatTicks: cfg.ticksPerBeat,
            measureTicks: measureTicks,
            loopTicks: section.lengthBars * measureTicks,
            loopMs: sectionClips.loopMs,
            bed: sectionAuditionBed(
              section,
              cfg,
              ref.read(saveSystemProvider).saves,
              drumPatterns: project.drumPatterns,
            ),
            clips: sectionClips.clips,
          );
        }
        final asset = await showModalBottomSheet<AudioAsset?>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => SongwriterAudioRecorderSheet(
            monitorTemplate: template,
            countInBarMs: songwriterAudioTickToMs(measureTicks, cfg),
            countInBeats: cfg.beatsPerBar,
          ),
        );
        if (asset != null) {
          _commit(ref, sectionId, laneId, startBar, sectionLengthBars, asset);
        }
      },
```

- [ ] **Step 2: Write the failing widget test**

Create `test/features/songwriter/songwriter_audio_recorder_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/songwriter/songwriter_audio_recorder_sheet.dart';

void main() {
  testWidgets('shows the three monitor toggles, all OFF by default', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioRecorderSheet(
              monitorTemplate: null,
              countInBarMs: 2000,
              countInBeats: 4,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('sw-rec-toggle-backing')), findsOneWidget);
    expect(find.byKey(const ValueKey('sw-rec-toggle-metronome')), findsOneWidget);
    expect(find.byKey(const ValueKey('sw-rec-toggle-countin')), findsOneWidget);
    for (final w in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(w.value, isFalse);
    }
  });
}
```

- [ ] **Step 3: Run test, verify it fails**

Run: `flutter test test/features/songwriter/songwriter_audio_recorder_sheet_test.dart`
Expected: FAIL — sheet has no such constructor params / keys.

- [ ] **Step 4: Make the sheet stateful with toggles**

Replace the whole `lib/features/songwriter/songwriter_audio_recorder_sheet.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../store/settings_store.dart';
import '../../store/song_audio_recorder_store.dart'
    show SongAudioRecorderStatus;
import '../../store/songwriter_audio_recorder_store.dart';
import '../../theme/muzician_theme.dart';

/// Recorder sheet. Pops with the recorded [AudioAsset] (or null on cancel).
/// Optional record-time monitoring: when [monitorTemplate] is non-null the user
/// can toggle Backing / Metronome / Count-in (defaults from settings).
class SongwriterAudioRecorderSheet extends ConsumerStatefulWidget {
  final SongwriterRecordMonitor? monitorTemplate;
  final int countInBarMs;
  final int countInBeats;
  const SongwriterAudioRecorderSheet({
    super.key,
    this.monitorTemplate,
    this.countInBarMs = 0,
    this.countInBeats = 4,
  });

  @override
  ConsumerState<SongwriterAudioRecorderSheet> createState() =>
      _SongwriterAudioRecorderSheetState();
}

class _SongwriterAudioRecorderSheetState
    extends ConsumerState<SongwriterAudioRecorderSheet> {
  late bool _backing;
  late bool _metronome;
  late bool _countIn;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backing = s.recordMonitorBacking;
    _metronome = s.recordMonitorMetronome;
    _countIn = s.recordCountIn;
  }

  void _onRecord() {
    final t = widget.monitorTemplate;
    final useMonitor = t != null && (_backing || _metronome);
    ref.read(songwriterAudioRecorderProvider.notifier).start(
          countInMs: _countIn ? widget.countInBarMs : 0,
          countInBeats: widget.countInBeats,
          monitor:
              useMonitor ? t.copyWith(backing: _backing, metronome: _metronome) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SongwriterAudioRecorderState>(songwriterAudioRecorderProvider, (
      prev,
      next,
    ) {
      if (next.status == SongAudioRecorderStatus.ready &&
          next.pendingAsset != null) {
        final asset = ref
            .read(songwriterAudioRecorderProvider.notifier)
            .consumePendingAsset();
        if (!context.mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(asset);
        }
      }
    });
    final state = ref.watch(songwriterAudioRecorderProvider);
    final n = ref.read(songwriterAudioRecorderProvider.notifier);

    if (state.status == SongAudioRecorderStatus.ready &&
        state.pendingAsset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final asset = ref
            .read(songwriterAudioRecorderProvider.notifier)
            .consumePendingAsset();
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(asset);
        }
      });
    }

    final label = switch (state.status) {
      SongAudioRecorderStatus.idle => 'Ready',
      SongAudioRecorderStatus.countIn => 'Count-in…',
      SongAudioRecorderStatus.recording => 'Recording…',
      SongAudioRecorderStatus.finalising => 'Finalising…',
      SongAudioRecorderStatus.ready => 'Done',
      SongAudioRecorderStatus.error => state.errorMessage ?? 'Error',
    };
    final isRec = state.status == SongAudioRecorderStatus.recording;
    final busy = state.status == SongAudioRecorderStatus.finalising ||
        state.status == SongAudioRecorderStatus.ready;
    final isCountIn = state.status == SongAudioRecorderStatus.countIn;
    final preRecord = state.status == SongAudioRecorderStatus.idle ||
        state.status == SongAudioRecorderStatus.error;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await n.cancel();
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(null);
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: MuzicianTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (preRecord) ...[
                _MonitorToggle(
                  itemKey: 'sw-rec-toggle-backing',
                  title: 'Backing',
                  subtitle: 'Loop the section (chords, drums, audio)',
                  value: _backing,
                  enabled: widget.monitorTemplate != null,
                  onChanged: (v) {
                    setState(() => _backing = v);
                    ref.read(settingsProvider.notifier).setRecordMonitorBacking(v);
                  },
                ),
                _MonitorToggle(
                  itemKey: 'sw-rec-toggle-metronome',
                  title: 'Metronome',
                  subtitle: 'Click on every beat',
                  value: _metronome,
                  enabled: widget.monitorTemplate != null,
                  onChanged: (v) {
                    setState(() => _metronome = v);
                    ref.read(settingsProvider.notifier).setRecordMonitorMetronome(v);
                  },
                ),
                _MonitorToggle(
                  itemKey: 'sw-rec-toggle-countin',
                  title: 'Count-in',
                  subtitle: 'One bar before recording',
                  value: _countIn,
                  enabled: true,
                  onChanged: (v) {
                    setState(() => _countIn = v);
                    ref.read(settingsProvider.notifier).setRecordCountIn(v);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Use headphones — speaker playback bleeds into the mic.',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (busy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      key: const ValueKey('sw-audio-rec-cancel'),
                      onPressed: () async {
                        await n.cancel();
                        if (context.mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop<AudioAsset?>(null);
                        }
                      },
                      child: Text(isRec || isCountIn ? 'Cancel' : 'Close'),
                    ),
                    if (isRec)
                      FilledButton.icon(
                        key: const ValueKey('sw-audio-rec-stop'),
                        onPressed: () => n.stop(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      )
                    else if (preRecord)
                      FilledButton.icon(
                        key: const ValueKey('sw-audio-rec-start'),
                        onPressed: _onRecord,
                        icon: const Icon(Icons.mic),
                        label: const Text('Record'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonitorToggle extends StatelessWidget {
  final String itemKey;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _MonitorToggle({
    required this.itemKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: ValueKey(itemKey),
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(
        title,
        style: const TextStyle(
          color: MuzicianTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: MuzicianTheme.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test, verify it passes**

Run: `flutter test test/features/songwriter/songwriter_audio_recorder_sheet_test.dart`
Expected: PASS.

- [ ] **Step 6: Static analysis**

Run: `flutter analyze lib/features/songwriter/songwriter_audio_recorder_sheet.dart lib/features/songwriter/songwriter_audio_actions.dart lib/store/songwriter_audio_recorder_store.dart`
Expected: No issues (resolve any unused imports).

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_audio_recorder_sheet.dart lib/features/songwriter/songwriter_audio_actions.dart test/features/songwriter/songwriter_audio_recorder_sheet_test.dart
git commit -m "feat(songwriter): record sheet backing/metronome/count-in toggles wired to monitor"
```

---

## Task 5: Full suite + analyze

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS (no regressions).

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "chore(songwriter): tidy record-monitoring after full-suite run"
```

(Skip if nothing changed.)

---

## Task 6 (verification-gated): iOS playAndRecord session flip

**Do this ONLY if device verification shows the recording is silent/corrupted or playback stops when monitoring is on.** The Song feature already plays transport audio during recording without this flip, so it is likely unnecessary; do not add speculative global audio-session mutation.

**Files:**
- Modify: `lib/store/song_playback_store.dart` (the `SongAudioClipSink` interface + `NoopSongAudioClipSink`)
- Modify: `lib/store/song_audio_player_sink.dart` (`AudioPlayersClipSink`)
- Modify: `lib/store/songwriter_audio_recorder_store.dart` (call enter/exit)

- [ ] **Step 1: Device test the current build first**

Run on a physical iOS device (sim mic/routing is unreliable), wearing headphones: open the Songwriter, add an audio lane, Record with Backing + Metronome on. Confirm: (a) you hear the backing + click; (b) Stop produces a clip; (c) playing that clip back contains only the captured voice/instrument. If all true, **stop here — Task 6 not needed.** Also confirm subsequent project playback still works (session not stuck).

- [ ] **Step 2: Add session methods to the interface**

In `lib/store/song_playback_store.dart`, in `abstract class SongAudioClipSink`, add **concrete default no-ops** (so existing implementers/fakes keep compiling):

```dart
  /// Switch the process audio session to allow simultaneous capture + playback
  /// (iOS: playAndRecord). No-op off iOS / on the no-op sink.
  Future<void> enterRecordSession() async {}

  /// Restore the playback-only session.
  Future<void> exitRecordSession() async {}
```

(`NoopSongAudioClipSink` inherits the no-ops; no change needed there.)

- [ ] **Step 3: Implement on the production sink**

In `lib/store/song_audio_player_sink.dart`, add to `AudioPlayersClipSink`:

```dart
  @override
  Future<void> enterRecordSession() => AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
            },
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );

  @override
  Future<void> exitRecordSession() => AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
```

- [ ] **Step 4: Call them around the monitored recording**

In `lib/store/songwriter_audio_recorder_store.dart` `start()`, immediately before `await driver.start();`, add:

```dart
    if (monitor != null && (monitor.backing || monitor.metronome)) {
      await ref.read(songwriterAudioClipSinkProvider).enterRecordSession();
    }
```

In `_stopMonitor()`, after the `stopAll()` line, add:

```dart
    unawaited(ref.read(songwriterAudioClipSinkProvider).exitRecordSession());
```

- [ ] **Step 5: Run the suite + re-test on device**

Run: `flutter test`
Expected: PASS (no-op default keeps existing tests green).
Then repeat the Step 1 device test and confirm the recording is now clean and the session restores afterward.

- [ ] **Step 6: Commit**

```bash
git add lib/store/song_playback_store.dart lib/store/song_audio_player_sink.dart lib/store/songwriter_audio_recorder_store.dart
git commit -m "fix(songwriter): playAndRecord session for monitored recording (iOS)"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** Backing scope (bed + section audio clips) → Task 1 rule + Task 3 loop. Two toggles + count-in → Task 2 (persist) + Task 4 (UI). Count-in → Task 3 (`countInMs`/`countInBeats`) + Task 4. Lockstep orchestration → Task 3. iOS session risk → Task 6 (gated, per shipped precedent). Edge cases (empty section, stop-during-prepare, teardown) → Task 3 tests + loop guards. Testing → Tasks 1–5. Out-of-scope items unchanged.
- **Placeholder scan:** none — every code/step is concrete.
- **Type consistency:** `SongwriterRecordMonitor` fields/`copyWith` defined in Task 3 match the Task 4 caller; `songwriterSectionSchedulableClips` return shape `({int loopMs, List<SongwriterScheduledClip> clips})` matches Task 4 usage; `SongwriterAuditionBed` record shape matches Task 3 test literal; settings field names match across Tasks 2 and 4.
- **Deviation from spec:** iOS session flip demoted from core to verification-gated Task 6 (YAGNI; Song feature is shipped precedent for play-during-record). Flagged to the user.
