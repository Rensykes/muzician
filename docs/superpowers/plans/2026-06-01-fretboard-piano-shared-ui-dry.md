# Fretboard / Piano Shared UI DRY Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the duplicated UI + provider plumbing across Fretboard, Piano, and Piano Roll's scale picker into binding-parameterized shared widgets, fixing the Piano scale-drawer chip/badge gap as a side effect.

**Architecture:** Keep the two instrument stores separate. Introduce a per-instrument `binding` (provider references + an action interface) that thin generic widgets read from. Port the existing widgets to `lib/features/instrument_shared/`, delete the copies, repoint call sites. Standardize styling (scale=emerald, chord=violet) inside the shared widgets.

**Tech Stack:** Flutter, Riverpod (`Notifier` + `StateProvider`), `package:flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-01-fretboard-piano-shared-ui-dry-design.md`

---

## File Structure

**Added**
- `lib/features/instrument_shared/instrument_binding.dart` — interfaces (`ScaleActions`, `SelectionActions`) + binding classes (`ScalePickerBinding`, `InstrumentBinding`).
- `lib/features/instrument_shared/shared_scale_picker.dart` — `SharedScalePicker`.
- `lib/features/instrument_shared/shared_detection_panel.dart` — `SharedDetectionPanel`.
- `lib/features/instrument_shared/chord_picker_parts.dart` — `ChordPickerHeader`, `RootPillRow`, `QualityPillRow`, `ChordPickerSync` mixin.
- `lib/features/instrument_shared/instrument_screen.dart` — `InstrumentScreen` scaffold.

**Modified**
- `lib/store/fretboard_store.dart`, `lib/store/piano_store.dart`, `lib/store/piano_roll_store.dart` — `implements` interfaces, derived providers, binding export.
- `lib/main.dart` — both screens call `InstrumentScreen`.
- `lib/features/fretboard/chord_voicing_picker.dart`, `lib/features/piano/piano_chord_picker.dart` — adopt shared parts.
- `lib/features/fretboard/fretboard_feature.dart` — fix exports.
- `lib/features/piano_roll/piano_roll_screen_v2.dart` — repoint to `SharedScalePicker`.

**Deleted**
- `lib/features/fretboard/note_detection_panel.dart`, `lib/features/piano/piano_note_detection_panel.dart`
- `lib/features/fretboard/scale_picker.dart`, `lib/features/piano/piano_scale_picker.dart`, `lib/features/piano_roll/piano_roll_scale_picker.dart`

**Tests touched**
- `test/features/fretboard/note_detection_panel_test.dart`, `test/features/piano/piano_note_detection_panel_test.dart`, `test/features/piano_roll/piano_roll_scale_picker_test.dart` — repoint to shared widgets.
- New: `test/features/instrument_shared/shared_scale_picker_test.dart`.

## Reference facts (verified in repo)

- `ExactSelectionNote({required int midiNote, required String pitchClass})` — `lib/models/harmonic_analysis.dart:6`.
- `ChordDetectionResult({required String root, required String quality, String? bass})`, `ScaleDetectionResult({required String root, required String scaleName})` — same file.
- Shared theory in `lib/utils/note_utils.dart`: `chromaticNotes`, `enum ScaleCategory { common, modes, extended }`, `scaleGroups`, `scaleCategoryLabels`, `getScaleNotes(root, scaleName)`, `getChordNotes(root, quality)`, `detectChordResultsFromExactNotes(List<ExactSelectionNote>)`, `detectScaleResultsFromExactNotes(...)`, `detectFirstChord(notes, {qualitySymbols})`, `formatChordSymbol(ChordDetectionResult)`, `formatScaleLabel(ScaleDetectionResult)`, `formatRootChoiceLabel(String)`.
- `FretboardNotifier` (`lib/store/fretboard_store.dart`) already defines `clearSelectedNotes`, `toggleFocusedNote(String)`, `setHighlightedNotes(List<String>)`, `removeNotesByPitchClass(List<String>)`.
- `PianoNotifier` (`lib/store/piano_store.dart`) defines the same four.
- `PianoRollNotifier` (`lib/store/piano_roll_store.dart`) defines `setHighlightedNotes` + `removeNotesByPitchClass` (NOT the other two).
- Conflict pitch-class source: Fretboard/Piano = `state.selectedNotes`; Piano Roll = `state.notes.map((n) => n.pitchClass)`.

---

### Task 1: Binding interfaces + classes

**Files:**
- Create: `lib/features/instrument_shared/instrument_binding.dart`
- Test: `test/features/instrument_shared/instrument_binding_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/instrument_shared/instrument_binding_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/instrument_binding.dart';
import 'package:muzician/models/harmonic_analysis.dart';

class _FakeActions implements SelectionActions {
  final List<String> highlighted = [];
  final List<String> removed = [];
  bool cleared = false;
  String? toggled;
  @override
  void setHighlightedNotes(List<String> notes) => highlighted
    ..clear()
    ..addAll(notes);
  @override
  void removeNotesByPitchClass(List<String> notes) => removed.addAll(notes);
  @override
  void clearSelectedNotes() => cleared = true;
  @override
  void toggleFocusedNote(String note) => toggled = note;
}

void main() {
  test('InstrumentBinding exposes scale + detection surface', () {
    final selected = Provider<List<String>>((_) => const ['C', 'E', 'G']);
    final highlighted = Provider<List<String>>((_) => const <String>[]);
    final focused = Provider<Set<String>>((_) => const <String>{});
    final exact = Provider<List<ExactSelectionNote>>((_) => const []);
    final pendingScale =
        StateProvider<({String root, String scaleName})?>((_) => null);
    final activeScale =
        StateProvider<({String root, String scaleName})?>((_) => null);
    final pendingChord =
        StateProvider<({String root, String quality})?>((_) => null);
    final activeChord =
        StateProvider<({String root, String quality})?>((_) => null);
    final manualEdit = StateProvider<int>((_) => 0);
    final committed = StateProvider<bool>((_) => false);

    final actions = _FakeActions();
    final binding = InstrumentBinding(
      selectedPitchClasses: selected,
      highlightedNotes: highlighted,
      actions: (_) => actions,
      pendingScale: pendingScale,
      activeScale: activeScale,
      selectedNotes: selected,
      focusedNotes: focused,
      exactNotes: exact,
      pendingChord: pendingChord,
      activeChord: activeChord,
      manualEdit: manualEdit,
      chordCommitted: committed,
      chordQualitySymbols: const ['', 'm', '7'],
    );

    // An InstrumentBinding is usable wherever a ScalePickerBinding is expected.
    final ScalePickerBinding scaleView = binding;
    expect(scaleView.activeScale, same(activeScale));
    expect(binding.chordQualitySymbols, contains('m'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/instrument_shared/instrument_binding_test.dart`
