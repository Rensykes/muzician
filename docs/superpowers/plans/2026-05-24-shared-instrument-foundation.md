# Shared Instrument Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the shared Fretboard and Piano harmonic-analysis foundation so detection is exact-note-aware, scale detection matches the full picker catalog, harmonic labels use shared contextual spelling, and the new behavior is protected by regression tests.

**Architecture:** Add shared harmonic-analysis value objects in `lib/models/`, extend `lib/utils/note_utils.dart` with exact-note-aware detection and formatting helpers while preserving compatibility wrappers, then wire both instrument detection panels and pickers to the new typed results. Keep internal provider payloads canonical and save-compatible.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, shared immutable models in `lib/models/`, pure Dart music helpers in `lib/utils/note_utils.dart`, `flutter_test`

---

## File Structure

### Create

- `lib/models/harmonic_analysis.dart`
  Shared exact-note and typed detection result models used by theory and UI.
- `test/utils/note_utils_test.dart`
  Unit tests for exact-note-aware detection, ranking, spelling, and parity.
- `test/features/fretboard/note_detection_panel_test.dart`
  Widget tests for fretboard detection output and pending-provider payloads.
- `test/features/piano/piano_note_detection_panel_test.dart`
  Widget tests for piano detection output and pending-provider payloads.

### Modify

- `lib/utils/note_utils.dart`
  Add shared exact-note-aware detection APIs, result ordering, and formatting helpers while keeping current wrappers intact.
- `lib/features/fretboard/note_detection_panel.dart`
  Use typed exact-note results instead of string-only parsing.
- `lib/features/piano/piano_note_detection_panel.dart`
  Use typed exact-note results instead of string-only parsing.
- `lib/features/fretboard/chord_voicing_picker.dart`
  Use shared root-label and chord-symbol formatting helpers on tool surfaces.
- `lib/features/piano/piano_chord_picker.dart`
  Use shared root-label and chord-symbol formatting helpers on tool surfaces.
- `lib/features/fretboard/scale_picker.dart`
  Use shared root-label and scale-label formatting helpers on tool surfaces.
- `lib/features/piano/piano_scale_picker.dart`
  Use shared root-label and scale-label formatting helpers on tool surfaces.
- `docs/fretboard.md`
  Document richer shared detection output where behavior changed.
- `docs/piano.md`
  Document richer shared detection output where behavior changed.
- `lib/ui/core/app_info_panel.dart`
  Update the user-facing help copy that mentions harmonic labels if implementation changes the visible wording.

## Task 1: Add Shared Harmonic Analysis Models And Failing Theory Tests

**Primary specialist:** `music-theory`

**Files:**
- Create: `lib/models/harmonic_analysis.dart`
- Create: `test/utils/note_utils_test.dart`
- Modify: `lib/utils/note_utils.dart`

- [ ] **Step 1: Write the failing theory tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmonic_analysis.dart';
import 'package:muzician/utils/note_utils.dart';

