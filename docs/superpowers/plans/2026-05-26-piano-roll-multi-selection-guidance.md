# Piano Roll Multi-Selection And Interaction Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Piano Roll V2 multi-selection explicit and manageable, and add a Roll-local guidance surface that teaches the interaction model without changing the existing raw-pointer grid architecture.

**Architecture:** Keep `PianoRollState` unchanged and extend `PianoRollNotifier` with explicit selection-management methods. Reuse the existing `selectedNoteIds` and `selectedColumnTick` contracts, upgrade the portrait/landscape selection surfaces in `PianoRollScreenV2`, keep grid gesture behavior intact in `PianoRollGrid`, and reuse the shared `showAppInfoPanel(..., initialTab: 2)` as the canonical help sheet.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, `flutter_test`, existing `CustomPainter`/`Listener` piano-roll grid, shared help sheet in `lib/ui/core/app_info_panel.dart`, manual simulator verification with `serve-sim`.

---

## File Structure

### Modify

- `lib/store/piano_roll_store.dart`
  Add explicit selection-management methods without changing `PianoRollState`.
- `lib/features/piano_roll/piano_roll_grid.dart`
  Route batch-delete and multi-select overlay behavior through the new store APIs.
- `lib/features/piano_roll/piano_roll_screen_v2.dart`
  Add a Roll-local help action and explicit selection-management UI in portrait and landscape.
- `lib/ui/core/app_info_panel.dart`
  Expand Piano Roll interaction guidance with a selection-management section.
- `docs/piano_roll.md`
  Update the Piano Roll documentation to describe the new explicit selection actions and Roll help entry point.
- `test/store/piano_roll_store_test.dart`
  Cover the new store actions.
- `test/features/piano_roll/piano_roll_grid_test.dart`
  Cover multi-select gesture management and batch delete.
- `test/features/piano_roll/piano_roll_screen_v2_test.dart`
  Cover the new help entry point and selection summaries/actions.

### Do Not Create Unless Implementation Forces It

- Avoid introducing new model files or new providers unless the implementation
  reveals a real reuse problem.
- Avoid a separate Roll-only help system; reuse the existing shared help sheet.

---

## Task 1: Add Explicit Selection Actions To The Store

**Files:**

- Modify: `lib/store/piano_roll_store.dart`
- Test: `test/store/piano_roll_store_test.dart`

- [ ] **Step 1: Write failing store tests for clear, delete, and select-at-column**

```dart
test('clearSelection empties selectedNoteIds without clearing column', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(pianoRollProvider.notifier);
  notifier.addNote(60, 0, 4);
  notifier.addNote(64, 4, 4);
  final ids = container.read(pianoRollProvider).notes.map((n) => n.id).toSet();
  notifier.setSelection(ids);
  notifier.selectColumn(4);

  notifier.clearSelection();

  final state = container.read(pianoRollProvider);
  expect(state.selectedNoteIds, isEmpty);
  expect(state.selectedColumnTick, 4);
});

test('deleteSelectedNotes removes only selected notes', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(pianoRollProvider.notifier);
  notifier.addNote(60, 0, 4);
  notifier.addNote(64, 0, 4);
  notifier.addNote(67, 8, 4);
  final state = container.read(pianoRollProvider);
  notifier.setSelection({
    state.notes[0].id,
    state.notes[1].id,
  });

  notifier.deleteSelectedNotes();

  final next = container.read(pianoRollProvider);
  expect(next.notes.map((n) => n.midiNote), [67]);
  expect(next.selectedNoteIds, isEmpty);
});

test('selectNotesAtTick selects every active note at the tick', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(pianoRollProvider.notifier);
  notifier.addNote(60, 0, 4);
  notifier.addNote(64, 0, 4);
  notifier.addNote(67, 8, 4);

  notifier.selectNotesAtTick(1);

  final state = container.read(pianoRollProvider);
  expect(state.selectedNoteIds, hasLength(2));
});
```

- [ ] **Step 2: Run the targeted store tests and confirm failure**

Run: `flutter test test/store/piano_roll_store_test.dart`

Expected: FAIL because `clearSelection`, `deleteSelectedNotes`, and `selectNotesAtTick` do not exist yet.

- [ ] **Step 3: Implement the minimal store API**

```dart
void clearSelection() {
  state = state.copyWith(selectedNoteIds: const <String>{});
}

void deleteSelectedNotes() {
  if (state.selectedNoteIds.isEmpty) return;
  state = state.copyWith(
    notes: state.notes
        .where((note) => !state.selectedNoteIds.contains(note.id))
        .toList(),
    selectedNoteIds: const <String>{},
  );
}

void selectNotesAtTick(int tick) {
  final ids = rules
      .getNotesAtTick(state.notes, tick)
      .map((note) => note.id)
      .toSet();
  state = state.copyWith(
    selectedColumnTick: () => tick,
    selectedNoteIds: ids,
  );
}
```

