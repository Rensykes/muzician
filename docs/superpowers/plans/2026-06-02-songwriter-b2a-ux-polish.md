# Songwriter B2a UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A feel/clarity pass over the merged Songwriter (B2a) tab: bar ruler + gridlines, tappable value pills for section bars/repeat, undo-snackbar deletes, drop the redundant header title, default new projects to C major, and an empty-state helper — before B2b adds playback.

**Architecture:** Mostly UI in `lib/features/songwriter/` driven by the existing `songwriterProvider`. The store gains three index-aware inserters so the UI can implement undo by capturing the removed object + index, deleting, then restoring on SnackBar action. The default project config changes to C major. New painters draw the bar ruler and lane gridlines.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses `songwriter_store.dart`, `songwriter_rules.dart`, `note_utils` (`chromaticNotes`).

**Spec:** `docs/superpowers/specs/2026-06-02-songwriter-b2a-ux-polish-design.md`
**Depends on:** B2a (merged into `main`).

> **Read before starting:** `lib/store/songwriter_store.dart` (esp. `_emptyProject`, `removeSection/removeLane/removeBlock`, `_replaceSection/_replaceLane`, `reorderSections`), `lib/features/songwriter/songwriter_section_card.dart`, `songwriter_lane_row.dart`, `songwriter_block_tile.dart`, `songwriter_header.dart`, `songwriter_screen.dart`. Run `flutter test` for a green baseline (380 tests).

---

### Task 1: Default new projects to C major

**Files:**
- Modify: `lib/store/songwriter_store.dart` (`_emptyProject`)
- Test: `test/store/songwriter_default_key_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_default_key_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh project defaults to C major', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cfg = c.read(songwriterProvider).config;
    expect(cfg.keyRoot, 0);
    expect(cfg.keyScaleName, 'major');
  });

  test('newProject resets to C major', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.setKey(null, null); // clear
    await n.newProject();
    final cfg = c.read(songwriterProvider).config;
    expect(cfg.keyRoot, 0);
    expect(cfg.keyScaleName, 'major');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_default_key_test.dart`
Expected: FAIL — default `keyRoot` is currently `null`.

- [ ] **Step 3: Change `_emptyProject`**

In `lib/store/songwriter_store.dart`:

```dart
SongwriterProjectSnapshot _emptyProject() => const SongwriterProjectSnapshot(
  config: SongwriterConfig(
    tempo: 120,
    beatsPerBar: 4,
    beatUnit: 4,
    keyRoot: 0,
    keyScaleName: 'major',
  ),
  sections: [],
);
```

- [ ] **Step 4: Run it (PASS) + full regression**

Run: `flutter test test/store/songwriter_default_key_test.dart`
Run: `flutter test test/store/ test/models/`
Expected: all PASS. (If any prior test asserted a null default key, it did not — confirm green.)

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_default_key_test.dart
git commit -m "feat(songwriter): default new projects to C major"
```

---

### Task 2: Store inserters for undo

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_insert_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/songwriter_insert_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('insertSection restores a removed section at its index', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'A', lengthBars: 4);
    n.addSection(label: 'B', lengthBars: 4);
    n.addSection(label: 'C', lengthBars: 4);

    final removed = c.read(songwriterProvider).sections[1]; // 'B'
    n.removeSection(removed.id);
    expect(c.read(songwriterProvider).sections.map((s) => s.label), ['A', 'C']);

    n.insertSection(removed, 1);
    final labels =
        c.read(songwriterProvider).sections.map((s) => s.label).toList();
    expect(labels, ['A', 'B', 'C']);
    final orders =
        c.read(songwriterProvider).sections.map((s) => s.order).toList();
    expect(orders, [0, 1, 2]);
  });

  test('insertLane restores a removed lane at its index', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'H');
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'G');
    final lane = c.read(songwriterProvider).sections.single.lanes[0];
    n.removeLane(sectionId: s, laneId: lane.id);
    expect(c.read(songwriterProvider).sections.single.lanes.length, 1);
    n.insertLane(sectionId: s, lane: lane, index: 0);
    expect(c.read(songwriterProvider).sections.single.lanes.map((l) => l.label),
        ['H', 'G']);
  });

  test('insertBlock restores a removed block', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final block =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    n.removeBlock(sectionId: s, laneId: l, blockId: block.id);
    expect(
        c.read(songwriterProvider).sections.single.lanes.single.blocks, isEmpty);
    n.insertBlock(sectionId: s, laneId: l, block: block);
    expect(c.read(songwriterProvider).sections.single.lanes.single.blocks.single.id,
        block.id);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_insert_test.dart`