void main() {
  group('exact-note chord detection', () {
    test('reports slash chord when bass differs from root', () {
      final results = detectChordResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 52, pitchClass: 'E'),
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 67, pitchClass: 'G'),
      ]);

      expect(results.first.root, 'C');
      expect(results.first.quality, '');
      expect(results.first.bass, 'E');
      expect(formatChordSymbol(results.first), 'C/E');
    });
  });

  group('scale parity', () {
    test('covers the full picker catalog through shared scale intervals', () {
      final results = detectScaleResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 62, pitchClass: 'D'),
        const ExactSelectionNote(midiNote: 64, pitchClass: 'E'),
        const ExactSelectionNote(midiNote: 66, pitchClass: 'F#'),
        const ExactSelectionNote(midiNote: 67, pitchClass: 'G'),
        const ExactSelectionNote(midiNote: 69, pitchClass: 'A'),
        const ExactSelectionNote(midiNote: 71, pitchClass: 'B'),
      ]);

      expect(results.any((result) => result.scaleName == 'lydian'), isTrue);
    });
  });

  group('contextual spelling', () {
    test('formats common flat harmonic labels musically', () {
      const chord = ChordDetectionResult(root: 'A#', quality: 'maj7', bass: 'D');
      const scale = ScaleDetectionResult(root: 'D#', scaleName: 'dorian');

      expect(formatChordSymbol(chord), 'Bbmaj7/D');
      expect(formatScaleLabel(scale), 'Eb dorian');
      expect(formatRootChoiceLabel('C#'), 'Db');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/utils/note_utils_test.dart`

Expected: FAIL because `harmonic_analysis.dart` and the new exact-note-aware note-utils APIs do not exist yet.

- [ ] **Step 3: Add the shared value objects**

```dart
// lib/models/harmonic_analysis.dart
enum NoteDisplayStyle { canonicalSharp, contextual }

class ExactSelectionNote {
  final int midiNote;
  final String pitchClass;

  const ExactSelectionNote({
    required this.midiNote,
    required this.pitchClass,
  });
}

class ChordDetectionResult {
  final String root;
  final String quality;
  final String? bass;

  const ChordDetectionResult({
    required this.root,
    required this.quality,
    this.bass,
  });
}

class ScaleDetectionResult {
  final String root;
  final String scaleName;

  const ScaleDetectionResult({
    required this.root,
    required this.scaleName,
  });
}
```

- [ ] **Step 4: Export or import the model where note-utils can use it**

```dart
// lib/utils/note_utils.dart
import '../models/harmonic_analysis.dart';
```

- [ ] **Step 5: Run the test to confirm the failure narrows to missing implementations**

Run: `flutter test test/utils/note_utils_test.dart`

Expected: FAIL with undefined method errors for the new note-utils helpers, which confirms the models are wired and the next task is the shared implementation.

- [ ] **Step 6: Commit**

```bash
git add lib/models/harmonic_analysis.dart test/utils/note_utils_test.dart lib/utils/note_utils.dart
git commit -m "test: scaffold shared harmonic analysis models"
```

## Task 2: Implement Exact-note Detection, Parity, And Shared Formatting In `note_utils.dart`

**Primary specialist:** `music-theory`

**Files:**
- Modify: `lib/utils/note_utils.dart`
- Test: `test/utils/note_utils_test.dart`

- [ ] **Step 1: Add the exact-note-aware detection and formatting helpers**

```dart
List<ChordDetectionResult> detectChordResultsFromExactNotes(
  List<ExactSelectionNote> notes, {
  List<String>? qualitySymbols,
}) {
  if (notes.length < 2) return const [];

  final sorted = [...notes]..sort((a, b) => a.midiNote.compareTo(b.midiNote));
  final pitchClasses = sorted.map((note) => note.pitchClass).toSet();
  final bass = sorted.first.pitchClass;
  final symbols = qualitySymbols ?? chordIntervals.keys.toList();
  final results = <ChordDetectionResult>[];

  for (final root in chromaticNotes) {
    final rootIndex = noteToPC[root]!;
    for (final quality in symbols) {
      final intervals = chordIntervals[quality];
      if (intervals == null) continue;
      final tones =
          intervals.map((interval) => chromaticNotes[(rootIndex + interval) % 12]).toSet();
      if (tones.length != pitchClasses.length) continue;
      if (!pitchClasses.every(tones.contains)) continue;
      results.add(
        ChordDetectionResult(
          root: root,
          quality: quality,
          bass: bass == root ? null : bass,
        ),
      );
    }
  }

  results.sort(_compareChordResults);
  return results;
}

List<ScaleDetectionResult> detectScaleResultsFromExactNotes(
  List<ExactSelectionNote> notes,
) {
  if (notes.length < 2) return const [];
  final pitchClasses = notes.map((note) => note.pitchClass).toSet();
  final results = <ScaleDetectionResult>[];

  for (final root in chromaticNotes) {
    for (final scaleName in scaleIntervals.keys) {
      final scaleTones = getScaleNotes(root, scaleName).toSet();
      if (pitchClasses.every(scaleTones.contains)) {
        results.add(ScaleDetectionResult(root: root, scaleName: scaleName));
      }
    }
  }

  results.sort((a, b) => _compareScaleResults(a, b, pitchClasses.length));
  return results;
}

String formatRootChoiceLabel(String canonicalRoot) => switch (canonicalRoot) {
  'A#' => 'Bb',
  'C#' => 'Db',
  'D#' => 'Eb',
  'G#' => 'Ab',
  _ => canonicalRoot,
};

String formatChordSymbol(ChordDetectionResult result) {
  final root = formatRootChoiceLabel(result.root);
  final bass = result.bass == null ? null : formatRootChoiceLabel(result.bass!);
  return bass == null ? '$root${result.quality}' : '$root${result.quality}/$bass';
}

String formatScaleLabel(ScaleDetectionResult result) =>
    '${formatRootChoiceLabel(result.root)} ${result.scaleName}';
```

- [ ] **Step 2: Add stable ranking helpers**

```dart
int _compareChordResults(ChordDetectionResult a, ChordDetectionResult b) {
  final aSlash = a.bass == null ? 0 : 1;
  final bSlash = b.bass == null ? 0 : 1;
  if (aSlash != bSlash) return aSlash.compareTo(bSlash);
  if (a.root != b.root) return chromaticNotes.indexOf(a.root).compareTo(chromaticNotes.indexOf(b.root));
  return a.quality.compareTo(b.quality);
}

int _compareScaleResults(
  ScaleDetectionResult a,
  ScaleDetectionResult b,
  int selectedPitchClassCount,
) {
  final aExtra = scaleIntervals[a.scaleName]!.length - selectedPitchClassCount;
  final bExtra = scaleIntervals[b.scaleName]!.length - selectedPitchClassCount;
  if (aExtra != bExtra) return aExtra.compareTo(bExtra);

  final aCategory = scaleGroups.entries.firstWhere((entry) => entry.value.any((scale) => scale.$1 == a.scaleName)).key;
  final bCategory = scaleGroups.entries.firstWhere((entry) => entry.value.any((scale) => scale.$1 == b.scaleName)).key;
  if (aCategory != bCategory) return aCategory.index.compareTo(bCategory.index);

  if (a.root != b.root) return chromaticNotes.indexOf(a.root).compareTo(chromaticNotes.indexOf(b.root));
  return a.scaleName.compareTo(b.scaleName);
}
```

- [ ] **Step 3: Preserve current wrappers for backward compatibility**

```dart
List<ChordDetectionResult> _detectChordResultsFromPitchClasses(
  Set<String> pitchClasses, {
  List<String>? qualitySymbols,
}) {
  final symbols = qualitySymbols ?? chordIntervals.keys.toList();
  final results = <ChordDetectionResult>[];

  for (final root in chromaticNotes) {
    final rootIndex = noteToPC[root]!;
    for (final quality in symbols) {
      final intervals = chordIntervals[quality];
      if (intervals == null) continue;
      final chordTones =
          intervals.map((interval) => chromaticNotes[(rootIndex + interval) % 12]).toSet();
      if (chordTones.length != pitchClasses.length) continue;
      if (!pitchClasses.every(chordTones.contains)) continue;
      results.add(ChordDetectionResult(root: root, quality: quality));
    }
  }

  results.sort(_compareChordResults);
  return results;
}

({String root, String quality})? detectFirstChord(
  List<String> notes, {
  List<String>? qualitySymbols,
}) {
  final results = _detectChordResultsFromPitchClasses(
    notes.toSet(),
    qualitySymbols: qualitySymbols,
  );
  final first = results.isEmpty ? null : results.first;
  return first == null ? null : (root: first.root, quality: first.quality);
}

({List<String> chords, List<String> scales}) detectChordsAndScales(
  List<String> notes,
) {
  final pitchClasses = notes.toSet();
  final chordResults = _detectChordResultsFromPitchClasses(pitchClasses);
  final scaleResults = detectScaleResultsFromExactNotes([
    for (final note in pitchClasses)
      ExactSelectionNote(midiNote: noteToPC[note]!, pitchClass: note),
  ]);
  return (
    chords: chordResults
        .take(8)
        .map((result) => '${result.root}${result.quality}')
        .toList(),
    scales: scaleResults
        .take(8)
        .map((result) => '${result.root} ${result.scaleName}')
        .toList(),
  );
}
```

- [ ] **Step 4: Run the theory tests**

Run: `flutter test test/utils/note_utils_test.dart`

Expected: PASS with exact-note slash-chord detection, shared scale parity, and contextual flat-label tests all green.

- [ ] **Step 5: Add one compatibility assertion before leaving the theory layer**

```dart
test('compatibility wrapper still returns canonical root and quality', () {
  final detected = detectFirstChord(['C', 'E', 'G']);
  expect(detected, isNotNull);
  expect(detected!.root, 'C');
  expect(detected.quality, '');
});
```

- [ ] **Step 6: Rerun the theory tests**

Run: `flutter test test/utils/note_utils_test.dart`

Expected: PASS with the compatibility test included.

- [ ] **Step 7: Commit**

```bash
git add lib/utils/note_utils.dart test/utils/note_utils_test.dart
git commit -m "feat: add shared exact-note harmonic detection"
```

## Task 3: Wire Fretboard Detection And Picker Surfaces To The Shared Result Objects

**Primary specialist:** `instrument-renderer`

**Secondary specialist:** `state-architect`

**Files:**
- Modify: `lib/features/fretboard/note_detection_panel.dart`
- Modify: `lib/features/fretboard/chord_voicing_picker.dart`
- Modify: `lib/features/fretboard/scale_picker.dart`
- Test: `test/features/fretboard/note_detection_panel_test.dart`

- [ ] **Step 1: Write the failing fretboard widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/note_detection_panel.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/fretboard_store.dart';

class FakeFretboardNotifier extends FretboardNotifier {
  FakeFretboardNotifier(this._initial);

  final FretboardState _initial;

  @override
  FretboardState build() => _initial;
}

void main() {
  testWidgets('shows slash chord label but writes canonical pending chord', (tester) async {
    final container = ProviderContainer(
      overrides: [
        fretboardProvider.overrideWith(
          () => FakeFretboardNotifier(
            const FretboardState(
              currentTuning: TuningName.standard,
              numFrets: 12,
              capo: 0,
              highlightedNotes: [],
              selectedNotes: ['C', 'E', 'G'],
              selectedCells: [
                FretCoordinate(stringIndex: 5, fret: 12, noteName: 'E'),
                FretCoordinate(stringIndex: 4, fret: 10, noteName: 'C'),
                FretCoordinate(stringIndex: 3, fret: 12, noteName: 'G'),
              ],
              viewMode: FretboardViewMode.exact,
              inputMode: FretboardInputMode.free,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: NoteDetectionPanel())),
      ),
    );

    expect(find.text('C/E'), findsOneWidget);
    await tester.tap(find.text('C/E'));
    await tester.pump();
    expect(container.read(pendingChordProvider), (root: 'C', quality: ''));
  });
}
```

- [ ] **Step 2: Run the fretboard widget test to confirm the current UI fails it**

Run: `flutter test test/features/fretboard/note_detection_panel_test.dart`

Expected: FAIL because the current panel only renders string labels from `detectChordsAndScales` and does not build exact-note-aware fretboard results.

- [ ] **Step 3: Derive exact notes in the detection panel and stop parsing display strings**

```dart
final tuning = tunings[state.currentTuning]!;
final exactNotes = state.selectedCells.map((cell) {
  final openMidi = tuning.strings[cell.stringIndex].midiNote;
  return ExactSelectionNote(
    midiNote: openMidi + cell.fret,
    pitchClass: cell.noteName,
  );
}).toList();

final chordResults = detectChordResultsFromExactNotes(exactNotes);
final scaleResults = detectScaleResultsFromExactNotes(exactNotes);
```

```dart
onTap: () {
  HapticFeedback.lightImpact();
  ref.read(pendingChordProvider.notifier).state = (
    root: result.root,
    quality: result.quality,
  );
  widget.onChordPanelRequested?.call();
}
```

- [ ] **Step 4: Reuse shared formatting on the chip labels and picker badges**

```dart
// note_detection_panel.dart
Text(formatChordSymbol(result))
Text(formatScaleLabel(result))

// chord_voicing_picker.dart
final chordBadge = selectedResult == null ? null : formatChordSymbol(selectedResult);
final rootLabel = formatRootChoiceLabel(root);

// scale_picker.dart
final rootLabel = formatRootChoiceLabel(note);
final activeScaleLabel = _selectedRoot == null || _selectedScale == null
    ? null
    : '${formatRootChoiceLabel(_selectedRoot!)} ${_selectedScale!}';
```

- [ ] **Step 5: Run the fretboard widget test**

Run: `flutter test test/features/fretboard/note_detection_panel_test.dart`

Expected: PASS, with the visible label rendered as `C/E` while the provider payload stays canonical.

- [ ] **Step 6: Commit**

```bash
git add lib/features/fretboard/note_detection_panel.dart lib/features/fretboard/chord_voicing_picker.dart lib/features/fretboard/scale_picker.dart test/features/fretboard/note_detection_panel_test.dart
git commit -m "feat: wire fretboard to shared harmonic result objects"
```

## Task 4: Wire Piano Detection And Picker Surfaces To The Shared Result Objects

**Primary specialist:** `instrument-renderer`

**Secondary specialist:** `state-architect`

**Files:**
- Modify: `lib/features/piano/piano_note_detection_panel.dart`
- Modify: `lib/features/piano/piano_chord_picker.dart`
- Modify: `lib/features/piano/piano_scale_picker.dart`
- Test: `test/features/piano/piano_note_detection_panel_test.dart`

- [ ] **Step 1: Write the failing piano widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano/piano_note_detection_panel.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/store/piano_store.dart';

class FakePianoNotifier extends PianoNotifier {
  FakePianoNotifier(this._initial);

  final PianoState _initial;

  @override
  PianoState build() => _initial;
}

void main() {
  testWidgets('shows contextual flat label for a detected scale', (tester) async {
    final container = ProviderContainer(
      overrides: [
        pianoProvider.overrideWith(
          () => FakePianoNotifier(
            const PianoState(
              currentRange: PianoRangeName.key61,
              highlightedNotes: [],
              selectedNotes: ['D#', 'F', 'F#', 'G#', 'A#', 'C', 'C#'],
              selectedKeys: [
                PianoCoordinate(keyIndex: 0, midiNote: 51, noteName: 'D#'),
                PianoCoordinate(keyIndex: 1, midiNote: 53, noteName: 'F'),
                PianoCoordinate(keyIndex: 2, midiNote: 54, noteName: 'F#'),
                PianoCoordinate(keyIndex: 3, midiNote: 56, noteName: 'G#'),
                PianoCoordinate(keyIndex: 4, midiNote: 58, noteName: 'A#'),
                PianoCoordinate(keyIndex: 5, midiNote: 60, noteName: 'C'),
                PianoCoordinate(keyIndex: 6, midiNote: 61, noteName: 'C#'),
              ],
              viewMode: PianoViewMode.exact,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PianoNoteDetectionPanel())),
      ),
    );

    expect(find.text('Eb dorian'), findsOneWidget);
    await tester.tap(find.text('Eb dorian'));
    await tester.pump();
    expect(
      container.read(pianoPendingScaleProvider),
      (root: 'D#', scaleName: 'dorian'),
    );
  });
}
```

- [ ] **Step 2: Run the piano widget test to confirm it fails**

Run: `flutter test test/features/piano/piano_note_detection_panel_test.dart`

Expected: FAIL because the current panel still relies on string-only display output and does not apply the shared formatter.

- [ ] **Step 3: Build exact notes directly from `selectedKeys`**

```dart
final exactNotes = state.selectedKeys.map((key) {
  return ExactSelectionNote(
    midiNote: key.midiNote,
    pitchClass: key.noteName,
  );
}).toList();

final chordResults = detectChordResultsFromExactNotes(
  exactNotes,
  qualitySymbols: _pianoQualitySymbols,
);
final scaleResults = detectScaleResultsFromExactNotes(exactNotes);
```

- [ ] **Step 4: Replace string parsing with typed-result routing**

```dart
onTap: () {
  HapticFeedback.lightImpact();
  ref.read(pianoPendingChordProvider.notifier).state = (
    root: result.root,
    quality: result.quality,
  );
  widget.onChordPanelRequested?.call();
}
```

```dart
Text(formatChordSymbol(result))
Text(formatScaleLabel(result))
Text(formatRootChoiceLabel(root))
```

- [ ] **Step 5: Run the piano widget test**

Run: `flutter test test/features/piano/piano_note_detection_panel_test.dart`

Expected: PASS with shared contextual spelling visible on the detection chip.

- [ ] **Step 6: Commit**

```bash
git add lib/features/piano/piano_note_detection_panel.dart lib/features/piano/piano_chord_picker.dart lib/features/piano/piano_scale_picker.dart test/features/piano/piano_note_detection_panel_test.dart
git commit -m "feat: wire piano to shared harmonic result objects"
```

## Task 5: Add Cross-instrument Regression Coverage And Update Product Docs

**Primary specialist:** `code-quality`

**Files:**
- Modify: `docs/fretboard.md`
- Modify: `docs/piano.md`
- Modify: `lib/ui/core/app_info_panel.dart`
- Test: `test/utils/note_utils_test.dart`
- Test: `test/features/fretboard/note_detection_panel_test.dart`
- Test: `test/features/piano/piano_note_detection_panel_test.dart`

- [ ] **Step 1: Update the docs to describe the new shared behavior**

```md
Shared detection now uses exact selected notes instead of pitch classes alone.
This means inversion-aware chord chips such as `C/E` and musically friendlier
flat labels such as `Bbmaj7` or `Eb dorian` can appear on both Fretboard and
Piano tool surfaces.
```

- [ ] **Step 2: Update help copy where harmonic labels changed visibly**

```dart
_Entry(
  icon: Icons.search,
  label: 'Detection',
  desc: 'Detection now uses the exact selected notes, so inversions such as C/E and friendlier spellings such as Bb or Eb can appear on the result chips.',
  color: MuzicianTheme.orange,
),
```

- [ ] **Step 3: Run the focused test suite**

Run:

```bash
flutter test test/utils/note_utils_test.dart
flutter test test/features/fretboard/note_detection_panel_test.dart
flutter test test/features/piano/piano_note_detection_panel_test.dart
```

Expected: PASS for all three test targets.

- [ ] **Step 4: Run format and analyzer**

Run:

```bash
dart format lib/models/harmonic_analysis.dart lib/utils/note_utils.dart lib/features/fretboard/note_detection_panel.dart lib/features/fretboard/chord_voicing_picker.dart lib/features/fretboard/scale_picker.dart lib/features/piano/piano_note_detection_panel.dart lib/features/piano/piano_chord_picker.dart lib/features/piano/piano_scale_picker.dart test/utils/note_utils_test.dart test/features/fretboard/note_detection_panel_test.dart test/features/piano/piano_note_detection_panel_test.dart docs/fretboard.md docs/piano.md lib/ui/core/app_info_panel.dart
flutter analyze
```

Expected: formatter makes no semantic changes; analyzer completes without new errors.

- [ ] **Step 5: Commit**

```bash
git add docs/fretboard.md docs/piano.md lib/ui/core/app_info_panel.dart test/utils/note_utils_test.dart test/features/fretboard/note_detection_panel_test.dart test/features/piano/piano_note_detection_panel_test.dart lib/models/harmonic_analysis.dart lib/utils/note_utils.dart lib/features/fretboard/note_detection_panel.dart lib/features/fretboard/chord_voicing_picker.dart lib/features/fretboard/scale_picker.dart lib/features/piano/piano_note_detection_panel.dart lib/features/piano/piano_chord_picker.dart lib/features/piano/piano_scale_picker.dart
git commit -m "test: cover shared fretboard and piano harmonic foundation"
```

## Final Verification Checklist

- [ ] Confirm the shared typed detection API is the only new source of truth for harmonic result formatting.
- [ ] Confirm both instruments still write canonical values into their pending chord and pending scale providers.
- [ ] Confirm shared scale detection uses `scaleIntervals` instead of a reduced duplicate list.
- [ ] Confirm no save-format migration was introduced.
- [ ] Confirm the focused test suite passes.
- [ ] Confirm `flutter analyze` passes.

## Execution Notes For The Orchestrator

- Run Task 1 and Task 2 before touching either instrument UI.
- Do not allow either instrument task to re-introduce local parsing of display strings.
- Prefer sharing helpers in `note_utils.dart` over adding instrument-specific formatting functions.
- Preserve unrelated worktree changes.
- If implementation reveals that selected-note chips can be re-spelled safely with no ambiguity, that is acceptable within Task 3 or Task 4. If not, keep that behavior canonical and do not expand scope.
