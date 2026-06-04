# Songwriter — Phase C v1: CAGED Voicing Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Read `docs/superpowers/HANDOFF-songwriter.md` and `docs/superpowers/specs/2026-06-04-songwriter-c-voicings-design.md` first.**

**Goal:** Tap a harmony block in the Writer tab → see up to 5 CAGED voicings of that chord on the fretboard → tap a voicing → it's persisted as a `SaveEntry` in a "Songwriter voicings" folder and added as a save-lane block aligned to the harmony block's bars.

**Architecture:** Pure CAGED rule (5 major + 3 minor templates, transposed per chord, max-fret 12 cutoff) emits `VoicingSuggestion`s. A store action `acceptVoicingSuggestion` persists a voicing as a `SaveEntry`, finds-or-creates the "Songwriter voicings" folder, finds-or-creates a save lane in the section, and inserts the block. A new bottom-sheet entry point `showHarmonyBlockSheet` extends the existing block-preview sheet to render chord info + a horizontal strip of voicing cards.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses `FretboardSnapshot`, `FretCoordinate`, `SavePreviewThumbnail`, `chromaticNotes`, `getChordNotes`, the songwriter store inserters, and the save-system store's `createSaveFolder` / `saveSnapshot`.

**Spec:** `docs/superpowers/specs/2026-06-04-songwriter-c-voicings-design.md` (decisions C-1 through C-5).
**Depends on:** B2a polish + B2b + chord wheel — already on branch `worktree-songwriter-ux-polish` (25 commits ahead of main). This slice lands as 5 more commits on the same branch.

> **Read before starting:**
> - `lib/utils/note_utils.dart` (lines 24-53: `chromaticNotes`, `noteToPC`; lines 127-156: `chordIntervals`, `getChordNotes`)
> - `lib/models/fretboard.dart` (line 80: `FretCoordinate` — fields `stringIndex`, `fret`, `noteName`)
> - `lib/models/save_system.dart` (line 84: `FretboardSnapshot` constructor; line 511: `SaveEntry`; line 462: `SaveFolder`)
> - `lib/schema/rules/fretboard_rules.dart` (lines 51-65: standard tuning — string 1 = E4 high, string 6 = E2 low)
> - `lib/store/save_system_store.dart` (line 40: `createSaveFolder(String name, String? parentId) → String?`; line 83: `saveSnapshot(String name, String folderId, InstrumentSnapshot snapshot) → String?`; line 267: `final saveSystemProvider`)
> - `lib/store/songwriter_store.dart` (line 155: `addLane`; line 196: `addSaveBlock`; the existing `_replaceLane`, `_replaceSection` helpers)
> - `lib/features/songwriter/songwriter_block_preview.dart` (existing `showBlockPreviewSheet` + `showBrokenReferenceSheet` — model the new sheet on these)
> - `lib/features/songwriter/songwriter_block_tile.dart` (existing `_onTap` calls `resolveBlockSnapshot`; for harmony blocks the result is null and it currently shows the broken-reference sheet — that branch becomes the new harmony sheet)
> - `lib/ui/save_previews/save_preview_thumbnail.dart` (`SavePreviewThumbnail` is the reusable widget — pass a constructed `FretboardSnapshot` to render the mini fretboard)

Run `flutter test` for a green baseline (416 tests after chord wheel).

---

### Task 1: CAGED voicing pure rules

