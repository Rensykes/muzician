# Pointer Button Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make right-click (and other non-primary mouse buttons) inert on the Piano Roll, Fretboard, and Writer melody canvases, and make the Piano Roll fully recover from a cancelled pointer.

**Architecture:** One shared predicate decides whether a pointer event was produced by a primary button or a device without a button mask. Each raw `Listener` canvas consults it before arming any gesture state, and the Piano Roll additionally gains an `onPointerCancel` handler that clears every in-flight gesture field.

**Tech Stack:** Flutter/Dart, Riverpod, `flutter_test` widget tests, `package:flutter/gestures.dart` pointer constants.

**Spec:** `docs/superpowers/specs/2026-11-01-pointer-button-guards-design.md`

## Global Constraints

- No new dependencies.
- Only these files change: `lib/utils/pointer_buttons.dart` (new), `lib/features/piano_roll/piano_roll_grid.dart`, `lib/features/fretboard/fretboard.dart`, `lib/features/songwriter/songwriter_melody_timeline.dart`, their mirrored tests, and the three feature docs.
- Do not add `BrowserContextMenu.disableContextMenu()` and do not touch text fields, wheel zoom, pinch zoom, long-press thresholds, or tool semantics.
- Keep `flutter_lints` clean: `dart format` on changed paths, `flutter analyze` clean, then the narrow test files.
- Conventional commits, one commit per task.

## Review Focus

- Touch and stylus events that report `buttons == 0` must keep painting and dragging (they are treated as primary).
- A cancelled pointer followed by one touch must not be read as a two-finger pinch (stale `_pointers` entry).
- A secondary button pressed during an active primary drag must not continue that drag.
- A long-press armed in scissors mode must not delete a note after its pointer is cancelled.
- A marquee interrupted mid-drag must not commit its partial preview on the next tap.

---

### Task 1: Shared primary-button predicate

**Files:**
- Create: `lib/utils/pointer_buttons.dart`
- Test: `test/utils/pointer_buttons_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `bool isPrimaryPointerButton(PointerEvent event)` in `lib/utils/pointer_buttons.dart` — true when `event.buttons == 0` or the primary button bit is set.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/pointer_buttons.dart';

PointerDownEvent _down(int buttons) => PointerDownEvent(buttons: buttons);

void main() {
  test('treats events without a button mask as primary', () {
    expect(isPrimaryPointerButton(_down(0)), isTrue);
  });

  test('accepts the primary button', () {
    expect(isPrimaryPointerButton(_down(kPrimaryButton)), isTrue);
  });

  test('rejects secondary and tertiary buttons', () {
    expect(isPrimaryPointerButton(_down(kSecondaryButton)), isFalse);
    expect(isPrimaryPointerButton(_down(kTertiaryButton)), isFalse);
  });

  test('rejects button chords without the primary button', () {
    expect(
      isPrimaryPointerButton(_down(kSecondaryButton | kTertiaryButton)),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/pointer_buttons_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'muzician' ... pointer_buttons.dart` (file does not exist).

- [ ] **Step 3: Implement the predicate**

```dart
import 'package:flutter/gestures.dart';

/// True when [event] comes from the primary mouse button, or from an input
/// device that reports no button mask (touch, some styluses).
bool isPrimaryPointerButton(PointerEvent event) =>
    event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/pointer_buttons_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
dart format lib/utils/pointer_buttons.dart test/utils/pointer_buttons_test.dart
git add lib/utils/pointer_buttons.dart test/utils/pointer_buttons_test.dart
git commit -m "feat: add primary pointer button predicate"
```

---

### Task 2: Piano Roll ignores non-primary buttons

**Files:**
- Modify: `lib/features/piano_roll/piano_roll_grid.dart` — `_onPointerDown` (`:810`), `_onPointerMove` (`:930`), `_onPointerUp` (`:1032`)
- Test: `test/features/piano_roll/piano_roll_grid_test.dart`
- Docs: `docs/piano_roll.md`

