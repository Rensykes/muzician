# Songwriter Audio Sampler — Plan 2: Record / Import + Sheet Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user create an `audio` lane in the Songwriter, record (count-in → record → auto-commit) or import a file into it, and see the recording as a draggable/resizable waveform clip tile on the bar grid. No transport playback yet (Plan 3), no trim/stretch editor yet (Plan 4).

**Architecture:** A project-agnostic `SongwriterAudioRecorderNotifier` (count-in blips via `NotePlayer`, finalise via `songwriterAudioRepositoryProvider`) feeds a recorder sheet that commits an `AudioClip` + audio `SongBlock` through the Plan-1 store ops. The sheet's lane rendering mirrors `_DrumLaneRow`; clip tiles reuse the Song feature's `AudioClipBody` waveform widget. Move/resize reuse the existing `setBlockPlacement` store op.

**Tech Stack:** Flutter, Riverpod, `record` (existing `SongAudioRecorderDriver`), `file_picker`, `flutter_test` (widget tests with a fake driver).

**Depends on:** Plan 1 (model + store CRUD + `songwriterAudioRepositoryProvider`). Spec: `docs/superpowers/specs/2026-06-25-songwriter-audio-sampler-design.md`.

Reference files:
- `lib/store/song_audio_recorder_store.dart` — the recorder state machine to mirror (`SongAudioRecorderStatus`, driver, `consumePendingAsset`).
- `lib/features/song/song_audio_recorder_sheet.dart` — recorder sheet UI to mirror.
- `lib/features/song/song_audio_picker_sheet.dart` — `SongAudioPickerSheet` (reused directly via callbacks).
- `lib/features/song/song_audio_clip_body.dart` — `AudioClipBody` (reused for the tile waveform).
- `lib/features/songwriter/songwriter_screen_sheet.dart:1569` — `_DrumLaneRow` (template for `_AudioLaneRow`); add-lane menu at `:601`.
- `lib/store/song_audio_recorder_driver_impl.dart` + `lib/main.dart:43` — the real driver override (`songAudioRecorderDriverProvider`, reused).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/store/songwriter_audio_recorder_store.dart` | Project-agnostic count-in→record→ready state machine | Create |
| `lib/features/songwriter/songwriter_audio_recorder_sheet.dart` | Recorder bottom sheet (mirrors Song's) | Create |
| `lib/features/songwriter/songwriter_audio_actions.dart` | `showSongwriterAudioPicker` — record/import entry + commit | Create |
| `lib/features/songwriter/songwriter_audio_lane_row.dart` | `SongwriterAudioLaneRow` clip-tile renderer | Create |
| `lib/features/songwriter/songwriter_screen_sheet.dart` | Add "Add audio lane" menu item; render audio lanes | Modify |
| `test/store/songwriter_audio_recorder_store_test.dart` | State machine with a fake driver | Create |
| `test/features/songwriter/songwriter_audio_lane_test.dart` | Lane renders a clip tile; empty-lane tap opens picker | Create |

---

### Task 1: `SongwriterAudioRecorderNotifier`

**Files:**
- Create: `lib/store/songwriter_audio_recorder_store.dart`
- Test: `test/store/songwriter_audio_recorder_store_test.dart`

This is leaner than the Song recorder: it owns no project state. It does a count-in, records, finalises to an `AudioAsset` via the songwriter repository, and exposes it via `consumePendingAsset()`. The caller chooses placement and commits.

- [ ] **Step 1: Write the failing test**

Create `test/store/songwriter_audio_recorder_store_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_recorder_store.dart'
    show SongAudioRecorderDriver, SongAudioRecorderStatus, songAudioRecorderDriverProvider;
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/songwriter_audio_recorder_store.dart';
import 'package:muzician/utils/wav_writer.dart';