Expected: FAIL — inserters missing.

- [ ] **Step 3: Add the inserters**

In `SongwriterNotifier` (next to the remove methods). `insertSection` renumbers `order`; lane/block insert restore by position:

```dart
  void insertSection(SongSection section, int index) {
    final list = [...state.sections];
    final i = index.clamp(0, list.length);
    list.insert(i, section);
    _set(state.copyWith(sections: [
      for (var k = 0; k < list.length; k++) list[k].copyWith(order: k),
    ]));
  }

  void insertLane({
    required String sectionId,
    required SongLane lane,
    required int index,
  }) {
    _replaceSection(sectionId, (s) {
      final list = [...s.lanes];
      final i = index.clamp(0, list.length);
      list.insert(i, lane);
      return s.copyWith(lanes: [
        for (var k = 0; k < list.length; k++) list[k].copyWith(order: k),
      ]);
    });
  }

  void insertBlock({
    required String sectionId,
    required String laneId,
    required SongBlock block,
  }) {
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(blocks: [...l.blocks, block]),
    );
  }
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_insert_test.dart`
Expected: PASS (3).

- [ ] **Step 5: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_insert_test.dart
git commit -m "feat(songwriter): index-aware inserters for undo"
```

---

### Task 3: Undo-snackbar delete helper

**Files:**
- Create: `lib/features/songwriter/songwriter_undo.dart`
- Test: `test/features/songwriter/songwriter_undo_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_undo_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_undo.dart';

