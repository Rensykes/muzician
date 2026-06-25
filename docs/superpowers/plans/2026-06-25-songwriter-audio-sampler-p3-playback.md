# Songwriter Audio Sampler — Plan 3: Transport Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make audio clips sound on the Songwriter transport — loop or one-shot per the clip's fit mode, scheduled in sync with the existing note/drum/metronome playback, started/stopped by millisecond as the tick clock advances.

**Architecture:** Mirror the Song feature's audio scheduling. A pure rule `songwriterSchedulableAudioClips` flattens placed clips across section repeats into `(asset, startMs, endMs, loop)` records; the transport pre-loads players, then a `fireAudioForTick` closure starts/stops clips as the playhead crosses their millisecond bounds. Reuse the Song `SongAudioClipSink` / `AudioPlayersClipSink`, extended with a `loop` flag.

**Tech Stack:** Dart, Riverpod, `audioplayers` (`ReleaseMode.loop`), `flutter_test` with a fake sink.

**Depends on:** Plan 1 (model + `songwriterAudioRepositoryProvider`), Plan 2 (clips exist on lanes). Spec: `docs/superpowers/specs/2026-06-25-songwriter-audio-sampler-design.md`. Stretch mode plays the *source* asset one-shot here; Plan 4 swaps in the pre-rendered asset.

Reference files:
- `lib/store/song_playback_store.dart:51` — `SongAudioClipSink` interface + `_NoopAudioSink` + `fireAudioForTick` scheduling pattern (lines 202–224).
- `lib/store/song_audio_player_sink.dart` — `AudioPlayersClipSink` (production sink to extend).
- `lib/schema/rules/song_audio_rules.dart:36` — `ScheduledAudioClip` / `schedulableAudioClips` (template).
- `lib/store/songwriter_playback_store.dart` — the transport to extend (tick loop at lines 119–135).
- `lib/schema/rules/songwriter_rules.dart` — `expandSections` / `tileLaneBlocks` / `flattenedBarCount`.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/store/song_playback_store.dart` | Add `loop` to `SongAudioClipSink.startClip` (+ noop) | Modify |
| `lib/store/song_audio_player_sink.dart` | Honor `loop` (`ReleaseMode.loop`); Song call site passes `loop: false` | Modify |
| `lib/schema/rules/songwriter_audio_rules.dart` | `songwriterAudioTickToMs`, `songwriterSchedulableAudioClips`, `SongwriterScheduledClip` | Create |
| `lib/store/songwriter_audio_sink.dart` | `songwriterAudioClipSinkProvider` (+ production binding) | Create |
| `lib/store/songwriter_playback_store.dart` | Schedule audio in the tick loop | Modify |
| `lib/main.dart` | Override `songwriterAudioClipSinkProvider` with production | Modify |
| `test/schema/rules/songwriter_audio_rules_test.dart` | Flatten + tick→ms + loop/one-shot bounds | Create |
| `test/store/songwriter_audio_playback_test.dart` | Transport fires start/stop on a fake sink | Create |

---

### Task 1: Add a `loop` flag to the clip sink

**Files:**
- Modify: `lib/store/song_playback_store.dart` (`SongAudioClipSink`, `_NoopAudioSink`)
- Modify: `lib/store/song_audio_player_sink.dart` (`AudioPlayersClipSink`)

- [ ] **Step 1: Extend the interface + noop**

In `lib/store/song_playback_store.dart`, change the abstract method and the noop impl to add `bool loop = false`:

```dart
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  });
```

```dart
  // in _NoopAudioSink:
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async {}
```

The Song transport's existing `startClip(...)` call (around line 207) does not pass `loop`, so it defaults to `false` — no behavior change there.

- [ ] **Step 2: Honor `loop` in the production sink**

In `lib/store/song_audio_player_sink.dart`, update `startClip` to set the release mode before resuming, and reset it on stop:

```dart
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async {
    var player = _players[asset.id];
    if (player == null) {
      final file = await repository.resolvePath(asset.id, asset.format);
      if (!file.existsSync()) return;
      player = AudioPlayer();
      await player.setSource(DeviceFileSource(file.path));
      _players[asset.id] = player;
    }
    await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    await player.setVolume(volume.clamp(0.0, 1.0));
    await player.seek(Duration(milliseconds: offsetMs));
    await player.resume();
  }