- [ ] **Step 4: Re-run the targeted store tests**

Run: `flutter test test/store/piano_roll_store_test.dart`

Expected: PASS for the new selection-management tests and the existing store suite.

- [ ] **Step 5: Commit**

```bash
git add lib/store/piano_roll_store.dart test/store/piano_roll_store_test.dart
git commit -m "feat(piano roll): add explicit selection actions"
```

---

## Task 2: Upgrade Grid-Level Multi-Selection Management

**Files:**

- Modify: `lib/features/piano_roll/piano_roll_grid.dart`
- Test: `test/features/piano_roll/piano_roll_grid_test.dart`

- [ ] **Step 1: Write failing widget tests for multi-select management and batch delete**

```dart
testWidgets('double-tap second note adds it to selection', (tester) async {
  final first = PianoRollNote(
    id: 'n1',
    midiNote: 60,
    pitchClass: 'C',
    noteWithOctave: 'C4',
    startTick: 0,
    durationTicks: 4,
  );
  final second = PianoRollNote(
    id: 'n2',
    midiNote: 64,
    pitchClass: 'E',
    noteWithOctave: 'E4',
    startTick: 4,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(notes: [first, second]);
  final notifier = _TrackingNotifier(initial);
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => notifier),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapGrid(container));
  await tester.pump();

  final grid = find.byKey(const ValueKey('piano-roll-grid-listener'));
  final topLeft = tester.getTopLeft(grid);
  Offset noteCenter(int midi, int tick) {
    final row = _defaultPRState.pitchRangeEnd - midi;
    return topLeft + Offset((tick * 28) + 14, (row * 18) + 9);
  }

  await tester.tapAt(noteCenter(60, 0));
  await tester.pump();
  await tester.tapAt(noteCenter(64, 4));
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(noteCenter(64, 4));
  await tester.pump(const Duration(milliseconds: 350));

  expect(container.read(pianoRollProvider).selectedNoteIds, hasLength(2));
});

testWidgets('Delete key removes the whole multi-selection through the store', (
  tester,
) async {
  final initial = _defaultPRState.copyWith(
    notes: const [
      PianoRollNote(
        id: 'n1',
        midiNote: 60,
        pitchClass: 'C',
        noteWithOctave: 'C4',
        startTick: 0,
        durationTicks: 4,
      ),
      PianoRollNote(
        id: 'n2',
        midiNote: 64,
        pitchClass: 'E',
        noteWithOctave: 'E4',
        startTick: 4,
        durationTicks: 4,
      ),
    ],
    selectedNoteIds: {'n1', 'n2'},
  );
  final notifier = _TrackingNotifier(initial);
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => notifier),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapGrid(container));
  await tester.pump();

  await tester.sendKeyEvent(LogicalKeyboardKey.delete);
  await tester.pump();

  final state = container.read(pianoRollProvider);
  expect(state.notes, isEmpty);
  expect(state.selectedNoteIds, isEmpty);
});
```

- [ ] **Step 2: Run the targeted grid tests and confirm failure**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart`

Expected: FAIL because the test coverage expects explicit multi-selection management behavior that the widget does not yet expose clearly.

- [ ] **Step 3: Route batch operations through the new store methods**

```dart
void _deleteSelectedNotes() {
  final notifier = ref.read(pianoRollProvider.notifier);
  final hasSelection = ref.read(pianoRollProvider).selectedNoteIds.isNotEmpty;
  if (!hasSelection) return;
  notifier.deleteSelectedNotes();
  HapticFeedback.mediumImpact();
}
```

```dart
if (state.selectedNoteIds.length > 1)
  Positioned(
    top: 8,
    right: 8,
    child: _GridSelectionOverlay(
      count: state.selectedNoteIds.length,
      onClear: () => ref.read(pianoRollProvider.notifier).clearSelection(),
      onDelete: () => ref.read(pianoRollProvider.notifier).deleteSelectedNotes(),
    ),
  ),
