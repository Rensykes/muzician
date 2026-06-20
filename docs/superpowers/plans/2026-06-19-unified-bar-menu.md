# Unified Bar Menu + Per-Verse Bar Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tapping any Writer bar open one consistent, non-destructive action sheet (long-press = delete), and make per-verse bar lyrics directly editable via a "Lyrics — Verse N" action.

**Architecture:** A reusable `showBarActionSheet` (built on `showWidgetSheet`) renders a list of `_BarAction` items. The `_BarRow` tap handlers (`_onTapBlock`, `_onTapSave`, empty-cell `_addAt`) are rewired to open it instead of acting directly. A `_VerseLyricDialog` (stateful, controller disposed) edits `block.lyrics[instanceIndex]` via `setBlockLyric`. No model changes — `SongBlock.lyrics`/`setBlockLyric` already support per-verse, and `_BarCell` already renders `block.lyrics[instanceIndex]`.

**Tech Stack:** Dart / Flutter, Riverpod (`songwriterProvider`), `package:flutter_test`, SharedPreferences mock.

**Spec:** `docs/superpowers/specs/2026-06-19-unified-bar-menu-design.md`

All work is in `lib/features/songwriter/songwriter_screen_sheet.dart` (+ one test file). Helpers referenced: `showWidgetSheet({context,title,child})` from `_mockup_shell.dart` (already imported); `MuzicianTheme.{red,textPrimary,surface}`; existing `_editBlock`, `showHarmonyBlockSheet`, `_pickFromLibrary`, `_addAt`, `_removeBlock`, `_onTapSave` in `_BarRow`.

---

## File Structure

- `lib/features/songwriter/songwriter_screen_sheet.dart`
  - New top-level: `_BarAction` (value type) + `showBarActionSheet(...)`.
  - New widget: `_VerseLyricDialog` (stateful).
  - Modified `_BarRow` methods: `_onTapBlock`, `_onTapSave`, and a new `_editVerseLyric` + `_onTapEmpty`.
- Test: `test/features/songwriter/songwriter_bar_menu_test.dart`

---