**Files:**
- Create: `lib/schema/rules/songwriter_voicing_rules.dart`
- Test: `test/schema/rules/songwriter_voicing_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_voicing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';

void main() {
  test('C major returns 5 shapes sorted by lowest fret, C-shape at fret 0', () {
    final v = suggestVoicings(chordRootPc: 0, quality: '');
    expect(v.length, 5);
    expect(v.first.shape, CagedShape.c);
    expect(v.first.lowestFret, 0);
    expect(v.first.label, 'C-shape (open)');
    // Sorted by lowest fret ascending.
    final frets = v.map((s) => s.lowestFret).toList();
    final sorted = [...frets]..sort();
    expect(frets, sorted);
  });

  test('A major includes A-shape at fret 0', () {
    final v = suggestVoicings(chordRootPc: 9, quality: '');
    final aShape = v.firstWhere((s) => s.shape == CagedShape.a);
    expect(aShape.lowestFret, 0);
    expect(aShape.label, 'A-shape (open)');
  });

  test('C minor returns 3 shapes (Am at 3, Em at 8, Dm at 10)', () {
    final v = suggestVoicings(chordRootPc: 0, quality: 'm');
    expect(v.length, 3);
    final byShape = {for (final s in v) s.shape: s.lowestFret};
    expect(byShape[CagedShape.a], 3);
    expect(byShape[CagedShape.e], 8);
    expect(byShape[CagedShape.d], 10);
  });

  test('unsupported quality returns empty', () {
    expect(suggestVoicings(chordRootPc: 0, quality: 'dim'), isEmpty);
    expect(suggestVoicings(chordRootPc: 0, quality: '7'), isEmpty);
  });

  test('shape whose transpose pushes top fret past 12 is skipped', () {
    // D-shape major has top fret 3 at anchor (D, pc=2). For Bb (pc=10),
    // shift = (10 - 2 + 12) % 12 = 8, max fret becomes 3 + 8 = 11 → still fits.
    // For B (pc=11), shift = 9, max fret = 12 → fits (boundary).
    // For C (pc=0), shift = 10, max fret = 13 → skipped.
    final v = suggestVoicings(chordRootPc: 0, quality: '');
    final hasDShape = v.any((s) => s.shape == CagedShape.d);
    expect(hasDShape, isFalse);
  });

  test('voicingToSnapshot produces snapshot with chord pitch classes', () {
    final v = suggestVoicings(chordRootPc: 0, quality: '').first; // C-shape
    final snap = voicingToSnapshot(v);
    expect(snap.tuning, TuningName.standard);
    expect(snap.numFrets, 12);
    expect(snap.capo, 0);
    expect(snap.viewMode, FretboardViewMode.exact);
    // Pitch classes of C major: C, E, G (in some order)
    expect(snap.selectedNotes.toSet(), {'C', 'E', 'G'});
    // Cells correspond to non-null openShape entries
    expect(snap.selectedCells.length, 5); // C-shape uses 5 strings
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/schema/rules/songwriter_voicing_test.dart`
Expected: FAIL — file/symbols missing.

- [ ] **Step 3: Implement**

Create `lib/schema/rules/songwriter_voicing_rules.dart`:

