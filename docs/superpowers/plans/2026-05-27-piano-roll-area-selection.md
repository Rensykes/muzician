# Piano Roll Area Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit `Select` mode to Piano Roll so users can drag a rectangular marquee to select arbitrary groups and sequences of notes, then refine with double-tap and edit the resulting selection with the existing `Draw` / `Scissors` workflows.

**Architecture:** Keep the committed selection state in `PianoRollState.selectedNoteIds`, but keep all marquee interaction state local to `PianoRollGrid`. Extend `PianoRollTool` with a dedicated `select` mode, add live marquee hit-testing against rendered note rectangles, and commit the final intersected note ids on pointer-up. Reframe the old column-based selection action as a secondary shortcut so the new explicit tool is clearly the main multi-selection entry point.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, existing raw-pointer `Listener` in `PianoRollGrid`, `flutter_test`, shared Piano Roll help/docs, compact and wide manual verification via Simulator / `serve-sim`.

---

## Task Graph

### Sequential spine

1. Task 1 adds the new `Select` tool to the shared Piano Roll model and shell.
2. Task 2 adds failing widget tests that define the marquee selection semantics.
3. Task 3 implements marquee state, hit-testing, and overlay rendering in the grid.
4. Task 4 resolves gesture ownership for `Select` mode without regressing `Draw`, `Scissors`, zoom, or navigation.
5. Task 5 updates product copy, docs, and in-app guidance to teach the new flow.
6. Task 6 performs focused review and final verification.

### Safe parallelization

- Task 1 and Task 5 can overlap once the `Select` tool name is locked.
- Task 2 must land before Tasks 3 and 4 if you want clean TDD.
- Task 6 happens after Tasks 1 through 5.

### Recommended ownership

- `instrument-renderer`: Tasks 2, 3, and 4
- `state-architect`: Task 1
- general-purpose sub-agent: Task 5
- `accessibility-ux`: review portion of Task 6
- `code-quality`: review portion of Task 6

### Multi-Agent Dispatch Notes

This plan is intentionally structured for external multi-agent execution.

#### Integration order

1. Task 1 lands first so every downstream agent can rely on the final `Select`
   naming and `PianoRollTool.select`.
2. Task 2 lands next or is at least merged into the working branch before Task 3
   starts, so marquee behavior is test-defined.
3. Tasks 3 and 4 should be handled by the same implementation agent or by two
   sequential agents that both own `lib/features/piano_roll/piano_roll_grid.dart`.
4. Task 5 should be merged only after the final user-visible behavior is stable.
5. Task 6 reviewers work on the integrated result, not on isolated partial diffs.

#### Ownership boundaries

- **Task 1 owner must not edit** `lib/features/piano_roll/piano_roll_grid.dart`
- **Task 2 owner edits only tests** under
  `test/features/piano_roll/piano_roll_grid_test.dart`
- **Task 3/4 owner owns grid implementation** and may update the same grid test
  file, but should not rewrite docs/help copy
- **Task 5 owner owns only docs/help/shell wording**:
  - `docs/piano_roll.md`
  - `lib/ui/core/app_info_panel.dart`
  - `lib/features/piano_roll/piano_roll_screen_v2.dart` only for visible copy
- **Review agents are audit-only**

#### Merge conflict hotspots

The orchestrator should expect shared edits in:

- `lib/features/piano_roll/piano_roll_screen_v2.dart`
- `test/features/piano_roll/piano_roll_screen_v2_test.dart`
- `test/features/piano_roll/piano_roll_grid_test.dart`

To reduce churn:

- merge Task 1 before any shell-copy work
- merge Task 2 before Task 3
- keep Task 5 from touching grid logic

#### Mandatory product docs/help outputs

The implementation is not complete until both are updated:

- `docs/piano_roll.md`
- Piano Roll content inside `lib/ui/core/app_info_panel.dart`

Those are required deliverables, not optional cleanup.

---

## File Structure

### Modify