```

```dart
class _GridSelectionOverlay extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  const _GridSelectionOverlay({
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count selected'),
        const SizedBox(width: 8),
        _SelectionActionChip(label: 'Clear', onTap: onClear),
        const SizedBox(width: 6),
        _SelectionActionChip(label: 'Delete', onTap: onDelete),
      ],
    );
  }
}
```

- [ ] **Step 4: Keep the existing gesture model intact**

```dart
if (isDoubleTap) {
  final toggled = _preTapSelection.contains(hit.id)
      ? _preTapSelection.difference({hit.id})
      : {..._preTapSelection, hit.id};
  notifier.setSelection(toggled.isEmpty ? {hit.id} : toggled);
}
```

Constraint:
Keep the raw `Listener` flow, the slop threshold, and the group-drag logic
unchanged except where the new store API removes duplication.

- [ ] **Step 5: Re-run the targeted grid tests**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart`

Expected: PASS for the new multi-select coverage and the pre-existing grid coverage.

- [ ] **Step 6: Commit**

```bash
git add lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart
git commit -m "feat(piano roll): improve grid multi-selection controls"
```

---

## Task 3: Expose Selection Management And Help In Piano Roll V2

**Files:**

- Modify: `lib/features/piano_roll/piano_roll_screen_v2.dart`
- Test: `test/features/piano_roll/piano_roll_screen_v2_test.dart`

- [ ] **Step 1: Write failing screen tests for Roll help and selection actions**

```dart
testWidgets('portrait roll app bar exposes help entry point', (tester) async {
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(
        () => _FakePianoRollNotifier(_defaultPRState),
      ),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapV2(container, surfaceSize: const Size(500, 800)));
  await tester.pump();

  expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
});

testWidgets('portrait action bar prioritizes selected note count', (tester) async {
  final initial = _defaultPRState.copyWith(
    notes: const [
      PianoRollNote(
        id: 'n1',
        midiNote: 60,
        pitchClass: 'C',
        noteWithOctave: 'C4',
        startTick: 0,
        durationTicks: 4,
      ),
    ],
    selectedNoteIds: {'n1'},
    selectedColumnTick: 0,
  );
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => _FakePianoRollNotifier(initial)),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapV2(container, surfaceSize: const Size(500, 800)));
  await tester.pump();

  expect(find.text('1 selected'), findsOneWidget);
});
```

- [ ] **Step 2: Run the targeted screen tests and confirm failure**

Run: `flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart`

Expected: FAIL because the Roll shell does not yet expose help or selection-management summaries/actions.

- [ ] **Step 3: Add a Roll-local help entry point**

```dart
import '../../ui/core/app_info_panel.dart';

void _openPanel(String key) {
  HapticFeedback.selectionClick();
  switch (key) {
    case 'help':
      showAppInfoPanel(context, initialTab: 2);
      return;
    case 'scale':
      showWidgetSheet(
        context: context,
        title: 'Scale Highlight',
        child: const PianoRollScalePicker(),
      );
      return;
  }
}
```

```dart
CompactAppBar(
  title: 'Roll',
  chipLabel: _headerChipLabel(state),
  actions: [
    IconBtn(
      icon: Icons.help_outline_rounded,
      onTap: () => _openPanel('help'),
    ),
    IconBtn(
      icon: Icons.settings_outlined,
      onTap: () => _openPanel('settings'),
    ),
  ],
)
```

- [ ] **Step 4: Make selection summaries and actions explicit**

```dart
final selectedCount = state.selectedNoteIds.length;
final columnCount = state.selectedColumnTick == null
    ? 0
    : rules.getNotesAtTick(state.notes, state.selectedColumnTick!).length;
```

```dart
if (selectedCount > 0) {
  return Row(
    children: [
      Text('$selectedCount selected'),
      _SelectionActionChip(label: 'Clear', onTap: notifier.clearSelection),
      _SelectionActionChip(label: 'Delete', onTap: notifier.deleteSelectedNotes),
    ],
  );
}

if (state.selectedColumnTick != null && columnCount > 0) {
  return Row(
    children: [
      Text('Col $barBeat  •  $columnCount notes'),
      _SelectionActionChip(
        label: 'Select column',
        onTap: () => notifier.selectNotesAtTick(state.selectedColumnTick!),
      ),
    ],
  );
}
```

```dart
class _SelectionActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SelectionActionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MuzicianTheme.glassBorder),
        ),
        child: Text(label),
      ),
    );
  }
}
```

Implementation notes:

- Keep portrait compact; do not introduce a new large panel row.
- In landscape, place the same actions in the existing `Selection` section.
- Every new action must expose semantics/tooltip text if icon-only.

- [ ] **Step 5: Re-run the targeted screen tests**

Run: `flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart`

Expected: PASS for portrait help entry, selection summary, and landscape action visibility.

- [ ] **Step 6: Commit**