class _FakeDriver implements SongAudioRecorderDriver {
  bool started = false;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async => started = true;
  @override
  Future<Uint8List> stop() async => writeWavPcm16Mono(
        Int16List.fromList(List<int>.filled(4410, 0)), sampleRate: 44100);
  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sw_rec_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('record → ready exposes a 100ms asset', () async {
    final c = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
      songwriterAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp, subdir: 'songwriter_audio')),
    ]);
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(countInMs: 0);
    expect(c.read(songwriterAudioRecorderProvider).status,
        SongAudioRecorderStatus.recording);
    await n.stop();
    expect(c.read(songwriterAudioRecorderProvider).status,
        SongAudioRecorderStatus.ready);

    final asset = n.consumePendingAsset();
    expect(asset, isNotNull);
    expect(asset!.durationMs, inInclusiveRange(90, 110));
    expect(c.read(songwriterAudioRecorderProvider).status,
        SongAudioRecorderStatus.idle);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_audio_recorder_store_test.dart`
Expected: FAIL — `songwriterAudioRecorderProvider` undefined.

- [ ] **Step 3: Implement the notifier**

Create `lib/store/songwriter_audio_recorder_store.dart`:

```dart
/// Project-agnostic count-in → record → ready state machine for the Songwriter
/// audio lane. Owns no project state: the caller commits the recorded asset.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart' show AudioAsset;
import '../utils/note_player.dart';
import 'song_audio_recorder_store.dart'
    show SongAudioRecorderDriver, SongAudioRecorderStatus, songAudioRecorderDriverProvider;
import 'song_audio_repository.dart';

class SongwriterAudioRecorderState {
  final SongAudioRecorderStatus status;
  final AudioAsset? pendingAsset;
  final String? errorMessage;
  const SongwriterAudioRecorderState({
    this.status = SongAudioRecorderStatus.idle,
    this.pendingAsset,
    this.errorMessage,
  });
  SongwriterAudioRecorderState copyWith({
    SongAudioRecorderStatus? status,
    AudioAsset? Function()? pendingAsset,
    String? Function()? errorMessage,
  }) => SongwriterAudioRecorderState(
    status: status ?? this.status,
    pendingAsset: pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

class SongwriterAudioRecorderNotifier
    extends Notifier<SongwriterAudioRecorderState> {
  @override
  SongwriterAudioRecorderState build() => const SongwriterAudioRecorderState();

  Future<void> start({int countInMs = 0}) async {
    final st = state.status;
    if (st != SongAudioRecorderStatus.idle &&
        st != SongAudioRecorderStatus.error) {
      return;
    }
    final driver = ref.read(songAudioRecorderDriverProvider);
    if (!await driver.ensurePermission()) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }
    state = const SongwriterAudioRecorderState(
        status: SongAudioRecorderStatus.countIn);
    if (countInMs > 0) {
      final beat = Duration(milliseconds: (countInMs / 4).round());
      for (var i = 0; i < 4; i++) {
        if (state.status != SongAudioRecorderStatus.countIn) return;
        NotePlayer.instance.playDrumLane(DrumLaneId.closedHiHat);
        await Future<void>.delayed(beat);
      }
    }
    if (state.status != SongAudioRecorderStatus.countIn) return;
    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    await driver.start();
  }

  Future<void> stop() async {
    if (state.status != SongAudioRecorderStatus.recording) return;
    state = state.copyWith(status: SongAudioRecorderStatus.finalising);
    final driver = ref.read(songAudioRecorderDriverProvider);
    try {
      final bytes = await driver.stop();
      final asset =
          await ref.read(songwriterAudioRepositoryProvider).writeRecording(bytes);
      state = state.copyWith(
        status: SongAudioRecorderStatus.ready,
        pendingAsset: () => asset,
      );
    } catch (e) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    }
  }