## Task 1: Reusable bar action sheet

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (add near other top-level helpers, e.g. just above `class _BarRow`)
- Test: `test/features/songwriter/songwriter_bar_menu_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/songwriter/songwriter_bar_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';

void main() {
  testWidgets('showBarActionSheet renders items and invokes the tapped action',
      (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const Key('open'),
              onPressed: () => showBarActionSheet(
                context: context,
                title: 'Bar',
                actions: [
                  BarAction(
                    key: const Key('act_a'),
                    label: 'Action A',
                    icon: Icons.edit,
                    onTap: () => tapped = 'a',
                  ),
                  BarAction(
                    key: const Key('act_del'),
                    label: 'Remove',
                    icon: Icons.delete,
                    destructive: true,
                    onTap: () => tapped = 'del',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Action A'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.byKey(const Key('act_del')));
    await tester.pumpAndSettle();
    expect(tapped, 'del');
    // Sheet closed after selection.
    expect(find.text('Action A'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: FAIL — `showBarActionSheet` / `BarAction` undefined (compile error).

- [ ] **Step 3: Implement**

In `songwriter_screen_sheet.dart`, add just above `class _BarRow extends ConsumerWidget {`:

```dart
/// One row in the unified bar action sheet. [onTap] runs after the sheet has
/// closed.
class BarAction {
  const BarAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.key,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Key? key;
  final bool destructive;
}

/// Single, non-destructive entrypoint for a bar: a bottom sheet listing
/// [actions]. Tapping a row closes the sheet, then invokes its callback.
Future<void> showBarActionSheet({
  required BuildContext context,
  required String title,
  required List<BarAction> actions,
}) {
  return showWidgetSheet(
    context: context,
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in actions)
          ListTile(
            key: a.key,
            leading: Icon(
              a.icon,
              color: a.destructive
                  ? MuzicianTheme.red
                  : MuzicianTheme.textPrimary,
            ),
            title: Text(
              a.label,
              style: TextStyle(
                color: a.destructive
                    ? MuzicianTheme.red
                    : MuzicianTheme.textPrimary,
              ),
            ),
            onTap: () {
              Navigator.of(context).pop();
              a.onTap();
            },
          ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_bar_menu_test.dart
git commit -m "feat(songwriter): reusable bar action sheet"
```

---

## Task 2: Per-verse lyric dialog + `_editVerseLyric`

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (add `_VerseLyricDialog` near `_SectionLyricsDialog`; add `_editVerseLyric` method inside `_BarRow`)
- Test: `test/features/songwriter/songwriter_bar_menu_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/features/songwriter/songwriter_bar_menu_test.dart` (add these imports at top of the file as well: `package:flutter_riverpod/flutter_riverpod.dart`, `package:shared_preferences/shared_preferences.dart`, `package:muzician/models/songwriter.dart`, `package:muzician/store/songwriter_store.dart`; and add `setUp(() => SharedPreferences.setMockInitialValues({}));` inside `main`):

```dart
  testWidgets('Lyrics action writes the lyric for the tapped verse',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.setSectionRepeat(sectionId, 2);
    final laneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony).id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: const SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: 'maj',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Open the action sheet from the SECOND verse row (instanceIndex 1).
    final secondRow = find.byKey(Key('sectionInstance_${sectionId}_1'));
    expect(secondRow, findsOneWidget);
    await tester.tap(find.descendant(of: secondRow, matching: find.text('C')));
    await tester.pumpAndSettle();

    // Tap "Lyrics — Verse 2".
    await tester.tap(find.byKey(const Key('barActionLyrics')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('verseLyricField')), 'second verse words');
    await tester.tap(find.byKey(const Key('verseLyricSave')));
    await tester.pumpAndSettle();

    final block = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony).blocks.first;
    expect(block.lyrics, ['', 'second verse words']);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: FAIL — no `barActionLyrics` item yet (Task 3 wires the menu; this task adds the dialog + method the menu will call). It may fail on the missing action key; that is expected until Task 3.

> Note: this test exercises Task 2 **and** Task 3 together (dialog + menu wiring). Keep it; it goes green at the end of Task 3. For Task 2's own green checkpoint, rely on Step 4 below (analyzer) — the dialog is leaf code with no standalone trigger yet.

- [ ] **Step 3: Implement the dialog + method**

Add near `_SectionLyricsDialog` (reuse the same shape):

```dart
class _VerseLyricDialog extends StatefulWidget {
  const _VerseLyricDialog({
    required this.verseNumber,
    required this.initialText,
    required this.onSave,
  });
  final int verseNumber;
  final String initialText;
  final ValueChanged<String> onSave;

  @override
  State<_VerseLyricDialog> createState() => _VerseLyricDialogState();
}

class _VerseLyricDialogState extends State<_VerseLyricDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MuzicianTheme.surface,
      title: Text('Lyrics — Verse ${widget.verseNumber}',
          style: const TextStyle(color: MuzicianTheme.textPrimary)),
      content: TextField(
        key: const Key('verseLyricField'),
        controller: _controller,
        autofocus: true,
        maxLines: null,
        minLines: 2,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Words for this verse…'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('verseLyricSave'),
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

Add this method inside `class _BarRow` (e.g. after `_editBlock`):

```dart
  void _editVerseLyric(BuildContext context, WidgetRef ref, SongBlock block) {
    final current = instanceIndex < block.lyrics.length
        ? block.lyrics[instanceIndex]
        : '';
    showDialog<void>(
      context: context,
      builder: (_) => _VerseLyricDialog(
        verseNumber: instanceIndex + 1,
        initialText: current,
        onSave: (text) => ref.read(songwriterProvider.notifier).setBlockLyric(
              sectionId: section.id,
              laneId: lane.id,
              blockId: block.id,
              verseIndex: instanceIndex,
              text: text,
            ),
      ),
    );
  }
```

- [ ] **Step 4: Run analyzer (Task-2 checkpoint)**

Run: `dart analyze lib/features/songwriter/songwriter_screen_sheet.dart`
Expected: No issues. (The appended widget test stays red until Task 3 wires the menu — that is expected.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart
git commit -m "feat(songwriter): per-verse bar lyric dialog + editor"
```

---

## Task 3: Wire chord/silent block tap to the action sheet

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` — rewrite `_onTapBlock`
- Test: the appended test from Task 2 now goes green; add one more below.

- [ ] **Step 1: Add a "tap does not delete" test**

Append to `test/features/songwriter/songwriter_bar_menu_test.dart`:

```dart
  testWidgets('tapping a chord opens the action sheet and does not remove it',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony).id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: const SongBlock(
        id: 'b1', startBar: 0, spanBars: 1, chordSymbol: 'C',
        chordQuality: 'maj', chordRootPc: 0, chordNotes: ['C', 'E', 'G'],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionChangeChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionLyrics')), findsOneWidget);
    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    // Block still present — tap was not destructive.
    expect(
      container.read(songwriterProvider).sections.first.lanes
          .firstWhere((l) => l.kind == SongLaneKind.harmony).blocks.length,
      1,
    );
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: FAIL — the action items aren't shown on chord tap yet.

- [ ] **Step 3: Rewrite `_onTapBlock`**

Replace the entire existing `_onTapBlock` method body with a version that opens the action sheet. Keep the chord-detection logic; route actions to existing methods:

```dart
  /// Tap on a placed block → unified, non-destructive action sheet.
  void _onTapBlock(BuildContext context, WidgetRef ref, SongBlock block) {
    final notifier = ref.read(songwriterProvider.notifier);
    final isChord = !block.isSilent &&
        block.chordRootPc != null &&
        block.chordQuality != null;
    final save = section.lanes
        .where((l) => l.kind == SongLaneKind.save)
        .expand((l) => l.blocks)
        .where((b) =>
            b.startBar < block.endBar && block.startBar < b.endBar)
        .firstOrNull;

    showBarActionSheet(
      context: context,
      title: isChord ? (block.chordSymbol ?? 'Chord') : 'Bar',
      actions: [
        if (isChord)
          BarAction(
            key: const Key('barActionChangeChord'),
            label: 'Change chord',
            icon: Icons.edit,
            onTap: () => _editBlock(context, ref, block),
          ),
        if (isChord)
          BarAction(
            key: const Key('barActionVoicings'),
            label: 'Voicings & library',
            icon: Icons.library_music,
            onTap: () => _openHarmonyTools(context, ref, block),
          ),
        BarAction(
          key: const Key('barActionLyrics'),
          label: 'Lyrics — Verse ${instanceIndex + 1}',
          icon: Icons.lyrics_outlined,
          onTap: () => _editVerseLyric(context, ref, block),
        ),
        if (save != null)
          BarAction(
            key: const Key('barActionRemoveSave'),
            label: 'Remove save',
            icon: Icons.bookmark_remove,
            destructive: true,
            onTap: () => _removeSave(context, ref, save),
          ),
        BarAction(
          key: const Key('barActionRemove'),
          label: isChord ? 'Remove chord' : 'Remove',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => _removeBlock(context, notifier, block),
        ),
      ],
    );
  }
```

Rename the OLD body of `_onTapBlock` (the chord-detection + `showHarmonyBlockSheet(...)` call) into a new method `_openHarmonyTools(BuildContext context, WidgetRef ref, SongBlock block)` — i.e. move everything that was previously after the `if (!isChord) { _editBlock(...); return; }` guard (the `cfg`/`voicings`/`thirdAbove`/`matches`/`showHarmonyBlockSheet(...)` block) verbatim into `_openHarmonyTools`. This preserves the voicings/library/third-above behavior, now one level down.

- [ ] **Step 4: Run to verify both tests pass**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: PASS (the Task-2 verse-lyric test and this chord-tap test both green).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_bar_menu_test.dart
git commit -m "feat(songwriter): chord bar tap opens unified action sheet"
```

---

## Task 4: Non-destructive save tap + `_removeSave`

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` — extract `_removeSave`, rewrite `_onTapSave`
- Test: append

Currently `_onTapSave` removes the save immediately (with undo). Split: `_removeSave` keeps the removal logic; `_onTapSave` opens an action sheet instead.

> **As shipped (post-plan):** the "Replace from library" item below was dropped
> — `addLibraryBlockAt` rejects an overlapping placement, so replace silently
> no-opped. The final save menu is **Lyrics — Verse N** + **Remove save** (see
> the "Post-plan additions" section at the end).

- [ ] **Step 1: Add a "save tap does not delete" test**

Append to `test/features/songwriter/songwriter_bar_menu_test.dart`:

```dart
  testWidgets('tapping a standalone save opens a menu and does not remove it',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final saveLaneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.save).id;
    n.addSaveBlock(
      sectionId: sectionId,
      laneId: saveLaneId,
      saveId: 'save-xyz',
      startBar: 0,
      spanBars: 1,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(Key('saveCell_save-xyz_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionRemoveSave')), findsOneWidget);
    // Still present.
    expect(
      container.read(songwriterProvider).sections.first.lanes
          .firstWhere((l) => l.kind == SongLaneKind.save).blocks.length,
      1,
    );
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: FAIL — tapping the save still removes it / no `barActionRemoveSave` shown.

- [ ] **Step 3: Refactor `_onTapSave` → `_removeSave` + menu**

Rename the current `_onTapSave` method to `_removeSave` (keep its body exactly — it resolves the save lane and removes the block with undo). Then add a new `_onTapSave` that opens the action sheet:

```dart
  void _onTapSave(BuildContext context, WidgetRef ref, SongBlock save) {
    showBarActionSheet(
      context: context,
      title: _saveName(ref, save),
      actions: [
        BarAction(
          key: const Key('barActionOpenSave'),
          label: 'Replace from library',
          icon: Icons.swap_horiz,
          onTap: () => _pickFromLibrary(context, ref, save.startBar),
        ),
        BarAction(
          key: const Key('barActionRemoveSave'),
          label: 'Remove save',
          icon: Icons.bookmark_remove,
          destructive: true,
          onTap: () => _removeSave(context, ref, save),
        ),
      ],
    );
  }
```

(The chord-bar "Remove save" action from Task 3 already calls `_removeSave` — now defined. The standalone-save cell and the badge both call `_onTapSave` via the existing `onTap`/`onSaveTap` wiring, which now opens the menu.)

Also add a long-press delete to the standalone save cell: in `_BarRow.build`, the standalone-save `_BarCell(...)` (the one keyed `saveCell_...`) currently has no `onLongPress`. Add:

```dart
                    onLongPress: () => _removeSave(context, ref, save),
```
to that `_BarCell` constructor call.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_bar_menu_test.dart
git commit -m "feat(songwriter): save tap opens menu instead of deleting"
```

---

## Task 5: Empty bar add sheet

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` — empty-cell `onTap`
- Test: append

Currently an empty cell's `onTap` calls `_addAt(...)` directly (opens the chord sheet). Wrap it in the action sheet for consistency: Add chord / Add from library.

- [ ] **Step 1: Add an "empty bar add menu" test**

Append to `test/features/songwriter/songwriter_bar_menu_test.dart`:

```dart
  testWidgets('tapping an empty bar opens an add menu', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // The first empty bar cell shows a centered '·'. Tap the first one.
    await tester.tap(find.text('·').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionAddChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionAddLibrary')), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: FAIL — empty tap opens the chord sheet directly, no add menu.

- [ ] **Step 3: Add `_onTapEmpty` and rewire the empty cell**

Add the method to `_BarRow`:

```dart
  void _onTapEmpty(BuildContext context, WidgetRef ref, int bar) {
    showBarActionSheet(
      context: context,
      title: 'Bar ${bar + 1}',
      actions: [
        BarAction(
          key: const Key('barActionAddChord'),
          label: 'Add chord',
          icon: Icons.piano,
          onTap: () => _addAt(context, ref, bar),
        ),
        BarAction(
          key: const Key('barActionAddLibrary'),
          label: 'Add from library',
          icon: Icons.library_music,
          onTap: () => _pickFromLibrary(context, ref, bar),
        ),
      ],
    );
  }
```

In `_BarRow.build`, change the empty cell's `onTap` from `onTap: () => _addAt(context, ref, bar)` to:

```dart
                  onTap: () => _onTapEmpty(context, ref, bar),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_bar_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Full verification + commit**

Run: `dart format lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_bar_menu_test.dart`
Run: `dart analyze lib/` → No issues.
Run: `flutter test` → all pass.

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_bar_menu_test.dart
git commit -m "feat(songwriter): empty bar tap opens add menu"
```

---

## Task 6: Manual verification (serve-sim)

**No automated test — confirm live per spec.**

- [ ] Boot the sim (serve-sim skill), open Writer, add a section.
- [ ] Tap an empty bar → add menu (Add chord / Add from library); add a chord.
- [ ] Tap the chord → action sheet (Change chord / Voicings & library / Lyrics — Verse 1 / Remove chord) — confirm nothing was deleted by the tap.
- [ ] Long-press the chord → it is removed (undo snackbar appears).
- [ ] Bump the section to ×2 (Verses pill). In verse 2's row, tap the chord → "Lyrics — Verse 2" → type words → Save. Confirm verse 2's bar shows those words and verse 1's does not.
- [ ] Add a save (from library), tap it → menu (Replace / Remove) — confirm the tap did not delete it. Capture a screenshot of the action sheet.

---

## Final verification

- [x] `flutter test` — all pass (610).
- [x] `dart analyze` — no issues.
- [x] All tasks committed + pushed.

## Post-plan additions (as shipped)

Changes made after the original 6 tasks, during review/iteration:

- **Dropped "Replace from library"** from the save menu (`ee4392d`):
  `addLibraryBlockAt` rejects a placement overlapping the existing save, so the
  replace silently no-opped. Real replace ships with the forced-save flow.
- **Long-press delete test** (`23cacf0`): added the missing widget test for the
  headline long-press = delete gesture (+ undo snackbar), refreshed a stale
  save-badge comment, and amended the spec re: the dropped replace.
- **Per-verse lyrics on save bars** (treat bar and save the same): the save
  action menu gained **Lyrics — Verse N**, editing the save block's own lyrics
  in its save lane. `_editVerseLyric` now takes an optional `laneId` (defaults to
  the row's harmony lane; saves pass their save lane via the new `_saveLaneId`).
  Save cells render their per-verse lyric. Tests: save menu writes the save
  block lyric; save cell renders it.
