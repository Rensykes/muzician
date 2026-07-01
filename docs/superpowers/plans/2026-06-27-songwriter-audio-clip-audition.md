# Songwriter Audio Clip Audition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Alone / With-section audition transport to the Songwriter Audio Clip sheet so a recording can be played by itself or over a looping bed of the section's other lanes.

**Architecture:** A pure rule (`sectionAuditionBed`) flattens a section's harmony + save + drum lanes into tick-indexed maps; a dedicated looping `Notifier` (`SongwriterAudioAuditionNotifier`, cloned from the drum audition store) drives the existing injectable note/drum/audio sinks; the clip sheet gains a Play/Stop + mode-toggle row. The audition and the main project transport are mutually exclusive.

**Tech Stack:** Dart, Flutter, Riverpod (Notifier/Provider), `flutter_test`. Spec: `docs/superpowers/specs/2026-06-27-songwriter-audio-clip-audition-design.md`.

---

## File Structure

- Modify `lib/schema/rules/songwriter_playback_rules.dart` — add `sectionAuditionBed`; extract a private harmony/save tiling helper shared with `sectionHarmonyLoop`.
- Create `lib/store/songwriter_audio_audition_store.dart` — audition transport notifier + state + provider.
- Modify `lib/store/songwriter_playback_store.dart` — stop a running audition when project playback starts.
- Modify `lib/features/songwriter/songwriter_audio_clip_sheet.dart` — transport row UI; stop audition on sheet dispose.
- Create `test/schema/rules/songwriter_audition_bed_test.dart`.
- Create `test/store/songwriter_audio_audition_store_test.dart`.

---

## Reference: existing signatures used by this plan

```dart
// lib/store/song_playback_store.dart — the audio sink interface
abstract class SongAudioClipSink {
  Future<void> prepare(Iterable<AudioAsset> assets);
  Future<void> startClip({required AudioAsset asset, required int offsetMs,
      double volume = 1.0, bool loop = false});
  Future<void> stopClip({required AudioAsset asset});
  Future<void> stopAll();
}

// lib/store/songwriter_audio_sink.dart
final songwriterAudioClipSinkProvider = Provider<SongAudioClipSink>(...);

// lib/store/songwriter_playback_store.dart
typedef SongwriterNoteSink = void Function(List<int> midiNotes);
final songwriterNoteSinkProvider = Provider<SongwriterNoteSink>(...);

// lib/store/drum_pattern_playback_store.dart
typedef DrumPatternPlaybackSink = Future<void> Function(List<DrumLaneId> lanes, double volume);
final drumPatternPlaybackSinkProvider = Provider<DrumPatternPlaybackSink>(...);

// lib/utils/tick_pacer.dart
final pacer = TickPacer(tickDuration);   // await pacer.awaitBoundary(elapsedTicks);

// lib/schema/rules/piano_roll_playback_rules.dart
rules.tickDuration(tempo)  // Duration per tick

// lib/models/songwriter.dart — SongwriterConfig.ticksPerBeat, .beatsPerBar, .tempo
// lib/models/song_project.dart — AudioClip.trimStartMs, AudioAsset, DrumLaneId
```

---

## Task 1: `sectionAuditionBed` rule

Adds the pure section-bed flattener and extracts the harmony/save tiling shared with `sectionHarmonyLoop`. The drum portion mirrors the drum branch of `flattenPlaybackEvents` (lines 160-178), scoped to a single section indexed from tick 0.