  Future<void> cancel() async {
    if (state.status == SongAudioRecorderStatus.idle) return;
    if (state.status == SongAudioRecorderStatus.recording) {
      try {
        await ref.read(songAudioRecorderDriverProvider).stop();
      } catch (_) {}
    }
    final asset = state.pendingAsset;
    if (asset != null) {
      try {
        await ref.read(songwriterAudioRepositoryProvider).delete(asset.id);
      } catch (_) {}
    }
    state = const SongwriterAudioRecorderState();
  }

  AudioAsset? consumePendingAsset() {
    final asset = state.pendingAsset;
    state = const SongwriterAudioRecorderState();
    return asset;
  }
}

final songwriterAudioRecorderProvider = NotifierProvider<
    SongwriterAudioRecorderNotifier, SongwriterAudioRecorderState>(
  SongwriterAudioRecorderNotifier.new,
);
```

> `NotePlayer.playDrumLane` and `DrumLaneId` are already used by the Song recorder (`song_audio_recorder_store.dart`); the `DrumLaneId` import resolves through `note_player.dart`'s existing export. If the analyzer cannot find `DrumLaneId`, add `import '../models/song_project.dart' show AudioAsset, DrumLaneId;`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_audio_recorder_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/store/songwriter_audio_recorder_store.dart test/store/songwriter_audio_recorder_store_test.dart
flutter analyze lib/store/songwriter_audio_recorder_store.dart
git add lib/store/songwriter_audio_recorder_store.dart test/store/songwriter_audio_recorder_store_test.dart
git commit -m "feat(songwriter): project-agnostic audio recorder store"
```

---

### Task 2: Recorder sheet + record/import actions

**Files:**
- Create: `lib/features/songwriter/songwriter_audio_recorder_sheet.dart`
- Create: `lib/features/songwriter/songwriter_audio_actions.dart`

- [ ] **Step 1: Write the recorder sheet**

Create `lib/features/songwriter/songwriter_audio_recorder_sheet.dart` — a near-copy of `song_audio_recorder_sheet.dart`, pointed at `songwriterAudioRecorderProvider`, with no `trackId`/`startTick` and `start(countInMs: ...)` only:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../store/song_audio_recorder_store.dart' show SongAudioRecorderStatus;
import '../../store/songwriter_audio_recorder_store.dart';
import '../../theme/muzician_theme.dart';

