# Songwriter Audio Sampler — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure data layer for the Songwriter audio sampler — a new `audio` lane kind, an `AudioClip` content type (trim + fit mode + stretch ref + chord segments), project-level asset/clip lists, isolated file storage, and the store CRUD ops — all unit-tested, with no UI or audio-device dependencies yet.

**Architecture:** Mirror the existing drum lane: a `SongLaneKind.audio` whose `SongBlock` carries an `audioClipId` referencing a project-level `AudioClip` list on `SongwriterProjectSnapshot` (exactly as drum blocks reference `drumPatterns`). Reuse the Song feature's `AudioAsset` and `SongAudioRepository`, extending the repository with a per-feature subdirectory so orphan reconcile in one feature can never delete the other's files.

**Tech Stack:** Dart, Flutter, Riverpod (`Notifier`), immutable models with `copyWith`/`toJson`/`fromJson`, `package:test` / `flutter_test`, `uuid` (via existing `generateId()`).

This is **Plan 1 of 5** for the audio sampler (spec: `docs/superpowers/specs/2026-06-25-songwriter-audio-sampler-design.md`). Later plans: P2 record/import + sheet lane, P3 transport playback, P4 clip editor + WSOLA stretch, P5 chord segments. The model types defined here are complete (incl. fields P4/P5 will populate) so there is exactly one JSON migration.

