# Songwriter — Phase C v2-a: 3rd-Above Harmony Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Read `docs/superpowers/HANDOFF-songwriter.md` and `docs/superpowers/specs/2026-06-04-songwriter-c-v2a-third-above-design.md` first.**

**Goal:** Tap a harmony block → existing harmony sheet now has two tabs (Voicings + Harmony); the Harmony tab shows one card with the full chord shifted up a diatonic 3rd as a piano highlight; one-tap accept persists a `PianoSnapshot` in a "Songwriter harmonies" folder + adds a save-lane block aligned to the harmony block's bars.

**Architecture:** Pure rule `suggestThirdAbove(chordRootPc, chordQuality, chordTonePcs, keyRootPc, keyScaleName)` emits a `ThirdAboveSuggestion?`. Snapshot factory `thirdAboveToSnapshot` wraps it as a `PianoSnapshot` anchored in the C4..B4 octave. The store gains `acceptThirdAboveSuggestion` (mirrors C v1's `acceptVoicingSuggestion`, but lands in a new "Songwriter harmonies" folder). The existing `showHarmonyBlockSheet` is refactored to `DefaultTabController` (Voicings | Harmony). Tile `_onTap` computes both suggestions and routes both onAccept callbacks.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses `PianoSnapshot`, `PianoCoordinate`, `SavePreviewThumbnail`, `chromaticNotes`, `noteToPC`, `scaleIntervals`, the songwriter store inserters + `_findOrCreateSaveLane`, the save-system store's `createSaveFolder` / `saveSnapshot`.

**Spec:** `docs/superpowers/specs/2026-06-04-songwriter-c-v2a-third-above-design.md` (decisions C2A-1 through C2A-5).
**Depends on:** C v1 (done on branch `worktree-songwriter-ux-polish` — 33 commits ahead of main).

> **Read before starting:**
> - `lib/utils/note_utils.dart` (lines 24-156: `chromaticNotes`, `noteToPC`, `scaleIntervals`, `getChordNotes`)
> - `lib/models/save_system.dart` (line 162: `PianoSnapshot` constructor — `currentRange`, `selectedKeys`, `selectedNotes`, `viewMode`, optional `pendingChord`/`pendingScale`)
> - `lib/models/piano.dart` (line 6: `enum PianoRangeName { key88, key61, key49 }`; line 45: `PianoCoordinate({keyIndex, midiNote, noteName})`; line 71: `enum PianoViewMode { exact, exactFocus }`)
> - `lib/schema/rules/piano_rules.dart` (lines 11-29: range table — `key49 startMidi 36`, `key61 startMidi 36`, `key88 startMidi 21`; line 46: `getKeysForRange` uses `keyIndex: keys.length`, confirming `keyIndex` is range-relative)
> - `lib/schema/rules/songwriter_voicing_rules.dart` (C v1 — same shape as the new rule file should follow)
> - `lib/store/songwriter_store.dart` (the existing `acceptVoicingSuggestion` near the bottom + helpers `_findOrCreateVoicingsFolder`, `_findOrCreateSaveLane`, top-level `_voicingsFolderName` const — model the new harmony action on this)
> - `lib/features/songwriter/songwriter_block_preview.dart` (existing `showHarmonyBlockSheet` with `suggestions` param + `_VoicingCard` — these need refactoring)
> - `lib/features/songwriter/songwriter_block_tile.dart` (existing `_onTap` harmony branch from C v1 Task 4)
> - `test/features/songwriter/songwriter_voicing_sheet_test.dart` (calls `showHarmonyBlockSheet(... suggestions: ...)` — must rename to `voicings:` and add `thirdAbove` + `onAcceptThirdAbove`)
> - `test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart` (asserts `find.text('Suggested voicings')` — when the strip moves inside a TabBarView, the Voicings tab must be selected for the heading to appear)

Run `flutter test` for a green baseline (430 tests after C v1).

---

### Task 1: 3rd-above pure rule + snapshot factory

**Files:**
- Create: `lib/schema/rules/songwriter_third_above_rules.dart`
- Test: `test/schema/rules/songwriter_third_above_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_third_above_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';

void main() {
  test('C major in C major key → targets E, G, B', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7], // C, E, G
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [4, 7, 11]); // E, G, B
    expect(s.label, '3rd above (E, G, B)');
  });

  test('A minor (A, C, E) in C major key → targets C, E, G', () {
    final s = suggestThirdAbove(
      chordRootPc: 9,
      chordQuality: 'm',
      chordTonePcs: const [9, 0, 4], // A, C, E
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [0, 4, 7]); // C, E, G
  });

  test('Bdim (B, D, F) in C major key → targets D, F, A', () {
    final s = suggestThirdAbove(
      chordRootPc: 11,
      chordQuality: 'dim',
      chordTonePcs: const [11, 2, 5], // B, D, F
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [2, 5, 9]); // D, F, A
  });

  test('G major (G, B, D) in F major key → drops non-diatonic B', () {
    // F major scale: F, G, A, Bb, C, D, E (pcs 5,7,9,10,0,2,4)
    // B (pc 11) is NOT in F major → skipped.
    // Remaining source pcs: G (7) → 3rd up is Bb (10). D (2) → 3rd up is F (5).
    final s = suggestThirdAbove(
      chordRootPc: 7,
      chordQuality: '',
      chordTonePcs: const [7, 11, 2], // G, B, D
      keyRootPc: 5, // F
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [10, 5]); // Bb, F
  });

  test('no key → null', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7],
      keyRootPc: null,
      keyScaleName: null,
    );
    expect(s, isNull);
  });

  test('unknown scale → null', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7],
      keyRootPc: 0,
      keyScaleName: 'nonexistent',
    );
    expect(s, isNull);
  });

  test('chord fully non-diatonic → null', () {
    // F# major triad (6, 10, 1) in C major key (0,2,4,5,7,9,11):
    // all three pcs are non-diatonic → null.
    final s = suggestThirdAbove(
      chordRootPc: 6,
      chordQuality: '',
      chordTonePcs: const [6, 10, 1], // F#, A#, C#
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNull);
  });

  test('thirdAboveToSnapshot round-trip', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7],
      keyRootPc: 0,
      keyScaleName: 'major',
    )!;
    final snap = thirdAboveToSnapshot(s);
    expect(snap.currentRange, PianoRangeName.key49);
    expect(snap.viewMode, PianoViewMode.exact);
    expect(snap.selectedNotes, ['E', 'G', 'B']);
    expect(snap.selectedKeys.length, 3);
    // Anchored octave: midi 60..71. For E,G,B that's 64, 67, 71.
    // key49 startMidi=36 → keyIndex = midi - 36 → 28, 31, 35.
    final byMidi = {for (final k in snap.selectedKeys) k.midiNote: k};
    expect(byMidi[64]!.keyIndex, 28);
    expect(byMidi[64]!.noteName, 'E');
    expect(byMidi[67]!.keyIndex, 31);
    expect(byMidi[71]!.keyIndex, 35);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/schema/rules/songwriter_third_above_test.dart`
Expected: FAIL — file/symbols missing.

- [ ] **Step 3: Implement**

Create `lib/schema/rules/songwriter_third_above_rules.dart`:

```dart
/// 3rd-above harmony suggestion rule for the Songwriter Phase C v2-a slice.
///
/// Given a harmony block's chord and the project key, returns a single
/// [ThirdAboveSuggestion] that shifts each source pitch class up by a
/// diatonic 3rd in the key. Source pcs not in the key's scale are dropped.
/// Returns null when no key is set, when the scale is unknown, or when the
/// chord is fully non-diatonic.
library;

import '../../models/piano.dart';
import '../../models/save_system.dart';
import '../../utils/note_utils.dart';

class ThirdAboveSuggestion {
  const ThirdAboveSuggestion({
    required this.rootPc,
    required this.quality,
    required this.sourcePcs,
    required this.targetPcs,
    required this.midiKeys,
    required this.label,
  });
  final int rootPc;
  final String quality;
  final List<int> sourcePcs;
  final List<int> targetPcs;
  final List<int> midiKeys;
  final String label;
}

/// Returns a single 3rd-above suggestion or null when the chord/key combo
/// has no diatonic targets.
ThirdAboveSuggestion? suggestThirdAbove({
  required int chordRootPc,
  required String chordQuality,
  required List<int> chordTonePcs,
  required int? keyRootPc,
  required String? keyScaleName,
}) {
  if (keyRootPc == null || keyScaleName == null) return null;
  final intervals = scaleIntervals[keyScaleName];
  if (intervals == null || intervals.length < 7) return null;

  final targetPcs = <int>[];
  for (final sourcePc in chordTonePcs) {
    final offset = ((sourcePc - keyRootPc) % 12 + 12) % 12;
    final degree = intervals.indexOf(offset);
    if (degree < 0) continue; // source pc not in scale — drop
    final targetDegree = (degree + 2) % 7;
    final targetPc = (keyRootPc + intervals[targetDegree]) % 12;
    if (!targetPcs.contains(targetPc)) targetPcs.add(targetPc);
  }
  if (targetPcs.isEmpty) return null;

  // Octave anchoring: midi 60..71 (C4..B4).
  final midiKeys = [for (final pc in targetPcs) 60 + pc];

  final names = targetPcs.map((pc) => chromaticNotes[pc]).join(', ');
  return ThirdAboveSuggestion(
    rootPc: chordRootPc,
    quality: chordQuality,
    sourcePcs: List.unmodifiable(chordTonePcs),
    targetPcs: List.unmodifiable(targetPcs),
    midiKeys: List.unmodifiable(midiKeys),
    label: '3rd above ($names)',
  );
}

/// Wraps a suggestion as a PianoSnapshot anchored in key49's middle octave.
PianoSnapshot thirdAboveToSnapshot(ThirdAboveSuggestion s) {
  // key49: startMidi = 36 (C2). keyIndex = midi - startMidi.
  const startMidi = 36;
  return PianoSnapshot(
    currentRange: PianoRangeName.key49,
    selectedKeys: [
      for (final m in s.midiKeys)
        PianoCoordinate(
          keyIndex: m - startMidi,
          midiNote: m,
          noteName: chromaticNotes[m % 12],
        ),
    ],
    selectedNotes: [for (final pc in s.targetPcs) chromaticNotes[pc]],
    viewMode: PianoViewMode.exact,
  );
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/schema/rules/songwriter_third_above_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_third_above_rules.dart test/schema/rules/songwriter_third_above_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): 3rd-above harmony rule + snapshot factory

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Store action — `acceptThirdAboveSuggestion`

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_third_above_accept_test.dart`

Mirror the C v1 `acceptVoicingSuggestion` pattern but write into a new "Songwriter harmonies" folder. `_findOrCreateSaveLane` is reused unchanged.

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_third_above_accept_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

VoicingSuggestion firstVoicingForC() =>
    suggestVoicings(chordRootPc: 0, quality: '').first;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(saveSystemProvider.notifier);
    return c;
  }

  ({String sectionId, String harmonyLaneId, String harmonyBlockId})
      seedSongWithHarmonyBlock(ProviderContainer c) {
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );
    return (sectionId: s, harmonyLaneId: l, harmonyBlockId: 'hb1');
  }

  ThirdAboveSuggestion freshSuggestion() => suggestThirdAbove(
        chordRootPc: 0,
        chordQuality: '',
        chordTonePcs: const [0, 4, 7],
        keyRootPc: 0,
        keyScaleName: 'major',
      )!;

  test('accept creates SaveEntry in auto-created "Songwriter harmonies" '
      'folder + save lane + block', () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);

    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final saves = c.read(saveSystemProvider);
    final folder = saves.folders
        .where((f) => f.name == 'Songwriter harmonies')
        .toList();
    expect(folder.length, 1);
    expect(folder.single.parentId, isNull);
    final newSave = saves.saves.firstWhere(
      (s) => s.folderId == folder.single.id,
    );
    expect(newSave.name, contains('C'));
    expect(newSave.name, contains('3rd above'));

    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLane = section.lanes.firstWhere(
      (l) => l.kind == SongLaneKind.save,
    );
    final block = saveLane.blocks.single;
    expect(block.saveId, newSave.id);
    expect(block.startBar, 0);
    expect(block.spanBars, 2);
  });

  test('second accept reuses both folder and save lane', () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);

    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );
    // Move the first block out of the way so the second accept doesn't
    // hit blocksOverlap.
    final firstBlockId = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .blocks
        .single
        .id;
    final saveLaneId = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .id;
    c.read(songwriterProvider.notifier).setBlockPlacement(
          sectionId: ids.sectionId,
          laneId: saveLaneId,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final folders = c
        .read(saveSystemProvider)
        .folders
        .where((f) => f.name == 'Songwriter harmonies')
        .toList();
    expect(folders.length, 1, reason: 'folder must not duplicate');
    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLanes =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList();
    expect(saveLanes.length, 1, reason: 'save lane must be reused');
    expect(saveLanes.single.blocks.length, 2);
  });

  test('harmonies and voicings folders coexist when both accept flows fire',
      () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);

    // Accept a voicing first (uses 'Songwriter voicings' folder).
    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: firstVoicingForC(),
        );
    // Move the voicing block out of the way.
    final saveLaneId = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .id;
    final firstBlockId = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .blocks
        .single
        .id;
    c.read(songwriterProvider.notifier).setBlockPlacement(
          sectionId: ids.sectionId,
          laneId: saveLaneId,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    // Now accept a 3rd-above harmony.
    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final folderNames = c
        .read(saveSystemProvider)
        .folders
        .map((f) => f.name)
        .toSet();
    expect(folderNames, containsAll(['Songwriter voicings', 'Songwriter harmonies']));
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_third_above_accept_test.dart`
Expected: FAIL — `acceptThirdAboveSuggestion` missing.

- [ ] **Step 3: Implement**

In `lib/store/songwriter_store.dart`:

1. Add a top-level const next to the existing `_voicingsFolderName`:

```dart
/// Name of the root-level folder that holds accepted 3rd-above harmonies.
const _harmoniesFolderName = 'Songwriter harmonies';
```

2. Add the import (if not already imported) right after the existing imports — the file already imports `songwriter_voicing_rules.dart`, add `songwriter_third_above_rules.dart`:

```dart
import '../schema/rules/songwriter_third_above_rules.dart';
```

3. Append a new method on `SongwriterNotifier`, placing it right after `acceptVoicingSuggestion` and before `_recomputeNumerals` (or wherever v1 placed its helper — keep co-located with the v1 accept):

```dart
/// Persists a 3rd-above harmony suggestion as a SaveEntry in the auto-created
/// "Songwriter harmonies" folder and inserts a save-lane block aligned to the
/// triggering harmony block's bars.
Future<void> acceptThirdAboveSuggestion({
  required String sectionId,
  required String harmonyBlockId,
  required ThirdAboveSuggestion suggestion,
}) async {
  final section = state.sections.firstWhere(
    (s) => s.id == sectionId,
    orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
  );
  if (section.id.isEmpty) return;
  SongBlock? harmonyBlock;
  for (final lane in section.lanes) {
    for (final b in lane.blocks) {
      if (b.id == harmonyBlockId) {
        harmonyBlock = b;
        break;
      }
    }
    if (harmonyBlock != null) break;
  }
  if (harmonyBlock == null) return;

  final saves = ref.read(saveSystemProvider.notifier);
  final folderId = _findOrCreateHarmoniesFolder(saves);
  if (folderId == null) return;

  final rootName = chromaticNotes[suggestion.rootPc];
  final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
  final saveId =
      saves.saveSnapshot(saveName, folderId, thirdAboveToSnapshot(suggestion));
  if (saveId == null) return;

  final laneId = _findOrCreateSaveLane(sectionId);
  if (laneId == null) return;

  addSaveBlock(
    sectionId: sectionId,
    laneId: laneId,
    saveId: saveId,
    startBar: harmonyBlock.startBar,
    spanBars: harmonyBlock.spanBars,
  );
}

String? _findOrCreateHarmoniesFolder(SaveSystemNotifier saves) {
  final existing = ref
      .read(saveSystemProvider)
      .folders
      .where((f) => f.parentId == null && f.name == _harmoniesFolderName)
      .toList();
  if (existing.isNotEmpty) return existing.first.id;
  return saves.createSaveFolder(_harmoniesFolderName, null);
}
```

> If the existing v1 code already imports `note_utils.dart`, don't add a duplicate import. Verify with `grep -n "note_utils\|songwriter_third_above_rules" lib/store/songwriter_store.dart` before editing.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_third_above_accept_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_third_above_accept_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): acceptThirdAboveSuggestion store action

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Tabbed harmony sheet — Voicings | Harmony

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_preview.dart`
- Test: `test/features/songwriter/songwriter_third_above_sheet_test.dart`

Refactor `showHarmonyBlockSheet` so the body uses `DefaultTabController` + `TabBar` + `TabBarView`. The chord header + chord-note chips stay above the tabs. Voicings tab content = the existing CAGED card strip. Harmony tab content = a single `_ThirdAboveCard` or an empty-state message.

The `suggestions` parameter is renamed to `voicings`, and two new parameters are added: `thirdAbove` and `onAcceptThirdAbove`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_third_above_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

void main() {
  ThirdAboveSuggestion freshThird() => suggestThirdAbove(
        chordRootPc: 0,
        chordQuality: '',
        chordTonePcs: const [0, 4, 7],
        keyRootPc: 0,
        keyScaleName: 'major',
      )!;

  testWidgets('sheet has Voicings + Harmony tabs', (tester) async {
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: freshThird(),
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsOneWidget);
  });

  testWidgets('switching to Harmony tab shows the third-above card '
      'and tapping it fires onAcceptThirdAbove', (tester) async {
    ThirdAboveSuggestion? picked;
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: freshThird(),
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (s) => picked = s,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Harmony'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('thirdAboveCard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('thirdAboveCard')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.targetPcs, [4, 7, 11]);
  });

  testWidgets('Harmony tab shows "Set a key" message when thirdAbove is null '
      'and no key context', (tester) async {
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: null,
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Harmony'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Set a key'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_third_above_sheet_test.dart`
Expected: FAIL — sheet still uses the v1 signature.

- [ ] **Step 3: Implement**

In `lib/features/songwriter/songwriter_block_preview.dart`:

1. Add the new import next to the existing `songwriter_voicing_rules.dart` import:

```dart
import '../../schema/rules/songwriter_third_above_rules.dart';
```

2. Replace the entire `showHarmonyBlockSheet` function with the tabbed version (and rename the parameter). Keep `_VoicingCard` and any other unrelated code in the file unchanged.

```dart
/// Opens the harmony-block sheet with two tabs:
/// - **Voicings**: horizontal strip of CAGED voicing cards (C v1).
/// - **Harmony**: one 3rd-above card or an empty state.
/// Tapping a card invokes the matching onAccept callback and closes the sheet.
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> voicings,
  required ThirdAboveSuggestion? thirdAbove,
  required void Function(VoicingSuggestion) onAcceptVoicing,
  required void Function(ThirdAboveSuggestion) onAcceptThirdAbove,
}) {
  final hasChord = block.chordRootPc != null && block.chordQuality != null;
  final title = block.chordSymbol ?? (hasChord ? '?' : 'Harmony');
  final numeral = block.romanNumeral;

  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note, size: 24),
                  const SizedBox(width: 8),
                  Text(title,
                      style: Theme.of(sheetCtx).textTheme.titleMedium),
                  if (numeral != null) ...[
                    const SizedBox(width: 8),
                    Text(numeral,
                        style: Theme.of(sheetCtx)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey)),
                  ],
                ],
              ),
              if (block.chordNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in block.chordNotes)
                      Chip(
                        label: Text(n),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const TabBar(
                tabs: [
                  Tab(text: 'Voicings'),
                  Tab(text: 'Harmony'),
                ],
              ),
              SizedBox(
                height: 170,
                child: TabBarView(
                  children: [
                    _VoicingsTab(
                      hasChord: hasChord,
                      voicings: voicings,
                      onAccept: (v) {
                        Navigator.pop(sheetCtx);
                        onAcceptVoicing(v);
                      },
                    ),
                    _HarmonyTab(
                      hasChord: hasChord,
                      thirdAbove: thirdAbove,
                      onAccept: (s) {
                        Navigator.pop(sheetCtx);
                        onAcceptThirdAbove(s);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VoicingsTab extends StatelessWidget {
  const _VoicingsTab({
    required this.hasChord,
    required this.voicings,
    required this.onAccept,
  });
  final bool hasChord;
  final List<VoicingSuggestion> voicings;
  final void Function(VoicingSuggestion) onAccept;

  @override
  Widget build(BuildContext context) {
    if (!hasChord) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set a chord to see voicings'),
      );
    }
    if (voicings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No voicings available for this chord '
          '(v1: major/minor triads only)',
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: voicings.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final s = voicings[i];
        return _VoicingCard(
          key: Key('voicingCard_${s.shape.name}'),
          suggestion: s,
          onTap: () => onAccept(s),
        );
      },
    );
  }
}

class _HarmonyTab extends StatelessWidget {
  const _HarmonyTab({
    required this.hasChord,
    required this.thirdAbove,
    required this.onAccept,
  });
  final bool hasChord;
  final ThirdAboveSuggestion? thirdAbove;
  final void Function(ThirdAboveSuggestion) onAccept;

  @override
  Widget build(BuildContext context) {
    if (!hasChord) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set a chord to see harmony'),
      );
    }
    final s = thirdAbove;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set a key to see harmony suggestions'),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: _ThirdAboveCard(
        key: const Key('thirdAboveCard'),
        suggestion: s,
        onTap: () => onAccept(s),
      ),
    );
  }
}