```dart
/// CAGED voicing suggestion rules for the Songwriter Phase C v1 slice.
///
/// Given a chord (root pitch-class + quality), [suggestVoicings] returns
/// up to 5 CAGED shape voicings transposed onto the standard-tuned fretboard,
/// sorted by lowest fret ascending. Shapes whose highest fret exceeds 12
/// after transposition are skipped. Only major ('') and minor ('m') triads
/// are supported in v1.
library;

import '../../models/fretboard.dart';
import '../../models/save_system.dart';
import '../../utils/note_utils.dart';

enum CagedShape { c, a, g, e, d }

/// A CAGED shape template defined in its open-position fingering.
///
/// [openShape] is indexed by [StringTuning.stringNumber]-1 with index 0 = high
/// E (string 1) and index 5 = low E (string 6). `null` = muted/unplayed.
class VoicingTemplate {
  const VoicingTemplate({
    required this.shape,
    required this.quality,
    required this.anchorPc,
    required this.openShape,
  });
  final CagedShape shape;
  final String quality;
  final int anchorPc;
  /// Indexed by `stringNumber - 1`: 0 = high e (string 1), 5 = low E (string 6).
  final List<int?> openShape;
}

class VoicingSuggestion {
  const VoicingSuggestion({
    required this.shape,
    required this.rootPc,
    required this.quality,
    required this.cells,
    required this.lowestFret,
    required this.label,
  });
  final CagedShape shape;
  final int rootPc;
  final String quality;
  final List<FretCoordinate> cells;
  final int lowestFret;
  final String label;
}

// ─── Templates ───────────────────────────────────────────────────────────────
//
// The spec table lists openShape in strings 6→1 order (low E first). We store
// in stringNumber-1 order (high e first) for direct alignment with the model.
// Each row below is the spec's `[s6, s5, s4, s3, s2, s1]` REVERSED, so:
//   spec  C major: [null, 3, 2, 0, 1, 0]   (s6→s1)
//   here  C major: [0, 1, 0, 2, 3, null]   (s1→s6, reversed)

const _templates = <VoicingTemplate>[
  // ── Major ──────────────────────────────────────────────────────────────────
  VoicingTemplate(
    shape: CagedShape.c, quality: '', anchorPc: 0,
    openShape: [0, 1, 0, 2, 3, null],
  ),
  VoicingTemplate(
    shape: CagedShape.a, quality: '', anchorPc: 9,
    openShape: [0, 2, 2, 2, 0, null],
  ),
  VoicingTemplate(
    shape: CagedShape.g, quality: '', anchorPc: 7,
    openShape: [3, 0, 0, 0, 2, 3],
  ),
  VoicingTemplate(
    shape: CagedShape.e, quality: '', anchorPc: 4,
    openShape: [0, 0, 1, 2, 2, 0],
  ),
  VoicingTemplate(
    shape: CagedShape.d, quality: '', anchorPc: 2,
    openShape: [2, 3, 2, 0, null, null],
  ),
  // ── Minor ──────────────────────────────────────────────────────────────────
  VoicingTemplate(
    shape: CagedShape.a, quality: 'm', anchorPc: 9,
    openShape: [0, 1, 2, 2, 0, null],
  ),
  VoicingTemplate(
    shape: CagedShape.e, quality: 'm', anchorPc: 4,
    openShape: [0, 0, 0, 2, 2, 0],
  ),
  VoicingTemplate(
    shape: CagedShape.d, quality: 'm', anchorPc: 2,
    openShape: [1, 3, 2, 0, null, null],
  ),
];

// ─── Public API ──────────────────────────────────────────────────────────────

/// Open-string pitch classes for standard tuning, indexed by `stringNumber - 1`.
/// String 1 (high e) at index 0 → E (pc 4). String 6 (low E) at index 5 → E (pc 4).
const _openPcByStringNumberMinus1 = <int>[4, 11, 7, 2, 9, 4];

List<VoicingSuggestion> suggestVoicings({
  required int chordRootPc,
  required String quality,
}) {
  if (quality != '' && quality != 'm') return const [];
  final out = <VoicingSuggestion>[];
  for (final t in _templates) {
    if (t.quality != quality) continue;
    final shift = ((chordRootPc - t.anchorPc) % 12 + 12) % 12;

    // Compute transposed frets; skip the whole shape if any fret > 12.
    final transposedFrets = <int?>[];
    var maxFret = -1;
    var minFret = 1 << 30;
    var fits = true;
    for (final f in t.openShape) {
      if (f == null) {
        transposedFrets.add(null);
        continue;
      }
      final newFret = f + shift;
      if (newFret > 12) {
        fits = false;
        break;
      }
      transposedFrets.add(newFret);
      if (newFret > maxFret) maxFret = newFret;
      if (newFret < minFret) minFret = newFret;
    }
    if (!fits || maxFret < 0) continue;

    // Build cells (string 1..6 → stringIndex 1..6 in the model).
    final cells = <FretCoordinate>[];
    for (var i = 0; i < transposedFrets.length; i++) {
      final f = transposedFrets[i];
      if (f == null) continue;
      final stringNumber = i + 1;
      final openPc = _openPcByStringNumberMinus1[i];
      final pc = (openPc + f) % 12;
      cells.add(FretCoordinate(
        stringIndex: stringNumber,
        fret: f,
        noteName: chromaticNotes[pc],
      ));
    }

    out.add(VoicingSuggestion(
      shape: t.shape,
      rootPc: chordRootPc,
      quality: quality,
      cells: cells,
      lowestFret: minFret,
      label: '${t.shape.name.toUpperCase()}-shape '
          '(${minFret == 0 ? 'open' : '${_ordinal(minFret)} fret'})',
    ));
  }
  out.sort((a, b) => a.lowestFret.compareTo(b.lowestFret));
  return out;
}

/// Wraps a voicing's cells into a `FretboardSnapshot` (standard tuning,
/// 12 frets, capo 0, exact view).
FretboardSnapshot voicingToSnapshot(VoicingSuggestion v) {
  final pcs = <String>{};
  for (final c in v.cells) {
    pcs.add(c.noteName);
  }
  return FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: v.cells,
    selectedNotes: pcs.toList(),
    viewMode: FretboardViewMode.exact,
  );
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/schema/rules/songwriter_voicing_test.dart`
Expected: PASS (6 tests).

