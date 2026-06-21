# Songwriter Drum Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated `SongLaneKind.drum` to Songwriter projects. Drum patterns live on the project, drum-lane blocks reference a pattern by id and loop it over a bar span, and the existing `DrumMachineEditor` is reused for editing patterns from inside Songwriter.

**Architecture:** `DrumPattern`, `DrumLaneSequence`, and `DrumLaneId` already exist in `lib/models/song_project.dart` and are reused unchanged. Songwriter gets a new `drumPatterns: List<DrumPattern>` field on `SongwriterProjectSnapshot` for project-local pattern storage (no cross-feature coupling with `SongProject`). A new lane kind hosts blocks whose `patternId` resolves into that list. `DrumMachineEditor` is generalized just enough to operate against an arbitrary `DrumPattern` + a callback (currently it reads from `songProjectProvider`).

**Tech Stack:** Dart, Flutter, Riverpod, existing `DrumPatternPlaybackNotifier`, `flutter_test`. No new packages.

**Non-goals (deferred to a follow-up plan):**
- **Songwriter transport drum playback.** Wiring drum patterns into `SongwriterPlaybackNotifier` so they trigger during section playback. Editor audition (existing `DrumPatternPlaybackNotifier`) is in-scope; full timeline playback is not.
- **Sheet variant rendering.** Sheet stays harmony-only; drum-lane visibility is Track + Classic only. A tiny "🥁 N bars" chip strip in Sheet can come later.
- **Cross-project pattern import** (copying a `DrumPattern` from a `SongProject` into a Songwriter project).
- **Pattern reuse across blocks within Songwriter** beyond simple `patternId` lookup (e.g. variant per block).

---

## File Structure

**Created:**
- `lib/features/songwriter/drum_pattern_sheet.dart` — bottom sheet that hosts the (generalized) drum machine editor for a single pattern.
- `test/models/songwriter_drum_lane_test.dart` — model round-trip tests for the new lane kind + drum patterns on the snapshot.
- `test/store/songwriter_drum_ops_test.dart` — store mutator tests.
- `test/features/songwriter/songwriter_drum_lane_render_test.dart` — widget tests for drum-lane rendering and pattern-sheet entry.

**Modified:**
- `lib/models/songwriter.dart` — add `SongLaneKind.drum`, optional `patternId` on `SongBlock`, `drumPatterns` field on `SongwriterProjectSnapshot`.
- `lib/store/songwriter_store.dart` — add `addDrumPattern`, `updateDrumPattern`, `removeDrumPattern`, `addDrumBlock` mutators.
- `lib/schema/rules/songwriter_rules.dart` — add `makeDrumPattern` + `makeDrumBlock` factories.
- `lib/features/song/drum_machine_editor.dart` — extract a reusable `DrumMachineEditorBody` widget that operates on an external `DrumPattern` + `onChanged` callback; keep the song-project entrypoint as a thin wrapper for backwards compatibility.
- `lib/features/songwriter/songwriter_lane_row.dart` — recognize drum-lane kind, render lane label and drum-block tiles.
- `lib/features/songwriter/songwriter_screen_track.dart` — wire "add drum lane" affordance in the section action menu.
- `lib/features/songwriter/songwriter_section_card.dart` — wire drum lane in the Classic variant card menu.

---

## Task 1: Extend `SongLaneKind` and the snapshot with drum patterns

**Files:**
- Modify: `lib/models/songwriter.dart` (enum at line 6, `_laneKindFromName` at 8, `SongBlock` at 15, `SongwriterProjectSnapshot` at 209)
- Test: `test/models/songwriter_drum_lane_test.dart`

- [ ] **Step 1: Write the failing test**

`test/models/songwriter_drum_lane_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  test('SongLaneKind.drum exists and round-trips by name', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.drum,
      label: 'Beat',
      order: 0,
      blocks: [
        SongBlock(id: 'b1', startBar: 0, spanBars: 4, patternId: 'p1'),
      ],
    );
    final back = SongLane.fromJson(lane.toJson());
    expect(back.kind, SongLaneKind.drum);
    expect(back.blocks.single.patternId, 'p1');
  });

  test('unknown lane kind still falls back to save', () {
    final back = SongLane.fromJson({
      'id': 'l2',
      'kind': 'mystery',
      'order': 0,
      'blocks': [],
    });
    expect(back.kind, SongLaneKind.save);
  });

  test('SongwriterProjectSnapshot round-trips drumPatterns', () {
    const pattern = DrumPattern(
      id: 'p1',
      name: 'Backbeat',
      lengthTicks: 16,
      lanes: [
        DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
        DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [4, 12]),
      ],
    );
    const snapshot = SongwriterProjectSnapshot(
      name: 'demo',
      config: SongwriterConfig(
        tempo: 120,
        beatsPerBar: 4,
        beatUnit: 4,
      ),
      drumPatterns: [pattern],
    );
    final back = SongwriterProjectSnapshot.fromJson(snapshot.toJson());
    expect(back.drumPatterns.single.id, 'p1');
    expect(back.drumPatterns.single.lanes.first.activeTicks, [0, 8]);
  });

  test('fromJson tolerates missing drumPatterns key', () {
    final back = SongwriterProjectSnapshot.fromJson({
      'type': 'songwriter',
      'instrument': 'songwriter',
      'name': 'demo',
      'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
    });
    expect(back.drumPatterns, isEmpty);
  });

  test('SongBlock round-trips patternId', () {
    const block = SongBlock(
      id: 'b1',
      startBar: 2,
      spanBars: 4,
      patternId: 'p42',
    );
    final back = SongBlock.fromJson(block.toJson());
    expect(back.patternId, 'p42');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/songwriter_drum_lane_test.dart`