Reference files (read before starting):
- `lib/models/songwriter.dart` — `SongBlock`, `SongLane`, `SongLaneKind`, `SongwriterProjectSnapshot`.
- `lib/models/song_project.dart:370` — `AudioAsset` (reused as-is).
- `lib/schema/rules/songwriter_rules.dart:131` — `makeLane` / `makeDrumBlock` / `makeDrumPattern` (factory pattern + `generateId()`).
- `lib/store/songwriter_store.dart:413` — `addDrumPattern` / `addDrumBlock` / `removeDrumPattern` / `_set` / `_replaceLane` (store-op pattern).
- `lib/store/song_audio_repository.dart` — repository to extend with a `subdir`.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/models/songwriter.dart` | `AudioFitMode`, `ChordSegment`, `AudioClip` types; `SongLaneKind.audio`; `SongBlock.audioClipId`; snapshot `audioAssets`/`audioClips`; `selectedNotes` includes segment notes | Modify |
| `lib/schema/rules/songwriter_rules.dart` | `makeAudioClip` / `makeAudioBlock` factories | Modify |
| `lib/store/song_audio_repository.dart` | Optional `subdir` (default `song_audio`); `songwriterAudioRepositoryProvider` (`songwriter_audio`) | Modify |
| `lib/store/songwriter_store.dart` | `addAudioClip` / `addAudioBlock` / `removeAudioBlock` / `updateAudioClip` / `setClipFitMode` / `setClipTrim` | Modify |
| `test/models/songwriter_audio_test.dart` | Model JSON round-trip + defaults + `selectedNotes` | Create |
| `test/schema/rules/songwriter_audio_factories_test.dart` | Factory output | Create |
| `test/store/song_audio_repository_subdir_test.dart` | Subdir write + reconcile isolation | Create |
| `test/store/songwriter_audio_store_test.dart` | Store CRUD | Create |

---

### Task 1: Model types — enums, `ChordSegment`, `AudioClip`, `SongBlock.audioClipId`, snapshot lists

**Files:**
- Modify: `lib/models/songwriter.dart`
- Test: `test/models/songwriter_audio_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/models/songwriter_audio_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  group('SongLaneKind.audio', () {
    test('round-trips through name', () {
      final lane = SongLane(id: 'l1', kind: SongLaneKind.audio, order: 0);
      final back = SongLane.fromJson(lane.toJson());
      expect(back.kind, SongLaneKind.audio);
    });
  });

  group('SongBlock.audioClipId', () {
    test('round-trips and clears', () {
      const block = SongBlock(
        id: 'b1', startBar: 0, spanBars: 2, audioClipId: 'clip1',
      );
      expect(SongBlock.fromJson(block.toJson()).audioClipId, 'clip1');
      expect(block.copyWith(clearAudioClipId: true).audioClipId, isNull);
    });
  });

  group('ChordSegment', () {
    test('round-trips a harmony pick', () {
      const seg = ChordSegment(
        id: 's1', startTick: 0, spanTicks: 480,
        chordSymbol: 'C', chordQuality: 'maj', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      );
      final back = ChordSegment.fromJson(seg.toJson());
      expect(back.chordSymbol, 'C');
      expect(back.chordNotes, ['C', 'E', 'G']);
      expect(back.romanNumeral, 'I');
      expect(back.saveId, isNull);
    });

    test('round-trips a save reference', () {
      const seg = ChordSegment(
        id: 's2', startTick: 480, spanTicks: 480, saveId: 'save9',
      );
      expect(ChordSegment.fromJson(seg.toJson()).saveId, 'save9');
    });
  });

  group('AudioClip', () {
    test('round-trips with defaults', () {
      const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000);
      final back = AudioClip.fromJson(clip.toJson());
      expect(back.assetId, 'a1');
      expect(back.trimStartMs, 0);
      expect(back.trimEndMs, 4000);
      expect(back.fitMode, AudioFitMode.loop);
      expect(back.stretchedAssetId, isNull);
      expect(back.segments, isEmpty);
    });

    test('round-trips stretch + segments', () {
      const clip = AudioClip(
        id: 'c2', assetId: 'a2', trimStartMs: 100, trimEndMs: 3000,
        fitMode: AudioFitMode.stretch, stretchedAssetId: 'a2s',
        segments: [ChordSegment(id: 's1', startTick: 0, spanTicks: 240, saveId: 'x')],
      );
      final back = AudioClip.fromJson(clip.toJson());
      expect(back.fitMode, AudioFitMode.stretch);
      expect(back.stretchedAssetId, 'a2s');
      expect(back.segments.single.saveId, 'x');
    });
  });

  group('SongwriterProjectSnapshot audio lists', () {
    test('round-trip and legacy default to empty', () {
      const snap = SongwriterProjectSnapshot(
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        audioAssets: [AudioAsset(
          id: 'a1', durationMs: 4000, sampleRate: 44100, channels: 1,
          format: 'wav', peaks: [1, 2, 3], sourceLabel: 'Recording',
        )],
        audioClips: [AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000)],
      );
      final back = SongwriterProjectSnapshot.fromJson(snap.toJson());
      expect(back.audioAssets.single.id, 'a1');
      expect(back.audioClips.single.assetId, 'a1');

      final legacy = SongwriterProjectSnapshot.fromJson({
        'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
      });
      expect(legacy.audioAssets, isEmpty);
      expect(legacy.audioClips, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/songwriter_audio_test.dart`
Expected: FAIL — `AudioFitMode`, `ChordSegment`, `AudioClip` undefined; `audioClipId` / `clearAudioClipId` / `audioAssets` / `audioClips` not members.

- [ ] **Step 3: Add the `audio` enum case and import `AudioAsset`**

In `lib/models/songwriter.dart`, the `song_project.dart` import already exists (`import 'song_project.dart';`) — it brings in `AudioAsset`. Extend the lane-kind enum:

```dart
enum SongLaneKind { harmony, save, drum, audio }
```

Add the fit-mode enum and its parser just below it:

```dart
enum AudioFitMode { loop, oneShot, stretch }

AudioFitMode _fitModeFromName(String? raw) {
  for (final v in AudioFitMode.values) {
    if (v.name == raw) return v;
  }
  return AudioFitMode.loop;
}
```

- [ ] **Step 4: Add the `ChordSegment` type**

Add to `lib/models/songwriter.dart` (above `SongBlock`):

```dart
/// A silent, beat-quantized chord annotation inside an [AudioClip].
///
/// Positions are clip-local ticks (multiples of the config's ticksPerBeat).
/// Carries either a harmony pick (chord* fields) or a [saveId] reference.
class ChordSegment {
  final String id;
  final int startTick;
  final int spanTicks;
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;
  final String? saveId;

  const ChordSegment({
    required this.id,
    required this.startTick,
    required this.spanTicks,
    this.chordSymbol,
    this.chordQuality,
    this.chordRootPc,
    this.chordNotes = const [],
    this.romanNumeral,
    this.saveId,
  });

  ChordSegment copyWith({
    int? startTick,
    int? spanTicks,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String>? chordNotes,
    String? romanNumeral,
    String? saveId,
    bool clearRomanNumeral = false,
    bool clearSaveId = false,
  }) => ChordSegment(
    id: id,
    startTick: startTick ?? this.startTick,
    spanTicks: spanTicks ?? this.spanTicks,
    chordSymbol: chordSymbol ?? this.chordSymbol,
    chordQuality: chordQuality ?? this.chordQuality,
    chordRootPc: chordRootPc ?? this.chordRootPc,
    chordNotes: chordNotes ?? this.chordNotes,
    romanNumeral: clearRomanNumeral ? null : (romanNumeral ?? this.romanNumeral),
    saveId: clearSaveId ? null : (saveId ?? this.saveId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTick': startTick,
    'spanTicks': spanTicks,
    'chordSymbol': chordSymbol,
    'chordQuality': chordQuality,
    'chordRootPc': chordRootPc,
    'chordNotes': chordNotes,
    'romanNumeral': romanNumeral,
    'saveId': saveId,
  };

  factory ChordSegment.fromJson(Map<String, dynamic> json) => ChordSegment(
    id: json['id'] as String,
    startTick: json['startTick'] as int? ?? 0,
    spanTicks: json['spanTicks'] as int? ?? 0,
    chordSymbol: json['chordSymbol'] as String?,
    chordQuality: json['chordQuality'] as String?,
    chordRootPc: json['chordRootPc'] as int?,
    chordNotes:
        (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
        const [],
    romanNumeral: json['romanNumeral'] as String?,
    saveId: json['saveId'] as String?,
  );
}
```

- [ ] **Step 5: Add the `AudioClip` type**

Add to `lib/models/songwriter.dart` (below `ChordSegment`):

```dart
/// Content for an audio-lane block: a reference to a recorded/imported
/// [AudioAsset] plus how it adapts to its bar span.
///
/// Referenced 1:1 by an audio [SongBlock] via [SongBlock.audioClipId], the same
/// way a drum block references a [DrumPattern]. The used region is
/// [trimStartMs]..[trimEndMs] of the source; [fitMode] decides how that region
/// fills the block's bars. When [fitMode] is [AudioFitMode.stretch] and a
/// pre-rendered asset exists, [stretchedAssetId] points at it.
class AudioClip {
  final String id;
  final String assetId;
  final int trimStartMs;
  final int trimEndMs;
  final AudioFitMode fitMode;
  final String? stretchedAssetId;
  final List<ChordSegment> segments;

  const AudioClip({
    required this.id,
    required this.assetId,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.fitMode = AudioFitMode.loop,
    this.stretchedAssetId,
    this.segments = const [],
  });

  AudioClip copyWith({
    String? assetId,
    int? trimStartMs,
    int? trimEndMs,
    AudioFitMode? fitMode,
    String? stretchedAssetId,
    List<ChordSegment>? segments,
    bool clearStretchedAssetId = false,
  }) => AudioClip(
    id: id,
    assetId: assetId ?? this.assetId,
    trimStartMs: trimStartMs ?? this.trimStartMs,
    trimEndMs: trimEndMs ?? this.trimEndMs,
    fitMode: fitMode ?? this.fitMode,
    stretchedAssetId:
        clearStretchedAssetId ? null : (stretchedAssetId ?? this.stretchedAssetId),
    segments: segments ?? this.segments,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetId': assetId,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'fitMode': fitMode.name,
    'stretchedAssetId': stretchedAssetId,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
    id: json['id'] as String,
    assetId: json['assetId'] as String,
    trimStartMs: json['trimStartMs'] as int? ?? 0,
    trimEndMs: json['trimEndMs'] as int? ?? 0,
    fitMode: _fitModeFromName(json['fitMode'] as String?),
    stretchedAssetId: json['stretchedAssetId'] as String?,
    segments:
        (json['segments'] as List?)
            ?.map((s) => ChordSegment.fromJson(s as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
```

- [ ] **Step 6: Add `audioClipId` to `SongBlock`**

In `SongBlock`, add the field after `patternId`:

```dart
  // audio-lane reference into SongwriterProjectSnapshot.audioClips
  final String? audioClipId;
```

Add `this.audioClipId,` to the constructor. In `copyWith`, add the parameter `String? audioClipId,` and `bool clearAudioClipId = false,`, and in the returned `SongBlock` add:

```dart
    audioClipId: clearAudioClipId ? null : (audioClipId ?? this.audioClipId),
```

In `toJson` add `'audioClipId': audioClipId,`. In `fromJson` add `audioClipId: json['audioClipId'] as String?,`.

- [ ] **Step 7: Add `audioAssets` / `audioClips` to the snapshot + segment notes in `selectedNotes`**

In `SongwriterProjectSnapshot`, add fields:

```dart
  final List<AudioAsset> audioAssets;
  final List<AudioClip> audioClips;
```

Constructor: add `this.audioAssets = const [],` and `this.audioClips = const [],`.

In `selectedNotes`, after the existing block loop, union segment chord notes:

```dart
    for (final clip in audioClips) {
      for (final seg in clip.segments) {
        set.addAll(seg.chordNotes);
      }
    }
```

`copyWith`: add `List<AudioAsset>? audioAssets,` and `List<AudioClip>? audioClips,` params and pass `audioAssets: audioAssets ?? this.audioAssets,` / `audioClips: audioClips ?? this.audioClips,`.

`toJson`: add `'audioAssets': audioAssets.map((a) => a.toJson()).toList(),` and `'audioClips': audioClips.map((c) => c.toJson()).toList(),`.

`fromJson`: add

```dart
        audioAssets:
            (json['audioAssets'] as List?)
                ?.map((a) => AudioAsset.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        audioClips:
            (json['audioClips'] as List?)
                ?.map((c) => AudioClip.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/models/songwriter_audio_test.dart`
Expected: PASS (all groups).

- [ ] **Step 9: Format + analyze**

Run: `dart format lib/models/songwriter.dart test/models/songwriter_audio_test.dart && flutter analyze lib/models/songwriter.dart test/models/songwriter_audio_test.dart`
Expected: no issues.

- [ ] **Step 10: Commit**

```bash
git add lib/models/songwriter.dart test/models/songwriter_audio_test.dart
git commit -m "feat(songwriter): audio lane model — AudioClip, ChordSegment, snapshot lists"
```

---

### Task 2: Rules factories — `makeAudioClip`, `makeAudioBlock`

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart`
- Test: `test/schema/rules/songwriter_audio_factories_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/songwriter_audio_factories_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('makeAudioClip sets full-region trim + loop default', () {
    final clip = makeAudioClip(assetId: 'a1', durationMs: 4000);
    expect(clip.id, isNotEmpty);
    expect(clip.assetId, 'a1');
    expect(clip.trimStartMs, 0);
    expect(clip.trimEndMs, 4000);
    expect(clip.fitMode, AudioFitMode.loop);
    expect(clip.segments, isEmpty);
  });

  test('makeAudioBlock carries the clip id and placement', () {
    final block = makeAudioBlock(audioClipId: 'c1', startBar: 1, spanBars: 2);
    expect(block.id, isNotEmpty);
    expect(block.audioClipId, 'c1');
    expect(block.startBar, 1);
    expect(block.spanBars, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_audio_factories_test.dart`
Expected: FAIL — `makeAudioClip` / `makeAudioBlock` undefined.

- [ ] **Step 3: Add the factories**

In `lib/schema/rules/songwriter_rules.dart`, just after `makeDrumBlock` (around line 209):

```dart
AudioClip makeAudioClip({
  required String assetId,
  required int durationMs,
}) => AudioClip(
  id: generateId(),
  assetId: assetId,
  trimStartMs: 0,
  trimEndMs: durationMs,
);

SongBlock makeAudioBlock({
  required String audioClipId,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  audioClipId: audioClipId,
);
```

(`AudioClip` and `AudioFitMode` come from the already-imported `models/songwriter.dart`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_audio_factories_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_audio_factories_test.dart
flutter analyze lib/schema/rules/songwriter_rules.dart
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_audio_factories_test.dart
git commit -m "feat(songwriter): makeAudioClip / makeAudioBlock factories"
```

---

### Task 3: Repository subdirectory isolation + `songwriterAudioRepositoryProvider`

**Files:**
- Modify: `lib/store/song_audio_repository.dart`
- Test: `test/store/song_audio_repository_subdir_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/store/song_audio_repository_subdir_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('repo_subdir_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('subdir scopes files and reconcile to one feature', () async {
    final songRepo =
        SongAudioRepository.testWith(rootDirectory: tmp, subdir: 'song_audio');
    final writerRepo = SongAudioRepository.testWith(
        rootDirectory: tmp, subdir: 'songwriter_audio');

    // A 100ms mono 44.1k silence WAV.
    final wav = buildWavBytes(
      samples: List<int>.filled(4410, 0), sampleRate: 44100, channels: 1);

    final a = await songRepo.writeRecording(wav);
    final b = await writerRepo.writeRecording(wav);

    // Each lands in its own subfolder.
    expect(File('${tmp.path}/song_audio/${a.id}.wav').existsSync(), isTrue);
    expect(File('${tmp.path}/songwriter_audio/${b.id}.wav').existsSync(), isTrue);

    // Reconciling the writer repo with NO referenced ids deletes only b.
    final result = await writerRepo.reconcileOrphans(referencedAssetIds: {});
    expect(result.deletedAssetIds, [b.id]);
    expect(File('${tmp.path}/song_audio/${a.id}.wav').existsSync(), isTrue);
    expect(File('${tmp.path}/songwriter_audio/${b.id}.wav').existsSync(), isFalse);
  });
}
```

> Note: confirm the WAV builder helper in `lib/utils/wav_writer.dart` is named `buildWavBytes` with this signature. If it differs, read `wav_writer.dart` and adjust the call (the test only needs any valid mono WAV).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_repository_subdir_test.dart`
Expected: FAIL — `testWith` has no `subdir` parameter.

- [ ] **Step 3: Add the `subdir` parameter**

In `lib/store/song_audio_repository.dart`, thread a subdirectory name through the constructor and `_root()`:

```dart
class SongAudioRepository {
  final Directory? _rootOverride;
  final String _subdir;
  final Uuid _uuid;
  Directory? _rootCache;

  SongAudioRepository._({Directory? root, String? subdir, Uuid? uuid})
    : _rootOverride = root,
      _subdir = subdir ?? 'song_audio',
      _uuid = uuid ?? const Uuid();

  factory SongAudioRepository.production({String? subdir}) =>
      SongAudioRepository._(subdir: subdir);

  factory SongAudioRepository.testWith({
    required Directory rootDirectory,
    String? subdir,
  }) => SongAudioRepository._(root: rootDirectory, subdir: subdir);
```

Update `_root()` so both the override and the production path use the subdir:

```dart
  Future<Directory> _root() async {
    final override = _rootOverride;
    if (override != null) {
      final dir = Directory(p.join(override.path, _subdir));
      if (!dir.existsSync()) await dir.create(recursive: true);
      return dir;
    }
    final cached = _rootCache;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    _rootCache = dir;
    return dir;
  }
```

> This changes the test-override layout from `<root>/` to `<root>/<subdir>/`. Existing repository tests that used `testWith(rootDirectory: tmp)` and read files directly at `tmp/<id>.wav` must update their paths to `tmp/song_audio/<id>.wav`. After Step 5, run the full repository test file and fix any such path assertions.

- [ ] **Step 4: Add the songwriter provider**

At the bottom of `lib/store/song_audio_repository.dart`, beside `songAudioRepositoryProvider`:

```dart
/// Repository for Songwriter audio, isolated in its own `songwriter_audio/`
/// subfolder so its orphan reconcile never touches the Song feature's files.
final songwriterAudioRepositoryProvider = Provider<SongAudioRepository>((ref) {
  return SongAudioRepository.production(subdir: 'songwriter_audio');
});
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/store/song_audio_repository_subdir_test.dart test/store/song_audio_repository_test.dart`
Expected: PASS. If the pre-existing `song_audio_repository_test.dart` fails on file paths, update those assertions to include `/song_audio/` and re-run.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/store/song_audio_repository.dart test/store/song_audio_repository_subdir_test.dart
flutter analyze lib/store/song_audio_repository.dart
git add lib/store/song_audio_repository.dart test/store/song_audio_repository_subdir_test.dart test/store/song_audio_repository_test.dart
git commit -m "feat(audio): per-feature subdir + songwriterAudioRepositoryProvider"
```

---

### Task 4: Store CRUD — clips and audio blocks

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_audio_store_test.dart`

The store methods mirror the drum equivalents (`addDrumPattern` / `addDrumBlock` / `removeDrumPattern` at `songwriter_store.dart:413`), using the existing `_set(state.copyWith(...))` persistence helper.

- [ ] **Step 1: Write the failing test**

Create `test/store/songwriter_audio_store_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  SongwriterStoreApi store() => c.read(songwriterProvider.notifier);

  String seedSectionWithAudioLane() {
    store().addSection(label: 'A', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store().addLane(sectionId: sectionId, kind: SongLaneKind.audio, label: 'Sample');
    return sectionId;
  }

  test('addAudioClip appends a clip and returns its id', () {
    seedSectionWithAudioLane();
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    final clip = c.read(songwriterProvider).audioClips.single;
    expect(clip.id, clipId);
    expect(clip.assetId, 'a1');
    expect(clip.trimEndMs, 4000);
    expect(clip.fitMode, AudioFitMode.loop);
  });

  test('addAudioBlock places a block on the audio lane', () {
    final sectionId = seedSectionWithAudioLane();
    final laneId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).id;
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    store().addAudioBlock(
      sectionId: sectionId, laneId: laneId, audioClipId: clipId,
      startBar: 0, spanBars: 2);
    final block = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).blocks.single;
    expect(block.audioClipId, clipId);
    expect(block.spanBars, 2);
  });

  test('setClipFitMode and setClipTrim mutate the clip', () {
    seedSectionWithAudioLane();
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    store().setClipFitMode(clipId: clipId, fitMode: AudioFitMode.oneShot);
    store().setClipTrim(clipId: clipId, trimStartMs: 250, trimEndMs: 3500);
    final clip = c.read(songwriterProvider).audioClips.single;
    expect(clip.fitMode, AudioFitMode.oneShot);
    expect(clip.trimStartMs, 250);
    expect(clip.trimEndMs, 3500);
  });

  test('removeAudioBlock drops the block and its clip', () {
    final sectionId = seedSectionWithAudioLane();
    final laneId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).id;
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    store().addAudioBlock(
      sectionId: sectionId, laneId: laneId, audioClipId: clipId,
      startBar: 0, spanBars: 2);
    final blockId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).blocks.single.id;

    store().removeAudioBlock(sectionId: sectionId, laneId: laneId, blockId: blockId);

    final lane = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio);
    expect(lane.blocks, isEmpty);
    expect(c.read(songwriterProvider).audioClips, isEmpty);
  });
}
```

> The test references the notifier type as `SongwriterStoreApi`. Read the top of `lib/store/songwriter_store.dart` and replace `SongwriterStoreApi` with the actual notifier class name (e.g. `SongwriterNotifier`). The `songwriterProvider` instantiates without a selected project (empty section list) — `addSection` seeds one, matching existing store tests; if the store rejects edits without a selected project, mirror the setup used in the existing `test/store/songwriter_store_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_audio_store_test.dart`
Expected: FAIL — `addAudioClip` / `addAudioBlock` / `setClipFitMode` / `setClipTrim` / `removeAudioBlock` undefined.

- [ ] **Step 3: Add the store methods**

In `lib/store/songwriter_store.dart`, after `addDrumBlock` (around line 475), add. Ensure `makeAudioClip` / `makeAudioBlock` are in scope (they live in the already-imported `songwriter_rules.dart`):

```dart
  // ── audio clips ──
  String addAudioClip({required String assetId, required int durationMs}) {
    final clip = makeAudioClip(assetId: assetId, durationMs: durationMs);
    _set(state.copyWith(audioClips: [...state.audioClips, clip]));
    return clip.id;
  }

  void updateAudioClip(AudioClip updated) {
    _set(
      state.copyWith(
        audioClips: state.audioClips
            .map((c) => c.id == updated.id ? updated : c)
            .toList(),
      ),
    );
  }

  void setClipFitMode({required String clipId, required AudioFitMode fitMode}) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(clip.copyWith(fitMode: fitMode));
  }

  void setClipTrim({
    required String clipId,
    required int trimStartMs,
    required int trimEndMs,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(
      clip.copyWith(
        trimStartMs: trimStartMs < 0 ? 0 : trimStartMs,
        trimEndMs: trimEndMs < trimStartMs ? trimStartMs : trimEndMs,
      ),
    );
  }

  void addAudioBlock({
    required String sectionId,
    required String laneId,
    required String audioClipId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      if (l.kind != SongLaneKind.audio) return l;
      final candidate = makeAudioBlock(
        audioClipId: audioClipId,
        startBar: startBar,
        spanBars: spanBars,
      );
      if (blocksOverlap(l.blocks, candidate)) return l; // ignore overlaps
      return l.copyWith(blocks: [...l.blocks, candidate]);
    });
  }

  /// Removes an audio block and its 1:1 clip. The underlying asset file is
  /// reclaimed by the load-time orphan reconcile (see SongAudioRepository).
  void removeAudioBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
  }) {
    final lane = state.sections
        .where((s) => s.id == sectionId)
        .expand((s) => s.lanes)
        .where((l) => l.id == laneId)
        .firstOrNull;
    final clipId =
        lane?.blocks.where((b) => b.id == blockId).firstOrNull?.audioClipId;
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(blocks: l.blocks.where((b) => b.id != blockId).toList()),
    );
    if (clipId != null) {
      _set(
        state.copyWith(
          audioClips: state.audioClips.where((c) => c.id != clipId).toList(),
        ),
      );
    }
  }
```

> `firstOrNull` comes from `package:collection`, already used across the stores. If the analyzer reports it missing, add `import 'package:collection/collection.dart';` at the top of the file (check whether it is already imported first).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_audio_store_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 5: Run the full songwriter store + model suite for regressions**

Run: `flutter test test/store/songwriter_store_test.dart test/models/songwriter_audio_test.dart`
Expected: PASS — confirms the new snapshot fields did not break existing serialization.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/store/songwriter_store.dart test/store/songwriter_audio_store_test.dart
flutter analyze lib/store/songwriter_store.dart
git add lib/store/songwriter_store.dart test/store/songwriter_audio_store_test.dart
git commit -m "feat(songwriter): audio clip + block store CRUD"
```

---

### Task 5: Foundation verification gate

**Files:** none (verification only)

- [ ] **Step 1: Run the full audio-foundation test set**

Run:
```bash
flutter test \
  test/models/songwriter_audio_test.dart \
  test/schema/rules/songwriter_audio_factories_test.dart \
  test/store/song_audio_repository_subdir_test.dart \
  test/store/songwriter_audio_store_test.dart
```
Expected: all PASS.

- [ ] **Step 2: Analyze the whole package**

Run: `flutter analyze`
Expected: no new issues in the files touched by this plan (`lib/models/songwriter.dart`, `lib/schema/rules/songwriter_rules.dart`, `lib/store/song_audio_repository.dart`, `lib/store/songwriter_store.dart`).

- [ ] **Step 3: Run the broader save/serialization suite for migration safety**

Run: `flutter test test/store test/models`
Expected: PASS — legacy songwriter JSON still loads (new lists default to empty), and no other store regressions.

- [ ] **Step 4: Final commit (if any format-only changes remain)**

```bash
git add -A
git commit -m "chore(songwriter): audio foundation verification gate" --allow-empty
```

---

## Self-Review

**Spec coverage (P1 = M1 only):**
- Model: `SongLaneKind.audio`, `AudioFitMode`, `AudioClip` (trim + fitMode + stretchedAssetId + segments), `ChordSegment`, `SongBlock.audioClipId`, snapshot `audioAssets`/`audioClips` → Task 1. ✓
- `selectedNotes` feeds segment notes (Decision 4) → Task 1 Step 7. ✓
- Factories → Task 2. ✓
- File isolation `songwriter_audio/` + scoped reconcile (Decision 8 / Risk 4) → Task 3. ✓
- Store CRUD → Task 4. ✓
- Migration safety (legacy defaults) → Task 1 test + Task 5 Step 3. ✓
- Out of P1 (later plans): record/import (P2), sheet lane UI (P2), transport playback (P3), trim/fit UI + WSOLA stretch (P4), segment editor (P5). Stretch/segment *fields* exist now to avoid a second migration; their *behavior* is later.

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Two explicit "confirm the real symbol name" notes (the WAV builder helper name in Task 3; the notifier class name in Task 4) — these are verification instructions with a concrete fallback, not unfilled blanks.

**Type consistency:** `AudioClip` / `ChordSegment` / `AudioFitMode` field and method names are identical across Tasks 1, 2, 4 (`assetId`, `trimStartMs`, `trimEndMs`, `fitMode`, `stretchedAssetId`, `segments`; `clearAudioClipId`, `clearStretchedAssetId`). Store methods (`addAudioClip`, `addAudioBlock`, `removeAudioBlock`, `updateAudioClip`, `setClipFitMode`, `setClipTrim`) match between Task 4's implementation and its test.