> If the "shape whose top fret pushes past 12 is skipped" test fails because the D-shape was unexpectedly included for C major, debug the shift math: `shift = (chordRootPc - anchorPc + 12) % 12`. For C (pc=0), D-shape (anchor pc=2): shift = 10. D-shape openShape top fret = 3. Transposed = 13 → skipped. The test must succeed.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_voicing_rules.dart test/schema/rules/songwriter_voicing_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): CAGED voicing rule + snapshot factory

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Store action — `acceptVoicingSuggestion`

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_voicing_accept_test.dart`

The action persists a voicing as a `SaveEntry` (auto-creating a "Songwriter voicings" folder on first call), finds-or-creates a save lane in the section, and inserts a save-lane block at the harmony block's `startBar` / `spanBars`.

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_voicing_accept_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Hydrate save system to ensure it's in a known empty state.
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

  test('accept creates SaveEntry in auto-created folder + save lane + block',
      () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);
    final voicing = suggestVoicings(chordRootPc: 0, quality: '').first;

    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: voicing,
        );

    final saves = c.read(saveSystemProvider);
    expect(saves.folders.any((f) => f.name == 'Songwriter voicings'), isTrue);
    final voicingsFolder =
        saves.folders.firstWhere((f) => f.name == 'Songwriter voicings');
    expect(voicingsFolder.parentId, isNull);
    final newSave = saves.saves.firstWhere(
      (s) => s.folderId == voicingsFolder.id,
    );
    expect(newSave.name, contains('C'));

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

  test('second accept reuses the same folder and the same save lane',
      () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: voicings[0],
        );
    // Move the existing block so the second accept doesn't overlap.
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
          laneId: c
              .read(songwriterProvider)
              .sections
              .firstWhere((s) => s.id == ids.sectionId)
              .lanes
              .firstWhere((l) => l.kind == SongLaneKind.save)
              .id,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: voicings[1],
        );

    final folders = c
        .read(saveSystemProvider)
        .folders
        .where((f) => f.name == 'Songwriter voicings')
        .toList();
    expect(folders.length, 1, reason: 'folder must not be duplicated');

    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLanes =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList();
    expect(saveLanes.length, 1, reason: 'save lane must be reused');
    expect(saveLanes.single.blocks.length, 2);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_voicing_accept_test.dart`
Expected: FAIL — `acceptVoicingSuggestion` missing.

- [ ] **Step 3: Implement**

Add imports at the top of `lib/store/songwriter_store.dart` (after existing imports):

```dart
import '../schema/rules/songwriter_voicing_rules.dart';
import '../utils/note_utils.dart';
import 'save_system_store.dart';
```

Append a new method to the `SongwriterNotifier` class (place it right before `_recomputeNumerals`):

