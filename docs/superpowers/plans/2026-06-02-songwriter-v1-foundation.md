# Songwriter v1 — Plan B1: Foundation (model · rules · store) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless, fully-tested data + logic layer for the Songwriter tab — models, validation/derivation rules, the Riverpod store with session auto-save, and shared save/load wiring — with no screen UI yet.

**Architecture:** A new immutable model file (`lib/models/songwriter.dart`) defines the project/section/lane/block tree as a new `InstrumentSnapshot` subtype. A rules file (`lib/schema/rules/songwriter_rules.dart`) holds pure functions: Roman-numeral derivation, block-overlap validation, factories, and timeline flattening (repeat semantics). A store (`lib/store/songwriter_store.dart`) exposes CRUD + session persistence. Everything is verifiable with unit tests before any widget exists (Plan B2).

**Tech Stack:** Flutter, Riverpod (`NotifierProvider`), `shared_preferences`, `package:uuid` (via existing `generateId`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-02-songwriter-v1-design.md`
**Depends on:** Plan A (save grid) is independent; B1 does not require it. Plan B2 (UI) requires B1.

> **Read before starting:** `lib/models/save_system.dart` (`InstrumentSnapshot` sealed class ~54–76, `SongProjectSnapshot` ~354–402 as the closest sibling, `generateId` usage), `lib/schema/rules/save_system_rules.dart` (factory + validation style), `lib/store/song_*` session auto-save pattern, `lib/utils/note_utils.dart` (`chromaticNotes` line 24, `scaleIntervals` line 96, `getChordNotes` line 150, quality symbol list ~line 67). Run `flutter test` for a green baseline.

> **Model refinement vs spec §3.5:** harmony-block extras are `chordSymbol`, `chordQuality`, `chordRootPc`, `chordNotes`, `romanNumeral`. (Spec listed symbol/root/numeral; quality + notes are added so the numeral can be recomputed on key change and so `selectedNotes` can aggregate without re-detection. Same intent, more complete.)

---

### Task 1: `SongwriterConfig` + lane enum

**Files:**
- Create: `lib/models/songwriter.dart`
- Test: `test/models/songwriter_config_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/songwriter_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongwriterConfig round-trips with nullable key', () {
    const a = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    expect(a.keyRoot, isNull);
    final back = SongwriterConfig.fromJson(a.toJson());
    expect(back.tempo, 120);
    expect(back.beatsPerBar, 4);
    expect(back.keyRoot, isNull);

    final keyed = a.copyWith(keyRoot: 0, keyScaleName: 'major');
    final back2 = SongwriterConfig.fromJson(keyed.toJson());
    expect(back2.keyRoot, 0);
    expect(back2.keyScaleName, 'major');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/songwriter_config_test.dart`
Expected: FAIL — `songwriter.dart` does not exist.

- [ ] **Step 3: Implement config + enum**

```dart
// lib/models/songwriter.dart
/// Songwriter project model — section/lane/block arrangement tree.
library;

import 'save_system.dart';

enum SongLaneKind { harmony, save }

SongLaneKind _laneKindFromName(String? raw) {
  for (final v in SongLaneKind.values) {
    if (v.name == raw) return v;
  }
  return SongLaneKind.save;
}

class SongwriterConfig {
  final int tempo; // BPM
  final int beatsPerBar; // time-signature numerator
  final int beatUnit; // time-signature denominator
  final int? keyRoot; // pitch class 0-11, null = no key
  final String? keyScaleName; // e.g. 'major'

  const SongwriterConfig({
    required this.tempo,
    required this.beatsPerBar,
    required this.beatUnit,
    this.keyRoot,
    this.keyScaleName,
  });

  SongwriterConfig copyWith({
    int? tempo,
    int? beatsPerBar,
    int? beatUnit,
    int? keyRoot,
    String? keyScaleName,
    bool clearKey = false,
  }) =>
      SongwriterConfig(
        tempo: tempo ?? this.tempo,
        beatsPerBar: beatsPerBar ?? this.beatsPerBar,
        beatUnit: beatUnit ?? this.beatUnit,
        keyRoot: clearKey ? null : (keyRoot ?? this.keyRoot),
        keyScaleName: clearKey ? null : (keyScaleName ?? this.keyScaleName),
      );

  Map<String, dynamic> toJson() => {
        'tempo': tempo,
        'beatsPerBar': beatsPerBar,
        'beatUnit': beatUnit,
        'keyRoot': keyRoot,
        'keyScaleName': keyScaleName,
      };

  factory SongwriterConfig.fromJson(Map<String, dynamic> json) =>
      SongwriterConfig(
        tempo: json['tempo'] as int? ?? 120,
        beatsPerBar: json['beatsPerBar'] as int? ?? 4,
        beatUnit: json['beatUnit'] as int? ?? 4,
        keyRoot: json['keyRoot'] as int?,
        keyScaleName: json['keyScaleName'] as String?,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/songwriter_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/songwriter.dart test/models/songwriter_config_test.dart
git commit -m "feat(songwriter): config model + lane kind enum"
```

---

### Task 2: `SongBlock` model

**Files:**
- Modify: `lib/models/songwriter.dart`
- Test: `test/models/song_block_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/song_block_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('save-reference block round-trips', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 4,
      saveId: 'save-123',
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.id, 'b1');
    expect(back.spanBars, 4);
    expect(back.saveId, 'save-123');
    expect(back.embedded, isNull);
    expect(back.romanNumeral, isNull);
  });

  test('harmony block carries chord extras', () {
    const b = SongBlock(
      id: 'h1',
      startBar: 0,
      spanBars: 2,
      chordSymbol: 'Cmaj7',
      chordQuality: 'maj7',
      chordRootPc: 0,
      chordNotes: ['C', 'E', 'G', 'B'],
      romanNumeral: 'I',
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.chordSymbol, 'Cmaj7');
    expect(back.chordNotes, ['C', 'E', 'G', 'B']);
    expect(back.romanNumeral, 'I');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/song_block_test.dart`
Expected: FAIL — `SongBlock` not defined.

- [ ] **Step 3: Implement `SongBlock`**

Add to `lib/models/songwriter.dart`:

```dart
class SongBlock {
  final String id;
  final int startBar; // 0-based offset within the section
  final int spanBars; // width in bars

  // save-lane reference (live link into SaveSystemState.saves)
  final String? saveId;
  // non-null when "Made Unique" — detached snapshot copy
  final InstrumentSnapshot? embedded;

  // harmony-lane extras (null on save-lane blocks)
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;

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
  }) =>
      SongBlock(
        id: id,
        startBar: startBar ?? this.startBar,
        spanBars: spanBars ?? this.spanBars,
        saveId: saveId ?? this.saveId,
        embedded: embedded ?? this.embedded,
        chordSymbol: chordSymbol ?? this.chordSymbol,
        chordQuality: chordQuality ?? this.chordQuality,
        chordRootPc: chordRootPc ?? this.chordRootPc,
        chordNotes: chordNotes ?? this.chordNotes,
        romanNumeral: romanNumeral ?? this.romanNumeral,
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
      };

  factory SongBlock.fromJson(Map<String, dynamic> json) => SongBlock(
        id: json['id'] as String,
        startBar: json['startBar'] as int? ?? 0,
        spanBars: json['spanBars'] as int? ?? 1,
        saveId: json['saveId'] as String?,
        embedded: json['embedded'] == null
            ? null
            : InstrumentSnapshot.fromJson(
                json['embedded'] as Map<String, dynamic>),
        chordSymbol: json['chordSymbol'] as String?,
        chordQuality: json['chordQuality'] as String?,
        chordRootPc: json['chordRootPc'] as int?,
        chordNotes:
            (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
                const [],
        romanNumeral: json['romanNumeral'] as String?,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/song_block_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/songwriter.dart test/models/song_block_test.dart
git commit -m "feat(songwriter): block model"
```

---

### Task 3: `SongLane` + `SongSection` models

**Files:**
- Modify: `lib/models/songwriter.dart`
- Test: `test/models/song_section_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/song_section_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('lane round-trips with kind and repeat', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.harmony,
      label: 'Harmony',
      order: 0,
      repeat: 2,
      blocks: [SongBlock(id: 'b1', startBar: 0, spanBars: 1, saveId: 's1')],
    );
    final back = SongLane.fromJson(lane.toJson());
    expect(back.kind, SongLaneKind.harmony);
    expect(back.repeat, 2);
    expect(back.blocks.single.id, 'b1');
  });

  test('section round-trips with optional label and repeat', () {
    const section = SongSection(
      id: 's1',
      label: null,
      lengthBars: 8,
      order: 0,
      repeat: 1,
      lanes: [],
    );
    final back = SongSection.fromJson(section.toJson());
    expect(back.label, isNull);
    expect(back.lengthBars, 8);
    expect(back.lanes, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/song_section_test.dart`
Expected: FAIL — `SongLane`/`SongSection` not defined.

- [ ] **Step 3: Implement `SongLane` and `SongSection`**

Add to `lib/models/songwriter.dart`:

```dart
class SongLane {
  final String id;
  final SongLaneKind kind;
  final String? label;
  final int order;
  final int repeat; // tiles this lane's block pattern N times
  final List<SongBlock> blocks;

  const SongLane({
    required this.id,
    required this.kind,
    required this.order,
    this.label,
    this.repeat = 1,
    this.blocks = const [],
  });

  SongLane copyWith({
    SongLaneKind? kind,
    String? label,
    int? order,
    int? repeat,
    List<SongBlock>? blocks,
  }) =>
      SongLane(
        id: id,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        order: order ?? this.order,
        repeat: repeat ?? this.repeat,
        blocks: blocks ?? this.blocks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'order': order,
        'repeat': repeat,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory SongLane.fromJson(Map<String, dynamic> json) => SongLane(
        id: json['id'] as String,
        kind: _laneKindFromName(json['kind'] as String?),
        label: json['label'] as String?,
        order: json['order'] as int? ?? 0,
        repeat: json['repeat'] as int? ?? 1,
        blocks: (json['blocks'] as List?)
                ?.map((b) => SongBlock.fromJson(b as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class SongSection {
  final String id;
  final String? label; // optional free text
  final int lengthBars;
  final int order;
  final int repeat; // loops the whole section N times
  final List<SongLane> lanes;

  const SongSection({
    required this.id,
    required this.lengthBars,
    required this.order,
    this.label,
    this.repeat = 1,
    this.lanes = const [],
  });

  SongSection copyWith({
    String? label,
    int? lengthBars,
    int? order,
    int? repeat,
    List<SongLane>? lanes,
    bool clearLabel = false,
  }) =>
      SongSection(
        id: id,
        label: clearLabel ? null : (label ?? this.label),
        lengthBars: lengthBars ?? this.lengthBars,
        order: order ?? this.order,
        repeat: repeat ?? this.repeat,
        lanes: lanes ?? this.lanes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'lengthBars': lengthBars,
        'order': order,
        'repeat': repeat,
        'lanes': lanes.map((l) => l.toJson()).toList(),
      };

  factory SongSection.fromJson(Map<String, dynamic> json) => SongSection(
        id: json['id'] as String,
        label: json['label'] as String?,
        lengthBars: json['lengthBars'] as int? ?? 4,
        order: json['order'] as int? ?? 0,
        repeat: json['repeat'] as int? ?? 1,
        lanes: (json['lanes'] as List?)
                ?.map((l) => SongLane.fromJson(l as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/song_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/songwriter.dart test/models/song_section_test.dart
git commit -m "feat(songwriter): lane + section models"
```

---

### Task 4: `SongwriterProjectSnapshot` + register in `InstrumentSnapshot.fromJson`

**Files:**
- Modify: `lib/models/songwriter.dart` (add snapshot subtype)
- Modify: `lib/models/save_system.dart` (`InstrumentSnapshot.fromJson` branch + import)
- Test: `test/models/songwriter_snapshot_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/songwriter_snapshot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('snapshot round-trips through InstrumentSnapshot.fromJson', () {
    const snap = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 4,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.harmony,
              order: 0,
              blocks: [
                SongBlock(
                  id: 'b1',
                  startBar: 0,
                  spanBars: 2,
                  chordSymbol: 'C',
                  chordNotes: ['C', 'E', 'G'],
                  romanNumeral: 'I',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final json = snap.toJson();
    expect(json['type'], 'songwriter');

    final back = InstrumentSnapshot.fromJson(json);
    expect(back, isA<SongwriterProjectSnapshot>());
    final sw = back as SongwriterProjectSnapshot;
    expect(sw.sections.single.lanes.single.blocks.single.romanNumeral, 'I');
    expect(sw.instrument, 'songwriter');
    expect(sw.pendingChord, isNull);
    expect(sw.selectedNotes, containsAll(['C', 'E', 'G']));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/songwriter_snapshot_test.dart`
Expected: FAIL — `SongwriterProjectSnapshot` not defined / not dispatched.

- [ ] **Step 3a: Implement the snapshot in `songwriter.dart`**

```dart
class SongwriterProjectSnapshot extends InstrumentSnapshot {
  final SongwriterConfig config;
  final List<SongSection> sections;

  const SongwriterProjectSnapshot({
    required this.config,
    this.sections = const [],
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
    SongwriterConfig? config,
    List<SongSection>? sections,
  }) =>
      SongwriterProjectSnapshot(
        config: config ?? this.config,
        sections: sections ?? this.sections,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'songwriter',
        'instrument': 'songwriter',
        'config': config.toJson(),
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory SongwriterProjectSnapshot.fromJson(Map<String, dynamic> json) =>
      SongwriterProjectSnapshot(
        config: SongwriterConfig.fromJson(
            json['config'] as Map<String, dynamic>? ?? const {}),
        sections: (json['sections'] as List?)
                ?.map((s) => SongSection.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
```

- [ ] **Step 3b: Register the dispatch branch in `save_system.dart`**

Add the import at the top of `lib/models/save_system.dart` with the other model imports:

```dart
import 'songwriter.dart';
```

In `InstrumentSnapshot.fromJson` (currently `lib/models/save_system.dart:62`), add this branch **before** the piano/fretboard fallbacks:

```dart
    if (type == 'songwriter' || instrument == 'songwriter') {
      return SongwriterProjectSnapshot.fromJson(json);
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/songwriter_snapshot_test.dart`
Expected: PASS.

Run the existing save-system tests to confirm no regression:
Run: `flutter test test/models/`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/songwriter.dart lib/models/save_system.dart test/models/songwriter_snapshot_test.dart
git commit -m "feat(songwriter): project snapshot + InstrumentSnapshot dispatch"
```

---

### Task 5: Roman-numeral derivation rule

**Files:**
- Create: `lib/schema/rules/songwriter_rules.dart`
- Test: `test/schema/rules/songwriter_roman_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_roman_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  // Key of C major (keyRootPc 0).
  test('diatonic majors and minors in C major', () {
    expect(romanNumeralFor(0, 'major', 0, 'major'), 'I');
    expect(romanNumeralFor(2, 'minor', 0, 'major'), 'ii');
    expect(romanNumeralFor(4, 'minor', 0, 'major'), 'iii');
    expect(romanNumeralFor(5, 'major', 0, 'major'), 'IV');
    expect(romanNumeralFor(7, 'major', 0, 'major'), 'V');
    expect(romanNumeralFor(9, 'minor', 0, 'major'), 'vi');
    expect(romanNumeralFor(11, 'dim', 0, 'major'), 'vii°');
  });

  test('non-diatonic root returns null', () {
    expect(romanNumeralFor(1, 'major', 0, 'major'), isNull); // C# not in C major
  });

  test('null key returns null', () {
    expect(romanNumeralFor(0, 'major', null, null), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_roman_test.dart`
Expected: FAIL — file/function missing.

- [ ] **Step 3: Implement the rule**

```dart
// lib/schema/rules/songwriter_rules.dart
/// Songwriter pure rules: Roman-numeral derivation, overlap validation,
/// factories, and timeline flattening.
library;

import '../../utils/note_utils.dart';

const _romanByDegree = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];

/// Classifies a chord quality string into how its Roman numeral is cased.
/// Aligns with the quality strings used by note_utils chord detection.
String _caseNumeral(String degreeUpper, String quality) {
  final q = quality.toLowerCase();
  if (q.contains('dim')) return '${degreeUpper.toLowerCase()}°';
  if (q.contains('aug')) return '$degreeUpper+';
  // minor-ish: starts with 'm' but not 'maj'
  final isMinor = (q.startsWith('m') && !q.startsWith('maj')) ||
      q.contains('min');
  return isMinor ? degreeUpper.toLowerCase() : degreeUpper;
}

/// Returns the diatonic Roman numeral for a chord whose root is [chordRootPc]
/// (pitch class 0-11) in the key [keyRootPc]/[keyScaleName], or null when no
/// key is set or the chord root is not a scale degree of that key.
String? romanNumeralFor(
  int chordRootPc,
  String quality,
  int? keyRootPc,
  String? keyScaleName,
) {
  if (keyRootPc == null || keyScaleName == null) return null;
  final intervals = scaleIntervals[keyScaleName];
  if (intervals == null) return null;
  final offset = ((chordRootPc - keyRootPc) % 12 + 12) % 12;
  final degree = intervals.indexOf(offset);
  if (degree < 0 || degree >= _romanByDegree.length) return null;
  return _caseNumeral(_romanByDegree[degree], quality);
}
```

> The `_caseNumeral` heuristic must match the actual quality strings emitted by detection. Open `lib/utils/note_utils.dart` around line 67 (the quality symbol list) and confirm strings like `'major'`, `'minor'`, `'dim'`/`'diminished'`, `'aug'`/`'augmented'`. If a real quality string slips through wrong-cased, extend the heuristic — keep the test green and add a case for the real string.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_roman_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_roman_test.dart
git commit -m "feat(songwriter): roman numeral derivation rule"
```

---

### Task 6: Factories + block-overlap validation

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart`
- Test: `test/schema/rules/songwriter_overlap_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_overlap_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('non-overlapping blocks with a gap are valid', () {
    final blocks = [
      const SongBlock(id: 'a', startBar: 0, spanBars: 2),
      const SongBlock(id: 'b', startBar: 4, spanBars: 2), // gap at 2-4 ok
    ];
    expect(blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 2, spanBars: 2)),
        isFalse);
  });

  test('overlapping placement is rejected', () {
    final blocks = [const SongBlock(id: 'a', startBar: 0, spanBars: 4)];
    expect(blocksOverlap(blocks, const SongBlock(id: 'c', startBar: 2, spanBars: 2)),
        isTrue);
  });

  test('makeSection produces a valid id and defaults', () {
    final s = makeSection(label: 'Verse', lengthBars: 8, order: 0);
    expect(s.id, isNotEmpty);
    expect(s.lengthBars, 8);
    expect(s.repeat, 1);
    expect(s.lanes, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_overlap_test.dart`
Expected: FAIL — `blocksOverlap`/`makeSection` missing.

- [ ] **Step 3: Implement factories + overlap check**

Add to `lib/schema/rules/songwriter_rules.dart`:

```dart
import '../../models/songwriter.dart';
import 'save_system_rules.dart' show generateId;

/// True if [candidate] overlaps any block in [existing] (same lane).
/// Gaps are allowed; touching edges (one ends where the next starts) is not
/// an overlap.
bool blocksOverlap(List<SongBlock> existing, SongBlock candidate) {
  for (final b in existing) {
    if (b.id == candidate.id) continue;
    final overlaps =
        candidate.startBar < b.endBar && b.startBar < candidate.endBar;
    if (overlaps) return true;
  }
  return false;
}

SongSection makeSection({String? label, required int lengthBars, required int order}) =>
    SongSection(id: generateId(), label: label, lengthBars: lengthBars, order: order);

SongLane makeLane({required SongLaneKind kind, String? label, required int order}) =>
    SongLane(id: generateId(), kind: kind, label: label, order: order);

SongBlock makeSaveBlock({
  required String saveId,
  required int startBar,
  required int spanBars,
}) =>
    SongBlock(
        id: generateId(), saveId: saveId, startBar: startBar, spanBars: spanBars);

SongBlock makeHarmonyBlock({
  required int startBar,
  required int spanBars,
  required String chordSymbol,
  required String chordQuality,
  required int chordRootPc,
  required List<String> chordNotes,
  String? romanNumeral,
}) =>
    SongBlock(
      id: generateId(),
      startBar: startBar,
      spanBars: spanBars,
      chordSymbol: chordSymbol,
      chordQuality: chordQuality,
      chordRootPc: chordRootPc,
      chordNotes: chordNotes,
      romanNumeral: romanNumeral,
    );
```

> Confirm `generateId` is exported from `lib/schema/rules/save_system_rules.dart`; if its name differs, import the correct symbol.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_overlap_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_overlap_test.dart
git commit -m "feat(songwriter): factories + block overlap validation"
```

---

### Task 7: Timeline flattening + repeat semantics (spec §4.4)

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart`
- Test: `test/schema/rules/songwriter_flatten_test.dart`

> This task encodes the spec's most subtle rule. Read spec §4.4 before implementing.

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_flatten_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('total flattened bars expands section repeats', () {
    const sections = [
      SongSection(id: 's1', lengthBars: 4, order: 0, repeat: 2), // 8
      SongSection(id: 's2', lengthBars: 8, order: 1, repeat: 1), // 8
    ];
    expect(flattenedBarCount(sections), 16);
  });

  test('lane tiling expands a 2-bar pattern to fill via repeat', () {
    // A 2-bar pattern (block at 0..2) tiled x2 -> placements at bar 0 and bar 2.
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.save,
      order: 0,
      repeat: 2,
      blocks: [SongBlock(id: 'b', startBar: 0, spanBars: 2, saveId: 's')],
    );
    final placed = tileLaneBlocks(lane, sectionLengthBars: 8);
    expect(placed.map((p) => p.startBar), [0, 2]);
  });

  test('tiled content is clipped to the section length', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.save,
      order: 0,
      repeat: 5, // would run to bar 10
      blocks: [SongBlock(id: 'b', startBar: 0, spanBars: 2, saveId: 's')],
    );
    final placed = tileLaneBlocks(lane, sectionLengthBars: 4);
    // patterns at 0 and 2 fit; 4,6,8 are clipped out
    expect(placed.map((p) => p.startBar), [0, 2]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_flatten_test.dart`
Expected: FAIL — functions missing.

- [ ] **Step 3: Implement flattening**

Add to `lib/schema/rules/songwriter_rules.dart`:

```dart
/// Total bar length of the whole project after expanding section repeats.
int flattenedBarCount(List<SongSection> sections) {
  var total = 0;
  for (final s in sections) {
    total += s.lengthBars * s.repeat;
  }
  return total;
}

/// Natural pattern length of a lane = the max block end bar (0 if empty).
int laneNaturalLength(SongLane lane) {
  var max = 0;
  for (final b in lane.blocks) {
    if (b.endBar > max) max = b.endBar;
  }
  return max;
}

/// Expands a lane's blocks into concrete placements, tiling the block pattern
/// [lane.repeat] times from bar 0, clipped to [sectionLengthBars]. A placement
/// keeps the original block but offsets its startBar by the tile origin; any
/// placement that would start at or beyond the section length is dropped, and
/// a placement is dropped if its (offset) startBar >= sectionLengthBars.
List<SongBlock> tileLaneBlocks(SongLane lane, {required int sectionLengthBars}) {
  final pattern = laneNaturalLength(lane);
  if (pattern <= 0) return const [];
  final out = <SongBlock>[];
  for (var tile = 0; tile < lane.repeat; tile++) {
    final origin = tile * pattern;
    if (origin >= sectionLengthBars) break;
    for (final b in lane.blocks) {
      final start = origin + b.startBar;
      if (start >= sectionLengthBars) continue;
      out.add(b.copyWith(startBar: start));
    }
  }
  return out;
}
```

> Note: blocks that start inside the section but whose span extends past it are kept (the visual/highlight clips at the section edge); only blocks that *start* at/after the section end are dropped. This matches "a lane never plays past its section."

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_flatten_test.dart`
Expected: PASS (all 3).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_flatten_test.dart
git commit -m "feat(songwriter): timeline flatten + repeat tiling"
```

---

### Task 8: Songwriter store (CRUD + Make Unique + session persistence)

**Files:**
- Create: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add section, add lane, add block', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 8);
    final sectionId = c.read(songwriterProvider).sections.single.id;

    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final laneId =
        c.read(songwriterProvider).sections.single.lanes.single.id;

    n.addSaveBlock(
        sectionId: sectionId, laneId: laneId, saveId: 'save-1',
        startBar: 0, spanBars: 4);

    final block = c
        .read(songwriterProvider)
        .sections.single.lanes.single.blocks.single;
    expect(block.saveId, 'save-1');
    expect(block.spanBars, 4);
  });

  test('overlapping block add is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'a', startBar: 0, spanBars: 4);
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'b', startBar: 2, spanBars: 4);
    expect(
        c.read(songwriterProvider).sections.single.lanes.single.blocks.length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_store_test.dart`
Expected: FAIL — `songwriterProvider` missing.

- [ ] **Step 3: Implement the store**

```dart
// lib/store/songwriter_store.dart
/// Songwriter project Riverpod store with debounced session auto-save.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/songwriter.dart';
import '../schema/rules/songwriter_rules.dart';

const _sessionKey = '@muzician/songwriter_session/v1';

SongwriterProjectSnapshot _emptyProject() => const SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );

class SongwriterNotifier extends Notifier<SongwriterProjectSnapshot> {
  Timer? _debounce;

  @override
  SongwriterProjectSnapshot build() {
    ref.onDispose(() => _debounce?.cancel());
    return _emptyProject();
  }

  // ── session persistence ──
  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null) {
      try {
        state = SongwriterProjectSnapshot.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(state.toJson()));
    });
  }

  void _set(SongwriterProjectSnapshot next) {
    state = next;
    _schedulePersist();
  }

  Future<void> newProject() async {
    _set(_emptyProject());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  // ── config ──
  void setKey(int? root, String? scaleName) {
    final cfg = (root == null)
        ? state.config.copyWith(clearKey: true)
        : state.config.copyWith(keyRoot: root, keyScaleName: scaleName);
    _set(state.copyWith(config: cfg));
    if (root != null) _recomputeNumerals();
  }

  void setTempo(int tempo) =>
      _set(state.copyWith(config: state.config.copyWith(tempo: tempo)));

  // ── sections ──
  void addSection({String? label, required int lengthBars}) {
    final section =
        makeSection(label: label, lengthBars: lengthBars, order: state.sections.length);
    _set(state.copyWith(sections: [...state.sections, section]));
  }

  void _replaceSection(String sectionId, SongSection Function(SongSection) f) {
    _set(state.copyWith(
      sections: state.sections
          .map((s) => s.id == sectionId ? f(s) : s)
          .toList(),
    ));
  }

  // ── lanes ──
  void addLane({required String sectionId, required SongLaneKind kind, String? label}) {
    _replaceSection(sectionId, (s) {
      final lane = makeLane(kind: kind, label: label, order: s.lanes.length);
      return s.copyWith(lanes: [...s.lanes, lane]);
    });
  }

  void _replaceLane(
      String sectionId, String laneId, SongLane Function(SongLane) f) {
    _replaceSection(sectionId, (s) => s.copyWith(
          lanes: s.lanes.map((l) => l.id == laneId ? f(l) : l).toList(),
        ));
  }

  // ── blocks ──
  void addSaveBlock({
    required String sectionId,
    required String laneId,
    required String saveId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      final candidate =
          makeSaveBlock(saveId: saveId, startBar: startBar, spanBars: spanBars);
      if (blocksOverlap(l.blocks, candidate)) return l; // ignore overlaps
      return l.copyWith(blocks: [...l.blocks, candidate]);
    });
  }

  void addHarmonyBlock({
    required String sectionId,
    required String laneId,
    required SongBlock block, // build with makeHarmonyBlock at the call site
  }) {
    _replaceLane(sectionId, laneId, (l) {
      if (blocksOverlap(l.blocks, block)) return l;
      return l.copyWith(blocks: [...l.blocks, block]);
    });
  }

  void removeBlock(
      {required String sectionId, required String laneId, required String blockId}) {
    _replaceLane(sectionId, laneId, (l) =>
        l.copyWith(blocks: l.blocks.where((b) => b.id != blockId).toList()));
  }

  /// Make Unique: detach a block from its live save by embedding a snapshot.
  void makeBlockUnique({
    required String sectionId,
    required String laneId,
    required String blockId,
    required InstrumentSnapshot snapshot,
  }) {
    _replaceLane(sectionId, laneId, (l) => l.copyWith(
          blocks: l.blocks
              .map((b) => b.id == blockId ? b.copyWith(embedded: snapshot) : b)
              .toList(),
        ));
  }

  void _recomputeNumerals() {
    final key = state.config;
    _set(state.copyWith(
      sections: state.sections
          .map((s) => s.copyWith(
                lanes: s.lanes
                    .map((l) => l.kind != SongLaneKind.harmony
                        ? l
                        : l.copyWith(
                            blocks: l.blocks.map((b) {
                              if (b.chordRootPc == null ||
                                  b.chordQuality == null) {
                                return b;
                              }
                              return b.copyWith(
                                romanNumeral: romanNumeralFor(
                                  b.chordRootPc!,
                                  b.chordQuality!,
                                  key.keyRoot,
                                  key.keyScaleName,
                                ),
                              );
                            }).toList(),
                          ))
                    .toList(),
              ))
          .toList(),
    ));
  }

  /// Replace the whole project (used when loading a named save).
  void loadProject(SongwriterProjectSnapshot project) => _set(project);
}

final songwriterProvider =
    NotifierProvider<SongwriterNotifier, SongwriterProjectSnapshot>(
  SongwriterNotifier.new,
);
```

> `_recomputeNumerals` calls `_set`, which re-persists — acceptable. If `setKey` with a non-null root should not double-persist, it is harmless here.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_store_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_store_test.dart
git commit -m "feat(songwriter): project store with session autosave"
```

---

### Task 9: Session restore test + full verification

**Files:**
- Test: `test/store/songwriter_session_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  test('hydrate restores a persisted session', () async {
    SharedPreferences.setMockInitialValues({});

    // First container: add a section, let the debounce flush.
    final c1 = ProviderContainer();
    c1.read(songwriterProvider.notifier).addSection(label: 'Chorus', lengthBars: 8);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    c1.dispose();

    // Second container: hydrate from the same mock prefs.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    await c2.read(songwriterProvider.notifier).hydrate();
    final sections = c2.read(songwriterProvider).sections;
    expect(sections.single.label, 'Chorus');
  });
}
```

- [ ] **Step 2: Run test to verify it fails (or passes)**

Run: `flutter test test/store/songwriter_session_test.dart`
Expected: PASS if the store is correct. If it FAILS because the debounce did not flush, increase the delay to 800 ms — do not change persistence behavior.

- [ ] **Step 3: Full analyze + test sweep**

Run: `dart format lib/models/songwriter.dart lib/schema/rules/songwriter_rules.dart lib/store/songwriter_store.dart lib/models/save_system.dart`
Run: `flutter analyze`
Run: `flutter test test/models/ test/schema/rules/ test/store/`
Expected: analyze clean; all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add test/store/songwriter_session_test.dart
git commit -m "test(songwriter): session restore coverage"
```

---

## Self-Review Notes

- **Spec coverage:** model §3.1–3.6 (Tasks 1–4), Roman numerals §4.1 (Task 5), broken-ref resolution is data-only (`embedded`/`saveId` present; UI renders broken in B2), Make Unique §4.3 (Task 8), repeat semantics §4.4 (Task 7), session auto-save §4.5 (Tasks 8–9). Named save/load §4.6 and all UI are **Plan B2**. ✓
- **Deferred to B2 (intentional):** the `'songwriter'` save-browser filter wiring, the tab, all widgets, transport, tap-into-save, structure editor.
- **Type consistency:** `SongwriterProjectSnapshot{config,sections}`, `SongSection{...,lengthBars,repeat,lanes}`, `SongLane{kind,repeat,blocks}`, `SongBlock{startBar,spanBars,saveId,embedded,chord*}`, `romanNumeralFor(int,String,int?,String?)`, store method names used identically in tests and impl. ✓
- **Placeholder scan:** none. Every code step is complete.

---

## Next plans (not written yet — write after B1 lands so they reflect real APIs)
- **Plan B2 — Songwriter UI:** tab + nav, section/lane/block widgets, structure-editor modal, transport reuse, palette wiring (consumes Plan A `onPick`), tap-into-save isolated editor, named save/load filter `'songwriter'`.
- **Plan (chord wheel):** circle-of-fifths diatonic picker feeding the harmony lane.
- **Plan C — enrichment:** arpeggio/sequence save type + suggestion rules.