Expected: FAIL — `SongLaneKind.drum` undefined, `patternId` param undefined, `drumPatterns` undefined.

- [ ] **Step 3: Update the model**

Edit `lib/models/songwriter.dart`:

1. Add the import at the top (it already imports `save_system.dart`):

```dart
import 'song_project.dart';
```

2. Extend the enum:

```dart
enum SongLaneKind { harmony, save, drum }
```

3. `_laneKindFromName` stays unchanged — fall-through to `save` is the explicit unknown-fallback behavior covered by the test.

4. Extend `SongBlock`. Final shape:

```dart
class SongBlock {
  final String id;
  final int startBar;
  final int spanBars;

  // save-lane reference (live link into SaveSystemState.saves)
  final String? saveId;
  final InstrumentSnapshot? embedded;

  // harmony-lane extras
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;

  // drum-lane reference into SongwriterProjectSnapshot.drumPatterns
  final String? patternId;

  const SongBlock({
    required this.id,
    required this.startBar,
    required this.spanBars,
    this.saveId,
    this.embedded,
    this.chordSymbol,
    this.chordQuality,
    this.chordRootPc,
    this.chordNotes = const [],
    this.romanNumeral,
    this.patternId,
  });

  int get endBar => startBar + spanBars;

  SongBlock copyWith({
    int? startBar,
    int? spanBars,
    String? saveId,
    InstrumentSnapshot? embedded,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String>? chordNotes,
    String? romanNumeral,
    String? patternId,
    bool clearRomanNumeral = false,
    bool clearSaveId = false,
    bool clearEmbedded = false,
    bool clearPatternId = false,
  }) => SongBlock(
    id: id,
    startBar: startBar ?? this.startBar,
    spanBars: spanBars ?? this.spanBars,
    saveId: clearSaveId ? null : (saveId ?? this.saveId),
    embedded: clearEmbedded ? null : (embedded ?? this.embedded),
    chordSymbol: chordSymbol ?? this.chordSymbol,
    chordQuality: chordQuality ?? this.chordQuality,
    chordRootPc: chordRootPc ?? this.chordRootPc,
    chordNotes: chordNotes ?? this.chordNotes,
    romanNumeral: clearRomanNumeral ? null : (romanNumeral ?? this.romanNumeral),
    patternId: clearPatternId ? null : (patternId ?? this.patternId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startBar': startBar,
    'spanBars': spanBars,
    'saveId': saveId,
    'embedded': embedded?.toJson(),
    'chordSymbol': chordSymbol,
    'chordQuality': chordQuality,
    'chordRootPc': chordRootPc,
    'chordNotes': chordNotes,
    'romanNumeral': romanNumeral,
    'patternId': patternId,
  };

  factory SongBlock.fromJson(Map<String, dynamic> json) => SongBlock(
    id: json['id'] as String,
    startBar: json['startBar'] as int? ?? 0,
    spanBars: json['spanBars'] as int? ?? 1,
    saveId: json['saveId'] as String?,
    embedded: json['embedded'] == null
        ? null
        : InstrumentSnapshot.fromJson(json['embedded'] as Map<String, dynamic>),
    chordSymbol: json['chordSymbol'] as String?,
    chordQuality: json['chordQuality'] as String?,
    chordRootPc: json['chordRootPc'] as int?,
    chordNotes:
        (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
        const [],
    romanNumeral: json['romanNumeral'] as String?,
    patternId: json['patternId'] as String?,
  );
}
```

5. Extend `SongwriterProjectSnapshot`:

```dart
class SongwriterProjectSnapshot extends InstrumentSnapshot {
  final String name;
  final SongwriterConfig config;
  final List<SongSection> sections;
  final List<DrumPattern> drumPatterns;

  const SongwriterProjectSnapshot({
    this.name = 'Untitled song',
    required this.config,
    this.sections = const [],
    this.drumPatterns = const [],
  });

  @override
  String get instrument => 'songwriter';

  @override
  List<String> get selectedNotes {
    final set = <String>{};
    for (final section in sections) {
      for (final lane in section.lanes) {
        for (final block in lane.blocks) {
          set.addAll(block.chordNotes);
        }
      }
    }
    return set.toList();
  }

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  SongwriterProjectSnapshot copyWith({
    String? name,
    SongwriterConfig? config,
    List<SongSection>? sections,
    List<DrumPattern>? drumPatterns,
  }) => SongwriterProjectSnapshot(
    name: name ?? this.name,
    config: config ?? this.config,
    sections: sections ?? this.sections,
    drumPatterns: drumPatterns ?? this.drumPatterns,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'songwriter',
    'instrument': 'songwriter',
    'name': name,
    'config': config.toJson(),
    'sections': sections.map((s) => s.toJson()).toList(),
    'drumPatterns': drumPatterns.map((p) => p.toJson()).toList(),
  };

  factory SongwriterProjectSnapshot.fromJson(Map<String, dynamic> json) =>
      SongwriterProjectSnapshot(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : 'Untitled song',
        config: SongwriterConfig.fromJson(
          json['config'] as Map<String, dynamic>? ?? const {},
        ),
        sections:
            (json['sections'] as List?)
                ?.map((s) => SongSection.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        drumPatterns:
            (json['drumPatterns'] as List?)
                ?.map((p) => DrumPattern.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/songwriter_drum_lane_test.dart`
Expected: PASS (5/5).

- [ ] **Step 5: Run all songwriter model tests**

Run: `flutter test test/models/songwriter_snapshot_test.dart test/models/song_section_test.dart test/models/song_block_test.dart`
Expected: PASS — JSON adds are backwards-compatible (new fields default to null/empty).

- [ ] **Step 6: Commit**

```bash
git add lib/models/songwriter.dart test/models/songwriter_drum_lane_test.dart
git commit -m "feat(songwriter): SongLaneKind.drum + drumPatterns on snapshot"
```

---

## Task 2: Factory helpers for drum patterns and blocks

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart` (add factories near existing `makeSection`, `makeLane`, `makeSaveBlock` at line 130)
- Test: extend `test/models/songwriter_drum_lane_test.dart`

- [ ] **Step 1: Add failing tests**

Append to `test/models/songwriter_drum_lane_test.dart`, inside the same `main()`:

```dart
import 'package:muzician/schema/rules/songwriter_rules.dart';

// inside main():
test('makeDrumPattern creates 16-tick empty pattern with named lanes', () {
  final pattern = makeDrumPattern(name: 'Empty');
  expect(pattern.name, 'Empty');
  expect(pattern.lengthTicks, 16);
  expect(pattern.lanes.length, DrumLaneId.values.length);
  for (final l in pattern.lanes) {
    expect(l.activeTicks, isEmpty);
  }
  expect(pattern.id.isNotEmpty, true);
});

test('makeDrumBlock fills required fields', () {
  final block = makeDrumBlock(
    patternId: 'p1',
    startBar: 4,
    spanBars: 8,
  );
  expect(block.patternId, 'p1');
  expect(block.startBar, 4);
  expect(block.spanBars, 8);
  expect(block.id.isNotEmpty, true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/songwriter_drum_lane_test.dart`
Expected: FAIL — `makeDrumPattern` and `makeDrumBlock` not defined.

- [ ] **Step 3: Add factories**

Append to `lib/schema/rules/songwriter_rules.dart` after `makeSaveBlock`:

```dart
DrumPattern makeDrumPattern({String name = 'Pattern'}) => DrumPattern(
  id: generateId(),
  name: name,
  lengthTicks: 16,
  lanes: [
    for (final id in DrumLaneId.values)
      DrumLaneSequence(laneId: id, activeTicks: const []),
  ],
);

SongBlock makeDrumBlock({
  required String patternId,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  patternId: patternId,
);
```

Add the imports at the top of the file if not present:

```dart
import '../../models/song_project.dart';
```

(`generateId` and `SongBlock` should already be imported via the existing file.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/songwriter_drum_lane_test.dart`
Expected: PASS (7/7).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/models/songwriter_drum_lane_test.dart
git commit -m "feat(songwriter): drum pattern + drum block factories"
```

---

## Task 3: Store mutators for drum patterns and blocks

**Files:**
- Modify: `lib/store/songwriter_store.dart` (add mutators after the existing block mutators ~ line 280)
- Test: `test/store/songwriter_drum_ops_test.dart`

- [ ] **Step 1: Write the failing test**

`test/store/songwriter_drum_ops_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('addDrumPattern appends and returns the new id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    final id = notifier.addDrumPattern(name: 'Backbeat');
    final state = container.read(songwriterProvider);
    expect(state.drumPatterns.length, 1);
    expect(state.drumPatterns.first.id, id);
    expect(state.drumPatterns.first.name, 'Backbeat');
  });

  test('updateDrumPattern replaces a pattern by id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    final id = notifier.addDrumPattern();
    final updated = container.read(songwriterProvider).drumPatterns.single
        .copyWith(name: 'Funky');
    notifier.updateDrumPattern(updated);
    expect(
      container.read(songwriterProvider).drumPatterns.single.name,
      'Funky',
    );
  });

  test('removeDrumPattern drops the pattern AND clears refs in blocks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;

    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern();
    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    notifier.removeDrumPattern(patternId);

    final state = container.read(songwriterProvider);
    expect(state.drumPatterns, isEmpty);
    final lane = state.sections.first.lanes.firstWhere((l) => l.id == laneId);
    expect(lane.blocks.single.patternId, isNull);
  });

  test('addDrumBlock places a block referencing the pattern', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    notifier.addSection(label: 'Verse', lengthBars: 8);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern();

    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 2,
      spanBars: 4,
    );

    final block = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;

    expect(block.patternId, patternId);
    expect(block.startBar, 2);
    expect(block.spanBars, 4);
  });
}
```

> Note: this test assumes `addLane` returns the new lane's id. Check the current signature first. If `addLane` is void in the existing code, **adjust this Task to also update `addLane`** to return the generated id (it already creates one via `generateId()`); that change is small and self-contained.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_drum_ops_test.dart`
Expected: FAIL — `addDrumPattern`, `updateDrumPattern`, `removeDrumPattern`, `addDrumBlock` undefined.