/// Recorder sheet. Pops with the recorded [AudioAsset] (or null on cancel).
class SongwriterAudioRecorderSheet extends ConsumerWidget {
  final int countInMs;
  const SongwriterAudioRecorderSheet({super.key, this.countInMs = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SongwriterAudioRecorderState>(songwriterAudioRecorderProvider,
        (prev, next) {
      if (next.status == SongAudioRecorderStatus.ready &&
          next.pendingAsset != null) {
        final asset =
            ref.read(songwriterAudioRecorderProvider.notifier).consumePendingAsset();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(asset);
        }
      }
    });
    final state = ref.watch(songwriterAudioRecorderProvider);
    final n = ref.read(songwriterAudioRecorderProvider.notifier);
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
    return Container(
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
            Text(label,
                style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            if (busy)
              const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4))
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
                    child: Text(isRec ||
                            state.status == SongAudioRecorderStatus.countIn
                        ? 'Cancel'
                        : 'Close'),
                  ),
                  if (isRec)
                    FilledButton.icon(
                      key: const ValueKey('sw-audio-rec-stop'),
                      onPressed: () => n.stop(),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    )
                  else if (state.status == SongAudioRecorderStatus.idle ||
                      state.status == SongAudioRecorderStatus.error)
                    FilledButton.icon(
                      key: const ValueKey('sw-audio-rec-start'),
                      onPressed: () => n.start(countInMs: countInMs),
                      icon: const Icon(Icons.mic),
                      label: const Text('Record'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the picker/commit actions**

Create `lib/features/songwriter/songwriter_audio_actions.dart`. This reuses the Song feature's `SongAudioPickerSheet` (it takes `onRecord`/`onImport` callbacks and a `trackId`/`startTick` it only echoes back — pass empty/zero). On record it opens the recorder sheet; on import it uses `file_picker`; either way it commits via Plan-1 store ops:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../store/song_audio_repository.dart';
import '../../store/songwriter_store.dart';
import '../song/song_audio_picker_sheet.dart';
import 'songwriter_audio_recorder_sheet.dart';

/// Opens the record/import picker for an audio lane and commits the result as
/// an AudioClip + audio block at [startBar].
Future<void> showSongwriterAudioPicker(
  WidgetRef ref, {
  required BuildContext context,
  required String sectionId,
  required String laneId,
  required int startBar,
  required int sectionLengthBars,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => SongAudioPickerSheet(
      trackId: '',
      startTick: 0,
      onRecord: () async {
        Navigator.of(sheetCtx).pop();
        final asset = await showModalBottomSheet<AudioAsset?>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const SongwriterAudioRecorderSheet(countInMs: 0),
        );
        if (asset != null) {
          _commit(ref, sectionId, laneId, startBar, sectionLengthBars, asset);
        }
      },
      onImport: () async {
        Navigator.of(sheetCtx).pop();
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['wav', 'mp3', 'm4a'],
          withData: kIsWeb,
        );
        final path = picked?.files.singleOrNull?.path;
        if (path == null) return;
        final repo = ref.read(songwriterAudioRepositoryProvider);
        final asset = await repo.importExternalFile(
          sourcePath: path,
          sourceLabel: picked!.files.single.name,
          explicitDurationMs: null,
        );
        _commit(ref, sectionId, laneId, startBar, sectionLengthBars, asset);
      },
    ),
  );
}

void _commit(WidgetRef ref, String sectionId, String laneId, int startBar,
    int sectionLengthBars, AudioAsset asset) {
  final store = ref.read(songwriterProvider.notifier);
  final clipId = store.addAudioClip(assetId: asset.id, durationMs: asset.durationMs);
  final span = (sectionLengthBars - 1).clamp(1, sectionLengthBars);
  store.addAudioBlock(
    sectionId: sectionId, laneId: laneId, audioClipId: clipId,
    startBar: startBar, spanBars: span);
}
```

> `singleOrNull` needs `package:collection` (already a transitive dep used across the app). If unresolved, add `import 'package:collection/collection.dart';`. Confirm `ref.read(songwriterProvider.notifier)` exposes `addAudioClip`/`addAudioBlock` from Plan 1.

- [ ] **Step 3: Analyze, commit (UI wired/tested in Tasks 3–4)**

```bash
dart format lib/features/songwriter/songwriter_audio_recorder_sheet.dart lib/features/songwriter/songwriter_audio_actions.dart
flutter analyze lib/features/songwriter/songwriter_audio_recorder_sheet.dart lib/features/songwriter/songwriter_audio_actions.dart
git add lib/features/songwriter/songwriter_audio_recorder_sheet.dart lib/features/songwriter/songwriter_audio_actions.dart
git commit -m "feat(songwriter): audio recorder sheet + record/import actions"
```

---

### Task 3: "Add audio lane" menu item

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (the section `PopupMenuButton`, ~line 601)

- [ ] **Step 1: Add the menu action**

In the section menu's `onSelected`, add a branch beside `addDrumLane`:

```dart
                if (value == 'addAudioLane') {
                  ref.read(songwriterProvider.notifier).addLane(
                        sectionId: section.id,
                        kind: SongLaneKind.audio,
                        label: 'Sample',
                      );
                }
```

Add the menu item to `itemBuilder`:

```dart
                PopupMenuItem(
                  key: Key('addAudioLaneSheetAction'),
                  value: 'addAudioLane',
                  child: ListTile(
                    leading: Icon(Icons.mic),
                    title: Text('Add audio lane'),
                    dense: true,
                  ),
                ),
```

> `itemBuilder` is currently `(_) => const [ ... ]`. Adding a second `PopupMenuItem` keeps it const-friendly; if the analyzer complains about `const`, drop `const` from the list literal.

- [ ] **Step 2: Analyze + commit**

```bash
dart format lib/features/songwriter/songwriter_screen_sheet.dart
flutter analyze lib/features/songwriter/songwriter_screen_sheet.dart
git add lib/features/songwriter/songwriter_screen_sheet.dart
git commit -m "feat(songwriter): add-audio-lane menu action"
```

---

### Task 4: `SongwriterAudioLaneRow` + wire into the sheet

**Files:**
- Create: `lib/features/songwriter/songwriter_audio_lane_row.dart`
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (render audio lanes, ~after the drum-lane block near line 315)
- Test: `test/features/songwriter/songwriter_audio_lane_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/songwriter/songwriter_audio_lane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_lane_row.dart';

void main() {
  testWidgets('renders a clip tile for an audio block', (tester) async {
    const section = SongSection(
      id: 'sec', lengthBars: 4, order: 0,
      lanes: [SongLane(id: 'ln', kind: SongLaneKind.audio, order: 0, blocks: [
        SongBlock(id: 'bl', startBar: 0, spanBars: 2, audioClipId: 'c1'),
      ])],
    );
    const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000);
    const asset = AudioAssetStub(); // see note

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SongwriterAudioLaneRow(
            section: section, lane: section.lanes.single, instanceIndex: 0,
            clipsById: const {'c1': clip},
            assetsById: const {'a1': asset},
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('sheetAudioTile_c1')), findsOneWidget);
  });
}
```

> Replace `AudioAssetStub()` with a real `AudioAsset(...)` literal (import `package:muzician/models/song_project.dart`): `AudioAsset(id: 'a1', durationMs: 4000, sampleRate: 44100, channels: 1, format: 'wav', peaks: [10,20,30], sourceLabel: 'Recording')`. The stub line is shorthand — use the real constructor.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_audio_lane_test.dart`
Expected: FAIL — `SongwriterAudioLaneRow` undefined.