void main() {
  testWidgets('showUndoSnack shows the message and fires onUndo when tapped',
      (tester) async {
    var undone = false;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ),
    ));

    showUndoSnack(ctx, 'Section deleted', () => undone = true);
    await tester.pump();
    expect(find.text('Section deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, true);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_undo_test.dart`
Expected: FAIL — file/function missing.

- [ ] **Step 3: Implement the helper**

```dart
// lib/features/songwriter/songwriter_undo.dart
import 'package:flutter/material.dart';

/// Shows a SnackBar with an Undo action. Used for section/lane/block deletes:
/// the caller deletes immediately, then calls this with a restore closure.
void showUndoSnack(BuildContext context, String message, VoidCallback onUndo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/songwriter_undo_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_undo.dart test/features/songwriter/songwriter_undo_test.dart
git commit -m "feat(songwriter): undo snackbar helper"
```

---

### Task 4: Wire undo into section/lane/block deletes

**Files:**
- Modify: `lib/features/songwriter/songwriter_section_card.dart` (section delete; add a lane-delete affordance)
- Modify: `lib/features/songwriter/songwriter_block_tile.dart` (block delete)
- Modify: `lib/features/songwriter/songwriter_structure_editor.dart` (section delete)
- Test: manual + the helper test above (logic is store inserters, already tested)

- [ ] **Step 1: Section delete → undo (section card)**

In `SongwriterSectionCard`, the section ✕ currently calls `notifier.removeSection(sectionId)`. Replace with a capture-then-undo flow. Read the section + its index first:

```dart
onPressed: () {
  final project = ref.read(songwriterProvider);
  final index = project.sections.indexWhere((s) => s.id == sectionId);
  if (index < 0) return;
  final removed = project.sections[index];
  notifier.removeSection(sectionId);
  showUndoSnack(context, 'Section deleted',
      () => notifier.insertSection(removed, index));
},
```
Import `songwriter_undo.dart`.

- [ ] **Step 2: Add a lane delete affordance with undo**

In `SongwriterSectionCard`, the lanes are rendered as `SongwriterLaneRow`. Add a small trailing delete (e.g. a `PopupMenuButton` or an `IconButton`) per lane gutter. Simplest: pass an `onDelete` to `SongwriterLaneRow` OR handle in the card by wrapping each lane row with a trailing delete `IconButton`. Implement in the card to keep the row focused:

```dart
for (final lane in section.lanes)
  Row(
    children: [
      Expanded(child: SongwriterLaneRow(sectionId: sectionId, laneId: lane.id)),
      IconButton(
        key: Key('removeLane_${lane.id}'),
        icon: const Icon(Icons.close, size: 16),
        onPressed: () {
          final s = ref.read(songwriterProvider)
              .sections.firstWhere((x) => x.id == sectionId);
          final idx = s.lanes.indexWhere((l) => l.id == lane.id);
          if (idx < 0) return;
          final removed = s.lanes[idx];
          notifier.removeLane(sectionId: sectionId, laneId: lane.id);
          showUndoSnack(context, 'Lane deleted',
              () => notifier.insertLane(
                  sectionId: sectionId, lane: removed, index: idx));
        },
      ),
    ],
  ),
```

- [ ] **Step 3: Block delete → undo (block tile)**

In `SongwriterBlockTile._openMenu`, the Delete `onTap` currently calls `removeBlock`. Capture the block + restore:

```dart
onTap: () {
  Navigator.pop(sheetCtx);
  ref.read(songwriterProvider.notifier)
      .removeBlock(sectionId: sectionId, laneId: laneId, blockId: blockId);
  showUndoSnack(context, 'Block deleted',
      () => ref.read(songwriterProvider.notifier)
          .insertBlock(sectionId: sectionId, laneId: laneId, block: block));
},
```
(`block` is already in scope in `_openMenu`.) Import `songwriter_undo.dart`.

- [ ] **Step 4: Structure editor section delete → undo**

Apply the same capture-then-`showUndoSnack` pattern to the ✕ in `SongwriterStructureEditor` (it has `notifier` and `sections` in scope).

- [ ] **Step 5: Analyze + targeted tests**

Run: `flutter analyze lib/features/songwriter/`
Run: `flutter test test/features/songwriter/`
Expected: clean; existing widget tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/
git commit -m "feat(songwriter): undo on section/lane/block delete"
```

---

### Task 5: Section value pills + stepper popover

**Files:**
- Modify: `lib/features/songwriter/songwriter_section_card.dart`
- Test: `test/features/songwriter/songwriter_section_pills_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_section_pills_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_section_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('bars pill shows value and a popover increments it',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 8);
    final id = container.read(songwriterProvider).sections.single.id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: SongwriterSectionCard(sectionId: id))),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // Pill shows the current bar count.
    expect(find.text('8 bars'), findsOneWidget);

    // Open the bars popover and increment.
    await tester.tap(find.byKey(Key('barsPill_$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stepperPlus')));
    await tester.pumpAndSettle();

    expect(container.read(songwriterProvider).sections.single.lengthBars, 9);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_section_pills_test.dart`
Expected: FAIL — no `barsPill_` key.

- [ ] **Step 3: Replace the inline steppers with pills + a shared popover**

In `SongwriterSectionCard`, replace the `_Stepper` widgets in the header row with pill buttons. Keep the name `TextFormField` and the section ✕ (now undo-wired). Add:

```dart
// In the header Row, after the name field:
_ValuePill(
  key: Key('barsPill_$sectionId'),
  label: '${section.lengthBars} bars',
  onTap: () => _openStepper(
    context,
    title: 'Bars',
    value: section.lengthBars,
    min: 1,
    onChanged: (v) => notifier.setSectionLength(sectionId, v),
  ),
),
const SizedBox(width: 6),
_ValuePill(
  key: Key('repeatPill_$sectionId'),
  label: '${section.repeat}×',
  onTap: () => _openStepper(
    context,
    title: 'Repeat',
    value: section.repeat,
    min: 1,
    onChanged: (v) => notifier.setSectionRepeat(sectionId, v),
  ),
),
```

Add to the file (a stepper dialog + the pill widget). The dialog updates live as +/− are tapped:

```dart
void _openStepper(
  BuildContext context, {
  required String title,
  required int value,
  required int min,
  required ValueChanged<int> onChanged,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _StepperDialog(
        title: title, initial: value, min: min, onChanged: onChanged),
  );
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}

class _StepperDialog extends StatefulWidget {
  const _StepperDialog({
    required this.title,
    required this.initial,
    required this.min,
    required this.onChanged,
  });
  final String title;
  final int initial;
  final int min;
  final ValueChanged<int> onChanged;
  @override
  State<_StepperDialog> createState() => _StepperDialogState();
}

