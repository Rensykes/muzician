# Lyrics Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lyrics lane to the songwriter whose blocks carry text with optional/soft bar positioning, serving both lead-sheet alignment and free jotting.

**Architecture:** New `SongLaneKind.lyrics` reusing the existing `SongBlock` (text in `lyrics`, position in `startBar`/`spanBars`, chord fields null). A `_LyricLaneRow` widget mirrors `_DrumLaneRow`. Store/persistence reuse existing lane-generic machinery.

**Tech Stack:** Dart / Flutter, Riverpod (`songwriterProvider`), `package:flutter_test`, SharedPreferences mock for store tests.

**Spec:** `docs/superpowers/specs/2026-06-18-lyrics-lane-design.md`

---

## File Structure

- `lib/models/songwriter.dart` — extend `SongLaneKind` enum with `lyrics`.
- `lib/schema/rules/songwriter_rules.dart` — add `makeLyricBlock`.
- `lib/store/songwriter_store.dart` — add `addLyricBlock` (reuses `removeBlock`, `setBlockLyric`).
- `lib/features/songwriter/songwriter_screen_sheet.dart` — add `_LyricLaneRow`, render it in `_SectionSheet`, add the "Add lyrics lane" menu item and the edit/add tap flows.
- Tests:
  - `test/models/songwriter_lyrics_lane_test.dart`
  - `test/schema/rules/songwriter_lyric_block_test.dart`
  - `test/store/songwriter_lyric_ops_test.dart`
  - `test/features/songwriter/songwriter_sheet_lyric_lane_test.dart`

---

## Task 1: Model — add `lyrics` lane kind

**Files:**
- Modify: `lib/models/songwriter.dart:7`
- Test: `test/models/songwriter_lyrics_lane_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/models/songwriter_lyrics_lane_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('lyrics lane kind round-trips through JSON', () {
    const lane = SongLane(
      id: 'l1',
      kind: SongLaneKind.lyrics,
      order: 0,
      blocks: [
        SongBlock(id: 'b1', startBar: 0, spanBars: 4, lyrics: ['hello world']),
      ],
    );
    final restored = SongLane.fromJson(lane.toJson());
    expect(restored.kind, SongLaneKind.lyrics);
    expect(restored.blocks.single.lyrics, ['hello world']);
  });

  test('unknown lane kind still falls back to save', () {
    final restored =
        SongLane.fromJson({'id': 'x', 'kind': 'bogus', 'order': 0});
    expect(restored.kind, SongLaneKind.save);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/songwriter_lyrics_lane_test.dart`
Expected: FAIL — `SongLaneKind.lyrics` is not defined (compile error).

- [ ] **Step 3: Add the enum value**

In `lib/models/songwriter.dart` line 7, change:

```dart
enum SongLaneKind { harmony, save, drum }
```

to:

```dart
enum SongLaneKind { harmony, save, drum, lyrics }
```