**Files:**
- Modify: `lib/schema/rules/songwriter_playback_rules.dart`
- Test: `test/schema/rules/songwriter_audition_bed_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/songwriter_audition_bed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  // 4/4, ticksPerBeat=4 → measureTicks=16.
  const config = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);

  SongSection sectionWith(List<SongLane> lanes, {int lengthBars = 1}) =>
      makeSection(order: 0, lengthBars: lengthBars).copyWith(lanes: lanes);

  test('harmony + save stabs land on bar boundaries, drum lanes excluded by '
      'sectionHarmonyLoop but included by the bed', () {
    final harmony = makeLane(kind: SongLaneKind.harmony, order: 0).copyWith(
      blocks: [
        makeHarmonyBlock(startBar: 0, spanBars: 1, chordRootPc: 0,
            chordQuality: 'maj', chordNotes: const [60, 64, 67]),
      ],
    );
    final drumPattern = const DrumPattern(
      id: 'dp1', name: 'k', lengthTicks: 16,
      lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8])],
    );
    final drumLane = makeLane(kind: SongLaneKind.drum, order: 1).copyWith(
      blocks: [makeSaveBlock(startBar: 0, spanBars: 1).copyWith(patternId: 'dp1')],
    );
    final section = sectionWith([harmony, drumLane]);

    final bed = sectionAuditionBed(section, config, const [],
        drumPatterns: [drumPattern]);

    expect(bed.loopTicks, 16);
    expect(bed.notesByTick[0], containsAll(<int>[60, 64, 67]));
    expect(bed.drumByTick[0], contains(DrumLaneId.kick));
    expect(bed.drumByTick[8], contains(DrumLaneId.kick));
  });

  test('empty section yields empty maps', () {
    final bed = sectionAuditionBed(sectionWith(const []), config, const []);
    expect(bed.notesByTick, isEmpty);
    expect(bed.drumByTick, isEmpty);
    expect(bed.loopTicks, 16);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_audition_bed_test.dart`
Expected: FAIL — `sectionAuditionBed` is undefined. (If `DrumLaneSequence`/`makeSection`/`makeHarmonyBlock` field names differ, fix the test against `lib/models/songwriter.dart` and `lib/schema/rules/songwriter_rules.dart` first — do not invent fields.)

- [ ] **Step 3: Extract the shared harmony/save helper**

In `lib/schema/rules/songwriter_playback_rules.dart`, refactor `sectionHarmonyLoop` to call a private helper, keeping its existing return unchanged:

```dart
/// Per-tick harmony + save voicing stabs for one section, indexed from tick 0.
/// Drum and audio lanes are skipped. Shared by [sectionHarmonyLoop] and
/// [sectionAuditionBed].
Map<int, List<int>> _sectionChordBed(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves,
) {
  final measureTicks = config.ticksPerBeat * config.beatsPerBar;
  final notesAt = <int, List<int>>{};
  for (final lane in section.lanes) {
    if (lane.kind == SongLaneKind.drum || lane.kind == SongLaneKind.audio) {
      continue;
    }
    final blocks = tileLaneBlocks(lane, sectionLengthBars: section.lengthBars);
    for (final block in blocks) {
      final clippedEnd = block.endBar > section.lengthBars
          ? section.lengthBars
          : block.endBar;
      final pitches = lane.kind == SongLaneKind.harmony
          ? chordMidiNotes(block)
          : snapshotMidiNotes(resolveBlockSnapshot(block, saves));
      if (pitches.isEmpty) continue;
      for (var bar = block.startBar; bar < clippedEnd; bar++) {
        (notesAt[bar * measureTicks] ??= <int>[]).addAll(pitches);
      }
    }
  }
  return notesAt;
}
```

Then make `sectionHarmonyLoop` delegate:

```dart
({int loopTicks, Map<int, List<int>> notesByTick}) sectionHarmonyLoop(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves,
) {
  final measureTicks = config.ticksPerBeat * config.beatsPerBar;
  return (
    loopTicks: section.lengthBars * measureTicks,
    notesByTick: _sectionChordBed(section, config, saves),
  );
}
```

- [ ] **Step 4: Add `sectionAuditionBed`**

Append to `lib/schema/rules/songwriter_playback_rules.dart`:

```dart
/// Looping bed for the audio-clip audition's "with section" mode: the section's
/// harmony + save voicings ([notesByTick]) and drum-lane hits ([drumByTick]),
/// both indexed from tick 0, plus the section [loopTicks]. Audio lanes are
/// excluded (the audition's recording is the foreground); [excludeAudioClipId]
/// is reserved for that exclusion and is currently a no-op for the bed.
({int loopTicks, Map<int, List<int>> notesByTick, Map<int, List<DrumLaneId>> drumByTick})
sectionAuditionBed(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves, {
  List<DrumPattern> drumPatterns = const [],
  String? excludeAudioClipId,
}) {
  final measureTicks = config.ticksPerBeat * config.beatsPerBar;
  final patterns = {for (final p in drumPatterns) p.id: p};
  final drumsAt = <int, Set<DrumLaneId>>{};

  for (final lane in section.lanes) {
    if (lane.kind != SongLaneKind.drum) continue;
    for (final block in tileLaneBlocks(
      lane,
      sectionLengthBars: section.lengthBars,
    )) {
      final pattern = patterns[block.patternId];
      if (pattern == null || pattern.lengthTicks <= 0) continue;
      final clippedEnd = block.endBar > section.lengthBars
          ? section.lengthBars
          : block.endBar;
      final startTick = block.startBar * measureTicks;
      final endTick = clippedEnd * measureTicks;
      for (
        var origin = 0;
        startTick + origin < endTick;
        origin += pattern.lengthTicks
      ) {
        for (final seq in pattern.lanes) {
          for (final t in seq.activeTicks) {
            final tick = startTick + origin + t;
            if (tick >= endTick) continue;
            (drumsAt[tick] ??= <DrumLaneId>{}).add(seq.laneId);
          }
        }
      }
    }
  }

  return (
    loopTicks: section.lengthBars * measureTicks,
    notesByTick: _sectionChordBed(section, config, saves),
    drumByTick: {for (final e in drumsAt.entries) e.key: e.value.toList()},
  );
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/schema/rules/songwriter_audition_bed_test.dart`
Expected: PASS. Also run the existing rules tests to confirm the refactor is non-breaking:
Run: `flutter test test/schema/rules/songwriter_playback_rules_test.dart` (skip if the file does not exist).

- [ ] **Step 6: Commit**

```bash
git add lib/schema/rules/songwriter_playback_rules.dart test/schema/rules/songwriter_audition_bed_test.dart
git commit -m "feat(songwriter): sectionAuditionBed rule + shared chord-bed helper"
```

---

## Task 2: `SongwriterAudioAuditionNotifier` store

A looping audition transport cloned from `DrumPatternPlaybackNotifier`. Foreground is the recording (audio sink, `loop: true`); With-section additionally runs a tick loop firing the bed's note + drum events.

**Files:**
- Create: `lib/store/songwriter_audio_audition_store.dart`
- Test: `test/store/songwriter_audio_audition_store_test.dart`

- [ ] **Step 1: Write the store**

Create `lib/store/songwriter_audio_audition_store.dart`:

```dart
/// Dedicated looping audition transport for a single Songwriter audio clip.
/// Mirrors [DrumPatternPlaybackNotifier]: an injected sink per voice, a
/// [TickPacer] anchoring ticks to the wall clock, and a version counter that
/// cancels the loop. Alone mode loops the recording only; with-section mode
/// also loops the section bed under it. See
/// docs/superpowers/specs/2026-06-27-songwriter-audio-clip-audition-design.md
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_project.dart';
import '../schema/rules/piano_roll_playback_rules.dart' as rules;
import '../utils/tick_pacer.dart';
import 'drum_pattern_playback_store.dart';
import 'songwriter_audio_sink.dart';
import 'songwriter_playback_store.dart';

enum SongwriterAudioAuditionMode { alone, withSection }

enum SongwriterAudioAuditionStatus { idle, playing }

class SongwriterAudioAuditionState {
  final SongwriterAudioAuditionStatus status;
  final SongwriterAudioAuditionMode mode;
  final int? currentTick;
  const SongwriterAudioAuditionState({
    this.status = SongwriterAudioAuditionStatus.idle,
    this.mode = SongwriterAudioAuditionMode.alone,
    this.currentTick,
  });

  SongwriterAudioAuditionState copyWith({
    SongwriterAudioAuditionStatus? status,
    SongwriterAudioAuditionMode? mode,
    int? Function()? currentTick,
  }) => SongwriterAudioAuditionState(
    status: status ?? this.status,
    mode: mode ?? this.mode,
    currentTick: currentTick != null ? currentTick() : this.currentTick,
  );
}

typedef SongwriterAuditionBed = ({
  int loopTicks,
  Map<int, List<int>> notesByTick,
  Map<int, List<DrumLaneId>> drumByTick,
});

class SongwriterAudioAuditionNotifier
    extends Notifier<SongwriterAudioAuditionState> {
  int _version = 0;

  @override
  SongwriterAudioAuditionState build() => const SongwriterAudioAuditionState();

  /// Starts the audition. No-op if already playing, or if [mode] is
  /// [SongwriterAudioAuditionMode.withSection] but [bed] is null/empty.
  Future<void> start({
    required AudioAsset asset,
    required int trimStartMs,
    required int tempo,
    required SongwriterAudioAuditionMode mode,
    SongwriterAuditionBed? bed,
  }) async {
    if (state.status == SongwriterAudioAuditionStatus.playing) return;
    final withSection = mode == SongwriterAudioAuditionMode.withSection;
    if (withSection && (bed == null || bed.loopTicks <= 0)) return;

    final audioSink = ref.read(songwriterAudioClipSinkProvider);
    await audioSink.prepare([asset]);

    final version = ++_version;
    state = SongwriterAudioAuditionState(
      status: SongwriterAudioAuditionStatus.playing,
      mode: mode,
      currentTick: 0,
    );

    unawaited(audioSink.startClip(
      asset: asset,
      offsetMs: trimStartMs.clamp(0, asset.durationMs),
      loop: true,
    ));

    if (!withSection) return; // Alone: the sink loops the recording until stop().

    final noteSink = ref.read(songwriterNoteSinkProvider);
    final drumSink = ref.read(drumPatternPlaybackSinkProvider);
    final loop = bed!.loopTicks;
    final tickDuration = rules.tickDuration(tempo);
    final pacer = TickPacer(tickDuration);

    var tick = 0;
    var elapsedTicks = 0;
    while (_version == version) {
      state = state.copyWith(currentTick: () => tick);
      final notes = bed.notesByTick[tick];
      if (notes != null && notes.isNotEmpty) noteSink(notes);
      final drums = bed.drumByTick[tick];
      if (drums != null && drums.isNotEmpty) unawaited(drumSink(drums, 0.8));
      await pacer.awaitBoundary(++elapsedTicks);
      if (_version != version) return;
      tick = (tick + 1) % loop;
    }
  }

  void stop() {
    _version++;
    unawaited(ref.read(songwriterAudioClipSinkProvider).stopAll());
    state = const SongwriterAudioAuditionState();
  }

  /// Set the audition mode while idle so the chip selection persists before the
  /// user presses Play. No-op while playing (change mode by restarting instead).
  void setMode(SongwriterAudioAuditionMode mode) {
    if (state.status == SongwriterAudioAuditionStatus.playing) return;
    state = state.copyWith(mode: mode);
  }
}

final songwriterAudioAuditionProvider =
    NotifierProvider<SongwriterAudioAuditionNotifier,
        SongwriterAudioAuditionState>(SongwriterAudioAuditionNotifier.new);
```

- [ ] **Step 2: Write the failing test**