```bash
git add lib/features/piano_roll/piano_roll_screen_v2.dart test/features/piano_roll/piano_roll_screen_v2_test.dart
git commit -m "feat(piano roll): surface selection actions and help"
```

---

## Task 4: Expand The Piano Roll Interaction Guide

**Files:**

- Modify: `lib/ui/core/app_info_panel.dart`
- Modify: `docs/piano_roll.md`

- [ ] **Step 1: Update the in-app help copy to explain the selection mental model**

```dart
_Entry(
  icon: Icons.layers_outlined,
  label: 'Selected column vs selected notes',
  desc:
      'The blue column marker is your timeline anchor for detection, add-stack, '
      'and playback. Note selection is separate: tap a note to solo-select it, '
      'double-tap another note to add or remove it from the selection.',
  color: MuzicianTheme.sky,
),
_Entry(
  icon: Icons.select_all_rounded,
  label: 'Select notes at the current column',
  desc:
      'Use the selection action in the Roll controls to select every note that '
      'is active at the current column, then drag or delete them as a group.',
  color: MuzicianTheme.sky,
),
_Entry(
  icon: Icons.open_with_outlined,
  label: 'Move a selected group',
  desc:
      'After more than one note is selected, drag any selected note body to move '
      'the whole group while keeping their relative spacing.',
  color: MuzicianTheme.sky,
),
```

- [ ] **Step 2: Update the repository docs**

```md
| **Select column notes** | Selection action: selects all notes active at the current column tick |
| **Clear selection** | Selection action: removes the current note selection without clearing the column |
| **Delete selected notes** | Selection action or `Delete`/`Backspace` on desktop/web |
```

```md
- **Help entry point**: Roll V2 app bar exposes a `help_outline_rounded` action
  that opens `showAppInfoPanel(context, initialTab: 2)`.
- **Selection model**: `selectedColumnTick` anchors timeline tools; `selectedNoteIds`
  tracks note selection for group editing.
```

- [ ] **Step 3: Format the changed docs and Dart files**

Run:

```bash
dart format lib/ui/core/app_info_panel.dart lib/features/piano_roll/piano_roll_screen_v2.dart lib/features/piano_roll/piano_roll_grid.dart lib/store/piano_roll_store.dart test/store/piano_roll_store_test.dart test/features/piano_roll/piano_roll_grid_test.dart test/features/piano_roll/piano_roll_screen_v2_test.dart
```

Expected: Files reformatted with no semantic changes.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/core/app_info_panel.dart docs/piano_roll.md
git commit -m "docs(piano roll): document selection guidance"
```

---

## Task 5: Verify End-To-End Before Completion

**Files:**

- Read/verify only: changed files from Tasks 1-4

- [ ] **Step 1: Run the focused test targets**

Run:

```bash
flutter test test/store/piano_roll_store_test.dart
flutter test test/features/piano_roll/piano_roll_grid_test.dart
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

Expected: PASS on all targeted suites.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`

Expected: No new analyzer errors.

- [ ] **Step 3: Manually verify portrait and landscape**

Run:

```bash
flutter run -d 453338A4-9100-4393-B3B6-3A008581FA7C
npx serve-sim --detach -q
```

Manual checklist:

- portrait shows Roll help action
- selecting a note changes the status summary
- selecting a second note via double-tap keeps both selected
- `Select column` selects all active notes at the current column
- `Clear` clears note selection but keeps the column anchor
- `Delete` removes only selected notes
- landscape rail shows equivalent selection actions
- help sheet opens to Piano Roll content and reflects the new instructions

- [ ] **Step 4: Stop simulator helpers**

Run:

```bash
npx serve-sim --kill
```

Expected: Detached helper shuts down cleanly.

- [ ] **Step 5: Final commit**

```bash
git add lib/store/piano_roll_store.dart lib/features/piano_roll/piano_roll_grid.dart lib/features/piano_roll/piano_roll_screen_v2.dart lib/ui/core/app_info_panel.dart docs/piano_roll.md test/store/piano_roll_store_test.dart test/features/piano_roll/piano_roll_grid_test.dart test/features/piano_roll/piano_roll_screen_v2_test.dart
git commit -m "feat(piano roll): improve multi-selection guidance"
```

---

## Self-Review Notes

- This plan intentionally keeps `PianoRollState` unchanged.
- The plan does not add a separate selection mode, marquee selection, or new
  persistence requirements.
- Every scoped requirement in the design doc maps to one of these tasks:
  - explicit selection actions -> Task 1
  - grid-level management -> Task 2
  - portrait/landscape visibility -> Task 3
  - in-product guidance -> Task 4
  - verification -> Task 5