- [ ] **Step 3: Add mutators**

In `lib/store/songwriter_store.dart`, add imports if missing:

```dart
import '../models/song_project.dart';
import '../schema/rules/songwriter_rules.dart' show makeDrumPattern, makeDrumBlock;
```

Append the mutators after the existing block-mutator section (search for `addSaveBlock` or the last block mutator and place these directly below):

```dart
String addDrumPattern({String name = 'Pattern'}) {
  final pattern = makeDrumPattern(name: name);
  _set(state.copyWith(drumPatterns: [...state.drumPatterns, pattern]));
  return pattern.id;
}

void updateDrumPattern(DrumPattern updated) {
  _set(
    state.copyWith(
      drumPatterns: state.drumPatterns
          .map((p) => p.id == updated.id ? updated : p)
          .toList(),
    ),
  );
}

void removeDrumPattern(String patternId) {
  final patterns =
      state.drumPatterns.where((p) => p.id != patternId).toList();
  final sections = state.sections.map((s) {
    final lanes = s.lanes.map((l) {
      if (l.kind != SongLaneKind.drum) return l;
      final blocks = l.blocks
          .map((b) =>
              b.patternId == patternId ? b.copyWith(clearPatternId: true) : b)
          .toList();
      return l.copyWith(blocks: blocks);
    }).toList();
    return s.copyWith(lanes: lanes);
  }).toList();
  _set(state.copyWith(drumPatterns: patterns, sections: sections));
}

void addDrumBlock({
  required String sectionId,
  required String laneId,
  required String patternId,
  required int startBar,
  required int spanBars,
}) {
  _set(
    state.copyWith(
      sections: state.sections.map((s) {
        if (s.id != sectionId) return s;
        return s.copyWith(
          lanes: s.lanes.map((l) {
            if (l.id != laneId || l.kind != SongLaneKind.drum) return l;
            return l.copyWith(
              blocks: [
                ...l.blocks,
                makeDrumBlock(
                  patternId: patternId,
                  startBar: startBar,
                  spanBars: spanBars,
                ),
              ],
            );
          }).toList(),
        );
      }).toList(),
    ),
  );
}
```

If `addLane` currently returns `void`, change its signature to return the generated id:

```dart
String addLane({
  required String sectionId,
  required SongLaneKind kind,
  String? label,
}) {
  final lane = makeLane(kind: kind, label: label, order: 0);
  _replaceSection(sectionId, (s) {
    final next = lane.copyWith(order: s.lanes.length);
    return s.copyWith(lanes: [...s.lanes, next]);
  });
  return lane.id;
}
```