```dart
/// Persists a voicing suggestion as a SaveEntry in the auto-created
/// "Songwriter voicings" folder and inserts a save-lane block in the section
/// aligned to the triggering harmony block's bars.
Future<void> acceptVoicingSuggestion({
  required String sectionId,
  required String harmonyBlockId,
  required VoicingSuggestion suggestion,
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
  final folderId = _findOrCreateVoicingsFolder(saves);
  if (folderId == null) return;

  final rootName = chromaticNotes[suggestion.rootPc];
  final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
  final saveId =
      saves.saveSnapshot(saveName, folderId, voicingToSnapshot(suggestion));
  if (saveId == null) return;

  final laneId = _findOrCreateSaveLane(sectionId, section);
  if (laneId == null) return;

  addSaveBlock(
    sectionId: sectionId,
    laneId: laneId,
    saveId: saveId,
    startBar: harmonyBlock.startBar,
    spanBars: harmonyBlock.spanBars,
  );
}

String? _findOrCreateVoicingsFolder(SaveSystemNotifier saves) {
  const targetName = 'Songwriter voicings';
  final existing = ref
      .read(saveSystemProvider)
      .folders
      .where((f) => f.parentId == null && f.name == targetName)
      .toList();
  if (existing.isNotEmpty) return existing.first.id;
  return saves.createSaveFolder(targetName, null);
}

String? _findOrCreateSaveLane(String sectionId, SongSection section) {
  final existing = section.lanes
      .where((l) => l.kind == SongLaneKind.save)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (existing.isNotEmpty) return existing.first.id;
  addLane(sectionId: sectionId, kind: SongLaneKind.save);
  // addLane appends a new lane; re-read state to get the id.
  final updated = state.sections.firstWhere((s) => s.id == sectionId);
  final saveLanes =
      updated.lanes.where((l) => l.kind == SongLaneKind.save).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  return saveLanes.isEmpty ? null : saveLanes.last.id;
}
```

> If the existing `songwriter_store.dart` already imports `note_utils.dart` indirectly via another import, the explicit import is still safe. If the file already imports `save_system_store.dart` (e.g. via the `_persist` path), don't duplicate it — verify with `grep -n save_system_store lib/store/songwriter_store.dart` before adding.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_voicing_accept_test.dart`
Expected: PASS (2 tests).

> If the second test fails because the second `addSaveBlock` is silently rejected by `blocksOverlap`, confirm the test moved the first block out of the way (the spec sets `startBar: 4`).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_voicing_accept_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): acceptVoicingSuggestion store action

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Harmony-block sheet with voicing strip

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_preview.dart`
- Test: `test/features/songwriter/songwriter_voicing_sheet_test.dart`

The new entry point `showHarmonyBlockSheet` mirrors `showBlockPreviewSheet`'s structure: chord header, optional notes chips, and a horizontal strip of voicing cards. Each card embeds a `SavePreviewThumbnail` rendered from the voicing's snapshot.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_voicing_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

void main() {
  testWidgets('sheet shows N voicing cards and tapping one fires onAccept',
      (tester) async {
    VoicingSuggestion? picked;
    final suggestions = suggestVoicings(chordRootPc: 0, quality: '');
    expect(suggestions.length, greaterThan(0));

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
              suggestions: suggestions,
              onAccept: (v) => picked = v,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Cards are keyed by shape so the test can pick a known one.
    expect(find.byKey(const Key('voicingCard_c')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voicingCard_c')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.shape, CagedShape.c);
  });

  testWidgets('sheet shows empty state when chordRootPc is null',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(id: 'hb', startBar: 0, spanBars: 1),
              suggestions: const [],
              onAccept: (_) {},
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

  testWidgets('sheet shows unsupported-quality message when suggestions empty'
      ' and chord is set', (tester) async {
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
              suggestions: const [],
              onAccept: (_) {},
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

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_voicing_sheet_test.dart`
Expected: FAIL — `showHarmonyBlockSheet` missing.

- [ ] **Step 3: Implement**

Append to `lib/features/songwriter/songwriter_block_preview.dart` (add the import for `songwriter_voicing_rules.dart` at the top):

```dart
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../models/songwriter.dart';
```