```

In `stopClip`, after `await player.stop();` add `await player.setReleaseMode(ReleaseMode.stop);` so a reused player does not stay in loop mode.

- [ ] **Step 3: Analyze + run Song playback tests for regressions**

Run: `flutter analyze lib/store/song_playback_store.dart lib/store/song_audio_player_sink.dart && flutter test test/store/song_playback_store_test.dart`
Expected: no issues; Song playback tests still PASS (the noop sink default keeps behavior identical).

- [ ] **Step 4: Commit**

```bash
git add lib/store/song_playback_store.dart lib/store/song_audio_player_sink.dart
git commit -m "feat(audio): optional loop flag on SongAudioClipSink.startClip"
```

---

### Task 2: `songwriterSchedulableAudioClips` rule

**Files:**
- Create: `lib/schema/rules/songwriter_audio_rules.dart`
- Test: `test/schema/rules/songwriter_audio_rules_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/songwriter_audio_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_audio_rules.dart';

const _asset = AudioAsset(
  id: 'a1', durationMs: 1500, sampleRate: 44100, channels: 1,
  format: 'wav', peaks: [1], sourceLabel: 'Recording');

SongwriterProjectSnapshot _project(AudioFitMode mode) {
  // 120 BPM, 4/4 → 1 bar = 2000ms. One section (4 bars), one audio lane,
  // one clip block at bar 0 spanning 2 bars (= 4000ms).
  const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 1500);
  return SongwriterProjectSnapshot(
    config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    audioAssets: const [_asset],
    audioClips: [clip.copyWith(fitMode: mode)],
    sections: const [SongSection(id: 's1', lengthBars: 4, order: 0, lanes: [
      SongLane(id: 'l1', kind: SongLaneKind.audio, order: 0, blocks: [
        SongBlock(id: 'b1', startBar: 0, spanBars: 2, audioClipId: 'c1'),
      ]),
    ])],
  );
}