(Adjust the inner detail to match the existing implementation — the only contract change is the return type.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_drum_ops_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Run all songwriter store tests for regressions**

Run: `flutter test test/store/songwriter_*.dart`
Expected: PASS — `addLane` return-type change is additive (existing callers that ignore the return still compile).

- [ ] **Step 6: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_drum_ops_test.dart
git commit -m "feat(songwriter): drum pattern + drum block store mutators"
```

---

## Task 4: Extract reusable `DrumMachineEditorBody`

**Files:**
- Modify: `lib/features/song/drum_machine_editor.dart`
- Test: rely on existing `test/features/song/drum_machine_editor_*` (or run `flutter test test/features/song/`)

- [ ] **Step 1: Locate the current editor's data sources**

Run: `grep -n "songProjectProvider\|patternId\|applyDrumPattern\|toggleDrumStep" lib/features/song/drum_machine_editor.dart`
Identify every place the editor reads/writes a pattern. Read the file end-to-end before editing — this task is structural.

- [ ] **Step 2: Add a generalized body widget**

Inside `lib/features/song/drum_machine_editor.dart`, alongside the existing `DrumMachineEditor` widget, add a new public widget that operates on an arbitrary pattern + callback:

```dart
/// Source-agnostic drum machine editor body.
///
/// Renders the same step grid + transport as [DrumMachineEditor] but reads
/// from [pattern] and emits the full updated pattern via [onChanged]. Has no
/// dependency on `songProjectProvider`, so it can be embedded by any feature
/// that owns its own pattern storage (Songwriter, ad-hoc dialogs, etc.).
class DrumMachineEditorBody extends ConsumerStatefulWidget {
  const DrumMachineEditorBody({
    super.key,
    required this.pattern,
    required this.tempo,
    required this.onChanged,
  });

  final DrumPattern pattern;
  final int tempo;
  final void Function(DrumPattern updated) onChanged;

  @override
  ConsumerState<DrumMachineEditorBody> createState() =>
      _DrumMachineEditorBodyState();
}

class _DrumMachineEditorBodyState extends ConsumerState<DrumMachineEditorBody> {
  late DrumPattern _pattern;

  @override
  void initState() {
    super.initState();
    _pattern = widget.pattern;
  }

  @override
  void didUpdateWidget(covariant DrumMachineEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pattern.id != widget.pattern.id) {
      _pattern = widget.pattern;
    }
  }

  void _toggle(DrumLaneId laneId, int tick) {
    final lanes = _pattern.lanes.map((l) {
      if (l.laneId != laneId) return l;
      final ticks = [...l.activeTicks];
      if (ticks.contains(tick)) {
        ticks.remove(tick);
      } else {
        ticks.add(tick);
      }
      ticks.sort();
      return l.copyWith(activeTicks: ticks);
    }).toList();
    setState(() => _pattern = _pattern.copyWith(lanes: lanes));
    widget.onChanged(_pattern);
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(drumPatternPlaybackProvider);
    final playing = playback.status == DrumPatternPlaybackStatus.playing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TODO(songwriter): copy the existing transport row from
        //   DrumMachineEditor.build into this column. Wire the play button to
        //   `ref.read(drumPatternPlaybackProvider.notifier).start(pattern: _pattern, tempo: widget.tempo)`
        //   and the stop button to `.stop()`. The original transport widgets
        //   already accept a `DrumPattern` directly.
        _DrumGrid(
          pattern: _pattern,
          playing: playing,
          activeTick: playback.activeTick,
          onToggle: _toggle,
        ),
      ],
    );
  }
}
```

Then refactor the existing `DrumMachineEditor` to wrap `DrumMachineEditorBody`, sourcing its pattern from `songProjectProvider` and emitting changes via the existing `applyDrumPattern` mutator. Only the wiring changes — the grid implementation (`_DrumGrid`) is reused as-is.

- [ ] **Step 3: Verify the song-project drum machine still works**

Run: `flutter test test/features/song/ test/store/drum_pattern_playback_store_test.dart`
Expected: PASS — refactor is internal; public API of `DrumMachineEditor` (the existing wrapper) is unchanged.

If any of the song-feature widget tests fail because the existing `DrumMachineEditor` widget tree shape changed, update the wrapper to preserve the prior tree structure (e.g. keep the top-level `Scaffold` / `AppBar` outside the body widget).

- [ ] **Step 4: Commit**

```bash
git add lib/features/song/drum_machine_editor.dart
git commit -m "refactor(drum-editor): extract source-agnostic DrumMachineEditorBody"
```

---

## Task 5: Songwriter drum-pattern sheet

**Files:**
- Create: `lib/features/songwriter/drum_pattern_sheet.dart`
- Test: covered by Task 6's render test

- [ ] **Step 1: Create the sheet wrapper**

`lib/features/songwriter/drum_pattern_sheet.dart`:

```dart
/// Bottom-sheet host that edits a single Songwriter [DrumPattern] using the
/// generalized [DrumMachineEditorBody].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../store/songwriter_store.dart';
import '../song/drum_machine_editor.dart';
import '../_mockup_shell.dart';

