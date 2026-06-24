# Drum User Loops via Save System (Phase 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users save a drum pattern as a reusable loop in the existing save system and load any saved loop back into the pattern they are editing — so custom grooves persist and are reusable across projects.

**Architecture:** A new `DrumLoopSnapshot` (`type: 'drum_loop'`) wraps a `DrumPattern` and plugs into the existing `InstrumentSnapshot` dispatch — no import cycle (`save_system.dart` already imports `song_project.dart`). A thin `DrumLoopSavePanel` mirrors `SongwriterSavePanel`: it wraps the shared `SaveBrowserPanel` filtered to `'drum_loop'`, capturing the current pattern on save and applying a loaded loop on load. The editor exposes a "My Loops" button (gated by the existing `enableLibrary` flag, so the Song feature is unaffected). Loading a loop overwrites the editable pattern in place (same id), exactly like applying a preset in Phase 3.

**Tech Stack:** Dart, Flutter, Riverpod, `flutter_test`. No new packages.

**Spec:** `docs/superpowers/specs/2026-06-23-songwriter-drum-loops-design.md` (Component 3, save half).

**Depends on:** Phases 1–3 already on this branch (the `enableLibrary` flag and the editor's apply-in-place pattern come from Phase 3).

**Deviation from spec:** loading a saved loop applies it in place (same pattern id), matching the Phase 3 preset flow, rather than inserting a brand-new pattern via `addDrumPatternFrom`. This keeps one coherent "apply into the pattern you're editing" model. `addDrumPatternFrom` is therefore not built in this phase.

---

## File Structure

**Created:**
- `lib/features/song/drum_loop_save_panel.dart` — `DrumLoopSavePanel` + `showDrumLoopLibrarySheet`.
- `test/models/drum_loop_snapshot_test.dart` — snapshot round-trip + dispatch tests.
- `test/features/song/drum_loop_save_panel_test.dart` — panel wiring widget test.

**Modified:**
- `lib/models/save_system.dart` — add `DrumLoopSnapshot` + a dispatch branch in `InstrumentSnapshot.fromJson`.
- `lib/features/song/drum_machine_editor.dart` — `_applyLoadedPattern` + a gated "My Loops" button in the transport row.
- `test/features/song/drum_library_test.dart` — extend with the My-Loops-button presence test.

---

## Task 1: `DrumLoopSnapshot` model + dispatch

**Files:**
- Modify: `lib/models/save_system.dart`
- Test: `test/models/drum_loop_snapshot_test.dart`

- [ ] **Step 1: Write the failing test**

`test/models/drum_loop_snapshot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  const pattern = DrumPattern(
    id: 'd1',
    name: 'My Beat',
    lengthTicks: 16,
    lanes: [
      DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
      DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [4, 12]),
    ],
  );

  test('DrumLoopSnapshot exposes the abstract contract', () {
    const snap = DrumLoopSnapshot(pattern: pattern);
    expect(snap.instrument, 'drum_loop');
    expect(snap.selectedNotes, isEmpty);
    expect(snap.pendingChord, isNull);
    expect(snap.pendingScale, isNull);
  });

  test('toJson carries the drum_loop type + pattern', () {
    const snap = DrumLoopSnapshot(pattern: pattern);
    final json = snap.toJson();
    expect(json['type'], 'drum_loop');
    expect(json['instrument'], 'drum_loop');
    expect(json['pattern'], isA<Map<String, dynamic>>());
  });

  test('InstrumentSnapshot.fromJson dispatches drum_loop', () {
    final back = InstrumentSnapshot.fromJson(
      const DrumLoopSnapshot(pattern: pattern).toJson(),
    );
    expect(back, isA<DrumLoopSnapshot>());
    final loop = back as DrumLoopSnapshot;
    expect(loop.pattern.name, 'My Beat');
    expect(loop.pattern.lengthTicks, 16);
    expect(loop.pattern.lanes.first.laneId, DrumLaneId.kick);
    expect(loop.pattern.lanes.first.activeTicks, [0, 8]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/drum_loop_snapshot_test.dart`
Expected: FAIL — `DrumLoopSnapshot` undefined.

- [ ] **Step 3: Add `DrumLoopSnapshot`**

In `lib/models/save_system.dart`, add the class (place it after the `SongProjectSnapshot` class, before the next non-snapshot type). `DrumPattern`, `PendingChord`, `PendingScale` are all already in scope in this file:

```dart
/// A single reusable drum [DrumPattern] saved to the library. Loaded loops are
/// applied into the pattern currently being edited (see the drum editor).
class DrumLoopSnapshot extends InstrumentSnapshot {
  final DrumPattern pattern;

  const DrumLoopSnapshot({required this.pattern});

  @override
  String get instrument => 'drum_loop';

  @override
  List<String> get selectedNotes => const [];

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'drum_loop',
    'instrument': 'drum_loop',
    'pattern': pattern.toJson(),
  };

  factory DrumLoopSnapshot.fromJson(Map<String, dynamic> json) =>
      DrumLoopSnapshot(
        pattern: DrumPattern.fromJson(json['pattern'] as Map<String, dynamic>),
      );
}
```

- [ ] **Step 4: Add the dispatch branch**

In the static `InstrumentSnapshot.fromJson` (around line 66), add a branch BEFORE the final `return FretboardSnapshot.fromJson(json);` fallback:

```dart
    if (type == 'drum_loop' || instrument == 'drum_loop') {
      return DrumLoopSnapshot.fromJson(json);
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/models/drum_loop_snapshot_test.dart`
Expected: PASS (3/3).

- [ ] **Step 6: Run the save-system model + store suites for regressions**

Run: `flutter test test/models/ test/store/save_system_store_test.dart`
Expected: PASS — the addition is backwards-compatible (new type, default-fallback unchanged for existing snapshots).

- [ ] **Step 7: Commit**

```bash
git add lib/models/save_system.dart test/models/drum_loop_snapshot_test.dart
git commit -m "feat(save): DrumLoopSnapshot drum_loop save type"
```

---

## Task 2: `DrumLoopSavePanel` + library sheet

A thin wrapper over `SaveBrowserPanel` (mirrors `SongwriterSavePanel`) that saves the current pattern as a `DrumLoopSnapshot` and applies a loaded loop via a callback.

**Files:**
- Create: `lib/features/song/drum_loop_save_panel.dart`
- Test: `test/features/song/drum_loop_save_panel_test.dart`

- [ ] **Step 1: Write the failing test**

`test/features/song/drum_loop_save_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/song/drum_loop_save_panel.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/ui/project_required_placeholder.dart';
import 'package:muzician/ui/save_browser_panel.dart';

DrumPattern _pattern() => const DrumPattern(
  id: 'd1',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
);

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: DrumLoopSavePanel(
            currentPattern: _pattern(),
            onApply: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows a project-required placeholder when no project selected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.byType(ProjectRequiredPlaceholder), findsOneWidget);
    expect(find.byType(SaveBrowserPanel), findsNothing);
  });

  testWidgets('renders the save browser when a project is selected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(saveSystemProvider.notifier);
    final projectId = notifier.createProject('Demo', const ProjectConfig());
    notifier.selectProject(projectId);

    await _pump(tester, container);

    expect(find.byType(SaveBrowserPanel), findsOneWidget);
    expect(find.byType(ProjectRequiredPlaceholder), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/song/drum_loop_save_panel_test.dart`
Expected: FAIL — `DrumLoopSavePanel` undefined.

- [ ] **Step 3: Implement the panel + sheet**

`lib/features/song/drum_loop_save_panel.dart`:

```dart
/// Save / load panel for reusable drum loops. Wraps the shared save browser
/// filtered to `'drum_loop'` snapshots: capturing saves the current pattern,
/// loading applies the loop back into the editor via [onApply].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../store/save_system_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';
import '../_mockup_shell.dart';

/// Opens the drum-loop library as a bottom sheet.
Future<void> showDrumLoopLibrarySheet({
  required BuildContext context,
  required DrumPattern currentPattern,
  required void Function(DrumPattern pattern) onApply,
}) {
  return showWidgetSheet(
    context: context,
    title: 'My Loops',
    child: DrumLoopSavePanel(currentPattern: currentPattern, onApply: onApply),
  );
}

class DrumLoopSavePanel extends ConsumerWidget {
  const DrumLoopSavePanel({
    super.key,
    required this.currentPattern,
    required this.onApply,
  });

  /// The pattern captured when the user saves a new loop.
  final DrumPattern currentPattern;

  /// Called with a loaded loop's pattern so the editor can apply it.
  final void Function(DrumPattern pattern) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      return const ProjectRequiredPlaceholder(
        message: 'Drum loops need a real project.\nDump is not allowed here.',
        allowDump: false,
      );
    }
    return SaveBrowserPanel(
      rootFolderId: selected.id,
      instrumentFilter: 'drum_loop',
      captureSnapshot: () => DrumLoopSnapshot(pattern: currentPattern),
      onLoad: (snapshot) {
        if (snapshot is DrumLoopSnapshot) onApply(snapshot.pattern);
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/song/drum_loop_save_panel_test.dart`
Expected: PASS (2/2).

> If `SaveBrowserPanel` requires a named param this wrapper doesn't pass (e.g. a required `onPick`), read `lib/ui/save_browser_panel.dart` and `lib/features/songwriter/songwriter_save_panel.dart` and match exactly what `SongwriterSavePanel` passes. The capture/onLoad pair above mirrors the songwriter panel; only add params that the constructor actually requires.

- [ ] **Step 5: Commit**

```bash
git add lib/features/song/drum_loop_save_panel.dart test/features/song/drum_loop_save_panel_test.dart
git commit -m "feat(drum): drum loop save/load panel"
```

---

## Task 3: "My Loops" button in the editor

**Files:**
- Modify: `lib/features/song/drum_machine_editor.dart`
- Test: extend `test/features/song/drum_library_test.dart`

- [ ] **Step 1: Add the failing test**

Append to `test/features/song/drum_library_test.dart` inside `main()` (the `emptyPattern` helper + `ProviderScope`/`DrumMachineEditorBody` imports already exist from Phase 3):

```dart
testWidgets('My Loops button shows when enableLibrary is true', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: emptyPattern('p1'),
            tempo: 120,
            enableLibrary: true,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  expect(find.byKey(const Key('drumLoopsButton')), findsOneWidget);
});

testWidgets('My Loops button hidden when enableLibrary is false', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: emptyPattern('p1'),
            tempo: 120,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  expect(find.byKey(const Key('drumLoopsButton')), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/song/drum_library_test.dart`
Expected: FAIL — `drumLoopsButton` not found.

- [ ] **Step 3: Add the import + apply method**

In `lib/features/song/drum_machine_editor.dart`, add the import (next to the existing `import 'drum_library_sheet.dart';`):

```dart
import 'drum_loop_save_panel.dart';
```

Add this method next to `_applyPreset`:

```dart
void _applyLoadedPattern(DrumPattern loaded) {
  setState(
    () => _pattern = _pattern.copyWith(
      name: loaded.name,
      lengthTicks: loaded.lengthTicks,
      lanes: loaded.lanes,
    ),
  );
  widget.onChanged(_pattern);
}
```

- [ ] **Step 4: Add the "My Loops" button**

In the transport `Row`, inside the existing `if (widget.enableLibrary) ...[ ... ]` block (which currently holds the `drumLibraryButton` IconButton + a trailing `SizedBox(width: 8)`), add a second IconButton AFTER the `drumLibraryButton` and before that trailing `SizedBox`, so the block reads:

```dart
            if (widget.enableLibrary) ...[
              IconButton(
                key: const Key('drumLibraryButton'),
                tooltip: 'Drum presets',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: MuzicianTheme.orange,
                icon: const Icon(Icons.library_music),
                onPressed: () =>
                    showDrumLibrarySheet(context: context, onPick: _applyPreset),
              ),
              IconButton(
                key: const Key('drumLoopsButton'),
                tooltip: 'My loops',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: MuzicianTheme.orange,
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: () => showDrumLoopLibrarySheet(
                  context: context,
                  currentPattern: _pattern,
                  onApply: _applyLoadedPattern,
                ),
              ),
              const SizedBox(width: 8),
            ],
```

(The `drumLibraryButton` tooltip changes from 'Drum library' to 'Drum presets' to disambiguate from 'My loops'. Everything else in that button is unchanged.)

- [ ] **Step 5: Run the test**

Run: `flutter test test/features/song/drum_library_test.dart`
Expected: PASS — both new tests plus the Phase 3 tests (the `drumLibraryButton` apply test still passes; the new button is additive).

- [ ] **Step 6: Run the editor regression suites**

Run: `flutter test test/features/song/ test/features/songwriter/`
Expected: PASS — `enableLibrary` defaults false, so the Song feature shows neither button; the Songwriter sheet (which passes `enableLibrary: true`) shows both.

- [ ] **Step 7: Commit**

```bash
git add lib/features/song/drum_machine_editor.dart test/features/song/drum_library_test.dart
git commit -m "feat(drum): My Loops button — save/load loops from the editor"
```

---

## Task 4: Full-suite regression + analyze + manual smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the affected suites**

Run: `flutter test test/models/ test/store/ test/features/song/ test/features/songwriter/`
Expected: PASS.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/models/save_system.dart lib/features/song/drum_loop_save_panel.dart lib/features/song/drum_machine_editor.dart`
Expected: No new issues.

- [ ] **Step 3: Manual smoke check**

Run: `flutter run -d <preferred-device>` (with a real project selected)
- Open a Songwriter drum pattern → the transport shows a **library_music** (presets) and a **bookmarks** (My Loops) button.
- Edit a groove, tap **My Loops** → the save browser opens → save it with a name.
- Apply a different preset, then tap **My Loops** → tap the saved loop → the grid restores your saved groove.
- Hot-restart the app → reopen My Loops → the saved loop is still there (persisted).
- Open the Song-feature drum editor → neither library button appears (Song path unchanged).

- [ ] **Step 4: Final commit (only if the smoke check required a fix)**

```bash
git add -A
git commit -m "fix(drum): address user-loops smoke-test findings"
```

---

## Self-Review Notes

- **Spec coverage (Component 3, save half):** `DrumLoopSnapshot` save type (Task 1), browse/save via the existing `SaveBrowserPanel` (Task 2), load applies into the editor (Task 2 `onLoad` → Task 3 `_applyLoadedPattern`), editor entry point gated to Songwriter (Task 3). Presets (Phase 3) and loops (Phase 4) now sit side by side in the transport.
- **No import cycle:** `DrumLoopSnapshot` lives in `save_system.dart`, which already imports `song_project.dart` (where `DrumPattern` is defined) — confirmed.
- **Shared-editor safety:** the "My Loops" button is inside the same `if (widget.enableLibrary)` block as the presets button; the Song wrapper omits `enableLibrary`, so neither appears there. Verified by the hidden-button test and the Song suite.
- **Apply-in-place (deviation):** loading a loop overwrites the current pattern's name/length/lanes but keeps its id, so referencing blocks stay linked — identical to the Phase 3 preset flow. `addDrumPatternFrom` is intentionally not built (YAGNI for this phase).
- **Persistence is real:** saving goes through `saveSystemProvider` → `SharedPreferences`, so loops survive restarts and are visible across projects in the browser.
- **Type consistency:** `DrumLoopSnapshot({required DrumPattern pattern})`, `instrument == 'drum_loop'`, `instrumentFilter: 'drum_loop'`, and the `fromJson` branch all use the identical `'drum_loop'` token. `onApply(DrumPattern)` matches between `showDrumLoopLibrarySheet`, `DrumLoopSavePanel`, and `_applyLoadedPattern`.
- **No placeholders:** every step has complete code; the one verification note (Task 2 Step 4) is to match `SaveBrowserPanel`'s actual required params against `SongwriterSavePanel`, not a code gap.

---

## Out-of-scope reminders (do NOT do here)

- No `addDrumPatternFrom` / "insert as a new pattern or lane" — loading applies in place (documented deviation).
- No tabbed Presets+Loops UI — two separate buttons keep it simple.
- No Song-feature library buttons (kept opt-in via `enableLibrary`).
- No preset → save-entry seeding (presets stay code-defined from Phase 3).
- No changes to `SaveBrowserPanel` itself — only a thin wrapper.