class _ThirdAboveCard extends StatelessWidget {
  const _ThirdAboveCard({
    super.key,
    required this.suggestion,
    required this.onTap,
  });
  final ThirdAboveSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SavePreviewThumbnail(
              snapshot: thirdAboveToSnapshot(suggestion),
              width: 84,
              height: 72,
            ),
            const SizedBox(height: 4),
            Text(
              suggestion.label,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
```

> The existing `_VoicingCard` widget stays. The new tabs delegate `Navigator.pop` to the wrapper callbacks so the cards no longer need to call it directly.

- [ ] **Step 4: Run the new test (PASS) + the renamed existing v1 sheet test (FAIL — to be fixed in Task 5)**

Run: `flutter test test/features/songwriter/songwriter_third_above_sheet_test.dart`
Expected: PASS (3 tests).

Run: `flutter test test/features/songwriter/songwriter_voicing_sheet_test.dart`
Expected: FAIL — v1 test still passes the old `suggestions:` named arg. Will be fixed in Task 5.

> Don't let the v1 widget test failures gate this commit; Task 5 owns the v1 test rename in the same PR series.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_block_preview.dart test/features/songwriter/songwriter_third_above_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): tabbed harmony sheet with 3rd-above tab

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Tile harmony branch — compute both suggestions

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_tile.dart`
- Test: `test/features/songwriter/songwriter_third_above_tile_test.dart`

The existing harmony branch in `_onTap` (added in C v1 Task 4) currently passes only `suggestions:` and `onAccept:`. Update it to compute the 3rd-above suggestion as well, derive the chord-tone pitch classes from `block.chordNotes`, and pass both onAccept callbacks.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_third_above_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_block_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tap → Harmony tab → card → store gets a new harmony save',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.setKey(0, 'major'); // C major
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l = container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320, height: 44,
            child: SongwriterBlockTile(
              sectionId: s,
              laneId: l,
              blockId: 'hb1',
              barWidth: 40,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('block_hb1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Harmony'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('thirdAboveCard')));
    await tester.pump(const Duration(milliseconds: 600));

    final saves = container.read(saveSystemProvider);
    expect(
      saves.folders.any((f) => f.name == 'Songwriter harmonies'),
      isTrue,
    );
    final folder =
        saves.folders.firstWhere((f) => f.name == 'Songwriter harmonies');
    expect(saves.saves.any((s) => s.folderId == folder.id), isTrue);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_third_above_tile_test.dart`
Expected: FAIL — current tile only calls `suggestVoicings`, no thirdAbove yet.

- [ ] **Step 3: Implement**

In `lib/features/songwriter/songwriter_block_tile.dart`:

1. Add the new imports next to the existing schema-rule + util imports:

```dart
import '../../schema/rules/songwriter_third_above_rules.dart';
import '../../utils/note_utils.dart';
```

2. Replace the harmony branch inside `_onTap`. The existing branch from C v1 looks like:

```dart
if (block.chordRootPc != null && block.chordQuality != null) {
  final suggestions = suggestVoicings(
    chordRootPc: block.chordRootPc!,
    quality: block.chordQuality!,
  );
  showHarmonyBlockSheet(
    context,
    block: block,
    suggestions: suggestions,
    onAccept: (v) {
      ref.read(songwriterProvider.notifier).acceptVoicingSuggestion(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            suggestion: v,
          );
    },
  );
  return;
}
```

Replace with:

```dart
if (block.chordRootPc != null && block.chordQuality != null) {
  final cfg = ref.read(songwriterProvider).config;
  final voicings = suggestVoicings(
    chordRootPc: block.chordRootPc!,
    quality: block.chordQuality!,
  );
  final thirdAbove = suggestThirdAbove(
    chordRootPc: block.chordRootPc!,
    chordQuality: block.chordQuality!,
    chordTonePcs: _chordPcs(block),
    keyRootPc: cfg.keyRoot,
    keyScaleName: cfg.keyScaleName,
  );
  showHarmonyBlockSheet(
    context,
    block: block,
    voicings: voicings,
    thirdAbove: thirdAbove,
    onAcceptVoicing: (v) {
      ref.read(songwriterProvider.notifier).acceptVoicingSuggestion(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            suggestion: v,
          );
    },
    onAcceptThirdAbove: (s) {
      ref.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            suggestion: s,
          );
    },
  );
  return;
}
```

3. Add the private helper near the bottom of the state class:

```dart
List<int> _chordPcs(SongBlock block) {
  final out = <int>[];
  for (final name in block.chordNotes) {
    final pc = noteToPC[name];
    if (pc != null && !out.contains(pc)) out.add(pc);
  }
  return out;
}
```

- [ ] **Step 4: Run it (PASS) + regression**

Run: `flutter test test/features/songwriter/songwriter_third_above_tile_test.dart`
Expected: PASS.

Run: `flutter test test/features/songwriter/songwriter_block_drag_test.dart`
Expected: PASS (unchanged — save-block path).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_block_tile.dart test/features/songwriter/songwriter_third_above_tile_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): tile harmony branch computes 3rd-above suggestion

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Update C v1 widget tests for renamed parameter

**Files:**
- Modify: `test/features/songwriter/songwriter_voicing_sheet_test.dart`
- Modify: `test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`

The C v1 tests still call `showHarmonyBlockSheet(... suggestions: ..., onAccept: ...)`. After Task 3 these named args don't exist. They must be renamed and supplied with the new required parameters. The tile-tap test must also click the **Voicings** tab before asserting the "Suggested voicings" heading — except the heading no longer exists (the heading is now the tab label).

- [ ] **Step 1: Run the failing tests**

Run: `flutter test test/features/songwriter/songwriter_voicing_sheet_test.dart test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`
Expected: FAIL — compile errors (`suggestions` not found) plus assertion failures on the removed "Suggested voicings" heading.

- [ ] **Step 2: Fix the voicing sheet test**

In `test/features/songwriter/songwriter_voicing_sheet_test.dart`, every call to `showHarmonyBlockSheet` must:

- Rename `suggestions:` → `voicings:`
- Rename `onAccept:` → `onAcceptVoicing:`
- Add `thirdAbove: null` (the v1 tests have no key context)
- Add `onAcceptThirdAbove: (_) {}`

The two existing assertions (`find.text('Set a chord to see voicings')` and `find.textContaining('No voicings available')`) test the Voicings tab's empty states. After Task 3 these are inside `_VoicingsTab`. Since Voicings is the default tab, no `tester.tap(find.text('Voicings'))` is needed — but the test still has to render at the tab area. The body should still find these texts because TabBarView renders the current tab eagerly.

Replace the file with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

void main() {
  testWidgets('sheet shows N voicing cards and tapping one fires onAcceptVoicing',
      (tester) async {
    VoicingSuggestion? picked;
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');
    expect(voicings.length, greaterThan(0));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb1', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: null,
              onAcceptVoicing: (v) => picked = v,
              onAcceptThirdAbove: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voicingCard_c')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voicingCard_c')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.shape, CagedShape.c);
  });

  testWidgets('Voicings tab shows empty state when chord is missing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(id: 'hb', startBar: 0, spanBars: 1),
              voicings: const [],
              thirdAbove: null,
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Set a chord to see voicings'), findsOneWidget);
  });

  testWidgets('Voicings tab shows unsupported-quality message when suggestions '
      'empty and chord is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 1,
                chordSymbol: 'Bdim', chordQuality: 'dim', chordRootPc: 11,
                chordNotes: ['B', 'D', 'F'], romanNumeral: 'vii°',
              ),
              voicings: const [],
              thirdAbove: null,
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No voicings available'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 3: Fix the tile harmony-tap test**

In `test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`, the assertion `expect(find.text('Suggested voicings'), findsOneWidget)` no longer matches anything (the heading was removed). The tab label `'Voicings'` is the new visible marker. Replace the assertion:

```dart
// before
expect(find.text('Suggested voicings'), findsOneWidget);
expect(find.textContaining('deleted save'), findsNothing);
// after
expect(find.text('Voicings'), findsOneWidget);
expect(find.text('Harmony'), findsOneWidget);
expect(find.textContaining('deleted save'), findsNothing);
```

- [ ] **Step 4: Run the two updated tests + a broader regression sweep**

Run: `flutter test test/features/songwriter/`
Expected: all PASS, including the new Task 3 + Task 4 tests.

- [ ] **Step 5: Commit**

```bash
git add test/features/songwriter/songwriter_voicing_sheet_test.dart test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart
git commit -m "$(cat <<'EOF'
test(songwriter): update C v1 widget tests for tabbed harmony sheet

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Verify + serve-sim

**Files:** none (verification only)

- [ ] **Step 1: Format + analyze**

Run:
```bash
dart format \
  lib/schema/rules/songwriter_third_above_rules.dart \
  lib/store/songwriter_store.dart \
  lib/features/songwriter/songwriter_block_preview.dart \
  lib/features/songwriter/songwriter_block_tile.dart
flutter analyze
```
Expected: clean.

- [ ] **Step 2: Full sweep**

Run: `flutter test`
Expected: all PASS (~430 baseline + 8 + 3 + 3 + 1 = ~445).

- [ ] **Step 3: Simulator check**

```bash
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted io.francescolacriola.muzician
```

Navigate to Writer. Default project is C major. Add a section + harmony lane + tap + on the harmony lane → pick C (I) from the chord wheel. Tap the C block: the sheet appears. Confirm:

- Voicings tab (default) shows the 4 CAGED cards (C-shape (open), A-shape (3rd fret), G-shape (5th fret), E-shape (8th fret) — D-shape skipped past fret 12).
- Tap **Harmony** tab. One card appears with label `3rd above (E, G, B)` and a piano thumbnail highlighting E, G, B in the C4..B4 octave.
- Tap the harmony card. Sheet closes. A new save lane (or the existing one) gains a save block aligned to bars 1-2.

Now clear the key (header → key chip → Clear key). Tap C block again, switch to Harmony tab. Expect: "Set a key to see harmony suggestions".

Set key back to A minor. Add an Am chord. Tap → Harmony tab. Expect: `3rd above (C, E, G)`.

Confirm in the save library that a new top-level folder "Songwriter harmonies" appears alongside "Songwriter voicings", each with their accepted saves.

- [ ] **Step 4: Commit any formatting drift**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(songwriter): format + verify C v2-a 3rd-above

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** decisions C2A-1 through C2A-5 each map to a task. C2A-1 (per-block) + C2A-2 (piano) + C2A-3 (diatonic 3rd) → Task 1's `suggestThirdAbove` + `thirdAboveToSnapshot`. C2A-4 (tabs in sheet) → Task 3. C2A-5 (auto folder + auto lane + bar-aligned block) → Task 2's `acceptThirdAboveSuggestion` + reuse of C v1's `_findOrCreateSaveLane`.
- **Deferred (note for the user):** arpeggio/sequence save type, 6th-above and other intervals, whole-section harmony lines, fretboard 3rd-above, configurable octave. None are in this plan.
- **Type / signature consistency:** `ThirdAboveSuggestion` (Task 1) → consumed in `acceptThirdAboveSuggestion` (Task 2), `showHarmonyBlockSheet` (Task 3), `_onTap` (Task 4). Sheet renamed `suggestions → voicings` consistently in Tasks 3, 4, 5. `_findOrCreateSaveLane(sectionId)` matches the C v1 polish signature.
- **Test gotchas:** Task 2 / Task 4 store-driving widget tests pump 600 ms after mutations to drain the 500 ms persistence debounce. Task 3 tests don't trigger the debounce because they use only callbacks. Task 5 strictly updates existing tests; no behavior change.
- **Risk:** Task 3 introduces a fixed `SizedBox(height: 170)` around the `TabBarView`. The Voicings card height was 130 in C v1; the harmony card height matches. Verify in the sim that the TabBar + 170 px content fit on iPhone 17 Pro without overflow. If overflow appears, the plan-time fallback is to wrap content in a scrollable column rather than reduce the height.

## Next slices (NOT in this plan)

- v2-b: Library-match engine (sibling spec `docs/superpowers/specs/2026-06-04-songwriter-c-v2b-library-match-design.md`) — adds a third Library tab, retroactively replaces v1 + v2-a's flat folders with a project-named folder.
- v3: Arpeggio / sequence save type, 6th-above / 5th-below, fretboard 3rd-above variant.