Future<void> showSongwriterDrumPatternSheet({
  required BuildContext context,
  required String patternId,
}) {
  return showWidgetSheet(
    context: context,
    title: 'Drum Pattern',
    child: _Body(patternId: patternId),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.patternId});
  final String patternId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final pattern = project.drumPatterns.firstWhere(
      (p) => p.id == patternId,
      orElse: () => const DrumPattern(
        id: '',
        name: '',
        lengthTicks: 16,
        lanes: [],
      ),
    );
    if (pattern.id.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Pattern not found.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: DrumMachineEditorBody(
        key: Key('drumPatternBody_$patternId'),
        pattern: pattern,
        tempo: project.config.tempo,
        onChanged: (updated) {
          ref.read(songwriterProvider.notifier).updateDrumPattern(updated);
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Commit (no tests yet — widget surface covered in Task 6)**

```bash
git add lib/features/songwriter/drum_pattern_sheet.dart
git commit -m "feat(songwriter): drum pattern editor sheet"
```

---

## Task 6: Drum-lane rendering + entry points in Track/Classic variants

**Files:**
- Modify: `lib/features/songwriter/songwriter_lane_row.dart`
- Modify: `lib/features/songwriter/songwriter_screen_track.dart`
- Modify: `lib/features/songwriter/songwriter_section_card.dart`
- Test: `test/features/songwriter/songwriter_drum_lane_render_test.dart`

- [ ] **Step 1: Write the failing widget test**

`test/features/songwriter/songwriter_drum_lane_render_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_track.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('track variant renders a drum lane with its block', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern(name: 'Backbeat');
    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenTrack()),
      ),
    );
    await tester.pump();

    expect(find.byKey(Key('drumLaneRow_$laneId')), findsOneWidget);
    expect(find.text('Beat'), findsOneWidget);
    expect(find.byKey(Key('drumBlockTile_$patternId')), findsOneWidget);
  });

  testWidgets('tapping a drum block opens the drum pattern sheet',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern();
    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenTrack()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(Key('drumBlockTile_$patternId')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('drumPatternBody_$patternId')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_drum_lane_render_test.dart`
Expected: FAIL — drum-lane widget keys not present.

- [ ] **Step 3: Render drum lanes in `songwriter_lane_row.dart`**

In `lib/features/songwriter/songwriter_lane_row.dart`:

1. Add imports:

```dart
import 'drum_pattern_sheet.dart';
```

2. Locate the existing branch on `lane.kind`. Add a third branch for drum lanes. Reuse the existing bar-grid block layout — only the tile contents change.

Replace the lane-label expression around line 68:

```dart
Text(
  lane.label ??
      switch (lane.kind) {
        SongLaneKind.harmony => 'Harmony',
        SongLaneKind.save => 'Lane',
        SongLaneKind.drum => 'Beat',
      },
)
```

For the lane row's accent color, extend the existing ternary into a switch:

```dart
color: switch (lane.kind) {
  SongLaneKind.harmony => MuzicianTheme.accentHarmony,
  SongLaneKind.save => MuzicianTheme.accentSave,
  SongLaneKind.drum => MuzicianTheme.orange,
},
```

(Substitute existing color tokens from `muzician_theme.dart` if the names differ — `MuzicianTheme.orange` is already used by song's drum-track header at [song_track_header.dart:19](lib/features/song/song_track_header.dart:19).)

For block tiles inside a drum lane, render a compact tile that shows the pattern name + bar span:

```dart
Widget _drumBlockTile(
  BuildContext context,
  WidgetRef ref,
  SongLane lane,
  SongBlock block,
) {
  final patternId = block.patternId;
  final pattern = patternId == null
      ? null
      : ref
          .read(songwriterProvider)
          .drumPatterns
          .firstWhere(
            (p) => p.id == patternId,
            orElse: () => const DrumPattern(
              id: '',
              name: 'Missing',
              lengthTicks: 0,
              lanes: [],
            ),
          );
  return GestureDetector(
    key: Key('drumBlockTile_${patternId ?? block.id}'),
    behavior: HitTestBehavior.opaque,
    onTap: () {
      if (patternId == null || pattern == null || pattern.id.isEmpty) return;
      showSongwriterDrumPatternSheet(
        context: context,
        patternId: patternId,
      );
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: MuzicianTheme.orange.withOpacity(0.18),
        border: Border.all(color: MuzicianTheme.orange.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq, size: 14),
          const SizedBox(width: 6),
          Text(
            pattern?.name ?? 'pattern?',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
```

Then in the existing block-render loop, route drum-lane blocks through `_drumBlockTile` instead of the harmony/save tile. Mirror the existing bar-positioning (use the same `startBar` × cell-width math as for save-lane blocks).

Also wrap the row with a key:

```dart
Container(
  key: Key('drumLaneRow_${lane.id}'),
  // ... existing decoration / contents
)
```

- [ ] **Step 4: Wire "add drum lane" entry point in track variant**

In `lib/features/songwriter/songwriter_screen_track.dart`, find the section action sheet/menu that currently surfaces "add harmony lane" / "add save lane" (grep for `addLane(` calls). Add a third entry:

```dart
ListTile(
  key: const Key('addDrumLaneAction'),
  leading: const Icon(Icons.graphic_eq),
  title: const Text('Add drum lane'),
  onTap: () async {
    final laneId = ref.read(songwriterProvider.notifier).addLane(
          sectionId: section.id,
          kind: SongLaneKind.drum,
          label: 'Beat',
        );
    final patternId =
        ref.read(songwriterProvider.notifier).addDrumPattern(name: 'Pattern');
    ref.read(songwriterProvider.notifier).addDrumBlock(
          sectionId: section.id,
          laneId: laneId,
          patternId: patternId,
          startBar: 0,
          spanBars: section.lengthBars,
        );
    Navigator.of(context).pop();
  },
),
```

This creates a lane and seeds a single block spanning the full section, so the test's drum-block expectation has something to render after the lane appears.

- [ ] **Step 5: Wire "add drum lane" entry point in Classic variant**

In `lib/features/songwriter/songwriter_section_card.dart`, locate the existing "add harmony / add save" menu (similar grep — `addLane(`). Add the same `ListTile` action with key `addDrumLaneActionClassic`.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_drum_lane_render_test.dart`
Expected: PASS (2/2).

- [ ] **Step 7: Run the full songwriter suite for regressions**

Run: `flutter test test/features/songwriter/ test/store/songwriter_*.dart test/models/songwriter_*.dart`
Expected: PASS.

- [ ] **Step 8: Manual smoke check in the running app**

Run: `flutter run -d <preferred-device>`
- Switch to Track variant. From a section, choose "Add drum lane" — a lane with one full-section pattern block appears.
- Tap the block — the drum machine sheet opens. Toggle a few steps, close, reopen — steps persist.
- Hot restart — pattern still present (debounced session save covers `drumPatterns`).
- Repeat in Classic variant.
- Sheet variant: no drum surface (consistent with the harmony-only design).

- [ ] **Step 9: Commit**

```bash
git add \
  lib/features/songwriter/songwriter_lane_row.dart \
  lib/features/songwriter/songwriter_screen_track.dart \
  lib/features/songwriter/songwriter_section_card.dart \
  test/features/songwriter/songwriter_drum_lane_render_test.dart
git commit -m "feat(songwriter): drum lane rendering + add-drum-lane entry points"
```

---

## Self-Review Notes

- **Spec coverage:** drum-lane kind (Task 1), block.patternId (Task 1), per-project drum patterns on snapshot (Task 1), factories (Task 2), store mutators incl. cascading patternId clear on remove (Task 3), generalized editor body so the existing `DrumMachineEditor` doesn't fork (Task 4), Songwriter editor sheet (Task 5), Track + Classic rendering and entry points (Task 6).
- **Sheet variant intentionally untouched** — drum visibility there is a deferred follow-up.
- **Songwriter transport playback** is the biggest deferred item. The pattern is stored, edited, and auditioned via the existing `DrumPatternPlaybackNotifier`; section-playback drum scheduling is a separate plan.
- **`addLane` signature change** (void → `String`) is the only non-additive API tweak; existing callers that ignore the return value continue to compile, and Task 3's tests confirm the change.
- **Naming consistency:** `addDrumPattern`, `updateDrumPattern`, `removeDrumPattern`, `addDrumBlock`, `SongLaneKind.drum`, `block.patternId`, `drumPatterns` used identically across model, store, and UI tasks.
- **Theme tokens:** plan references `MuzicianTheme.orange` (already in use by song's drum track header) and the harmony/save accent tokens used by the current lane row. If the writer-glass-retheme branch introduces different tokens, substitute the nearest equivalents from `lib/theme/muzician_theme.dart`.

---

## Implementation Addendum (Verified Against HEAD)

> Verified on branch `writer-glass-retheme` at the start of this plan.

**Verified theme tokens used by current lane row** (`lib/features/songwriter/songwriter_lane_row.dart` lines 70-72, 134-136):

- harmony lane accent = `MuzicianTheme.violet` (`Color(0xFFA78BFA)`)
- save lane accent = `MuzicianTheme.teal` (`Color(0xFF4ECDC4)`)
- drum lane accent (new) = `MuzicianTheme.orange` (`Color(0xFFFB923C)`) — already in use at `lib/features/song/song_track_header.dart:19`

Replace the `switch` snippet in Task 6 Step 3 with this exact mapping:

```dart
color: switch (lane.kind) {
  SongLaneKind.harmony => MuzicianTheme.violet,
  SongLaneKind.save => MuzicianTheme.teal,
  SongLaneKind.drum => MuzicianTheme.orange,
},
```

(There is no `MuzicianTheme.accentHarmony` / `MuzicianTheme.accentSave` — those names in the original Task 6 draft do not exist. Use `violet` / `teal` / `orange` directly.)

**Verified `addLane` signature** (`lib/store/songwriter_store.dart:159`):

```dart
void addLane({
  required String sectionId,
  required SongLaneKind kind,
  String? label,
}) {
  _replaceSection(sectionId, (s) {
    final lane = makeLane(kind: kind, label: label, order: s.lanes.length);
    return s.copyWith(lanes: [...s.lanes, lane]);
  });
}
```

Returns `void` today — Task 3 must change it to return `String` (the new lane id). New body:

```dart
String addLane({
  required String sectionId,
  required SongLaneKind kind,
  String? label,
}) {
  final lane = makeLane(kind: kind, label: label, order: 0);
  _replaceSection(sectionId, (s) {
    final positioned = lane.copyWith(order: s.lanes.length);
    return s.copyWith(lanes: [...s.lanes, positioned]);
  });
  return lane.id;
}
```

The early `order: 0` is overwritten via `copyWith` inside `_replaceSection`; the returned `lane.id` is stable because `makeLane` calls `generateId()` once.

**Verified existing callers of `addLane`** (run before Task 3):

```bash
grep -rn "\.addLane(" lib/ test/
```

Expected matches (current branch): only call sites in `songwriter_screen_sheet.dart`, `songwriter_screen_track.dart`, `songwriter_section_card.dart`. All ignore the return value. The signature change is therefore safe — no other rewrites needed.

**Drum lane block-tile width math** (Task 6 Step 3):

The existing save-lane block tile uses bar-cell math from the section's `lengthBars` × the lane row's available width. The drum tile reuses the same layout — search for `startBar`/`spanBars` in `songwriter_lane_row.dart` and apply the same `LayoutBuilder` / `Positioned` pattern that save-lane blocks already use. Do **not** introduce a new layout strategy.

**`DrumMachineEditorBody` refactor scope (Task 4):**

Inspect `lib/features/song/drum_machine_editor.dart` end-to-end before editing. Today the editor:
- Reads pattern via `ref.watch(songProjectProvider).drumPatterns.firstWhere((p) => p.id == patternId)` (around line 56).
- Mutates via `ref.read(songProjectProvider.notifier).applyDrumPattern(...)` (around line 77) and `.toggleDrumStep(...)` (around line 167).
- Drives playback via `ref.read(drumPatternPlaybackProvider.notifier).start(...)` (around line 65).

The body refactor inverts the data dependency: pattern + tempo come in via constructor; mutations call back via `onChanged`. Playback continues to use `drumPatternPlaybackProvider` directly (it's already source-agnostic). Keep the `_DrumGrid` private widget reused as-is.

The old `DrumMachineEditor` wrapper retains the existing `Scaffold` / `AppBar`, reads from `songProjectProvider`, and forwards `onChanged` to `applyDrumPattern`. No visible behavior change in the Song feature.

**Verified `DrumPatternPlaybackNotifier.start` API** (`lib/store/drum_pattern_playback_store.dart:64`):

```dart
Future<void> start({required DrumPattern pattern, required int tempo}) async { … }
```

Used as-is by the new `DrumMachineEditorBody` transport row (Task 4 Step 2, TODO comment).

**Risks / edge cases:**
- **Orphaned `patternId`.** Covered by Task 3's `removeDrumPattern` cascade — clears `patternId` on all drum blocks. Block stays placed (start/span untouched) so user can re-assign a pattern.
- **Drum lane added to a Sheet view.** Sheet variant ignores drum lanes by design (`SongwriterScreenSheet` only iterates harmony lanes). Confirm Sheet still renders without crashing when a project has drum lanes (it should — `_SectionSheet.build` does not iterate all lanes).
- **`DrumPattern` JSON round-trip.** Patterns inside `SongwriterProjectSnapshot.toJson()` use the existing `DrumPattern.toJson()` shape (`lib/models/song_project.dart:345`); no schema duplication.
- **`addLane` signature change.** Verified additive (Task 3 addendum above). Re-run all songwriter tests after Task 3 to confirm no compile breakage from inferred void usage.
- **Pattern preview thumbnails.** Not implemented in this plan. Drum tile shows only the pattern name. Adding mini-grid previews is a follow-up.

**Branch strategy:**
- New branch off `writer-glass-retheme` (post-lyrics merge if both run sequentially): `songwriter-drum-lane`.
- If both plans run in parallel, base both off `writer-glass-retheme` and resolve any incidental conflict in `songwriter_screen_track.dart` / `songwriter_section_card.dart` (both plans touch these files in different regions: lyrics adds a footer row, drum adds a menu item).
- One PR at the end, scoped to `lib/features/songwriter/`, `lib/features/song/drum_machine_editor.dart`, `lib/models/songwriter.dart`, `lib/schema/rules/songwriter_rules.dart`, `lib/store/songwriter_store.dart`, plus the new test files.

**Out-of-scope reminders (do NOT do):**
- No songwriter transport drum scheduling (separate plan).
- No sheet variant drum surface.
- No `SongProject` → Songwriter pattern import.
- No drum tile mini-grid preview.
- Do not touch the `SongProject` storage layer or the Song feature's drum track type.