Create `test/store/songwriter_audio_audition_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_playback_store.dart'
    show SongAudioClipSink;
import 'package:muzician/store/songwriter_audio_audition_store.dart';
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';

class _FakeSink implements SongAudioClipSink {
  int startCount = 0;
  int stopAllCount = 0;
  bool? lastLoop;
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({required AudioAsset asset, required int offsetMs,
      double volume = 1.0, bool loop = false}) async {
    startCount++;
    lastLoop = loop;
  }
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async {
    stopAllCount++;
  }
}

void main() {
  const asset = AudioAsset(
    id: 'a1', sourceLabel: 'take', format: 'wav',
    durationMs: 2000, peaks: [], path: 'a1.wav',
  );

  test('alone mode starts the looping clip and fires no bed events', () async {
    final sink = _FakeSink();
    final notes = <List<int>>[];
    final drums = <List<DrumLaneId>>[];
    final container = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
      songwriterNoteSinkProvider.overrideWithValue((n) => notes.add(n)),
      drumPatternPlaybackSinkProvider
          .overrideWithValue((l, v) async => drums.add(l)),
    ]);
    addTearDown(container.dispose);

    final n = container.read(songwriterAudioAuditionProvider.notifier);
    await n.start(
      asset: asset, trimStartMs: 100, tempo: 120,
      mode: SongwriterAudioAuditionMode.alone,
    );

    expect(sink.startCount, 1);
    expect(sink.lastLoop, isTrue);
    expect(notes, isEmpty);
    expect(drums, isEmpty);

    n.stop();
    expect(sink.stopAllCount, 1);
    expect(container.read(songwriterAudioAuditionProvider).status,
        SongwriterAudioAuditionStatus.idle);
  });

  test('with-section is a no-op when the bed is empty', () async {
    final sink = _FakeSink();
    final container = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    final n = container.read(songwriterAudioAuditionProvider.notifier);
    await n.start(
      asset: asset, trimStartMs: 0, tempo: 120,
      mode: SongwriterAudioAuditionMode.withSection,
      bed: (loopTicks: 0, notesByTick: const {}, drumByTick: const {}),
    );
    expect(sink.startCount, 0);
    expect(container.read(songwriterAudioAuditionProvider).status,
        SongwriterAudioAuditionStatus.idle);
  });

  test('with-section fires bed note + drum events under the recording',
      () async {
    final sink = _FakeSink();
    final notes = <List<int>>[];
    final drums = <List<DrumLaneId>>[];
    final container = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
      songwriterNoteSinkProvider.overrideWithValue((nn) => notes.add(nn)),
      drumPatternPlaybackSinkProvider
          .overrideWithValue((l, v) async => drums.add(l)),
    ]);
    addTearDown(container.dispose);

    final n = container.read(songwriterAudioAuditionProvider.notifier);
    unawaited(n.start(
      asset: asset, trimStartMs: 0, tempo: 120,
      mode: SongwriterAudioAuditionMode.withSection,
      bed: (
        loopTicks: 16,
        notesByTick: const {0: [60, 64, 67]},
        drumByTick: const {0: [DrumLaneId.kick]},
      ),
    ));
    // Let a couple of ticks elapse, then stop.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    n.stop();

    expect(sink.startCount, 1);
    expect(sink.lastLoop, isTrue);
    expect(notes, isNotEmpty);
    expect(notes.first, containsAll(<int>[60, 64, 67]));
    expect(drums, isNotEmpty);
    expect(drums.first, contains(DrumLaneId.kick));
  });
}
```

Add `import 'dart:async';` at the top of the test for `unawaited`.

- [ ] **Step 3: Run tests to verify they pass**

Run: `flutter test test/store/songwriter_audio_audition_store_test.dart`
Expected: PASS. If `AudioAsset`'s constructor params differ (e.g. no `path`/`sourceLabel`), correct the literal against `lib/models/song_project.dart` — do not change the store.

- [ ] **Step 4: Commit**

```bash
git add lib/store/songwriter_audio_audition_store.dart test/store/songwriter_audio_audition_store_test.dart
git commit -m "feat(songwriter): looping audio-clip audition transport"
```

---

## Task 3: Mutual exclusion with the project transport