class _StepperDialogState extends State<_StepperDialog> {
  late int _v = widget.initial;
  void _set(int next) {
    if (next < widget.min) return;
    setState(() => _v = next);
    widget.onChanged(_v); // live-apply
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('stepperMinus'),
            icon: const Icon(Icons.remove),
            onPressed: () => _set(_v - 1),
          ),
          Text('$_v', style: Theme.of(context).textTheme.headlineSmall),
          IconButton(
            key: const Key('stepperPlus'),
            icon: const Icon(Icons.add),
            onPressed: () => _set(_v + 1),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
```

Remove the now-unused `_Stepper` class from the file (it is replaced).

- [ ] **Step 4: Run it (PASS) + section card regression**

Run: `flutter test test/features/songwriter/songwriter_section_pills_test.dart test/features/songwriter/songwriter_section_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_section_card.dart test/features/songwriter/songwriter_section_pills_test.dart
git commit -m "feat(songwriter): section bars/repeat value pills + stepper"
```

---

### Task 6: Bar ruler + lane gridlines

**Files:**
- Create: `lib/features/songwriter/songwriter_grid.dart` (ruler widget + gridline painter)
- Modify: `lib/features/songwriter/songwriter_section_card.dart` (mount ruler above lanes)
- Modify: `lib/features/songwriter/songwriter_lane_row.dart` (paint gridlines behind blocks)
- Test: `test/features/songwriter/songwriter_grid_test.dart`

Layout note: lane rows use a fixed **72 px gutter** then an `Expanded` body. The ruler must use the same 72 px leading gap so its numbers line up with the lane bars.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_grid_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_grid.dart';

void main() {
  testWidgets('bar ruler renders a number per bar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BarRuler(lengthBars: 4, gutter: 72)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_grid_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement ruler + painter**

```dart
// lib/features/songwriter/songwriter_grid.dart
import 'package:flutter/material.dart';

/// Bar-number ruler. Leads with [gutter] px (to align with the lane gutter),
/// then one evenly-sized cell per bar showing its 1-based number.
class BarRuler extends StatelessWidget {
  const BarRuler({super.key, required this.lengthBars, required this.gutter});
  final int lengthBars;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final bars = lengthBars < 1 ? 1 : lengthBars;
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          SizedBox(width: gutter),
          Expanded(
            child: Row(
              children: [
                for (var b = 1; b <= bars; b++)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('$b', style: style),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint vertical gridlines at each bar boundary, painted behind lane blocks.
class BarGridPainter extends CustomPainter {
  BarGridPainter({required this.lengthBars, required this.color});
  final int lengthBars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = lengthBars < 1 ? 1 : lengthBars;
    final barWidth = size.width / bars;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 1; i < bars; i++) {
      final x = i * barWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(BarGridPainter old) =>
      old.lengthBars != lengthBars || old.color != color;
}
```

- [ ] **Step 4: Mount the ruler in the section card**

In `SongwriterSectionCard`, between the header row and the lanes, add:

```dart
if (section.lanes.isNotEmpty) BarRuler(lengthBars: section.lengthBars, gutter: 72),
```
Import `songwriter_grid.dart`.

- [ ] **Step 5: Paint gridlines in the lane body**

In `SongwriterLaneRow`, inside the `LayoutBuilder`'s `Stack`, add a full-size `CustomPaint` as the first child (behind blocks):

```dart
return Stack(
  children: [
    Positioned.fill(
      child: CustomPaint(
        painter: BarGridPainter(
          lengthBars: lengthBars,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
    ),
    for (final block in lane.blocks)
      Positioned( ... existing ... ),
  ],
);
```
Import `songwriter_grid.dart`. (`withValues` requires a recent Flutter; if the analyzer flags it, use `.withOpacity(0.2)`.)

- [ ] **Step 6: Run tests (PASS) + analyze**

Run: `flutter test test/features/songwriter/songwriter_grid_test.dart test/features/songwriter/songwriter_lane_row_test.dart`
Run: `flutter analyze lib/features/songwriter/`
Expected: PASS / clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_grid_test.dart
git commit -m "feat(songwriter): bar ruler + lane gridlines"
```

---

### Task 7: Drop header title + empty-state helper

**Files:**
- Modify: `lib/features/songwriter/songwriter_header.dart`
- Modify: `lib/features/songwriter/songwriter_screen.dart`
- Modify: `test/features/songwriter/songwriter_header_overflow_test.dart` (still valid; title gone)
- Test: `test/features/songwriter/songwriter_empty_state_test.dart`

- [ ] **Step 1: Drop the title in the header**

In `SongwriterHeader`, remove the `Flexible`/`Expanded` "Songwriter" `Text` and its trailing `SizedBox`. Lead the Row with `const Spacer()` (so chips + actions right-align), then the key chip, tempo chip, new-project button, popup menu. Because the title is gone, the chips no longer need `Flexible` — render them directly (full text). Keep the compact buttons.

```dart
child: Row(
  children: [
    const Spacer(),
    _Chip(label: keyLabel, onTap: () => _editKey(context, ref)),
    const SizedBox(width: 6),
    _Chip(
      label: '${config.tempo} BPM',
      onTap: () => _editTempo(context, ref),
    ),
    IconButton( /* new project, compact — unchanged */ ),
    PopupMenuButton<String>( /* unchanged */ ),
  ],
),
```

- [ ] **Step 2: Update the overflow regression test**

The existing `songwriter_header_overflow_test.dart` asserts no overflow at 360 px and finds 'Songwriter'. Remove the `find.text('Songwriter')` expectation (title is gone) and keep the overflow assertion. Also pump at a realistic small width with a normal key:

```dart
expect(tester.takeException(), isNull);
expect(find.text('No key').evaluate().isNotEmpty || find.textContaining('major').evaluate().isNotEmpty, true);
```
(Just verify it renders + no overflow; drop the title check.)

- [ ] **Step 3: Run header tests (PASS)**

Run: `flutter test test/features/songwriter/songwriter_header_overflow_test.dart test/features/songwriter/songwriter_header_test.dart`
Expected: PASS.

- [ ] **Step 4: Write the empty-state test**

```dart
// test/features/songwriter/songwriter_empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty Writer tab shows guidance', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: SongwriterScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('songwriterEmptyHint')), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run it (FAIL), add the hint, run (PASS)**

Run: `flutter test test/features/songwriter/songwriter_empty_state_test.dart` → FAIL.

In `SongwriterScreen`'s `ListView`, when `project.sections.isEmpty`, render a hint above the "Add section" button:

```dart
if (project.sections.isEmpty)
  const Padding(
    key: Key('songwriterEmptyHint'),
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Build a song: add a section, add lanes (harmony + saves), '
      'then drop chord and voicing blocks.',
      style: TextStyle(color: Colors.white70),
    ),
  ),
```
Run again → PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_header_overflow_test.dart test/features/songwriter/songwriter_empty_state_test.dart
git commit -m "feat(songwriter): drop header title + empty-state guidance"
```

---

### Task 8: Verify + serve-sim

**Files:** none (verification only)

- [ ] **Step 1: Format + analyze**

Run: `dart format lib/features/songwriter/ lib/store/songwriter_store.dart`
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 2: Full test sweep**

Run: `flutter test`
Expected: all PASS (380 baseline + new polish tests).

- [ ] **Step 3: Simulator visual check**

Launch (`flutter run`), open the **Writer** tab. Confirm: empty hint shows; new project shows "C major"; add a section → bar ruler `1..8` + gridlines visible; bars/repeat pills open a stepper; add a harmony lane + chord → shows a Roman numeral (I, V); delete a section → "Section deleted · Undo" restores it; header shows full "C major"/"120 BPM" with no truncation/overflow. Check one compact (~360px) + one wide width.

- [ ] **Step 4: Commit any formatting**

```bash
git add -A
git commit -m "chore(songwriter): format + verify UX polish" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** default C major (T1), inserters + undo (T2–T4), value pills (T5), bar ruler + gridlines (T6), drop title + empty state (T7), verify (T8). All six spec items covered. ✓
- **Type/name consistency:** `insertSection(SongSection, int)`, `insertLane({sectionId, lane, index})`, `insertBlock({sectionId, laneId, block})`; `showUndoSnack(context, message, onUndo)`; `BarRuler(lengthBars, gutter)`, `BarGridPainter(lengthBars, color)`; pill keys `barsPill_<id>`/`repeatPill_<id>`, stepper keys `stepperPlus`/`stepperMinus`. Used consistently across tasks.
- **Placeholder scan:** none — every step has concrete code.
- **Adaptation flags:** verify the 72 px gutter constant against the current `SongwriterLaneRow` (adjust `BarRuler.gutter` to match if it changed); `withValues` vs `withOpacity` per installed Flutter. Default-C-major change (T1) may surface assumptions in existing tests — run the full store/model suite in T1 Step 4.

## Next plan
- **B2b** — playback transport + playhead + metronome, drag move/resize, tap-block-to-open-the-save (isolated editor), Make-Unique / Re-link. Then chord wheel, then C (enrichment).