```dart
/// Opens the harmony-block sheet: chord header + horizontal strip of CAGED
/// voicing suggestions. Tapping a voicing card invokes [onAccept] and closes
/// the sheet. v1 covers major and minor triads only.
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> suggestions,
  required void Function(VoicingSuggestion) onAccept,
}) {
  final hasChord = block.chordRootPc != null && block.chordQuality != null;
  final title = block.chordSymbol ??
      (hasChord ? '?' : 'Harmony');
  final numeral = block.romanNumeral;

  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 16),
            const Text('Suggested voicings',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (!hasChord)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Set a chord to see voicings'),
              )
            else if (suggestions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No voicings available for this chord '
                  '(v1: major/minor triads only)',
                ),
              )
            else
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = suggestions[i];
                    return _VoicingCard(
                      key: Key('voicingCard_${s.shape.name}'),
                      suggestion: s,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        onAccept(s);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _VoicingCard extends StatelessWidget {
  const _VoicingCard({
    super.key,
    required this.suggestion,
    required this.onTap,
  });
  final VoicingSuggestion suggestion;
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
              snapshot: voicingToSnapshot(suggestion),
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

> If the file already imports `songwriter.dart` or `SavePreviewThumbnail`, don't duplicate. The existing `showBlockPreviewSheet` already uses `SavePreviewThumbnail`, so its import is in place; just add the two new imports listed above.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/songwriter_voicing_sheet_test.dart`
Expected: PASS (3 tests).

> If a card-tap test fails because `Navigator.pop` is called twice (e.g. test taps a card after the sheet already closed), confirm the test does not call `pumpAndSettle` between two taps on the same key.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_block_preview.dart test/features/songwriter/songwriter_voicing_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): harmony-block sheet with CAGED voicing strip

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Route harmony-block tap to the new sheet

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_tile.dart`
- Test: `test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`

Currently `_onTap` calls `resolveBlockSnapshot(block, saves)`. For harmony blocks that returns null and the broken-reference sheet is shown — wrong behaviour. The fix: detect harmony blocks (`chordRootPc != null && chordQuality != null`) and route them through `showHarmonyBlockSheet` instead.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_block_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a harmony block opens the voicing sheet (not broken-ref)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
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

    // The new harmony sheet renders the label "Suggested voicings".
    expect(find.text('Suggested voicings'), findsOneWidget);
    // Broken-ref sheet's title should NOT appear.
    expect(find.textContaining('deleted save'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`
Expected: FAIL — the harmony tap still goes through `showBrokenReferenceSheet`, so the "Suggested voicings" label is not found.

- [ ] **Step 3: Implement**

In `lib/features/songwriter/songwriter_block_tile.dart`, add the new import next to the existing schema-rule import:

```dart
import '../../schema/rules/songwriter_voicing_rules.dart';
```

Modify `_onTap` so the harmony branch is taken first:

```dart
void _onTap(BuildContext context, SongBlock block, List<SaveEntry> saves) {
  // Harmony block: show the chord + voicing suggestions.
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
  // Save block: existing flow.
  final snapshot = resolveBlockSnapshot(block, saves);
  if (snapshot != null) {
    showBlockPreviewSheet(context, snapshot);
  } else {
    showBrokenReferenceSheet(
      context,
      onDelete: () {
        ref.read(songwriterProvider.notifier).removeBlock(
              sectionId: widget.sectionId,
              laneId: widget.laneId,
              blockId: widget.blockId,
            );
      },
    );
  }
}
```

> The existing `_onTap` may have a slightly different signature (no broken-ref branch params, etc.). Preserve the existing save-block branch verbatim and only add the harmony branch at the top.

- [ ] **Step 4: Run it (PASS) + regression**

Run: `flutter test test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`
Run: `flutter test test/features/songwriter/songwriter_block_drag_test.dart test/features/songwriter/songwriter_save_block_test.dart`
Expected: all PASS.

> If a B2b regression test fails because it expected a save-block tap path and now the test seed includes chord fields, audit the failing test's seed — the new code only branches on harmony blocks (`chordRootPc != null && chordQuality != null`). Save blocks must remain on the existing flow.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_block_tile.dart test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart
git commit -m "$(cat <<'EOF'
feat(songwriter): route harmony-block tap to voicing sheet

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Verify + serve-sim

**Files:** none (verification only)