- [ ] **Step 3: Implement the lane row**

Create `lib/features/songwriter/songwriter_audio_lane_row.dart`, modeled on `_DrumLaneRow`. Empty bars are tappable (open the picker); a clip tile shows `AudioClipBody` + a fit-mode glyph; tapping a tile opens a fit-mode/delete menu (the full editor arrives in Plan 4):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../song/song_audio_clip_body.dart';
import 'songwriter_audio_actions.dart';

IconData fitGlyph(AudioFitMode m) => switch (m) {
      AudioFitMode.loop => Icons.repeat,
      AudioFitMode.oneShot => Icons.play_arrow,
      AudioFitMode.stretch => Icons.swap_horiz,
    };

class SongwriterAudioLaneRow extends ConsumerWidget {
  const SongwriterAudioLaneRow({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
    required this.clipsById,
    required this.assetsById,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final Map<String, AudioClip> clipsById;
  final Map<String, AudioAsset> assetsById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final ownerByBar = <int, SongBlock>{};
    for (final b in lane.blocks) {
      for (var i = b.startBar; i < b.endBar; i++) {
        ownerByBar[i] = b;
      }
    }
    final cells = <Widget>[];
    var i = 0;
    while (i < bars) {
      final owner = ownerByBar[i];
      if (owner != null && owner.startBar == i) {
        final span = owner.spanBars.clamp(1, bars - i);
        final clip = owner.audioClipId == null ? null : clipsById[owner.audioClipId];
        final asset = clip == null ? null : assetsById[clip.assetId];
        cells.add(Expanded(
          flex: span,
          child: GestureDetector(
            key: Key('sheetAudioTile_${owner.audioClipId ?? owner.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _tileMenu(context, ref, owner, clip),
            child: Container(
              key: const ValueKey('sheetAudioTileBody'),
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Stack(children: [
                Positioned.fill(
                  child: asset == null
                      ? Container(color: const Color(0xFF13314A))
                      : AudioClipBody(
                          name: asset.sourceLabel,
                          durationMs: clip!.trimEndMs - clip.trimStartMs,
                          format: asset.format,
                          peaks: asset.peaks,
                          isBroken: false,
                        ),
                ),
                if (clip != null)
                  Positioned(
                    right: 4, top: 2,
                    child: Icon(fitGlyph(clip.fitMode), size: 12,
                        color: MuzicianTheme.textPrimary),
                  ),
              ]),
            ),
          ),
        ));
        i += span;
      } else if (owner != null) {
        i++;
      } else {
        final barIndex = i;
        cells.add(Expanded(
          flex: 1,
          child: GestureDetector(
            key: Key('sheetAudioEmpty_${lane.id}_$barIndex'),
            behavior: HitTestBehavior.opaque,
            onTap: () => showSongwriterAudioPicker(
              ref,
              context: context,
              sectionId: section.id,
              laneId: lane.id,
              startBar: barIndex,
              sectionLengthBars: bars,
            ),
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: Border.all(color: MuzicianTheme.glassBorder),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ));
        i++;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(lane.label ?? 'Sample',
              style: const TextStyle(
                  color: MuzicianTheme.textMuted, fontSize: 11, letterSpacing: 1.2)),
        ),
        Row(children: cells),
      ],
    );
  }

  void _tileMenu(
      BuildContext context, WidgetRef ref, SongBlock block, AudioClip? clip) {
    if (clip == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final mode in AudioFitMode.values)
            ListTile(
              leading: Icon(fitGlyph(mode)),
              title: Text(mode.name),
              trailing: clip.fitMode == mode ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(songwriterProvider.notifier)
                    .setClipFitMode(clipId: clip.id, fitMode: mode);
                Navigator.of(ctx).pop();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () {
              ref.read(songwriterProvider.notifier).removeAudioBlock(
                  sectionId: section.id, laneId: lane.id, blockId: block.id);
              Navigator.of(ctx).pop();
            },
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the widget test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_audio_lane_test.dart`
Expected: PASS.

- [ ] **Step 5: Render audio lanes in the sheet**

In `songwriter_screen_sheet.dart`, find the drum-lane rendering block (the `section.lanes.where((l) => l.kind == SongLaneKind.drum)` loop near line 315) and add an analogous block right after it:

```dart
        // Audio lanes (one strip per audio lane on this section).
        for (final lane in section.lanes.where(
          (l) => l.kind == SongLaneKind.audio,
        ))
          Padding(
            key: Key('sheetAudioLane_${lane.id}_$instanceIndex'),
            padding: const EdgeInsets.only(top: 8),
            child: SongwriterAudioLaneRow(
              section: section,
              lane: lane,
              instanceIndex: instanceIndex,
              clipsById: {
                for (final c in ref.read(songwriterProvider).audioClips) c.id: c,
              },
              assetsById: {
                for (final a in ref.read(songwriterProvider).audioAssets) a.id: a,
              },
            ),
          ),
```

Add the import at the top of the file: `import 'songwriter_audio_lane_row.dart';`. Match the exact variable names used by the surrounding drum block (`instanceIndex`); read lines ~300–330 first and mirror them.

- [ ] **Step 6: Run sheet widget tests for regressions, format, analyze, commit**

Run: `flutter test test/features/songwriter/`
Expected: PASS.

```bash
dart format lib/features/songwriter/songwriter_audio_lane_row.dart lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_audio_lane_test.dart
flutter analyze lib/features/songwriter
git add lib/features/songwriter/songwriter_audio_lane_row.dart lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_audio_lane_test.dart
git commit -m "feat(songwriter): audio lane row + clip tiles in the sheet"
```

---

### Task 5: Move/resize wiring + verification gate

**Files:**
- Modify: `lib/features/songwriter/songwriter_audio_lane_row.dart` (optional drag affordance)

Move/resize use the existing `setBlockPlacement` store op (clamps + rejects overlaps). The drum lane has no drag UI either (placement is set at creation / via menu), so for parity the audio lane resizes via a span control in the tile menu rather than a custom drag surface.

- [ ] **Step 1: Add span +/- to the tile menu**

In `_tileMenu`, add above the Delete tile:

```dart
          ListTile(
            leading: const Icon(Icons.unfold_more),
            title: Text('Span: ${block.spanBars} bar(s)'),
            subtitle: const Text('tap +/- to resize (max section − 1)'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const ValueKey('sheetAudioSpanMinus'),
                icon: const Icon(Icons.remove),
                onPressed: () => ref.read(songwriterProvider.notifier).setBlockPlacement(
                    sectionId: section.id, laneId: lane.id, blockId: block.id,
                    startBar: block.startBar,
                    spanBars: (block.spanBars - 1).clamp(1, section.lengthBars - 1)),
              ),
              IconButton(
                key: const ValueKey('sheetAudioSpanPlus'),
                icon: const Icon(Icons.add),
                onPressed: () => ref.read(songwriterProvider.notifier).setBlockPlacement(
                    sectionId: section.id, laneId: lane.id, blockId: block.id,
                    startBar: block.startBar,
                    spanBars: (block.spanBars + 1).clamp(1, section.lengthBars - 1)),
              ),
            ]),
          ),
```

> Confirm `setBlockPlacement`'s exact parameter names by reading `songwriter_store.dart:479`; the call above matches `{sectionId, laneId, blockId, startBar, spanBars}`.

- [ ] **Step 2: Verification gate**

Run:
```bash
flutter test test/store/songwriter_audio_recorder_store_test.dart test/features/songwriter/
flutter analyze lib/features/songwriter lib/store/songwriter_audio_recorder_store.dart
```
Expected: PASS, no issues.

- [ ] **Step 3: Manual device smoke (record + import)**

On an iOS or Android device: open a project → a section menu → Add audio lane → tap an empty bar → Record (grant mic) → Stop → a waveform tile appears spanning section−1 bars. Tap the tile → switch fit mode / resize / delete. Repeat with Import. (No sound yet — playback is Plan 3.)

- [ ] **Step 4: Commit**

```bash
dart format lib/features/songwriter/songwriter_audio_lane_row.dart
git add lib/features/songwriter/songwriter_audio_lane_row.dart
git commit -m "feat(songwriter): audio clip span control in tile menu"
```

---

## Self-Review

**Spec coverage (P2 = record/import + sheet lane, part of M2/M3):** recorder store ✓ (T1); recorder sheet + import via file_picker ✓ (T2); add-audio-lane ✓ (T3); `_AudioLaneRow` clip tiles with waveform + fit glyph + empty-bar picker + fit/delete/span menu ✓ (T4, T5); move/resize via existing `setBlockPlacement` ✓ (T5); web (record hidden via `SongAudioPickerSheet.recordSupported = !kIsWeb`) ✓ (reused). Out of P2: playback (P3), trim/stretch editor (P4), segments (P5).

**Placeholder scan:** No "TBD"/"handle later". Explicit "confirm symbol/var name" notes carry concrete fallbacks (the `AudioAsset` literal in T4, `setBlockPlacement` params in T5, `instanceIndex` var in T4 S5).

**Type consistency:** `songwriterAudioRecorderProvider`, `SongwriterAudioRecorderSheet`, `showSongwriterAudioPicker`, `SongwriterAudioLaneRow`, `fitGlyph`, store ops (`addAudioClip`/`addAudioBlock`/`setClipFitMode`/`removeAudioBlock`/`setBlockPlacement`) are used identically across tasks and match Plan 1's definitions. `SongAudioRecorderStatus` reused from the Song store; recorder state is the new `SongwriterAudioRecorderState`.