- `lib/models/piano_roll.dart`
- `lib/features/piano_roll/piano_roll_grid.dart`
- `lib/features/piano_roll/piano_roll_screen_v2.dart`
- `docs/piano_roll.md`
- `lib/ui/core/app_info_panel.dart`
- `test/features/piano_roll/piano_roll_grid_test.dart`
- `test/features/piano_roll/piano_roll_screen_v2_test.dart`

### No new global store file expected

The current store API is already sufficient for the first iteration:

- `setSelection(Set<String> ids)`
- `selectNote(String? noteId)`
- `clearSelection()`

Only touch `lib/store/piano_roll_store.dart` if an implementation detail makes a
very small helper unavoidable. Do not move marquee drag state into the store.

### New keys / UI identifiers to add

- `ValueKey('piano-roll-select-marquee')` for the live marquee overlay
- optional `ValueKey('piano-roll-select-hint')` if an inline hint is added

### Naming cleanup to include

The old column shortcut currently branded as `Multi-select` should be renamed to
something secondary such as `Select column` so it does not compete with the new
primary `Select` tool.

---

## Task 1: Expose The New Select Tool In Shared UI

**Owner:** `state-architect`  
**Scope:** `PianoRollTool` enum, shell controls, tool labels, column-selection naming cleanup  
**Dependencies:** none

**Files:**

- Modify: `lib/models/piano_roll.dart`
- Modify: `lib/features/piano_roll/piano_roll_screen_v2.dart`
- Test: `test/features/piano_roll/piano_roll_screen_v2_test.dart`

- [ ] **Step 1: Write the failing shell tests first**

Add or extend `test/features/piano_roll/piano_roll_screen_v2_test.dart` to pin:

- the new `Select` tool is visible in the main tool segment
- the landscape inspector exposes `Select` alongside `Draw` / `Scissors`
- the old column shortcut is no longer the primary `Multi-select` label

Suggested additions:

```dart
testWidgets('tool segment exposes Select mode', (tester) async {
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

  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(_wrapV2(container));
  await tester.pump();

  expect(find.text('Select'), findsWidgets);
});

testWidgets('column selection action uses secondary wording', (tester) async {
  final state = _defaultPRState.copyWith(
    notes: const [_columnNote],
    selectedColumnTick: () => 0,
  );
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => _FakePianoRollNotifier(state)),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(1200, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(_wrapV2(container));
  await tester.pump();

  expect(find.text('Select column'), findsOneWidget);
  expect(find.text('Multi-select'), findsNothing);
});
```

- [ ] **Step 2: Run the shell test target and confirm failure**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

Expected: fail because `PianoRollTool.select` and the new labels do not exist yet.

- [ ] **Step 3: Extend the shared tool enum**

Modify `lib/models/piano_roll.dart`:

```dart
enum PianoRollTool { draw, select, scissors, paint, delete }
```

Also update the enum doc comment so the new contract is explicit:

```dart
///   * [select]   — drag a marquee box to select intersected notes.
```

- [ ] **Step 4: Add Select to the shell and rename the old column shortcut**

Update `lib/features/piano_roll/piano_roll_screen_v2.dart` in both places that
surface tool selection:

```dart
static const _entries = <(PianoRollTool, IconData, String)>[
  (PianoRollTool.draw, Icons.edit_rounded, 'Draw'),
  (PianoRollTool.select, Icons.select_all_rounded, 'Select'),
  (PianoRollTool.scissors, Icons.content_cut_rounded, 'Split'),
  (PianoRollTool.paint, Icons.brush_rounded, 'Paint'),
  (PianoRollTool.delete, Icons.delete_outline_rounded, 'Delete'),
];
```

And in the landscape inspector:

```dart
_ToolPill(
  label: '▭ Select',
  active: tool == PianoRollTool.select,
  onTap: () => notifier.setActiveTool(PianoRollTool.select),
),
```

Rename the legacy column shortcut:

```dart
_QuickChip(
  label: 'Select column',
  icon: Icons.view_column_rounded,
  color: MuzicianTheme.sky,
  onTap: selectColumnNotes,
)
```

Use the existing icon if it reads better visually, but keep the wording
secondary and column-specific.

- [ ] **Step 5: Re-run the shell tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/models/piano_roll.dart \
  lib/features/piano_roll/piano_roll_screen_v2.dart \
  test/features/piano_roll/piano_roll_screen_v2_test.dart
git commit -m "feat(piano roll): surface explicit select tool"
```

**Acceptance criteria:**

- `Select` is visible anywhere the user changes Piano Roll tools
- the old column-selection action is clearly a shortcut, not the primary
  multi-selection feature

---

## Task 2: Define Marquee Selection Behavior With Failing Grid Tests

**Owner:** `instrument-renderer`  
**Scope:** regression suite for area-selection semantics  
**Dependencies:** Task 1

**Files:**

- Modify: `test/features/piano_roll/piano_roll_grid_test.dart`

- [ ] **Step 1: Add the failing marquee-selection tests**

Cover these exact behaviors:

- dragging a marquee in `Select` replaces the current selection
- partial overlap counts as selected
- dragging in `Select` does not move notes
- dragging on empty space in `Draw` still scrolls rather than marquee-selecting

Suggested tests:

```dart
testWidgets('select tool marquee replaces current selection with intersected notes', (tester) async {
  final noteA = PianoRollNote(
    id: 'box-a',
    midiNote: 80,
    pitchClass: 'G#',
    noteWithOctave: 'G#5',
    startTick: 0,
    durationTicks: 4,
  );
  final noteB = PianoRollNote(
    id: 'box-b',
    midiNote: 78,
    pitchClass: 'F#',
    noteWithOctave: 'F#5',
    startTick: 6,
    durationTicks: 4,
  );
  final noteC = PianoRollNote(
    id: 'box-c',
    midiNote: 70,
    pitchClass: 'A#',
    noteWithOctave: 'A#4',
    startTick: 14,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    activeTool: PianoRollTool.select,
    notes: [noteA, noteB, noteC],
    selectedNoteIds: {'box-c'},
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

  final gridFinder = find.byKey(const ValueKey('piano-roll-grid-listener'));
  final gridRect = tester.getRect(gridFinder);
  final gesture = await tester.startGesture(
    gridRect.topLeft + const Offset(44, 64),
  );
  await gesture.moveTo(gridRect.topLeft + const Offset(252, 160));
  await tester.pump();
  await gesture.up();
  await tester.pump();

  expect(container.read(pianoRollProvider).selectedNoteIds, {'box-a', 'box-b'});
});

testWidgets('select tool marquee includes notes touched only partially', (tester) async {
  final note = PianoRollNote(
    id: 'partial-a',
    midiNote: 80,
    pitchClass: 'G#',
    noteWithOctave: 'G#5',
    startTick: 0,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    activeTool: PianoRollTool.select,
    notes: [note],
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

  final gridFinder = find.byKey(const ValueKey('piano-roll-grid-listener'));
  final gridRect = tester.getRect(gridFinder);
  final gesture = await tester.startGesture(
    gridRect.topLeft + const Offset(108, 80),
  );
  await gesture.moveTo(gridRect.topLeft + const Offset(132, 96));
  await tester.pump();
  await gesture.up();
  await tester.pump();

  expect(container.read(pianoRollProvider).selectedNoteIds, {'partial-a'});
});
```

Add two more focused tests:

```dart
testWidgets('select tool drag does not move selected notes', ...)
testWidgets('draw tool empty drag does not commit marquee selection', ...)
```

- [ ] **Step 2: Run the grid test target and confirm failure**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_grid_test.dart
```

Expected: fail because `Select` has no marquee behavior yet.

- [ ] **Step 3: Commit nothing yet**

Do not commit red tests alone unless your branch policy explicitly wants that.

**Acceptance criteria:**

- the test suite clearly describes the new selection semantics before any grid
  code changes are made

---

## Task 3: Implement Marquee State, Hit Testing, And Overlay Rendering

**Owner:** `instrument-renderer`  
**Scope:** local marquee interaction state, note-rect intersection, live preview, final selection commit on pointer-up  
**Dependencies:** Task 2

**Files:**

- Modify: `lib/features/piano_roll/piano_roll_grid.dart`
- Reuse tests: `test/features/piano_roll/piano_roll_grid_test.dart`

- [ ] **Step 1: Add local marquee interaction state to the grid**

Inside `_PianoRollGridState`, introduce the smallest local state necessary:

```dart
enum _DragMode {
  none,
  moveNote,
  resizeNote,
  paintBrush,
  deleteBrush,
  marqueeSelect,
}

Offset? _marqueeStart;
Offset? _marqueeCurrent;
Rect? _marqueeRect;
Set<String> _marqueePreviewIds = const <String>{};
```

Keep this state local to the grid widget. Do not add it to `PianoRollState`.

- [ ] **Step 2: Add deterministic note-rectangle hit testing helpers**

Add private helpers near the other grid helpers:

```dart
Rect _noteRect(PianoRollNote note, PianoRollState state) {
  final rowIdx = state.pitchRangeEnd - note.midiNote;
  return Rect.fromLTWH(
    note.startTick * _cellW + 1,
    rowIdx * _rowH + 1,
    note.durationTicks * _cellW - 2,
    _rowH - 2,
  );
}

Rect _marqueeFromPoints(Offset a, Offset b) => Rect.fromPoints(a, b);

Set<String> _intersectedNoteIds(Rect marquee, PianoRollState state) => {
  for (final note in state.notes)
    if (_noteRect(note, state).overlaps(marquee)) note.id,
};
```

This codifies the locked “partial overlap counts” rule.

- [ ] **Step 3: Render live preview without committing store changes mid-drag**

Extend `_GridPainter` so it can render candidate notes like selected notes:

```dart
class _GridPainter extends CustomPainter {
  final Set<String> previewSelectedNoteIds;

  _GridPainter({
    required this.state,
    required this.previewSelectedNoteIds,
    ...
  });
}
```

When calculating note color/selection:

```dart
final effectiveSelectedIds = previewSelectedNoteIds.isNotEmpty
    ? previewSelectedNoteIds
    : state.selectedNoteIds;
```

Use the effective set only for painting. Do not mutate the store during drag.

- [ ] **Step 4: Add the marquee overlay to the existing grid Stack**

Inside the existing `Stack` in `build()`, add an `IgnorePointer` overlay after
the grid listener:

```dart
if (_marqueeRect != null)
  Positioned(
    key: const ValueKey('piano-roll-select-marquee'),
    left: _marqueeRect!.left - _hScroll.offset,
    top: _marqueeRect!.top - _vScroll.offset,
    width: _marqueeRect!.width,
    height: _marqueeRect!.height,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MuzicianTheme.sky.withValues(alpha: 0.12),
          border: Border.all(
            color: MuzicianTheme.sky.withValues(alpha: 0.85),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
  ),
```

Keep the overlay purely visual. The hit testing stays on the raw `Listener`.

- [ ] **Step 5: Commit the final selection only on pointer-up**

Add private helpers:

```dart
void _updateMarquee(Offset gridPos, PianoRollState state) {
  final rect = _marqueeFromPoints(_marqueeStart!, gridPos);
  setState(() {
    _marqueeCurrent = gridPos;
    _marqueeRect = rect;
    _marqueePreviewIds = _intersectedNoteIds(rect, state);
  });
}

void _commitMarquee(WidgetRef ref) {
  ref.read(pianoRollProvider.notifier).setSelection(_marqueePreviewIds);
  setState(() {
    _marqueeStart = null;
    _marqueeCurrent = null;
    _marqueeRect = null;
    _marqueePreviewIds = const <String>{};
  });
}
```

If `_marqueePreviewIds` is empty, `setSelection(const {})` is correct because
the locked behavior says empty marquee clears selection.

- [ ] **Step 6: Re-run the grid tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_grid_test.dart
```

Expected: the intersection/replace tests now pass, while any gesture-routing
tests that depend on `Select` mode entry may still fail until Task 4 lands.

- [ ] **Step 7: Commit**

```bash
git add lib/features/piano_roll/piano_roll_grid.dart \
  test/features/piano_roll/piano_roll_grid_test.dart
git commit -m "feat(piano roll): add marquee selection overlay"
```

**Acceptance criteria:**

- the grid can compute intersected notes from a rectangle
- live marquee preview is visible during drag
- selection is committed on pointer-up, not continuously during drag

---

## Task 4: Route Pointer Semantics Cleanly For Select Mode

**Owner:** `instrument-renderer`  
**Scope:** pointer-mode separation, no move/resize in `Select`, two-finger navigation while selecting, cursor behavior  
**Dependencies:** Task 3

**Files:**

- Modify: `lib/features/piano_roll/piano_roll_grid.dart`
- Reuse tests: `test/features/piano_roll/piano_roll_grid_test.dart`

- [ ] **Step 1: Add the remaining failing behavior tests if still missing**

If Task 2 did not already add them, add:

```dart
testWidgets('select tool drag over selected note does not move note', ...)
testWidgets('draw tool drag on empty space does not leave marquee overlay behind', ...)
```

The “does not move note” assertion should pin both `startTick` and `midiNote`:

```dart
final updated = container.read(pianoRollProvider).notes.single;
expect(updated.startTick, 4);
expect(updated.midiNote, 70);
```

- [ ] **Step 2: Route one-finger pointer-down into marquee mode only when activeTool is Select**

In `_onPointerDown` before the existing note move / scroll logic:

```dart
if (state.activeTool == PianoRollTool.select) {
  _pinching = false;
  _dragMode = _DragMode.marqueeSelect;
  _dragNoteId = null;
  _multiDragOriginals = {};
  _multiResizeOriginalDurations = {};
  _longPressTimer?.cancel();
  _marqueeStart = _localToGrid(event.localPosition);
  _marqueeCurrent = _marqueeStart;
  _marqueeRect = Rect.fromPoints(_marqueeStart!, _marqueeCurrent!);
  _marqueePreviewIds = const <String>{};
  return;
}
```

This is the key boundary that prevents `Select` from colliding with `Draw`.

- [ ] **Step 3: Route one-finger move and up for marquee instead of scroll/move**

In `_onPointerMove`:

```dart
if (_dragMode == _DragMode.marqueeSelect) {
  _updateMarquee(_localToGrid(event.localPosition), state);
  return;
}
```

In `_onPointerUp`:

```dart
if (_dragMode == _DragMode.marqueeSelect) {
  _commitMarquee(ref);
  _dragMode = _DragMode.none;
  _movedBeyondSlop = false;
  _totalPointerDelta = Offset.zero;
  return;
}
```

Do not fall through to note tap / empty-cell insertion branches.

- [ ] **Step 4: Keep Draw semantics untouched**

Re-read the existing `Draw` path and confirm these branches remain unchanged:

```dart
if (_dragMode == _DragMode.none) {
  _manualScroll(event.delta);
  return;
}

if (_dragMode == _DragMode.moveNote) { ... }
if (_dragMode == _DragMode.resizeNote) { ... }
```

No marquee code should run when `activeTool != PianoRollTool.select`.

- [ ] **Step 5: Add two-finger navigation support while Select is active**

Because one-finger drag now belongs to the marquee, add centroid-based
navigation for two-finger gestures while `Select` is active.

Minimal local state:

```dart
Offset? _lastTwoFingerCenter;
```

In the existing multi-pointer branch:

```dart
final center = Offset(
  (positions[0].dx + positions[1].dx) / 2,
  (positions[0].dy + positions[1].dy) / 2,
);
final hScale = hDist / _pinchInitHDist;
final vScale = vDist / _pinchInitVDist;
final isMostlyPan =
    (hScale - 1).abs() < 0.04 && (vScale - 1).abs() < 0.04;

if (state.activeTool == PianoRollTool.select && isMostlyPan) {
  if (_lastTwoFingerCenter != null) {
    _manualScroll(center - _lastTwoFingerCenter!);
  }
  _lastTwoFingerCenter = center;
  return;
}

_lastTwoFingerCenter = center;
```

Keep the current zoom behavior as the fallback when the gesture is not mostly
pan.

- [ ] **Step 6: Make hover / cursor state sensible for Select**

Update `_onHover`:

```dart
if (tool == PianoRollTool.select) {
  next = SystemMouseCursors.precise;
}
```

Do not show move/resize cursors in `Select` mode.

- [ ] **Step 7: Re-run the grid tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_grid_test.dart
```

Expected: green.

- [ ] **Step 8: Commit**

```bash
git add lib/features/piano_roll/piano_roll_grid.dart \
  test/features/piano_roll/piano_roll_grid_test.dart
git commit -m "feat(piano roll): route explicit select mode gestures"
```

**Acceptance criteria:**

- one-finger drag in `Select` always means marquee selection
- notes do not move or resize in `Select`
- `Draw` retains its current editing behavior
- `Select` mode still allows navigation/zoom with two fingers

---

## Task 5: Update Product Copy, Help, And Piano Roll Docs

**Owner:** general-purpose sub-agent  
**Scope:** remove outdated “no marquee” language, teach the new workflow, demote the old column shortcut  
**Dependencies:** Task 1 and Task 4

**Files:**

- Modify: `docs/piano_roll.md`
- Modify: `lib/ui/core/app_info_panel.dart`
- Possibly modify: `lib/features/piano_roll/piano_roll_screen_v2.dart`

- [ ] **Step 1: Write or update one failing expectation in the shell/help tests if needed**

If you add a persistent hint or rename copy in the visible shell, pin it in
`test/features/piano_roll/piano_roll_screen_v2_test.dart`:

```dart
expect(find.text('Select column'), findsNothing);
expect(find.bySemanticsLabel('Select column notes'), findsOneWidget);
```

Only add a test here if the user-visible shell copy changes. Doc-only changes do
not need widget assertions.

- [ ] **Step 2: Update `docs/piano_roll.md`**

Replace the old guidance:

- remove or rewrite “This iteration intentionally does not include marquee/lasso
  selection.”
- document `Select` as the primary multi-selection workflow
- reframe the old column action as `Select column`

Target wording:

```md
### Explicit selection actions

- **Select tool**: drag a box around notes to replace the current selection.
- **Double-tap a note**: add or remove that note from the current selection.
- **Select column**: shortcut that selects all notes active at the current column.
- **Edit after selection**: switch back to Draw to move/resize, or Scissors to split.
```

- [ ] **Step 3: Update the in-app help tab**

In `lib/ui/core/app_info_panel.dart`, rewrite the Piano Roll help entries so the
primary flow is explicit:

```dart
_Entry(
  icon: Icons.select_all_rounded,
  label: 'Select tool',
  desc:
      'Switch to Select, then drag a box across the grid to select any notes '
      'the box touches. Use Draw afterward to move or resize the selected group.',
  color: MuzicianTheme.sky,
),
_Entry(
  icon: Icons.view_column_outlined,
  label: 'Select column',
  desc:
      'Secondary shortcut: select all notes active at the current column tick.',
  color: MuzicianTheme.sky,
),
```

Also update any stale wording that still claims multi-selection is only
double-tap or only column-based.

- [ ] **Step 4: Re-run the narrowest affected test target**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

If no shell text changed beyond what Task 1 already covered, you may skip this
and rely on the final combined verification in Task 6.

- [ ] **Step 5: Commit**

```bash
git add docs/piano_roll.md \
  lib/ui/core/app_info_panel.dart \
  lib/features/piano_roll/piano_roll_screen_v2.dart \
  test/features/piano_roll/piano_roll_screen_v2_test.dart
git commit -m "docs(piano roll): teach area selection workflow"
```

**Acceptance criteria:**

- docs and help describe the new `Select -> Draw/Scissors` workflow
- users are no longer told that column selection is the main multi-selection
  answer

---

## Task 6: Review And Final Verification

**Owner:** primary implementer + review specialists  
**Scope:** analyze, targeted tests, compact/wide verification, focused reviews  
**Dependencies:** Tasks 1 through 5

**Files:**

- Review all touched files
- No new product code unless fixing review findings

- [ ] **Step 1: Run the full targeted test suite**

Run:

```bash
flutter test \
  test/features/piano_roll/piano_roll_grid_test.dart \
  test/features/piano_roll/piano_roll_screen_v2_test.dart
```

Expected: all green.

- [ ] **Step 2: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Review the changed files with `accessibility-ux`**

Review focus:

- compact portrait readability of the new `Select` affordance
- touch-target size for any new or relabeled tool
- clarity of the mode distinction between `Draw` and `Select`
- marquee visibility against the current glass background

If findings are actionable, fix them before the next step.

- [ ] **Step 4: Review the changed files with `code-quality`**

Review focus:

- no marquee state leaked into global store unnecessarily
- no regressions in raw pointer cleanup paths
- no dead branches left from old selection assumptions
- no stale `Multi-select` copy remaining where it would confuse users

If findings are actionable, fix them before the next step.

- [ ] **Step 5: Verify compact mobile behavior manually**

Use Simulator or `serve-sim` on an iPhone portrait viewport and check:

- switch to `Select`
- drag a marquee across a phrase
- verify partially touched notes are included
- verify the second marquee replaces the first selection
- switch back to `Draw` and move the selected group
- switch to `Scissors` and split a selected note
- use double-tap to add/remove one note from the selected group
- verify two-finger pan and pinch still let you navigate while `Select` is active

- [ ] **Step 6: Verify wide behavior manually**

Use a wide or landscape viewport and check:

- `Select` is clearly visible in the shell
- marquee drag works with mouse/trackpad
- hover cursor in `Select` is not a move/resize cursor
- the `Select column` shortcut still works as a secondary path

- [ ] **Step 7: Final commit or squash per branch policy**

If multiple task commits already exist, either keep them or create one final
integration commit only if your branch policy prefers it.

Suggested final commit if needed:

```bash
git add lib/models/piano_roll.dart \
  lib/features/piano_roll/piano_roll_grid.dart \
  lib/features/piano_roll/piano_roll_screen_v2.dart \
  docs/piano_roll.md \
  lib/ui/core/app_info_panel.dart \
  test/features/piano_roll/piano_roll_grid_test.dart \
  test/features/piano_roll/piano_roll_screen_v2_test.dart
git commit -m "feat: add piano roll area selection mode"
```

**Acceptance criteria:**

- marquee selection works on arbitrary note groups and sequences
- mobile interaction is mode-clear and not gesture-ambiguous
- existing edit flows still work once a group is selected
- docs and help match shipped behavior

---

## Spec Coverage Check

This plan covers every locked decision from
`docs/superpowers/specs/2026-05-27-piano-roll-area-selection-design.md`:

- explicit `Select` tool: Task 1
- marquee rectangle: Tasks 2 through 4
- partial overlap selection: Tasks 2 and 3
- replacement semantics: Task 2 and Task 3
- double-tap refinement preserved: Tasks 2, 4, and 5
- separate column-selection shortcut: Tasks 1 and 5
- local ephemeral marquee state: Task 3
- compact + wide verification: Task 6

No uncovered spec requirement remains.