void main() {
  test('tick→ms at 120 BPM, 4/4 (480 tpb): 1 bar = 2000ms', () {
    final cfg = const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
    expect(songwriterAudioTickToMs(measureTicks, cfg), 2000);
  });

  test('loop clip fills the whole 2-bar span (4000ms)', () {
    final clips = songwriterSchedulableAudioClips(_project(AudioFitMode.loop));
    final c = clips.single;
    expect(c.startMs, 0);
    expect(c.endMs, 4000);
    expect(c.loop, isTrue);
    expect(c.offsetIntoAsset(0), 0);
  });

  test('one-shot clip stops at natural end (1500ms), not span end', () {
    final clips =
        songwriterSchedulableAudioClips(_project(AudioFitMode.oneShot));
    final c = clips.single;
    expect(c.endMs, 1500);
    expect(c.loop, isFalse);
  });

  test('section repeat ×2 yields two placements', () {
    final base = _project(AudioFitMode.loop);
    final repeated = base.copyWith(sections: [
      base.sections.single.copyWith(repeat: 2),
    ]);
    final clips = songwriterSchedulableAudioClips(repeated);
    expect(clips.length, 2);
    expect(clips[1].startMs, 8000); // section length 4 bars = 8000ms
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_audio_rules_test.dart`
Expected: FAIL — `songwriterAudioTickToMs` / `songwriterSchedulableAudioClips` undefined.

- [ ] **Step 3: Implement the rule**

Create `lib/schema/rules/songwriter_audio_rules.dart`:

```dart
/// Pure scheduling helpers for Songwriter audio-lane playback.
library;

import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import 'songwriter_rules.dart';

int songwriterAudioTickToMs(int tick, SongwriterConfig config) {
  final msPerBeat = 60000.0 / config.tempo;
  return (tick * msPerBeat / config.ticksPerBeat).round();
}

/// A placed audio clip resolved to absolute transport milliseconds.
class SongwriterScheduledClip {
  final AudioAsset asset;
  final int startMs;
  final int endMs;
  final int trimStartMs;
  final bool loop;
  final double volume;
  const SongwriterScheduledClip({
    required this.asset,
    required this.startMs,
    required this.endMs,
    required this.trimStartMs,
    required this.loop,
    this.volume = 1.0,
  });

  /// In-asset position to seek to when the playhead is at [nowMs].
  int offsetIntoAsset(int nowMs) => trimStartMs + (nowMs - startMs);
}

/// Flattens placed audio clips across section repeats into absolute-ms records.
///
/// Stretch mode resolves to the pre-rendered [AudioClip.stretchedAssetId] when
/// present (Plan 4); until then it plays the source one-shot.
List<SongwriterScheduledClip> songwriterSchedulableAudioClips(
  SongwriterProjectSnapshot project,
) {
  final cfg = project.config;
  final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
  final assetsById = {for (final a in project.audioAssets) a.id: a};
  final clipsById = {for (final c in project.audioClips) c.id: c};
  final out = <SongwriterScheduledClip>[];

  for (final exp in expandSections(project.sections)) {
    final section =
        project.sections.where((s) => s.id == exp.sectionId).firstOrNull;
    if (section == null) continue;
    for (final lane in section.lanes) {
      if (lane.kind != SongLaneKind.audio) continue;
      for (final block in tileLaneBlocks(lane, sectionLengthBars: section.lengthBars)) {
        final clip = clipsById[block.audioClipId];
        if (clip == null) continue;
        final playAsset = clip.fitMode == AudioFitMode.stretch &&
                clip.stretchedAssetId != null
            ? assetsById[clip.stretchedAssetId]
            : assetsById[clip.assetId];
        if (playAsset == null) continue;

        final clippedEnd =
            block.endBar > section.lengthBars ? section.lengthBars : block.endBar;
        final startTick = (exp.globalStartBar + block.startBar) * measureTicks;
        final spanEndTick = (exp.globalStartBar + clippedEnd) * measureTicks;
        final startMs = songwriterAudioTickToMs(startTick, cfg);
        final spanMs = songwriterAudioTickToMs(spanEndTick, cfg) - startMs;
        final regionMs = (clip.trimEndMs - clip.trimStartMs)
            .clamp(0, playAsset.durationMs);

        final loop = clip.fitMode == AudioFitMode.loop;
        // Stretched asset already fills the span; otherwise loop fills the span
        // and one-shot/stretch-fallback stop at the natural region end.
        final usesStretched = clip.fitMode == AudioFitMode.stretch &&
            clip.stretchedAssetId != null;
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
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out;
}
```

> `firstOrNull` is from `package:collection`. If unresolved, add `import 'package:collection/collection.dart';`. Confirm `expandSections` returns items with `sectionId` + `globalStartBar` (it does — see `songwriter_playback_rules.dart` usage) and that `ExpandedSection` is exported from `songwriter_rules.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_audio_rules_test.dart`
Expected: PASS (all four).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/schema/rules/songwriter_audio_rules.dart test/schema/rules/songwriter_audio_rules_test.dart
flutter analyze lib/schema/rules/songwriter_audio_rules.dart
git add lib/schema/rules/songwriter_audio_rules.dart test/schema/rules/songwriter_audio_rules_test.dart
git commit -m "feat(songwriter): audio clip scheduling rule"
```

---

### Task 3: Songwriter audio clip sink provider

**Files:**
- Create: `lib/store/songwriter_audio_sink.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Define the provider + production binding**

Create `lib/store/songwriter_audio_sink.dart`:

```dart
/// Clip sink for the Songwriter transport. Defaults to the no-op sink; the real
/// `AudioPlayersClipSink` (bound to the songwriter audio repository) is wired in
/// main.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'song_audio_player_sink.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart' show SongAudioClipSink;

final songwriterAudioClipSinkProvider = Provider<SongAudioClipSink>(
  (ref) => const NoopSongAudioClipSink(),
);

final productionSongwriterAudioClipSinkProvider = Provider<SongAudioClipSink>(
  (ref) => AudioPlayersClipSink(ref.read(songwriterAudioRepositoryProvider)),
);
```

> `_NoopAudioSink` in `song_playback_store.dart` is private. Add a public `const NoopSongAudioClipSink()` next to it (a one-line class implementing the interface with empty bodies), or reuse the existing default by reading `songAudioClipSinkProvider`'s default. Simplest: in `song_playback_store.dart`, rename `_NoopAudioSink` → `NoopSongAudioClipSink` (public) and update its single reference. Do that rename in this step and re-run `flutter analyze`.

- [ ] **Step 2: Wire production in main.dart**

In `lib/main.dart`, beside the existing `songAudioClipSinkProvider.overrideWith(...)` (line 46), add:

```dart
        songwriterAudioClipSinkProvider.overrideWith(
          (ref) => ref.watch(productionSongwriterAudioClipSinkProvider),
        ),
```

Add the import: `import 'store/songwriter_audio_sink.dart';` (match main.dart's existing import style).

- [ ] **Step 3: Analyze + commit**

```bash
dart format lib/store/songwriter_audio_sink.dart lib/store/song_playback_store.dart lib/main.dart
flutter analyze lib/store/songwriter_audio_sink.dart lib/main.dart
git add lib/store/songwriter_audio_sink.dart lib/store/song_playback_store.dart lib/main.dart
git commit -m "feat(songwriter): audio clip sink provider + production wiring"
```

---

### Task 4: Schedule audio in the transport

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_audio_playback_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/store/songwriter_audio_playback_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/song_playback_store.dart' show SongAudioClipSink;
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';

class _RecordingSink implements SongAudioClipSink {
  final started = <(String, bool)>[];
  final stopped = <String>[];
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset, required int offsetMs,
    double volume = 1.0, bool loop = false,
  }) async => started.add((asset.id, loop));
  @override
  Future<void> stopClip({required AudioAsset asset}) async =>
      stopped.add(asset.id);
  @override
  Future<void> stopAll() async {}
}

void main() {
  testWidgets('transport starts and stops a looped audio clip', (tester) async {
    final sink = _RecordingSink();
    final c = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(c.dispose);

    // Seed a 1-section project with one looped audio clip (bar 0, span 1).
    final store = c.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 1);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).id;
    // Inject an asset + clip directly (recorder is exercised in Plan 2).
    store.loadProject(c.read(songwriterProvider).copyWith(audioAssets: const [
      AudioAsset(id: 'a1', durationMs: 800, sampleRate: 44100, channels: 1,
          format: 'wav', peaks: [1], sourceLabel: 'r'),
    ]));
    final clipId = store.addAudioClip(assetId: 'a1', durationMs: 800);
    store.setClipFitMode(clipId: clipId, fitMode: AudioFitMode.loop);
    store.addAudioBlock(sectionId: sectionId, laneId: laneId,
        audioClipId: clipId, startBar: 0, spanBars: 1);

    // Run the transport fast.
    await c.read(songwriterPlaybackProvider.notifier).startPlayback(
        tickDurationOverride: const Duration(microseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    expect(sink.started.map((e) => e.$1), contains('a1'));
    expect(sink.started.firstWhere((e) => e.$1 == 'a1').$2, isTrue); // loop
    expect(sink.stopped, contains('a1'));
  });
}
```

> The test seeds the asset via `loadProject(copyWith(audioAssets: ...))` then adds the clip/block. If `loadProject` is not the right entry to inject assets, read `songwriter_store.dart` for the closest test-seeding path used by the existing playback tests and mirror it. The assertion (a1 started with loop=true and later stopped) is the contract.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_audio_playback_test.dart`
Expected: FAIL — no `startClip` recorded (transport does not schedule audio yet).

- [ ] **Step 3: Schedule audio in `startPlayback`**

In `lib/store/songwriter_playback_store.dart`, add the imports:

```dart
import '../models/song_project.dart' show AudioAsset;
import '../schema/rules/songwriter_audio_rules.dart';
import 'song_playback_store.dart' show SongAudioClipSink;
import 'songwriter_audio_sink.dart';
```

Near the other sink reads in `startPlayback` (after `final drumSink = ...`), add:

```dart
    final audioSink = ref.read(songwriterAudioClipSinkProvider);
    final scheduled = songwriterSchedulableAudioClips(project)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final pendingAudioStops = <(AudioAsset, int)>[];
    await audioSink.prepare(scheduled.map((c) => c.asset));
```

Add a `tickToMs` helper using the rule and a `fireAudio` closure. Inside the tick loop, after the event-firing `while`, call it. Because the songwriter loop has no scrub/loop-region, the scheduling is monotonic and simple:

```dart
    var nextClip = 0;
    void fireAudio(int tick) {
      final nowMs = songwriterAudioTickToMs(tick, cfg);
      while (nextClip < scheduled.length && scheduled[nextClip].startMs <= nowMs) {
        final clip = scheduled[nextClip++];
        unawaited(audioSink.startClip(
          asset: clip.asset,
          offsetMs: clip.offsetIntoAsset(nowMs).clamp(0, clip.asset.durationMs),
          volume: clip.volume,
          loop: clip.loop,
        ));
        pendingAudioStops.add((clip.asset, clip.endMs));
      }
      pendingAudioStops.removeWhere((p) {
        if (p.$2 <= nowMs) {
          unawaited(audioSink.stopClip(asset: p.$1));
          return true;
        }
        return false;
      });
    }
```

Call `fireAudio(tick);` inside the loop right after the existing event `while (eventIndex < events.length ...)` block. After the loop completes (both the early-return paths in `stopPlayback` and the natural completion), ensure all clips stop: in `stopPlayback()` add `unawaited(ref.read(songwriterAudioClipSinkProvider).stopAll());`, and after the `for` loop ends naturally add:

```dart
    for (final p in pendingAudioStops) {
      unawaited(audioSink.stopClip(asset: p.$1));
    }
```

> `cfg` is already in scope in `startPlayback` (`final cfg = project.config;`). Place `fireAudio` after `cfg`/`measureTicks` are defined. Keep `unawaited` imported (already used in the file).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_audio_playback_test.dart`
Expected: PASS — a1 started with `loop=true` and later stopped.

- [ ] **Step 5: Run the songwriter playback suite for regressions**

Run: `flutter test test/store/songwriter_playback_store_test.dart test/store/songwriter_audio_playback_test.dart`
Expected: PASS — note/drum/metronome scheduling unchanged.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/store/songwriter_playback_store.dart test/store/songwriter_audio_playback_test.dart
flutter analyze lib/store/songwriter_playback_store.dart
git add lib/store/songwriter_playback_store.dart test/store/songwriter_audio_playback_test.dart
git commit -m "feat(songwriter): schedule audio clips on the transport"
```

---

### Task 5: Verification gate

- [ ] **Step 1: Full audio test set**

Run:
```bash
flutter test \
  test/schema/rules/songwriter_audio_rules_test.dart \
  test/store/songwriter_audio_playback_test.dart \
  test/store/song_playback_store_test.dart \
  test/store/songwriter_playback_store_test.dart
```
Expected: all PASS.

- [ ] **Step 2: Analyze touched files**

Run: `flutter analyze lib/store lib/schema/rules/songwriter_audio_rules.dart`
Expected: no new issues.

- [ ] **Step 3: Device smoke**

On a device: a section with a recorded loop clip → press play → the clip loops under the metronome/chords and stops at its span end; a one-shot clip plays once. Confirm note/drum lanes still sound.

---

## Self-Review

**Spec coverage (P3 = M5 playback):** `loop` flag on the sink ✓ (T1); flatten across section repeats + tick→ms + loop/one-shot end bounds ✓ (T2); sink provider + production wiring ✓ (T3); transport scheduling + stopAll on stop ✓ (T4). Stretch plays source one-shot now; the `usesStretched` branch in T2 is ready for Plan 4 to populate `stretchedAssetId`. Drift risk accepted per spec Risk 3.

**Placeholder scan:** No "TBD"/"handle later". The "rename `_NoopAudioSink`" and "confirm `loadProject` seed path" notes are concrete instructions with fallbacks.

**Type consistency:** `SongAudioClipSink.startClip(..., bool loop)` matches across T1 interface, T1 noop, T1 production sink, T4 fake sink, and T4 call site. `SongwriterScheduledClip` fields (`asset`/`startMs`/`endMs`/`trimStartMs`/`loop`/`volume`/`offsetIntoAsset`) match between T2 definition and T4 usage. `songwriterAudioClipSinkProvider` / `songwriterSchedulableAudioClips` / `songwriterAudioTickToMs` names are identical across T2–T4.