Expected: FAIL — `instrument_binding.dart` does not exist / `InstrumentBinding` undefined.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/instrument_shared/instrument_binding.dart
/// Binding contracts that let generic instrument widgets work against any of
/// the instrument stores without merging them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';

/// Minimal mutation surface the shared scale picker needs. Satisfied by every
/// instrument notifier (Fretboard, Piano, Piano Roll).
abstract interface class ScaleActions {
  void setHighlightedNotes(List<String> notes);
  void removeNotesByPitchClass(List<String> notes);
}

/// Full selection surface for the detection panel + chord pickers.
/// Satisfied by Fretboard and Piano notifiers.
abstract interface class SelectionActions implements ScaleActions {
  void clearSelectedNotes();
  void toggleFocusedNote(String note);
}

/// Everything `SharedScalePicker` needs from an instrument.
class ScalePickerBinding {
  /// Current selected pitch classes, for out-of-key conflict detection.
  final ProviderListenable<List<String>> selectedPitchClasses;

  /// Currently highlighted scale pitch classes.
  final ProviderListenable<List<String>> highlightedNotes;

  /// Resolves the mutation surface against a ref.
  final ScaleActions Function(WidgetRef) actions;

  /// Scale hand-off providers, shared with the detection panel.
  final StateProvider<({String root, String scaleName})?> pendingScale;
  final StateProvider<({String root, String scaleName})?> activeScale;

  const ScalePickerBinding({
    required this.selectedPitchClasses,
    required this.highlightedNotes,
    required this.actions,
    required this.pendingScale,
    required this.activeScale,
  });
}

/// Adds the detection panel + chord picker surface. Fretboard + Piano only.
class InstrumentBinding extends ScalePickerBinding {
  final ProviderListenable<List<ExactSelectionNote>> exactNotes;
  final ProviderListenable<List<String>> selectedNotes;
  final ProviderListenable<Set<String>> focusedNotes;

  final StateProvider<({String root, String quality})?> pendingChord;
  final StateProvider<({String root, String quality})?> activeChord;
  final StateProvider<int> manualEdit;
  final StateProvider<bool> chordCommitted;

  /// Chord qualities this instrument's chord picker offers.
  final List<String> chordQualitySymbols;

  const InstrumentBinding({
    required super.selectedPitchClasses,
    required super.highlightedNotes,
    required SelectionActions Function(WidgetRef) actions,
    required super.pendingScale,
    required super.activeScale,
    required this.exactNotes,
    required this.selectedNotes,
    required this.focusedNotes,
    required this.pendingChord,
    required this.activeChord,
    required this.manualEdit,
    required this.chordCommitted,
    required this.chordQualitySymbols,
  })  : selectionActions = actions,
        super(actions: actions);