(No change needed to `_laneKindFromName` — it iterates `SongLaneKind.values` and already falls back to `save`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/songwriter_lyrics_lane_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/songwriter.dart test/models/songwriter_lyrics_lane_test.dart
git commit -m "feat(songwriter): add lyrics lane kind to model"
```

---

## Task 2: Rules — `makeLyricBlock`

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart` (after `makeSilentBlock`, ~line 188)
- Test: `test/schema/rules/songwriter_lyric_block_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/songwriter_lyric_block_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('makeLyricBlock stores text in first verse, no chord', () {
    final b = makeLyricBlock(startBar: 2, spanBars: 1, text: 'la la');
    expect(b.startBar, 2);
    expect(b.spanBars, 1);
    expect(b.lyrics, ['la la']);
    expect(b.chordSymbol, isNull);
    expect(b.isSilent, isFalse);
    expect(b.id, isNotEmpty);
  });

  test('makeLyricBlock allocates one empty verse per verseCount when no text', () {
    final b = makeLyricBlock(startBar: 0, spanBars: 4, verseCount: 3);
    expect(b.lyrics, ['', '', '']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_lyric_block_test.dart`
Expected: FAIL — `makeLyricBlock` is not defined.

- [ ] **Step 3: Add the rule**

In `lib/schema/rules/songwriter_rules.dart`, immediately after `makeSilentBlock` (after line 188), add:

```dart
SongBlock makeLyricBlock({
  required int startBar,
  required int spanBars,
  String text = '',
  int verseCount = 1,
}) {
  final count = verseCount.clamp(1, 16);
  final lyrics = List<String>.filled(count, '', growable: true);
  if (text.isNotEmpty) lyrics[0] = text;
  return SongBlock(
    id: generateId(),
    startBar: startBar,
    spanBars: spanBars,
    lyrics: lyrics,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_lyric_block_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_lyric_block_test.dart
git commit -m "feat(songwriter): add makeLyricBlock rule"
```

---

## Task 3: Store — `addLyricBlock`

**Files:**
- Modify: `lib/store/songwriter_store.dart` (after `addSilentBlock`, ~line 317)
- Test: `test/store/songwriter_lyric_ops_test.dart`

Note: `removeBlock` (line 318) and `setBlockLyric` (line 275) are already lane-generic and reused as-is. `blocksOverlap` already exists and is used by `addSaveBlock`/`addHarmonyBlock`.

- [ ] **Step 1: Write the failing test**

Create `test/store/songwriter_lyric_ops_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('addLyricBlock inserts a positioned lyric block; overlap is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.lyrics, label: 'Lyrics');
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;

    n.addLyricBlock(sectionId: s, laneId: l, startBar: 0, spanBars: 2, text: 'hi');
    var lane = c.read(songwriterProvider).sections.single.lanes.single;
    expect(lane.blocks.single.lyrics, ['hi']);
    expect(lane.blocks.single.startBar, 0);

    // Overlapping insert is rejected, leaving one block.
    n.addLyricBlock(sectionId: s, laneId: l, startBar: 1, spanBars: 2, text: 'no');
    lane = c.read(songwriterProvider).sections.single.lanes.single;
    expect(lane.blocks.length, 1);

    // Non-overlapping insert succeeds.
    n.addLyricBlock(sectionId: s, laneId: l, startBar: 4, spanBars: 2, text: 'bye');
    lane = c.read(songwriterProvider).sections.single.lanes.single;
    expect(lane.blocks.length, 2);
  });

  test('setBlockLyric updates a lyric-lane block per verse index', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.lyrics, label: 'Lyrics');
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addLyricBlock(sectionId: s, laneId: l, startBar: 0, spanBars: 4);
    final b = c.read(songwriterProvider).sections.single.lanes.single.blocks.single.id;

    n.setBlockLyric(sectionId: s, laneId: l, blockId: b, verseIndex: 0, text: 'verse one');
    final block =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    expect(block.lyrics, ['verse one']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_lyric_ops_test.dart`
Expected: FAIL — `addLyricBlock` is not defined.

- [ ] **Step 3: Add the store method**

In `lib/store/songwriter_store.dart`, immediately after `addSilentBlock` (after its closing `}` near line 317, before `removeBlock`), add:

```dart
  void addLyricBlock({
    required String sectionId,
    required String laneId,
    required int startBar,
    required int spanBars,
    String text = '',
    int verseCount = 1,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      final candidate = makeLyricBlock(
        startBar: startBar,
        spanBars: spanBars,
        text: text,
        verseCount: verseCount,
      );
      if (blocksOverlap(l.blocks, candidate)) return l; // soft: skip overlaps
      return l.copyWith(blocks: [...l.blocks, candidate]);
    });
  }
```

Verify `makeLyricBlock` is in scope — `songwriter_rules.dart` is already imported (it provides `makeSilentBlock`/`makeSaveBlock` used above). If the analyzer reports it unresolved, the import is already present; no new import is needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_lyric_ops_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_lyric_ops_test.dart
git commit -m "feat(songwriter): add addLyricBlock store op"
```

---

## Task 4: UI — render & edit the lyrics lane

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
  - Render loop in `_SectionSheet.build` (after the drum-lane loop, ~line 269)
  - Add-lane menu in `_SectionHeading` (`PopupMenuButton`, ~line 357-395)
  - New `_LyricLaneRow` widget (add near `_DrumLaneRow`, ~line 1207)
- Test: `test/features/songwriter/songwriter_sheet_lyric_lane_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/songwriter/songwriter_sheet_lyric_lane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lyrics lane renders its text and an add-lyric affordance',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(sectionId: section.id, kind: SongLaneKind.lyrics, label: 'Lyrics');
    final laneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.lyrics).id;
    n.addLyricBlock(
      sectionId: section.id,
      laneId: laneId,
      startBar: 0,
      spanBars: 4,
      text: 'first line of the song',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(Key('sheetLyricLane_${laneId}_0')), findsOneWidget);
    expect(find.text('first line of the song'), findsOneWidget);
  });

  testWidgets('Add lyrics lane menu action creates a lyrics lane',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addLyricLaneSheetAction')));
    await tester.pumpAndSettle();

    final lanes = container.read(songwriterProvider).sections.first.lanes;
    expect(lanes.where((l) => l.kind == SongLaneKind.lyrics), hasLength(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_sheet_lyric_lane_test.dart`
Expected: FAIL — lyrics lane not rendered (`sheetLyricLane_*` not found) and no `addLyricLaneSheetAction`.

- [ ] **Step 3: Add the `_LyricLaneRow` widget**

In `lib/features/songwriter/songwriter_screen_sheet.dart`, add this class just before `_AddSectionRule` (~line 1209). It mirrors `_DrumLaneRow`: a full-width row of bar cells; cells owned by a lyric block show the text (tap to edit), empty cells are tappable to add a 1-bar lyric block at that bar. The lane label area carries a full-width "+ lyrics" tap target for the jotter flow.

```dart
class _LyricLaneRow extends ConsumerWidget {
  const _LyricLaneRow({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final notifier = ref.read(songwriterProvider.notifier);
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
        final text = instanceIndex < owner.lyrics.length
            ? owner.lyrics[instanceIndex]
            : '';
        cells.add(Expanded(
          flex: span,
          child: GestureDetector(
            key: Key('sheetLyricTile_${owner.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _editLyric(context, notifier, owner, text),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: MuzicianTheme.sky.withValues(alpha: 0.12),
                border: Border.all(
                  color: MuzicianTheme.sky.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text.isEmpty ? 'Add lyrics' : text,
                style: TextStyle(
                  fontSize: 12,
                  color: text.isEmpty
                      ? MuzicianTheme.textMuted
                      : MuzicianTheme.textPrimary,
                ),
              ),
            ),
          ),
        ));
        i += span;
      } else if (owner != null) {
        i++;
      } else {
        final bar = i;
        cells.add(Expanded(
          flex: 1,
          child: GestureDetector(
            key: Key('sheetLyricEmpty_${lane.id}_$bar'),
            behavior: HitTestBehavior.opaque,
            onTap: () => notifier.addLyricBlock(
              sectionId: section.id,
              laneId: lane.id,
              startBar: bar,
              spanBars: 1,
              verseCount: section.repeat,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 28,
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
        GestureDetector(
          key: Key('sheetLyricJot_${lane.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: lane.blocks.isEmpty
              ? () => notifier.addLyricBlock(
                    sectionId: section.id,
                    laneId: lane.id,
                    startBar: 0,
                    spanBars: bars,
                    verseCount: section.repeat,
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              lane.label ?? 'Lyrics',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        Row(children: cells),
      ],
    );
  }

  void _editLyric(
    BuildContext context,
    SongwriterNotifier notifier,
    SongBlock block,
    String current,
  ) {
    final controller = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text('Lyrics', style: TextStyle(color: MuzicianTheme.textPrimary)),
        content: TextField(
          key: const Key('lyricLaneEditField'),
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Type lyrics…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('lyricLaneEditSave'),
            onPressed: () {
              notifier.setBlockLyric(
                sectionId: section.id,
                laneId: lane.id,
                blockId: block.id,
                verseIndex: instanceIndex,
                text: controller.text,
              );
              Navigator.pop(dialogCtx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Render the lyrics lanes in `_SectionSheet`**

In `_SectionSheet.build`, directly after the drum-lane `for (...) ...[ ... ]` block that ends at line 269 (before the closing `],` of the `children:` list at line 270), add:

```dart
        // Lyrics lanes (one strip per lyrics lane on this section).
        for (final lane
            in section.lanes.where((l) => l.kind == SongLaneKind.lyrics)) ...[
          const SizedBox(height: 8),
          _LyricLaneRow(
            key: Key('sheetLyricLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
          ),
        ],
```

- [ ] **Step 5: Add the "Add lyrics lane" menu item**

In `_SectionHeading`'s `PopupMenuButton`, extend `onSelected` (after the `addDrumLane` `if` block closes at line 383) with:

```dart
                if (value == 'addLyricLane') {
                  ref.read(songwriterProvider.notifier).addLane(
                        sectionId: section.id,
                        kind: SongLaneKind.lyrics,
                        label: 'Lyrics',
                      );
                }
```

and add a second entry to the `itemBuilder` list (alongside the existing drum item; remove `const` from the list literal if the analyzer requires it):

```dart
                PopupMenuItem(
                  key: Key('addLyricLaneSheetAction'),
                  value: 'addLyricLane',
                  child: ListTile(
                    leading: Icon(Icons.lyrics_outlined),
                    title: Text('Add lyrics lane'),
                    dense: true,
                  ),
                ),
```

- [ ] **Step 6: Run the widget test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_sheet_lyric_lane_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Run analyzer + full songwriter test slice**

Run: `dart analyze lib/features/songwriter/songwriter_screen_sheet.dart lib/store/songwriter_store.dart lib/models/songwriter.dart lib/schema/rules/songwriter_rules.dart`
Expected: no errors.

Run: `flutter test test/models/songwriter_lyrics_lane_test.dart test/schema/rules/songwriter_lyric_block_test.dart test/store/songwriter_lyric_ops_test.dart test/features/songwriter/songwriter_sheet_lyric_lane_test.dart`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_sheet_lyric_lane_test.dart
git commit -m "feat(songwriter): render and edit the lyrics lane"
```

---

## Task 5: Manual visual verification (serve-sim)

**No automated test — manual confirmation per spec.**

- [ ] **Step 1: Launch the simulator preview**

Use the `serve-sim` skill to boot/stream the iOS simulator.

- [ ] **Step 2: Walk the two flows**

1. Open a song, open a section's `⋮` menu → **Add lyrics lane**.
2. **Jotter:** tap the lane label/empty strip → a full-width block appears → tap it → type free text → Save. Confirm text shows.
3. **Precision:** tap a single empty bar cell → a 1-bar block anchors at that bar directly under the corresponding chord in the harmony lane. Confirm column alignment.
4. Save the project, reload it, confirm the lyrics lane and its text persist.

- [ ] **Step 3: Capture proof**

Screenshot the aligned lead-sheet view (lyrics under chords) and the reloaded project. Share with the user.

---

## Final verification

- [ ] Run the whole suite: `flutter test`
- [ ] Confirm zero analyzer errors: `dart analyze`
- [ ] All five tasks committed.