- [ ] **Step 1: Format + analyze**

Run:
```bash
dart format \
  lib/schema/rules/songwriter_voicing_rules.dart \
  lib/store/songwriter_store.dart \
  lib/features/songwriter/songwriter_block_preview.dart \
  lib/features/songwriter/songwriter_block_tile.dart
flutter analyze
```
Expected: clean.

- [ ] **Step 2: Full sweep**

Run: `flutter test`
Expected: all PASS (~416 baseline + 6 + 2 + 3 + 1 = ~428).

- [ ] **Step 3: Simulator check**

```bash
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted io.francescolacriola.muzician
```

Navigate to the Writer tab. New project (which defaults to C major). Add a 4-bar section, a harmony lane, then add a chord via the wheel (e.g. C / I). Tap the C block: a bottom sheet appears showing "C" + "I" + chord-note chips + a "Suggested voicings" strip with up to 5 cards (C-shape (open), A-shape (3rd fret), G-shape (5th fret), E-shape (8th fret); D-shape is skipped for C because the transposed top fret exceeds 12). Tap the C-shape card: the sheet closes, a save lane appears under the harmony lane (if it didn't already exist) with a save block aligned to bars 1-2. Repeat with a minor chord (e.g. add Am via the wheel → tap → 3 voicings: Am-shape (open), Em-shape (5th fret), Dm-shape (7th fret)). Repeat with a Bdim (vii°) chord: sheet shows "No voicings available for this chord (v1: major/minor triads only)".

Confirm a new folder named "Songwriter voicings" appears in the save library (the Settings or save-load tab), containing one save per acceptance.

- [ ] **Step 4: Commit any formatting drift**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(songwriter): format + verify C v1 voicings

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** decisions C-1 through C-5 are each delivered by an explicit task. C-1 (reuse `FretboardSnapshot`) → Task 1's `voicingToSnapshot`. C-2 (tap-block sheet) → Task 3 sheet + Task 4 wiring. C-3 (pure rule-based, no library-match) → Task 1. C-4 (CAGED, 5 major / 3 minor) → Task 1 template table. C-5 (1-tap accept = persisted save + auto folder + auto save lane + bar-aligned block) → Task 2.
- **Deferred (note for the user):** arpeggio/sequence save type, diminished/aug/7th/extended voicings, 3rd-above harmony lines, library-match engine, per-section batch suggestions, piano voicings. None of those are in this plan — all sit behind v2/v3 slices.
- **Type / signature consistency:** `VoicingSuggestion` (Task 1) → consumed in `acceptVoicingSuggestion` (Task 2), `showHarmonyBlockSheet` (Task 3), `_onTap` (Task 4). `CagedShape` enum used in the widget test's `Key('voicingCard_${s.shape.name}')` matches the painter's wedge keying. `chordRootPc` / `chordQuality` field names on `SongBlock` match the existing model (verified in B2b). `addLane(sectionId, kind, label?)` and `addSaveBlock(sectionId, laneId, saveId, startBar, spanBars)` match the store. `saveSnapshot(name, folderId, snapshot)` and `createSaveFolder(name, parentId)` match the save store.
- **Test gotchas:** Task 2 uses the 500 ms store-debounce drain implicitly via `await tester.pump(const Duration(milliseconds: 600))` in widget tests; the pure store test runs against a fresh `ProviderContainer` so timers fire on the test scheduler. Task 4 reuses the seed pattern from B2b drag tests. Task 3 keys voicing cards by `shape.name` so tests don't rely on tap coordinates.
- **Risk:** the second test in Task 2 ("reuse folder + reuse lane") moves the first block to bar 4 before the second accept so `blocksOverlap` doesn't silently reject. If the spec ever changes "align to harmony block" to "next free bar", this test must be updated.

## Next slices (NOT in this plan)

- v2-a: 3rd-above harmony line (forces the arpeggio/sequence save type decision).
- v2-b: Library-match engine — find user's saves whose notes fit the chord/key.
- v3: diminished / aug / 7th / extended voicings; piano voicings.