**Interfaces:**
- Consumes: `isPrimaryPointerButton` from Task 1.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/piano_roll/piano_roll_grid_test.dart` (import `package:flutter/gestures.dart` for `kSecondaryButton`):

```dart
testWidgets('secondary mouse button does not paint a note', (tester) async {
  final initial = _defaultPRState.copyWith(
    activeTool: PianoRollTool.paint,
    snapTicks: 4,
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
  final gesture = await tester.startGesture(
    tester.getCenter(gridFinder),
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pump();

  expect(
    container.read(pianoRollProvider).notes,
    isEmpty,
    reason: 'A right-click must not paint a note',
  );
});

testWidgets('secondary mouse button marquee selects nothing', (tester) async {
  const note = PianoRollNote(
    id: 'marquee-note',
    midiNote: 60,
    pitchClass: 'C',
    noteWithOctave: 'C4',
    startTick: 0,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    notes: const [note],
    activeTool: PianoRollTool.select,
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
    gridRect.topLeft + const Offset(8, 8),
    pointer: 7,
    buttons: kSecondaryButton,
  );
  await gesture.moveTo(gridRect.topLeft + const Offset(1000, 1000));
  await gesture.up();
  await tester.pump();

  expect(
    container.read(pianoRollProvider).selectedNoteIds,
    isEmpty,
    reason: 'A right-button marquee must not commit a selection',
  );
});

testWidgets('secondary button move does not extend a paint drag', (
  tester,
) async {
  final initial = _defaultPRState.copyWith(
    activeTool: PianoRollTool.paint,
    snapTicks: 4,
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
  final start = gridRect.topLeft + const Offset(20, 20);
  final end = gridRect.topLeft + const Offset(200, 200);

  final gesture = await tester.startGesture(start, pointer: 8);
  await gesture.updateWithCustomEvent(
    PointerMoveEvent(
      pointer: 8,
      position: end,
      delta: end - start,
      buttons: kSecondaryButton,
    ),
  );
  await gesture.up();
  await tester.pump();

  expect(
    container.read(pianoRollProvider).notes,
    hasLength(1),
    reason: 'A secondary-button move must not paint another cell',
  );
});
```

The note-move case is not tested directly: in `PianoRollTool.select` the grid
short-circuits to a marquee before hit-testing, so no drag moves a note, and the
move guard is covered through the paint brush instead.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart --plain-name 'secondary'`
Expected: three FAILs — the paint test finds one note, the marquee test commits
`{'marquee-note'}`, and the paint-drag test finds two notes.

- [ ] **Step 3: Implement the guards**

In `_onPointerDown`, first line of the body:

```dart
if (!isPrimaryPointerButton(event)) return;
```

In `_onPointerMove`, first two lines of the body:

```dart
if (!_pointers.containsKey(event.pointer)) return;
if (!isPrimaryPointerButton(event)) return;
```

In `_onPointerUp`, insert as the first statement of the body:

```dart
if (!_pointers.containsKey(event.pointer)) return;
```

Add `import '../utils/pointer_buttons.dart';` to the file's imports.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart --plain-name 'secondary mouse button'`
Expected: PASS, 2 tests. Then run the whole file: `flutter test test/features/piano_roll/piano_roll_grid_test.dart` — all pass, confirming touch still paints and drags.

- [ ] **Step 5: Document the behaviour**

In `docs/piano_roll.md`, add under `## Selection Model`:

```markdown
### Mouse buttons

Only the primary mouse button drives the roll. Right-click and middle-click are
ignored on web and desktop, so they never start a marquee, brush, move or
resize; the browser's own context menu is unaffected. Keyboard copy and paste
still work in text fields.
```

- [ ] **Step 6: Commit**

```bash
dart format lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart
flutter analyze
git add lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart docs/piano_roll.md
git commit -m "fix: ignore non-primary mouse buttons in piano roll"
```

---

### Task 3: Piano Roll recovers from a cancelled pointer

**Files:**
- Modify: `lib/features/piano_roll/piano_roll_grid.dart` — new `_onPointerCancel` after `_onPointerUp`, plus the grid `Listener` at `:1426`
- Test: `test/features/piano_roll/piano_roll_grid_test.dart`

**Interfaces:**
- Consumes: the `_pointers` bookkeeping established in Task 2.
- Produces: `void _onPointerCancel(PointerCancelEvent event)` — private to `_PianoRollGridState`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('cancelled pointer does not fake a second finger', (tester) async {
  const note = PianoRollNote(
    id: 'cancel-note',
    midiNote: 66,
    pitchClass: 'F#',
    noteWithOctave: 'F#4',
    startTick: 0,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    notes: const [note],
    activeTool: PianoRollTool.select,
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
  // midi 66, tick 0: row index 84 - 66 = 18, so y = 18 * 18 = 324..342.
  final notePoint = tester.getRect(gridFinder).topLeft + const Offset(56, 333);

  // Start a marquee away from the note, then lose the pointer the way a
  // browser context menu does.
  final cancelled = await tester.startGesture(
    tester.getRect(gridFinder).topLeft + const Offset(20, 20),
    pointer: 9,
  );
  await cancelled.moveBy(const Offset(160, 160));
  await tester.pump();
  await cancelled.cancel();
  await tester.pump();

  await tester.tapAt(notePoint);
  await tester.pump();

  expect(
    container.read(pianoRollProvider).selectedNoteIds,
    {'cancel-note'},
    reason: 'The tap after a cancel must behave like a first touch',
  );
});

testWidgets('cancelled long-press does not delete in scissors mode', (
  tester,
) async {
  const note = PianoRollNote(
    id: 'scissors-note',
    midiNote: 66,
    pitchClass: 'F#',
    noteWithOctave: 'F#4',
    startTick: 0,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    notes: const [note],
    activeTool: PianoRollTool.scissors,
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
  // midi 66, tick 0: row index 84 - 66 = 18, so y = 18 * 18 = 324..342.
  final notePoint = tester.getRect(gridFinder).topLeft + const Offset(56, 333);

  final gesture = await tester.startGesture(notePoint, pointer: 11);
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.cancel();
  await tester.pump(const Duration(milliseconds: 600));

  expect(
    container.read(pianoRollProvider).notes,
    hasLength(1),
    reason: 'A cancelled long-press must not delete the note',
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart --plain-name 'cancelled'`
Expected: both FAIL — the first reports an empty selection, the second finds zero notes.

- [ ] **Step 3: Implement the cancel handler**

```dart
void _onPointerCancel(PointerCancelEvent event) {
  if (!_pointers.containsKey(event.pointer)) return;
  _pointers.remove(event.pointer);
  _longPressTimer?.cancel();
  _dragMode = _DragMode.none;
  _dragNoteId = null;
  _multiDragOriginals = {};
  _multiResizeOriginalDurations = {};
  _pinching = false;
  _movedBeyondSlop = false;
  _longPressConsumed = false;
  _totalPointerDelta = Offset.zero;
  if (!mounted) return;
  setState(() {
    _marqueeStart = null;
    _marqueeCurrent = null;
    _marqueeRect = null;
    _marqueePreviewIds = const <String>{};
    _paintBrushedCells = null;
    _deleteBrushedNoteIds = null;
  });
}
```

Wire it on the grid `Listener` next to `onPointerUp`:

```dart
onPointerCancel: _onPointerCancel,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart`
Expected: PASS, whole file.

- [ ] **Step 5: Commit**

```bash
dart format lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart
git add lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart
git commit -m "fix: reset piano roll gesture state on pointer cancel"
```

---

### Task 4: Fretboard ignores non-primary buttons

**Files:**
- Modify: `lib/features/fretboard/fretboard.dart` — `Listener` at `:225`
- Test: `test/features/instrument_shared/fretboard_pointer_buttons_test.dart` (new)
- Docs: `docs/fretboard.md`

**Interfaces:**
- Consumes: `isPrimaryPointerButton` from Task 1.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: StudioTheme.data(AppThemeVariant.studio),
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('secondary mouse button does not toggle a fret cell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(fretboardProvider.notifier);
    // Empty highlights make `_guardOutOfKey` confirm immediately, so a
    // primary tap toggles the cell instead of opening the out-of-key dialog.
    notifier.setHighlightedNotes([]);
    notifier.setCapo(2);
    notifier.toggleCell(0, 2, 'F#');

    await tester.pumpWidget(
      _host(container, const GuitarFretboard(hideToolbar: true)),
    );
    await tester.pumpAndSettle();

    final paintFinder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_FretboardPainter',
    );
    // Cell (string 0, fret 2) paints at local (190, 36) with capo 2.
    final cellPoint = tester.getRect(paintFinder).topLeft +
        const Offset(190, 36);

    final gesture = await tester.startGesture(
      cellPoint,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final cells = container.read(fretboardProvider).selectedCells;
    expect(
      cells.any((cell) => cell.stringIndex == 0 && cell.fret == 2),
      isTrue,
      reason: 'A right-click must not toggle the cell off',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/instrument_shared/fretboard_pointer_buttons_test.dart`
Expected: FAIL — the cell is toggled off by the right-click.

If it passes, the click missed the cell: confirm the point with
`tester.getRect(paintFinder)` on a board rendered at `Size(1024, 768)` (the
`instrument_note_visibility_test.dart` layout, where cell (0, 2) is known to
paint at `Offset(190, 36)`) before changing any production code.

- [ ] **Step 3: Implement the guard**

Change the `Listener` in `fretboard.dart` to:

```dart
onPointerDown: (e) {
  if (!isPrimaryPointerButton(e)) return;
  _pointerDownLocal = e.localPosition;
},
```

Add `import '../../utils/pointer_buttons.dart';` to the file's imports.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/instrument_shared/fretboard_pointer_buttons_test.dart`
Expected: PASS.

- [ ] **Step 5: Document the behaviour**

In `docs/fretboard.md`, under `## Playing and settings`, add:

```markdown
Only the primary mouse button plays or selects a fret. Right-click and
middle-click are ignored on web and desktop.
```

- [ ] **Step 6: Commit**

```bash
dart format lib/features/fretboard/fretboard.dart test/features/instrument_shared/fretboard_pointer_buttons_test.dart
git add lib/features/fretboard/fretboard.dart test/features/instrument_shared/fretboard_pointer_buttons_test.dart docs/fretboard.md
git commit -m "fix: ignore non-primary mouse buttons on fretboard"
```

---

### Task 5: Writer melody timeline ignores non-primary buttons

**Files:**
- Modify: `lib/features/songwriter/songwriter_melody_timeline.dart` — `_start` (`:76`)
- Test: `test/features/songwriter/songwriter_pattern_lane_test.dart`
- Docs: `docs/songwriter.md`

**Interfaces:**
- Consumes: `isPrimaryPointerButton` from Task 1.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Add to `test/features/songwriter/songwriter_pattern_lane_test.dart` (import `package:flutter/gestures.dart`):

```dart
testWidgets('secondary mouse button does not resize a melody block', (
  tester,
) async {
  final f = await _timelineFixture(tester, bars: 8, span: 2);
  final handle = find.byKey(Key('melodyResize_${f.blockId}_0'));
  await tester.ensureVisible(handle);
  await tester.pumpAndSettle();

  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    buttons: kSecondaryButton,
  );
  await gesture.moveBy(const Offset(-140, 0));
  await gesture.up();
  await tester.pumpAndSettle();

  final block = f.container
      .read(songwriterProvider)
      .sections
      .single
      .lanes
      .singleWhere((lane) => lane.id == f.laneId)
      .blocks
      .single;
  expect(
    block.spanBars,
    2,
    reason: 'A right-button drag must not resize the block',
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_pattern_lane_test.dart --plain-name 'secondary mouse button does not resize'`
Expected: FAIL — `spanBars` shrinks to 1. If it passes, the drag did not reach the handle: widen the drag to `Offset(-200, 0)` and re-run before changing any production code.

- [ ] **Step 3: Implement the guard**

Replace the existing first line of `_start` with these two lines:

```dart
if (!mounted || _dragPointer != null) return;
if (!isPrimaryPointerButton(event)) return;
```

Add `import '../../utils/pointer_buttons.dart';` to the file's imports.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/songwriter/songwriter_pattern_lane_test.dart`
Expected: PASS, whole file.

- [ ] **Step 5: Document the behaviour**

In `docs/songwriter.md`, under `## Studio workspace`, add:

```markdown
Only the primary mouse button drags or resizes a melody block. Right-click and
middle-click are ignored on web and desktop.
```

- [ ] **Step 6: Final verification**

Run:

```bash
dart format lib/utils/pointer_buttons.dart lib/features/piano_roll/piano_roll_grid.dart lib/features/fretboard/fretboard.dart lib/features/songwriter/songwriter_melody_timeline.dart test/utils/pointer_buttons_test.dart test/features/piano_roll/piano_roll_grid_test.dart test/features/instrument_shared/fretboard_pointer_buttons_test.dart test/features/songwriter/songwriter_pattern_lane_test.dart
flutter analyze
flutter test test/utils/pointer_buttons_test.dart test/features/piano_roll/piano_roll_grid_test.dart test/features/instrument_shared/fretboard_pointer_buttons_test.dart test/features/songwriter/songwriter_pattern_lane_test.dart
```

Expected: format makes no changes, analyze reports no issues, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_melody_timeline.dart test/features/songwriter/songwriter_pattern_lane_test.dart docs/songwriter.md
git commit -m "fix: ignore non-primary mouse buttons in writer melody timeline"
```