Starting project playback must stop any running audition (the reverse — audition stopping project playback — is handled in the UI, Task 4).

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart` (inside `SongwriterPlaybackNotifier.startPlayback`)

- [ ] **Step 1: Stop the audition at the top of `startPlayback`**

In `lib/store/songwriter_playback_store.dart`, add the import:

```dart
import 'songwriter_audio_audition_store.dart';
```

Then, immediately after the existing early-return guard at the start of `startPlayback`:

```dart
  Future<void> startPlayback({Duration? tickDurationOverride}) async {
    if (state.status == SongwriterPlaybackStatus.playing) return;
    ref.read(songwriterAudioAuditionProvider.notifier).stop();
```

- [ ] **Step 2: Verify the suite still compiles and passes**

Run: `flutter test test/store/songwriter_audio_playback_test.dart`
Expected: PASS (no behavioral change for the existing transport tests; `stop()` on an idle audition is a safe no-op).

- [ ] **Step 3: Commit**

```bash
git add lib/store/songwriter_playback_store.dart
git commit -m "feat(songwriter): stop audio audition when project playback starts"
```

---

## Task 4: Clip sheet transport row

Add the Play/Stop button + Alone / With-section toggle to `SongwriterAudioClipBody`, stop the audition on dispose, and stop the project transport when an audition starts.

**Files:**
- Modify: `lib/features/songwriter/songwriter_audio_clip_sheet.dart`

- [ ] **Step 1: Convert the body to a stateful consumer and add the transport row**

In `lib/features/songwriter/songwriter_audio_clip_sheet.dart`, add imports:

```dart
import '../../store/songwriter_audio_audition_store.dart';
import '../../store/songwriter_playback_store.dart';
import '../../schema/rules/songwriter_playback_rules.dart';
import '../../store/save_system_store.dart';
```

Change the class declaration:

```dart
class SongwriterAudioClipBody extends ConsumerStatefulWidget {
  const SongwriterAudioClipBody({
    super.key,
    required this.sectionId,
    required this.laneId,
    required this.clipId,
  });
  final String sectionId;
  final String laneId;
  final String clipId;

  @override
  ConsumerState<SongwriterAudioClipBody> createState() =>
      _SongwriterAudioClipBodyState();
}

class _SongwriterAudioClipBodyState
    extends ConsumerState<SongwriterAudioClipBody> {
  @override
  void dispose() {
    // Stop the audition loop so it does not keep playing after the sheet pops.
    ref.read(songwriterAudioAuditionProvider.notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionId = widget.sectionId;
    final laneId = widget.laneId;
    final clipId = widget.clipId;
    // ... existing body below uses `ref` directly (no WidgetRef param now) ...
```

Update the existing method body: replace every `ref` already in scope (it now comes from `ConsumerState`) and remove the old `WidgetRef ref` parameter usage. The lookups for `project`, `clip`, `asset`, `section`, `block`, `store`, `maxSpan`, and `rerenderIfStretch` stay identical.

- [ ] **Step 2: Insert the transport row in the Column**

Inside the `Column` children of `build`, after the span `Row` (the one with `clipSpanMinus` / `clipSpanPlus`) and before the stretch-processing indicator, add:

```dart
          const SizedBox(height: 16),
          _AuditionRow(
            asset: asset,
            trimStartMs: clip.trimStartMs,
            tempo: project.config.tempo,
            bed: () => sectionAuditionBed(
              section,
              project.config,
              ref.read(saveSystemProvider).saves,
              drumPatterns: project.drumPatterns,
              excludeAudioClipId: clipId,
            ),
          ),
```

- [ ] **Step 3: Add the `_AuditionRow` widget**

Append to the file:

```dart
class _AuditionRow extends ConsumerWidget {
  const _AuditionRow({
    required this.asset,
    required this.trimStartMs,
    required this.tempo,
    required this.bed,
  });
  final AudioAsset asset;
  final int trimStartMs;
  final int tempo;
  final SongwriterAuditionBed Function() bed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(songwriterAudioAuditionProvider);
    final n = ref.read(songwriterAudioAuditionProvider.notifier);
    final playing = state.status == SongwriterAudioAuditionStatus.playing;
    final computed = bed();
    final hasBed =
        computed.notesByTick.isNotEmpty || computed.drumByTick.isNotEmpty;

    Future<void> startWith(SongwriterAudioAuditionMode mode) async {
      // One owner of the audio sink: stop the project transport first.
      ref.read(songwriterPlaybackProvider.notifier).stopPlayback();
      n.stop();
      await n.start(
        asset: asset,
        trimStartMs: trimStartMs,
        tempo: tempo,
        mode: mode,
        bed: mode == SongwriterAudioAuditionMode.withSection ? computed : null,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('clipAuditionPlay'),
          icon: Icon(playing ? Icons.stop : Icons.play_arrow),
          onPressed: () => playing ? n.stop() : startWith(state.mode),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          key: const ValueKey('clipAuditionAlone'),
          label: const Text('Alone'),
          selected: state.mode == SongwriterAudioAuditionMode.alone,
          onSelected: (_) => playing
              ? startWith(SongwriterAudioAuditionMode.alone)
              : n.setMode(SongwriterAudioAuditionMode.alone),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          key: const ValueKey('clipAuditionWithSection'),
          label: const Text('With section'),
          selected: state.mode == SongwriterAudioAuditionMode.withSection,
          onSelected: hasBed
              ? (_) => playing
                  ? startWith(SongwriterAudioAuditionMode.withSection)
                  : n.setMode(SongwriterAudioAuditionMode.withSection)
              : null,
        ),
      ],
    );
  }
}
```

`setMode` lets the user pick a mode while idle; the selection persists until Play. When playing, tapping a chip restarts the audition in that mode via `startWith`.

- [ ] **Step 4: Run the analyzer and the existing clip-sheet widget test**

Run: `flutter analyze lib/features/songwriter/songwriter_audio_clip_sheet.dart lib/store/songwriter_audio_audition_store.dart`
Expected: No errors. (Warnings about unused imports → remove them.)

Run: `flutter test test/widget/songwriter/songwriter_audio_clip_sheet_test.dart`
Expected: PASS — the existing trim/fit/span tests still pass with the row added. If the test pumps the body directly, it must wrap with a `ProviderScope`; it already does (it tests the sheet today).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_audio_clip_sheet.dart lib/store/songwriter_audio_audition_store.dart
git commit -m "feat(songwriter): audition transport row in the audio clip sheet"
```

---

## Task 5: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS, no new failures.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: No new errors or warnings introduced by this change.

- [ ] **Step 3: Manual smoke (optional, simulator)**

Open a Songwriter project with an audio lane clip + a harmony/drum lane in the same section. Open the clip → press Play (Alone) → hear the recording loop. Switch to With section → hear the bed under it. Close the sheet → playback stops. Start the project transport → any audition stops.

- [ ] **Step 4: Commit any cleanup**

```bash
git add -A
git commit -m "chore(songwriter): audio clip audition cleanup" --allow-empty
```

---

## Self-review notes

- **Spec coverage:** `sectionAuditionBed` (Task 1) ↔ spec §1; audition transport (Task 2) ↔ §2; clip-sheet UI + dispose-stop (Task 4) ↔ §3; mutual exclusion (Task 3 + Task 4 `startWith`) ↔ spec Risks/notes; wiring (§4) needs no change because the audition store reads the already-overridden `songwriterAudioClipSinkProvider` — confirmed in Task 2's import.
- **Type consistency:** `SongwriterAuditionBed` record type is defined in Task 2 and reused by `_AuditionRow` (Task 4); its shape matches `sectionAuditionBed`'s return (Task 1). `start(...)` / `stop()` / `setMode(...)` signatures are consistent across Tasks 2 and 4.
- **Open verification during execution:** confirm exact constructor params for `AudioAsset`, `DrumPattern`, `DrumLaneSequence`, and the factory signatures `makeSection`/`makeLane`/`makeHarmonyBlock`/`makeSaveBlock` against the models before running each test; correct the test literals (not the production code) if they differ.