  /// Same callback as [actions] but typed to the wider [SelectionActions].
  final SelectionActions Function(WidgetRef) selectionActions;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/instrument_shared/instrument_binding_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/instrument_shared/instrument_binding.dart test/features/instrument_shared/instrument_binding_test.dart
git commit -m "feat(instrument-shared): add binding interfaces + classes"
```

---

### Task 2: Adopt interfaces + add derived providers + binding exports in the three stores

**Files:**
- Modify: `lib/store/fretboard_store.dart`, `lib/store/piano_store.dart`, `lib/store/piano_roll_store.dart`
- Test: `test/features/instrument_shared/store_bindings_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/instrument_shared/store_bindings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/features/instrument_shared/instrument_binding.dart';

void main() {
  test('notifiers implement the shared action interfaces', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(fretboardProvider.notifier), isA<SelectionActions>());
    expect(container.read(pianoProvider.notifier), isA<SelectionActions>());
    expect(container.read(pianoRollProvider.notifier), isA<ScaleActions>());
  });

  test('bindings expose live reads', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Default selections are empty; reads must not throw and must be typed.
    expect(container.read(fretboardBinding.selectedPitchClasses), isA<List<String>>());
    expect(container.read(pianoBinding.exactNotes), isNotNull);
    expect(container.read(pianoRollScaleBinding.highlightedNotes), isA<List<String>>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/instrument_shared/store_bindings_test.dart`
Expected: FAIL — `fretboardBinding` / `pianoBinding` / `pianoRollScaleBinding` undefined; notifiers not yet declared `implements`.

- [ ] **Step 3a: Fretboard store** — add the import, `implements`, derived providers, and binding.

In `lib/store/fretboard_store.dart`:

Add to imports:
```dart
import '../features/instrument_shared/instrument_binding.dart';
import '../models/harmonic_analysis.dart';
```

Change the class declaration:
```dart
class FretboardNotifier extends Notifier<FretboardState>
    implements SelectionActions {
```

Append before the final `final fretboardProvider = ...` line (or at end of file):
```dart
final fretboardSelectedNotesProvider = Provider<List<String>>(
  (ref) => ref.watch(fretboardProvider.select((s) => s.selectedNotes)),
);
final fretboardFocusedNotesProvider = Provider<Set<String>>(
  (ref) => ref.watch(fretboardProvider.select((s) => s.focusedNotes)),
);
final fretboardHighlightedNotesProvider = Provider<List<String>>(
  (ref) => ref.watch(fretboardProvider.select((s) => s.highlightedNotes)),
);
final fretboardExactNotesProvider = Provider<List<ExactSelectionNote>>((ref) {
  final state = ref.watch(fretboardProvider);
  final tuning = tunings[state.currentTuning]!;
  return state.selectedCells
      .map(
        (cell) => ExactSelectionNote(
          midiNote: tuning.strings[cell.stringIndex].midiNote + cell.fret,
          pitchClass: cell.noteName,
        ),
      )
      .toList();
});

final fretboardBinding = InstrumentBinding(
  selectedPitchClasses: fretboardSelectedNotesProvider,
  highlightedNotes: fretboardHighlightedNotesProvider,
  actions: (ref) => ref.read(fretboardProvider.notifier),
  pendingScale: pendingScaleProvider,
  activeScale: activeScaleProvider,
  selectedNotes: fretboardSelectedNotesProvider,
  focusedNotes: fretboardFocusedNotesProvider,
  exactNotes: fretboardExactNotesProvider,
  pendingChord: pendingChordProvider,
  activeChord: activeChordProvider,
  manualEdit: fretboardManualEditProvider,
  chordCommitted: fretboardChordCommittedProvider,
  chordQualitySymbols: const [
    '5', '', 'm', '7', 'maj7', 'm7', 'sus2', 'sus4', 'dim', 'aug',
    'm7b5', 'add9', 'maj9', '6', 'm6', 'dim7', '7sus4',
  ],
);
```

- [ ] **Step 3b: Piano store** — same pattern in `lib/store/piano_store.dart`.

Add imports:
```dart
import '../features/instrument_shared/instrument_binding.dart';
import '../models/harmonic_analysis.dart';
```

Change declaration:
```dart
class PianoNotifier extends Notifier<PianoState> implements SelectionActions {
```

Append at end of file:
```dart
final pianoSelectedNotesProvider = Provider<List<String>>(
  (ref) => ref.watch(pianoProvider.select((s) => s.selectedNotes)),
);
final pianoFocusedNotesProvider = Provider<Set<String>>(
  (ref) => ref.watch(pianoProvider.select((s) => s.focusedNotes)),
);
final pianoHighlightedNotesProvider = Provider<List<String>>(
  (ref) => ref.watch(pianoProvider.select((s) => s.highlightedNotes)),
);
final pianoExactNotesProvider = Provider<List<ExactSelectionNote>>((ref) {
  final keys = ref.watch(pianoProvider.select((s) => s.selectedKeys));
  return keys
      .map((k) => ExactSelectionNote(midiNote: k.midiNote, pitchClass: k.noteName))
      .toList();
});

final pianoBinding = InstrumentBinding(
  selectedPitchClasses: pianoSelectedNotesProvider,
  highlightedNotes: pianoHighlightedNotesProvider,
  actions: (ref) => ref.read(pianoProvider.notifier),
  pendingScale: pianoPendingScaleProvider,
  activeScale: pianoActiveScaleProvider,
  selectedNotes: pianoSelectedNotesProvider,
  focusedNotes: pianoFocusedNotesProvider,
  exactNotes: pianoExactNotesProvider,
  pendingChord: pianoPendingChordProvider,
  activeChord: pianoActiveChordProvider,
  manualEdit: pianoManualEditProvider,
  chordCommitted: pianoChordCommittedProvider,
  chordQualitySymbols: const [
    '5', '', 'm', '7', 'maj7', 'm7', 'sus2', 'sus4', 'dim', 'aug',
    'm7b5', 'add9', 'maj9', '6', 'm6', 'dim7', '7sus4',
  ],
);
```

- [ ] **Step 3c: Piano Roll store** — `lib/store/piano_roll_store.dart`.

Add imports:
```dart
import '../features/instrument_shared/instrument_binding.dart';
```

Change declaration:
```dart
class PianoRollNotifier extends Notifier<PianoRollState>
    implements ScaleActions {
```

Append at end of file:
```dart
final pianoRollSelectedPitchClassesProvider = Provider<List<String>>(
  (ref) => ref
      .watch(pianoRollProvider.select((s) => s.notes))
      .map((n) => n.pitchClass)
      .toSet()
      .toList(),
);
final pianoRollHighlightedNotesProvider = Provider<List<String>>(
  (ref) => ref.watch(pianoRollProvider.select((s) => s.highlightedNotes)),
);

final pianoRollScaleBinding = ScalePickerBinding(
  selectedPitchClasses: pianoRollSelectedPitchClassesProvider,
  highlightedNotes: pianoRollHighlightedNotesProvider,
  actions: (ref) => ref.read(pianoRollProvider.notifier),
  pendingScale: pianoRollPendingScaleProvider,
  activeScale: pianoRollActiveScaleProvider,
);
```

> NOTE: if `PianoRollState.notes` elements use a property other than `pitchClass`, adjust the `.map` accordingly — verify against `lib/models/piano_roll.dart` while implementing. The existing `piano_roll_scale_picker.dart:381-387` uses `currentNotes.map((n) => n.pitchClass)`, so `pitchClass` is correct.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/instrument_shared/store_bindings_test.dart`
Expected: PASS. Then run `flutter analyze` and confirm no new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/store/fretboard_store.dart lib/store/piano_store.dart lib/store/piano_roll_store.dart test/features/instrument_shared/store_bindings_test.dart
git commit -m "feat(stores): implement shared action interfaces + export bindings"
```

---

### Task 3: SharedScalePicker (fixes the Piano chip gap)

**Files:**
- Create: `lib/features/instrument_shared/shared_scale_picker.dart`
- Test: `test/features/instrument_shared/shared_scale_picker_test.dart`

This widget is a verbatim port of `lib/features/piano_roll/piano_roll_scale_picker.dart` (the
superset: it already has the named active-scale chip + restore-from-active + stale-guard), with
every direct store reference replaced by the binding. Use the substitution table below while
copying the body.

**Substitution table (apply to the ported body):**

| In `piano_roll_scale_picker.dart` | Replace with |
|---|---|
| `class PianoRollScalePicker extends ConsumerStatefulWidget` | `class SharedScalePicker extends ConsumerStatefulWidget` (add `final ScalePickerBinding binding;` field + `const SharedScalePicker({super.key, required this.binding});`) |
| `_PianoRollScalePickerState` | `_SharedScalePickerState` |
| `ref.watch(pianoRollProvider)` (the whole-state read at top) | remove; read only what's needed via binding (see below) |
| `state.highlightedNotes` | `ref.watch(widget.binding.highlightedNotes)` |
| `ref.watch(pianoRollPendingScaleProvider)` | `ref.watch(widget.binding.pendingScale)` |
| `ref.watch(pianoRollActiveScaleProvider)` | `ref.watch(widget.binding.activeScale)` |
| `ref.read(pianoRollActiveScaleProvider.notifier)` | `ref.read(widget.binding.activeScale.notifier)` |
| `ref.read(pianoRollPendingScaleProvider.notifier)` | `ref.read(widget.binding.pendingScale.notifier)` |
| `ref.listen(pianoRollProvider.select((s) => s.highlightedNotes), ...)` | `ref.listen(widget.binding.highlightedNotes, ...)` |
| `notifier.setHighlightedNotes(...)` and `ref.read(pianoRollProvider.notifier).setHighlightedNotes(...)` | `widget.binding.actions(ref).setHighlightedNotes(...)` |
| `ref.read(pianoRollProvider.notifier).removeNotesByPitchClass(conflicts)` | `widget.binding.actions(ref).removeNotesByPitchClass(conflicts)` |
| conflict source `ref.read(pianoRollProvider).notes.map((n) => n.pitchClass).toSet()` | `ref.read(widget.binding.selectedPitchClasses).toSet()` |
| the active-chip label expression using `scaleGroups.values.expand(...)` | `formatScaleLabel(ScaleDetectionResult(root: _selectedRoot!, scaleName: _selectedScale!))` (import `harmonic_analysis.dart` + `note_utils.dart`) |

**Visual standardization while porting:** replace the `_catColor`/`MuzicianTheme.sky` used for the
active-scale chip, root pills, and scale pills with `MuzicianTheme.emerald`. Keep the per-category
tab accent (`_catColor`) for the category tab underline only.

Required imports for the new file:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';
```

- [ ] **Step 1: Write the failing test**

```dart
// test/features/instrument_shared/shared_scale_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/shared_scale_picker.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Fretboard binding: selecting root+scale shows named chip', (tester) async {
    await _pump(tester, const SharedScalePicker(binding: fretboardBinding));
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Major').first);
    await tester.pumpAndSettle();
    // Named active chip in the header (e.g. "C major").
    expect(find.textContaining('major'), findsWidgets);
    expect(find.text('✕'), findsOneWidget);
  });

  testWidgets('Piano binding: selecting root+scale shows named chip', (tester) async {
    await _pump(tester, const SharedScalePicker(binding: pianoBinding));
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Major').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('major'), findsWidgets);
    expect(find.text('✕'), findsOneWidget);
  });
}
```

> NOTE while implementing: confirm the scale pill label text for the major scale via
> `scaleGroups[ScaleCategory.common]` in `note_utils.dart` and adjust `find.text('Major')` to the
> exact label string if different.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/instrument_shared/shared_scale_picker_test.dart`
Expected: FAIL — `shared_scale_picker.dart` does not exist.

- [ ] **Step 3: Create `shared_scale_picker.dart`** by porting per the substitution table above.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/instrument_shared/shared_scale_picker_test.dart`
Expected: PASS (both cases — this proves the Piano chip gap is fixed).

- [ ] **Step 5: Commit**

```bash
git add lib/features/instrument_shared/shared_scale_picker.dart test/features/instrument_shared/shared_scale_picker_test.dart
git commit -m "feat(instrument-shared): add SharedScalePicker with named active chip"
```

---

### Task 4: Switch all three call sites to SharedScalePicker; delete the three old pickers

**Files:**
- Modify: `lib/main.dart` (Fretboard + Piano dock Scale tabs), `lib/features/piano_roll/piano_roll_screen_v2.dart`
- Modify: `lib/features/fretboard/fretboard_feature.dart` (remove `scale_picker.dart` export)
- Modify: `test/features/piano_roll/piano_roll_scale_picker_test.dart`
- Delete: `lib/features/fretboard/scale_picker.dart`, `lib/features/piano/piano_scale_picker.dart`, `lib/features/piano_roll/piano_roll_scale_picker.dart`

- [ ] **Step 1: Repoint `lib/main.dart`.**

Add import:
```dart
import 'features/instrument_shared/shared_scale_picker.dart';
```

Fretboard Scale `DockTab` (`main.dart:434-441`) — change `child: const ScalePicker()` to:
```dart
child: const SharedScalePicker(binding: fretboardBinding),
```

Piano Scale `DockTab` (`main.dart:733-740`) — change `child: const PianoScalePicker()` to:
```dart
child: const SharedScalePicker(binding: pianoBinding),
```

Remove now-unused imports of `scale_picker.dart` / `piano_scale_picker.dart` if present
(`ScalePicker` came via `fretboard_feature.dart`; `PianoScalePicker` via its file).

- [ ] **Step 2: Repoint `piano_roll_screen_v2.dart`** (two sites: lines 115 and 228).

Add import:
```dart
import '../instrument_shared/shared_scale_picker.dart';
import '../../store/piano_roll_store.dart'; // if not already imported
```

Replace both `const PianoRollScalePicker()` occurrences with:
```dart
const SharedScalePicker(binding: pianoRollScaleBinding)
```

Remove the now-unused `piano_roll_scale_picker.dart` import.

- [ ] **Step 3: Fix `fretboard_feature.dart`** — delete the line:
```dart
export 'scale_picker.dart';
```

- [ ] **Step 4: Repoint the Piano Roll picker test.**

In `test/features/piano_roll/piano_roll_scale_picker_test.dart`, replace the import of
`piano_roll_scale_picker.dart` with:
```dart
import 'package:muzician/features/instrument_shared/shared_scale_picker.dart';
import 'package:muzician/store/piano_roll_store.dart';
```
and replace every `PianoRollScalePicker()` construction with
`SharedScalePicker(binding: pianoRollScaleBinding)`. Keep all assertions; if an assertion checks
the `sky`-colored chip, update the expected color to `emerald` per the visual-standardization
decision.

- [ ] **Step 5: Delete the three old picker files.**

```bash
git rm lib/features/fretboard/scale_picker.dart lib/features/piano/piano_scale_picker.dart lib/features/piano_roll/piano_roll_scale_picker.dart
```

- [ ] **Step 6: Run analyzer + affected tests.**

Run: `flutter analyze`
Expected: no errors (no dangling references to the deleted classes).
Run: `flutter test test/features/piano_roll/ test/features/instrument_shared/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: route all scale pickers through SharedScalePicker; delete copies"
```

---

### Task 5: SharedDetectionPanel; switch both screens; delete the two old panels

**Files:**
- Create: `lib/features/instrument_shared/shared_detection_panel.dart`
- Modify: `lib/main.dart`, `lib/features/fretboard/fretboard_feature.dart`
- Modify: `test/features/fretboard/note_detection_panel_test.dart`, `test/features/piano/piano_note_detection_panel_test.dart`
- Delete: `lib/features/fretboard/note_detection_panel.dart`, `lib/features/piano/piano_note_detection_panel.dart`

`SharedDetectionPanel` is a verbatim port of `lib/features/fretboard/note_detection_panel.dart`
(it carries the extra "No exact match" hint we want to keep), with binding substitutions.

**Substitution table:**

| In `note_detection_panel.dart` | Replace with |
|---|---|
| `class NoteDetectionPanel extends ConsumerStatefulWidget` | `class SharedDetectionPanel extends ConsumerStatefulWidget` with fields `final InstrumentBinding binding;` and existing `final VoidCallback? onChordPanelRequested;`; ctor `const SharedDetectionPanel({super.key, required this.binding, this.onChordPanelRequested});` |
| `_NoteDetectionPanelState` | `_SharedDetectionPanelState` |
| `final state = ref.watch(fretboardProvider);` + manual exact-note build from `state.selectedCells` (lines 44-54) | `final selectedNotes = ref.watch(widget.binding.selectedNotes);` `final focusedNotes = ref.watch(widget.binding.focusedNotes);` `final exactNotes = ref.watch(widget.binding.exactNotes);` then `chordResults = exactNotes.length >= 2 ? detectChordResultsFromExactNotes(exactNotes) : const [];` (same for scales) |
| `final notifier = ref.read(fretboardProvider.notifier);` | `final actions = widget.binding.selectionActions(ref);` |
| `ref.listen(fretboardProvider.select((s) => s.highlightedNotes), ...)` | `ref.listen(widget.binding.highlightedNotes, ...)` |
| `state.selectedNotes` (chips, count, hasNotes) | `selectedNotes` |
| `state.focusedNotes.contains(note)` | `focusedNotes.contains(note)` |
| `notifier.clearSelectedNotes()` | `actions.clearSelectedNotes()` |
| `notifier.toggleFocusedNote(note)` | `actions.toggleFocusedNote(note)` |
| chord chip tap: `ref.read(pendingChordProvider.notifier)` / `ref.read(activeChordProvider.notifier)` | `ref.read(widget.binding.pendingChord.notifier)` / `ref.read(widget.binding.activeChord.notifier)` |
| scale `_tryApplyScale` body: `ref.read(fretboardProvider).selectedNotes` | `ref.read(widget.binding.selectedNotes)` |
| `ref.read(fretboardProvider.notifier).setHighlightedNotes(...)` / `.removeNotesByPitchClass(...)` | `widget.binding.selectionActions(ref).setHighlightedNotes(...)` / `.removeNotesByPitchClass(...)` |
| `ref.read(pendingScaleProvider.notifier)` / `ref.read(activeScaleProvider.notifier)` | `ref.read(widget.binding.pendingScale.notifier)` / `ref.read(widget.binding.activeScale.notifier)` |

**Visual standardization while porting:** the chord chip currently uses `Color(0x1FC084FC)` /
`Color(0x66C084FC)` (purple). Replace with violet to match the dock Chord tab:
`MuzicianTheme.violet.withValues(alpha: 0.12)` (fill) and `...alpha: 0.45` (border). Scale chips
stay emerald (already are).

Required imports:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';
```

- [ ] **Step 1: Write the failing test** — new shared test plus a compile guard.

```dart
// test/features/instrument_shared/shared_detection_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/shared_detection_panel.dart';
import 'package:muzician/store/piano_store.dart';

void main() {
  testWidgets('Piano binding: empty selection renders nothing visible', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SharedDetectionPanel(binding: pianoBinding),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // No notes selected -> the panel collapses (SizedBox.shrink).
    expect(find.text('DETECTION'), findsNothing);
  });

  testWidgets('Piano binding: after selecting 2 keys, DETECTION header shows', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pianoProvider.notifier);
    // Select C4 and E4 (midi 60, 64) so detection has >= 2 notes.
    final keys = notifier.getKeys();
    final c4 = keys.firstWhere((k) => k.midiNote == 60);
    final e4 = keys.firstWhere((k) => k.midiNote == 64);
    notifier.toggleKey(c4.keyIndex, c4.midiNote, c4.noteName);
    notifier.toggleKey(e4.keyIndex, e4.midiNote, e4.noteName);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETECTION'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/instrument_shared/shared_detection_panel_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create `shared_detection_panel.dart`** via the substitution table.

- [ ] **Step 4: Repoint `lib/main.dart`.**

Add import:
```dart
import 'features/instrument_shared/shared_detection_panel.dart';
```

Fretboard detection (`main.dart:408-418`): replace `NoteDetectionPanel(key: ..., onChordPanelRequested: ...)` with:
```dart
SharedDetectionPanel(
  key: const ValueKey('fret-detect'),
  binding: fretboardBinding,
  onChordPanelRequested: () => showWidgetSheet(
    context: context,
    title: 'Chord voicings',
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: ChordVoicingPicker(),
    ),
  ),
)
```

Piano detection (`main.dart:707-717`): replace `PianoNoteDetectionPanel(...)` with:
```dart
SharedDetectionPanel(
  key: const ValueKey('piano-detect'),
  binding: pianoBinding,
  onChordPanelRequested: () => showWidgetSheet(
    context: context,
    title: 'Chords',
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: PianoChordPicker(),
    ),
  ),
)
```

- [ ] **Step 5: Fix `fretboard_feature.dart`** — delete `export 'note_detection_panel.dart';`.

- [ ] **Step 6: Repoint the two old panel tests.**

In `test/features/fretboard/note_detection_panel_test.dart`: change the import to
`shared_detection_panel.dart` + `fretboard_store.dart`, and replace every `NoteDetectionPanel(...)`
with `SharedDetectionPanel(binding: fretboardBinding, ...)`. Keep assertions; if any assert the
purple chord-chip color, update to violet.

In `test/features/piano/piano_note_detection_panel_test.dart`: same, with `pianoBinding`.

- [ ] **Step 7: Delete the two old panels.**

```bash
git rm lib/features/fretboard/note_detection_panel.dart lib/features/piano/piano_note_detection_panel.dart
```

- [ ] **Step 8: Run analyzer + tests.**

Run: `flutter analyze`
Expected: no errors.
Run: `flutter test test/features/fretboard/ test/features/piano/ test/features/instrument_shared/`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: route detection through SharedDetectionPanel; delete copies"
```

---

### Task 6: Extract chord-picker shared parts

**Files:**
- Create: `lib/features/instrument_shared/chord_picker_parts.dart`
- Modify: `lib/features/fretboard/chord_voicing_picker.dart`, `lib/features/piano/piano_chord_picker.dart`
- Test: `test/features/instrument_shared/chord_picker_parts_test.dart`

The shared parts are the header, the root/quality pill rows, and the pending/manualEdit/commit/
active-publish sync block (identical logic in both chord pickers, see
`chord_voicing_picker.dart:176-253` and `piano_chord_picker.dart:119-194`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/instrument_shared/chord_picker_parts_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/chord_picker_parts.dart';

void main() {
  testWidgets('ChordPickerHeader renders title + active badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChordPickerHeader(
            title: 'CHORD VOICINGS',
            root: 'C',
            quality: 'm7',
          ),
        ),
      ),
    );
    expect(find.text('CHORD VOICINGS'), findsOneWidget);
    // Badge shows the formatted symbol; just assert a chord glyph is present.
    expect(find.textContaining('C'), findsWidgets);
  });

  testWidgets('RootPillRow reports taps', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RootPillRow(
            selectedRoot: null,
            accent: Colors.green,
            onTap: (r) => tapped = r,
          ),
        ),
      ),
    );
    await tester.tap(find.text('C').first);
    expect(tapped, 'C');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/instrument_shared/chord_picker_parts_test.dart`
Expected: FAIL — file/classes undefined.

- [ ] **Step 3: Create `chord_picker_parts.dart`.**

```dart
// lib/features/instrument_shared/chord_picker_parts.dart
/// Shared building blocks for the Fretboard and Piano chord pickers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';

/// Header row: section title on the left, active-chord badge on the right.
class ChordPickerHeader extends StatelessWidget {
  final String title;
  final String? root;
  final String quality;
  const ChordPickerHeader({
    super.key,
    required this.title,
    required this.root,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (root != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: MuzicianTheme.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatChordSymbol(
                ChordDetectionResult(root: root!, quality: quality),
              ),
              style: const TextStyle(
                color: MuzicianTheme.violet,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// Horizontal row of the 12 chromatic root pills.
class RootPillRow extends StatelessWidget {
  final String? selectedRoot;
  final Color accent;
  final ValueChanged<String> onTap;
  const RootPillRow({
    super.key,
    required this.selectedRoot,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chromaticNotes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final root = chromaticNotes[i];
          final active = selectedRoot == root;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap(root);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: active
                    ? accent.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
              child: Text(
                formatRootChoiceLabel(root),
                style: TextStyle(
                  color: active ? accent : const Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal row of chord-quality pills.
class QualityPillRow extends StatelessWidget {
  final List<(String symbol, String label)> qualities;
  final String selectedQuality;
  final Color accent;
  final ValueChanged<String> onTap;
  const QualityPillRow({
    super.key,
    required this.qualities,
    required this.selectedQuality,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: qualities.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (symbol, label) = qualities[i];
          final active = selectedQuality == symbol;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap(symbol);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: active
                    ? accent.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.04),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? accent : const Color(0xFF475569),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Result of detecting the first chord, used by the sync helper.
typedef DetectedChord = ({String root, String quality})?;

/// Shared listener block: live-syncs root/quality from detection while not
/// committed, drops the commit on manual edit, consumes pendingChord, and
/// publishes activeChord. Call [installChordSync] from the picker's build.
mixin ChordPickerSync<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Picker supplies how it reads the first detected chord from current notes.
  DetectedChord detectFirstChordFromState();

  /// Picker mutates its own selection here.
  void applyDetectedChord(DetectedChord chord, {required bool committed});

  /// Picker's current (root, quality) for publishing to activeChord.
  ({String root, String quality})? get currentActiveChord;

  void installChordSync(InstrumentBinding binding, {required bool committed}) {
    ref.listen(binding.selectedNotes, (_, _) {
      if (committed) return;
      applyDetectedChord(detectFirstChordFromState(), committed: false);
    });
    ref.listen(binding.manualEdit, (_, _) {
      applyDetectedChord(detectFirstChordFromState(), committed: false);
      ref.read(binding.chordCommitted.notifier).state = false;
    });
    final pending = ref.watch(binding.pendingChord);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        applyDetectedChord((root: pending.root, quality: pending.quality),
            committed: true);
        ref.read(binding.chordCommitted.notifier).state = true;
        ref.read(binding.pendingChord.notifier).state = null;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = currentActiveChord;
      final cur = ref.read(binding.activeChord);
      if (cur?.root != next?.root || cur?.quality != next?.quality) {
        ref.read(binding.activeChord.notifier).state = next;
      }
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/instrument_shared/chord_picker_parts_test.dart`
Expected: PASS.

- [ ] **Step 5: Refactor `chord_voicing_picker.dart` onto the shared parts.**

- Add `import '../instrument_shared/chord_picker_parts.dart';` and `import '../instrument_shared/instrument_binding.dart';`.
- Add `with ChordPickerSync` to `_ChordVoicingPickerState` and implement the three mixin members:
  ```dart
  @override
  DetectedChord detectFirstChordFromState() =>
      detectFirstChord(ref.read(fretboardProvider).selectedNotes);
  @override
  void applyDetectedChord(DetectedChord chord, {required bool committed}) {
    setState(() {
      _voicingCommitted = committed;
      _selectedRoot = chord?.root;
      _selectedQuality = chord?.quality ?? '';
      _selectedVoicingIdx = null;
    });
  }
  @override
  ({String root, String quality})? get currentActiveChord => _selectedRoot != null
      ? (root: _selectedRoot!, quality: _selectedQuality)
      : null;
  ```
- Replace the inline `ref.listen(...selectedNotes...)`, `ref.listen(fretboardManualEditProvider...)`, the `pendingChord` watch/post-frame block, and the active-publish post-frame block (`chord_voicing_picker.dart:176-253`, EXCEPT the capo-transpose `ref.listen` at 203-213 which is Fretboard-specific and must stay) with a single call near the top of `build`:
  ```dart
  installChordSync(fretboardBinding, committed: _voicingCommitted);
  ```
- Replace the header `Padding(... Row(...))` (lines 262-304) with:
  ```dart
  Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    child: ChordPickerHeader(
      title: 'CHORD VOICINGS',
      root: chordNotes.isNotEmpty ? _selectedRoot : null,
      quality: _selectedQuality,
    ),
  ),
  ```
- Replace the root pills `SizedBox` (lines 306-355) with:
  ```dart
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: RootPillRow(
      selectedRoot: _selectedRoot,
      accent: MuzicianTheme.violet,
      onTap: (root) => setState(() {
        _selectedRoot = _selectedRoot == root ? null : root;
        _selectedVoicingIdx = null;
      }),
    ),
  ),
  ```
- Replace the quality pills `SizedBox` (lines 359-408) with:
  ```dart
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: QualityPillRow(
      qualities: _qualities,
      selectedQuality: _selectedQuality,
      accent: MuzicianTheme.violet,
      onTap: (symbol) => setState(() {
        _selectedQuality = symbol;
        _selectedVoicingIdx = null;
      }),
    ),
  ),
  ```
- Keep `_generateVoicings`, the voicing carousel, and all empty-state text unchanged.

- [ ] **Step 6: Refactor `piano_chord_picker.dart` onto the shared parts** — same pattern.

- Add the two imports.
- Add `with ChordPickerSync` and implement:
  ```dart
  @override
  DetectedChord detectFirstChordFromState() =>
      _detectFirstChordForPiano(ref.read(pianoProvider).selectedNotes);
  @override
  void applyDetectedChord(DetectedChord chord, {required bool committed}) {
    setState(() {
      _voicingCommitted = committed;
      _selectedRoot = chord?.root;
      _selectedQuality = chord?.quality ?? '';
      _selectedVoicingIdx = null;
    });
  }
  @override
  ({String root, String quality})? get currentActiveChord => _selectedRoot != null
      ? (root: _selectedRoot!, quality: _selectedQuality)
      : null;
  ```
- Replace the inline listeners + pending block + active-publish block (`piano_chord_picker.dart:119-194`) with:
  ```dart
  installChordSync(pianoBinding, committed: _voicingCommitted);
  ```
- Replace the header `Row` (lines 202-240) with `ChordPickerHeader(title: 'Chord Voicings', root: _selectedRoot, quality: _selectedQuality)`.
- Replace root pills (lines 243-291) with `RootPillRow(selectedRoot: _selectedRoot, accent: MuzicianTheme.violet, onTap: ...)` (same onTap body as Fretboard).
- Replace quality pills (lines 294-342) with `QualityPillRow(qualities: _pianoQualities, selectedQuality: _selectedQuality, accent: MuzicianTheme.violet, onTap: ...)`.
- Keep the octave selector, voicing list, and `_OctaveButton` unchanged.

> Visual note: Piano chord picker previously used `emerald` for these pills; switching the `accent`
> to `violet` is the intended standardization (chords = violet everywhere).

- [ ] **Step 7: Run analyzer + chord/picker tests.**

Run: `flutter analyze`
Expected: no errors; `_qualities` in Fretboard and `_pianoQualities` in Piano are still referenced (now passed to `QualityPillRow`).
Run: `flutter test test/features/fretboard/ test/features/piano/ test/features/instrument_shared/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(chord-pickers): share header, pill rows, and sync via chord_picker_parts"
```

---

### Task 7: InstrumentScreen scaffold; collapse the two screens in main.dart

**Files:**
- Create: `lib/features/instrument_shared/instrument_screen.dart`
- Modify: `lib/main.dart`

`InstrumentScreen` factors out the shared body of `_FretboardScreen` (`main.dart:304-463`) and
`_PianoScreen` (`main.dart:620-762`): gradient container, `SafeArea`, `CompactAppBar`, an optional
mode-segment slot, the pinned board `SizedBox`, the `Expanded` `AnimatedSwitcher` detection area
with `_InsightHint`, and the `DockedToolbar` with Scale + Chord tabs.

- [ ] **Step 1: Create `instrument_screen.dart`.**

```dart
// lib/features/instrument_shared/instrument_screen.dart
/// Shared scaffold for an instrument screen (app bar + board + detection + dock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import 'instrument_binding.dart';
import 'shared_detection_panel.dart';

class InstrumentScreen extends ConsumerWidget {
  final InstrumentBinding binding;
  final String title;
  final String? appBarChipLabel;
  final List<Widget> appBarActions;

  /// Optional mode segment shown directly under the app bar (Fretboard only).
  final Widget? modeSegment;

  /// The instrument board, pinned to [boardHeight].
  final Widget board;
  final double boardHeight;

  final String emptyTitle;
  final String emptySubtitle;

  /// Opens the chord picker sheet (used by detection + dock Chord tab).
  final VoidCallback onChordPanelRequested;

  /// Opens the scale picker sheet (used by dock Scale tab).
  final VoidCallback onScalePanelRequested;

  /// Reactive flags for the dock badges.
  final bool scaleHasValue;
  final bool chordHasValue;

  final ValueKey<String> detectionKey;

  const InstrumentScreen({
    super.key,
    required this.binding,
    required this.title,
    required this.appBarChipLabel,
    required this.appBarActions,
    required this.board,
    required this.boardHeight,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onChordPanelRequested,
    required this.onScalePanelRequested,
    required this.scaleHasValue,
    required this.chordHasValue,
    required this.detectionKey,
    this.modeSegment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNotes = ref.watch(binding.selectedNotes);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CompactAppBar(
              title: title,
              chipLabel: appBarChipLabel,
              actions: appBarActions,
            ),
            if (modeSegment != null) modeSegment!,
            SizedBox(height: boardHeight, child: board),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                reverseDuration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.08),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
                child: selectedNotes.isNotEmpty
                    ? SharedDetectionPanel(
                        key: detectionKey,
                        binding: binding,
                        onChordPanelRequested: onChordPanelRequested,
                      )
                    : InstrumentInsightHint(
                        key: ValueKey('${detectionKey.value}-empty'),
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                      ),
              ),
            ),
            DockedToolbar(
              children: [
                DockTab(
                  icon: Icons.stacked_line_chart,
                  label: 'Scale',
                  color: MuzicianTheme.emerald,
                  hasValue: scaleHasValue,
                  onTap: onScalePanelRequested,
                ),
                DockTab(
                  icon: Icons.library_music_outlined,
                  label: 'Chord',
                  color: MuzicianTheme.violet,
                  hasValue: chordHasValue,
                  onTap: onChordPanelRequested,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

> NOTE while implementing: `CompactAppBar`, `DockedToolbar`, `DockTab`, and `MuzicianTheme.gradientColors`
> are defined in `lib/main.dart` (or imported there). If they are private to `main.dart`, either
> (a) move them into a shared `lib/ui/core/` file and import from both, or (b) keep `InstrumentScreen`
> in `main.dart`. Prefer (a): create `lib/ui/core/dock.dart` exporting `CompactAppBar`, `DockedToolbar`,
> `DockTab`, `IconBtn`, `ModeSegment` and import it in both `main.dart` and `instrument_screen.dart`.
> Also move `_InsightHint` → public `InstrumentInsightHint` in `instrument_screen.dart` and delete the
> copy in `main.dart`.

- [ ] **Step 2: Move shared chrome widgets to `lib/ui/core/dock.dart`.**

Cut `CompactAppBar`, `DockedToolbar`, `DockTab`, `IconBtn`, `ModeSegment`, and the `gradientColors`
usage dependencies out of `main.dart` into `lib/ui/core/dock.dart` (make them public). Add
`import 'ui/core/dock.dart';` to `main.dart` and `import '../../ui/core/dock.dart';` to
`instrument_screen.dart`. Run `flutter analyze` to confirm references resolve.

- [ ] **Step 3: Rewrite `_FretboardScreen.build`** to return `InstrumentScreen(...)`.

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(fretboardProvider);
  final notifier = ref.read(fretboardProvider.notifier);
  final activeScale = ref.watch(activeScaleProvider);
  final activeChord = ref.watch(activeChordProvider);
  final chordCommitted = ref.watch(fretboardChordCommittedProvider);

  return InstrumentScreen(
    binding: fretboardBinding,
    title: 'Fretboard',
    appBarChipLabel: state.selectedNotes.isEmpty
        ? null
        : '${state.selectedNotes.length} note${state.selectedNotes.length == 1 ? "" : "s"}',
    appBarActions: [
      IconBtn(icon: Icons.help_outline_rounded, onTap: () => showAppInfoPanel(context, initialTab: 0)),
      IconBtn(
        icon: Icons.bookmark_border_rounded,
        onTap: () => showWidgetSheet(
          context: context,
          title: 'Saves',
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: FretboardSavePanel(),
          ),
        ),
      ),
      IconBtn(
        icon: Icons.tune_rounded,
        onTap: () => showWidgetSheet(
          context: context,
          title: 'Settings',
          child: _FretSettingsSheetContent(),
        ),
      ),
    ],
    modeSegment: ModeSegment<FretboardInputMode>(
      current: state.inputMode,
      onSelect: notifier.setInputMode,
      options: const [
        (FretboardInputMode.free, Icons.touch_app_rounded, 'Free'),
        (FretboardInputMode.chord, Icons.library_music_rounded, 'Chord'),
      ],
    ),
    board: const GlassFrame(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GuitarFretboard(hideToolbar: true, palette: FretboardPalette.wood),
    ),
    boardHeight: fretboardBoardHeight,
    emptyTitle: 'Tap the fretboard to begin',
    emptySubtitle: 'Selected notes turn into detected chords and scales here.',
    detectionKey: const ValueKey('fret-detect'),
    scaleHasValue: activeScale != null,
    chordHasValue: activeChord != null || chordCommitted,
    onScalePanelRequested: () => showWidgetSheet(
      context: context,
      title: 'Scale',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SharedScalePicker(binding: fretboardBinding),
      ),
    ),
    onChordPanelRequested: () => showWidgetSheet(
      context: context,
      title: 'Chord voicings',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: ChordVoicingPicker(),
      ),
    ),
  );
}
```

- [ ] **Step 4: Rewrite `_PianoScreen.build`** the same way.

```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(pianoProvider);
  final activeScale = ref.watch(pianoActiveScaleProvider);
  final activeChord = ref.watch(pianoActiveChordProvider);
  final chordCommitted = ref.watch(pianoChordCommittedProvider);

  return InstrumentScreen(
    binding: pianoBinding,
    title: 'Piano',
    appBarChipLabel: state.selectedNotes.isEmpty
        ? null
        : '${state.selectedNotes.length} note${state.selectedNotes.length == 1 ? "" : "s"}',
    appBarActions: [
      IconBtn(icon: Icons.help_outline_rounded, onTap: () => showAppInfoPanel(context, initialTab: 1)),
      IconBtn(
        icon: Icons.bookmark_border_rounded,
        onTap: () => showWidgetSheet(
          context: context,
          title: 'Saves',
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PianoSavePanel(),
          ),
        ),
      ),
      IconBtn(
        icon: Icons.tune_rounded,
        onTap: () => showWidgetSheet(
          context: context,
          title: 'Settings',
          child: _PianoSettingsSheetContent(),
        ),
      ),
    ],
    board: const GlassFrame(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: PianoKeyboard(hideToolbar: true),
    ),
    boardHeight: pianoKeyboardHeight,
    emptyTitle: 'Tap the keyboard to begin',
    emptySubtitle: 'Selected notes turn into detected chords and scales here.',
    detectionKey: const ValueKey('piano-detect'),
    scaleHasValue: activeScale != null,
    chordHasValue: activeChord != null || chordCommitted,
    onScalePanelRequested: () => showWidgetSheet(
      context: context,
      title: 'Scale',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SharedScalePicker(binding: pianoBinding),
      ),
    ),
    onChordPanelRequested: () => showWidgetSheet(
      context: context,
      title: 'Chords',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: PianoChordPicker(),
      ),
    ),
  );
}
```

- [ ] **Step 5: Delete the now-dead `_InsightHint` in `main.dart`** (replaced by `InstrumentInsightHint`). Remove the old `AnimatedSwitcher`/`DockedToolbar` bodies that were inlined in the two screens (now gone with the rewrites above).

- [ ] **Step 6: Run analyzer + full suite.**

Run: `flutter analyze`
Expected: no errors, no unused-import warnings (remove any leftover imports for `NoteDetectionPanel`/`PianoNoteDetectionPanel`/`ScalePicker`/`PianoScalePicker`).
Run: `flutter test`
Expected: PASS (whole suite).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(main): collapse both screens onto shared InstrumentScreen"
```

---

### Task 8: Final verification + manual smoke

- [ ] **Step 1: Full analyze + test + format.**

Run: `flutter analyze && flutter test && dart format --set-exit-if-changed lib test`
Expected: analyzer clean, all tests pass, formatter reports no changes (if it reformats, `git add -A && git commit -m "style: dart format"`).

- [ ] **Step 2: Manual smoke (simulator or device).**

Verify on both Fretboard and Piano:
1. Tap ≥2 notes → detection shows chords + scales.
2. Tap a detected **scale** chip → notes highlight, open the Scale drawer → header shows the named chip (`C major ✕`) and the dock Scale tab badge is lit. (Previously broken on Piano.)
3. Tap a detected **chord** chip → chord picker opens, header shows the violet chord badge, dock Chord tab badge lit.
4. Confirm scale chips/pills are emerald and chord chips/pills are violet on both pages.
5. Open Piano Roll, open its scale picker → still works (now `SharedScalePicker`), conflict dialog still appears for out-of-key notes.

- [ ] **Step 3: Final commit (if any format/cleanup).**

```bash
git add -A
git commit -m "chore: final cleanup after shared-UI refactor" || true
```

---

## Self-Review Notes

- **Spec coverage:** binding (Task 1–2), SharedScalePicker + Piano chip fix (Task 3–4), SharedDetectionPanel (Task 5), chord-picker partial share (Task 6), InstrumentScreen (Task 7), visual standardization (applied inside Tasks 3/5/6: scale=emerald, chord=violet), delete 5 copies (Tasks 4–5), repoint call sites incl. piano_roll_screen_v2 + feature barrel (Tasks 4–5–7), tests (each task). All spec sections mapped.
- **Type consistency:** `SelectionActions`/`ScaleActions`/`ScalePickerBinding`/`InstrumentBinding` names are stable across tasks; `installChordSync(binding, committed:)`, `detectFirstChordFromState`, `applyDetectedChord`, `currentActiveChord` are used consistently in Tasks 6.
- **Known verify-while-implementing points (flagged inline):** exact major-scale pill label string (Task 3 test), `PianoRollState.notes[].pitchClass` property name (Task 2), and whether `CompactAppBar`/`DockedToolbar`/`DockTab` are private in `main.dart` (Task 7 → extract to `lib/ui/core/dock.dart`).
