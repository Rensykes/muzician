# Drum Preset Library (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a built-in library of drum loops and fills that a user can browse and apply to the drum pattern they are editing — the preset's content is copied into the project pattern (same id, so the block stays linked) and is then freely editable.

**Architecture:** Presets are code-defined `const` data (`drum_presets.dart`) — no persistence. A picker sheet (`drum_library_sheet.dart`) lists them grouped by category and returns the chosen `DrumPreset` via a callback. Applying a preset happens INSIDE `DrumMachineEditorBody` (which owns the editable `_pattern`), so the grid refreshes immediately via `setState`; the change is emitted through the existing `onChanged`. A new optional `enableLibrary` flag gates the Library button so the Song feature path is unchanged. The Songwriter drum sheet opts in.

**Tech Stack:** Dart, Flutter, Riverpod, `flutter_test`. No new packages. No persistence/save-system changes (those are Phase 4).

**Spec:** `docs/superpowers/specs/2026-06-23-songwriter-drum-loops-design.md` (Component 3, factory half).

**Depends on:** Phases 1–2 already on this branch. Key fact: `DrumMachineEditorBody` caches `_pattern` and only re-syncs in `didUpdateWidget` when `pattern.id` changes — so a preset MUST be applied inside the body (setState), not by mutating the store and relying on a rebuild with the same id.

---

## File Structure

**Created:**
- `lib/schema/rules/drum_presets.dart` — `DrumPreset` value type + `const drumPresets` library.
- `lib/features/song/drum_library_sheet.dart` — `showDrumLibrarySheet` picker (grouped by category) with an `onPick(DrumPreset)` callback.
- `test/schema/rules/drum_presets_test.dart` — preset integrity tests.
- `test/features/song/drum_library_test.dart` — picker widget test + body-level apply tests.
- `test/features/songwriter/drum_pattern_sheet_library_test.dart` — sheet opt-in test.

**Modified:**
- `lib/features/song/drum_machine_editor.dart` — optional `enableLibrary` flag + a Library button in the transport row + `_applyPreset`.
- `lib/features/songwriter/drum_pattern_sheet.dart` — pass `enableLibrary: true` to the body.

---

## Task 1: Preset data (`drum_presets.dart`)

**Files:**
- Create: `lib/schema/rules/drum_presets.dart`
- Test: `test/schema/rules/drum_presets_test.dart`

- [ ] **Step 1: Write the failing test**

`test/schema/rules/drum_presets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/drum_presets.dart';

void main() {
  test('library is non-empty and every preset is valid', () {
    expect(drumPresets, isNotEmpty);
    for (final p in drumPresets) {
      expect(p.lengthTicks, greaterThan(0), reason: p.name);
      expect(p.name.trim(), isNotEmpty);
      expect(p.category.trim(), isNotEmpty);
      final hitCount = p.hits.values.fold<int>(0, (n, t) => n + t.length);
      expect(hitCount, greaterThan(0), reason: '${p.name} has no hits');
      for (final entry in p.hits.entries) {
        for (final t in entry.value) {
          expect(
            t,
            inInclusiveRange(0, p.lengthTicks - 1),
            reason: '${p.name} / ${entry.key}',
          );
        }
      }
    }
  });

  test('preset names are unique', () {
    final names = drumPresets.map((p) => p.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('buildLanes yields all eight voices in canonical order', () {
    final lanes = drumPresets.first.buildLanes();
    expect(lanes.map((l) => l.laneId).toList(), DrumLaneId.values);
  });

  test('toPattern carries id, name, and length', () {
    final preset = drumPresets.first;
    final pattern = preset.toPattern('x1');
    expect(pattern.id, 'x1');
    expect(pattern.name, preset.name);
    expect(pattern.lengthTicks, preset.lengthTicks);
    expect(pattern.lanes.length, DrumLaneId.values.length);
  });

  test('Four on the Floor lands the kick on every beat', () {
    final preset = drumPresets.firstWhere((p) => p.name == 'Four on the Floor');
    expect(preset.hits[DrumLaneId.kick], [0, 4, 8, 12]);
  });

  test('categories cover the expected genres', () {
    final cats = drumPresets.map((p) => p.category).toSet();
    expect(
      cats,
      containsAll(<String>['Rock', 'Funk', 'Pop', 'Latin', 'Hip-Hop', 'Fills']),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/drum_presets_test.dart`
Expected: FAIL — `drum_presets.dart` / `DrumPreset` / `drumPresets` undefined.

- [ ] **Step 3: Implement the presets**

`lib/schema/rules/drum_presets.dart`:

```dart
/// Built-in drum loop + fill library.
///
/// Presets are pure, code-defined templates (no persistence). Each carries a
/// per-voice hit map on a 16-tick (one-bar, sixteenth-grid) pattern. [buildLanes]
/// always materialises all eight [DrumLaneId] voices (empty where unused) so an
/// applied preset fills the full editor grid.
library;

import '../../models/song_project.dart';

class DrumPreset {
  final String name;
  final String category;
  final int lengthTicks;
  final Map<DrumLaneId, List<int>> hits;

  const DrumPreset({
    required this.name,
    required this.category,
    required this.hits,
    this.lengthTicks = 16,
  });

  /// All eight voices in [DrumLaneId] order, empty where the preset has no hits.
  List<DrumLaneSequence> buildLanes() => [
    for (final id in DrumLaneId.values)
      DrumLaneSequence(laneId: id, activeTicks: hits[id] ?? const []),
  ];

  /// A concrete [DrumPattern] with the given [id], adopting this preset's
  /// name, length, and voices.
  DrumPattern toPattern(String id) => DrumPattern(
    id: id,
    name: name,
    lengthTicks: lengthTicks,
    lanes: buildLanes(),
  );
}

// Common hi-hat figures (sixteenth grid).
const List<int> _eighths = [0, 2, 4, 6, 8, 10, 12, 14];
const List<int> _sixteenths = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const List<int> _backbeat = [4, 12];

/// The built-in library, grouped by category in display order.
const List<DrumPreset> drumPresets = [
  // ── Rock ──
  DrumPreset(
    name: 'Four on the Floor',
    category: 'Rock',
    hits: {
      DrumLaneId.kick: [0, 4, 8, 12],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Basic Rock',
    category: 'Rock',
    hits: {
      DrumLaneId.kick: [0, 8],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Half-Time Rock',
    category: 'Rock',
    hits: {
      DrumLaneId.kick: [0, 10],
      DrumLaneId.snare: [8],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  // ── Funk ──
  DrumPreset(
    name: 'Funk Groove',
    category: 'Funk',
    hits: {
      DrumLaneId.kick: [0, 6, 10],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Sixteenth Funk',
    category: 'Funk',
    hits: {
      DrumLaneId.kick: [0, 3, 8, 11],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _sixteenths,
    },
  ),
  // ── Pop ──
  DrumPreset(
    name: 'Pop Backbeat',
    category: 'Pop',
    hits: {
      DrumLaneId.kick: [0, 8],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Dance Pop',
    category: 'Pop',
    hits: {
      DrumLaneId.kick: [0, 4, 8, 12],
      DrumLaneId.clap: _backbeat,
      DrumLaneId.closedHiHat: [2, 6, 10, 14],
    },
  ),
  // ── Latin ──
  DrumPreset(
    name: 'Bossa Nova',
    category: 'Latin',
    hits: {
      DrumLaneId.kick: [0, 8],
      DrumLaneId.snare: [3, 6, 10, 13],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Samba',
    category: 'Latin',
    hits: {
      DrumLaneId.kick: [0, 4, 8, 12],
      DrumLaneId.snare: [2, 6, 10, 14],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  // ── Hip-Hop ──
  DrumPreset(
    name: 'Boom Bap',
    category: 'Hip-Hop',
    hits: {
      DrumLaneId.kick: [0, 10],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Trap',
    category: 'Hip-Hop',
    hits: {
      DrumLaneId.kick: [0, 6],
      DrumLaneId.snare: [8],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Lo-Fi',
    category: 'Hip-Hop',
    hits: {
      DrumLaneId.kick: [0, 9],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: [0, 4, 8, 12],
    },
  ),
  // ── Fills ──
  DrumPreset(
    name: 'Snare Roll',
    category: 'Fills',
    hits: {
      DrumLaneId.snare: [8, 10, 12, 13, 14, 15],
    },
  ),
  DrumPreset(
    name: 'Tom Fill',
    category: 'Fills',
    hits: {
      DrumLaneId.highTom: [8, 9],
      DrumLaneId.lowTom: [10, 11],
      DrumLaneId.snare: [12, 13],
      DrumLaneId.crash: [0],
    },
  ),
  DrumPreset(
    name: 'Crash Accent',
    category: 'Fills',
    hits: {
      DrumLaneId.crash: [0],
      DrumLaneId.kick: [0],
    },
  ),
  DrumPreset(
    name: 'Build Up',
    category: 'Fills',
    hits: {
      DrumLaneId.snare: [8, 9, 10, 11, 12, 13, 14, 15],
    },
  ),
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/drum_presets_test.dart`
Expected: PASS (6/6).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/drum_presets.dart test/schema/rules/drum_presets_test.dart
git commit -m "feat(drum): built-in preset loop + fill library"
```

---

## Task 2: Library picker sheet

**Files:**
- Create: `lib/features/song/drum_library_sheet.dart`
- Test: `test/features/song/drum_library_test.dart`

- [ ] **Step 1: Write the failing test**

`test/features/song/drum_library_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_library_sheet.dart';
import 'package:muzician/schema/rules/drum_presets.dart';

void main() {
  testWidgets('library sheet lists presets by category and fires onPick', (
    tester,
  ) async {
    DrumPreset? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDrumLibrarySheet(
                context: context,
                onPick: (p) => picked = p,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A category header and a known preset tile are present.
    expect(find.text('Rock'), findsWidgets);
    expect(find.byKey(const Key('preset_Four on the Floor')), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset_Four on the Floor')));
    await tester.pumpAndSettle();

    expect(picked?.name, 'Four on the Floor');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/song/drum_library_test.dart`
Expected: FAIL — `showDrumLibrarySheet` undefined.

- [ ] **Step 3: Implement the picker**

`lib/features/song/drum_library_sheet.dart`:

```dart
/// Picker for the built-in drum [drumPresets] library, grouped by category.
library;

import 'package:flutter/material.dart';

import '../../schema/rules/drum_presets.dart';
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';

/// Shows the drum library. Calls [onPick] with the chosen preset and closes.
Future<void> showDrumLibrarySheet({
  required BuildContext context,
  required void Function(DrumPreset preset) onPick,
}) {
  return showWidgetSheet(
    context: context,
    title: 'Drum Library',
    child: _DrumLibraryBody(onPick: onPick),
  );
}

class _DrumLibraryBody extends StatelessWidget {
  const _DrumLibraryBody({required this.onPick});
  final void Function(DrumPreset preset) onPick;

  /// Categories in first-seen order across [drumPresets].
  List<String> get _orderedCategories {
    final seen = <String>[];
    for (final p in drumPresets) {
      if (!seen.contains(p.category)) seen.add(p.category);
    }
    return seen;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _orderedCategories;
    // SingleChildScrollView + min Column scrolls when the sheet bounds it and
    // sizes to content otherwise — robust regardless of the sheet's layout.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                category.toUpperCase(),
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final preset
                in drumPresets.where((p) => p.category == category))
              _PresetTile(
                preset: preset,
                onTap: () {
                  onPick(preset);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.onTap});
  final DrumPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final voices = preset.hits.entries.where((e) => e.value.isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: MuzicianTheme.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('preset_${preset.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.graphic_eq,
                  size: 16,
                  color: MuzicianTheme.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    preset.name,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$voices voices',
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/song/drum_library_test.dart`
Expected: PASS (1/1).

- [ ] **Step 5: Commit**

```bash
git add lib/features/song/drum_library_sheet.dart test/features/song/drum_library_test.dart
git commit -m "feat(drum): drum library picker sheet"
```

---

## Task 3: Apply presets from the editor (gated `enableLibrary`)

Wire a Library button into `DrumMachineEditorBody`. Applying a preset replaces the body's editable pattern (keeping the same id) and emits via `onChanged`. The button only appears when `enableLibrary` is true; the Songwriter sheet opts in, the Song feature does not.

**Files:**
- Modify: `lib/features/song/drum_machine_editor.dart`
- Modify: `lib/features/songwriter/drum_pattern_sheet.dart`
- Test: extend `test/features/song/drum_library_test.dart`; create `test/features/songwriter/drum_pattern_sheet_library_test.dart`

- [ ] **Step 1: Add failing body-level tests**

Append to `test/features/song/drum_library_test.dart` (add the imports at the top, then the tests inside `main`):

Add imports at the top:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';
```

Add inside `main()`:

```dart
DrumPattern _emptyPattern(String id) => DrumPattern(
  id: id,
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    for (final laneId in DrumLaneId.values)
      DrumLaneSequence(laneId: laneId, activeTicks: const []),
  ],
);

testWidgets('Library button applies a preset to the pattern, same id', (
  tester,
) async {
  DrumPattern? captured;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: _emptyPattern('p1'),
            tempo: 120,
            enableLibrary: true,
            onChanged: (p) => captured = p,
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('drumLibraryButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('preset_Four on the Floor')));
  await tester.pumpAndSettle();

  expect(captured, isNotNull);
  expect(captured!.id, 'p1'); // same id → block stays linked
  final kick = captured!.lanes.firstWhere((l) => l.laneId == DrumLaneId.kick);
  expect(kick.activeTicks, [0, 4, 8, 12]);
});

testWidgets('no Library button when enableLibrary is false', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: _emptyPattern('p1'),
            tempo: 120,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  expect(find.byKey(const Key('drumLibraryButton')), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/song/drum_library_test.dart`
Expected: FAIL — `enableLibrary` is not a parameter; `drumLibraryButton` not found.

- [ ] **Step 3: Add imports + the `enableLibrary` field**

In `lib/features/song/drum_machine_editor.dart`, add imports (after the existing `import '../../schema/rules/drum_fill_rules.dart';`):

```dart
import '../../schema/rules/drum_presets.dart';
import 'drum_library_sheet.dart';
```

Add the field + constructor param to `DrumMachineEditorBody` (keep all existing params, including `backing`):

```dart
  /// When true, the transport shows a Library button that replaces the pattern
  /// with a chosen built-in preset (same id, so referencing blocks stay linked).
  final bool enableLibrary;
```

The constructor becomes:

```dart
  const DrumMachineEditorBody({
    super.key,
    required this.pattern,
    required this.tempo,
    required this.onChanged,
    this.beatUnit = 4,
    this.backing,
    this.enableLibrary = false,
  });
```

- [ ] **Step 4: Add `_applyPreset` to `_DrumMachineEditorBodyState`**

Add this method next to `_applyLaneTicks`:

```dart
void _applyPreset(DrumPreset preset) {
  setState(() => _pattern = preset.toPattern(_pattern.id));
  widget.onChanged(_pattern);
}
```

- [ ] **Step 5: Render the Library button in the transport row**

In the transport `Row` (which currently ends with `const Spacer()` then the BPM `Text`), insert the Library button between the `Spacer` and the BPM text, so the tail of the children list reads:

```dart
    const Spacer(),
    if (widget.enableLibrary) ...[
      IconButton(
        key: const Key('drumLibraryButton'),
        tooltip: 'Drum library',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: MuzicianTheme.orange,
        icon: const Icon(Icons.library_music),
        onPressed: () =>
            showDrumLibrarySheet(context: context, onPick: _applyPreset),
      ),
      const SizedBox(width: 8),
    ],
    Text(
      '${widget.tempo} BPM',
      style: const TextStyle(
        color: MuzicianTheme.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
```

(Leave the leading part of the `Row` — play button + optional backing chip — unchanged.)

- [ ] **Step 6: Run the body-level tests**

Run: `flutter test test/features/song/drum_library_test.dart`
Expected: PASS (3/3 — picker + apply + no-button).

- [ ] **Step 7: Opt the Songwriter sheet in**

In `lib/features/songwriter/drum_pattern_sheet.dart`, the `DrumMachineEditorBody(...)` call currently passes `pattern`, `tempo`, `backing`, `onChanged`. Add `enableLibrary: true`:

```dart
      child: DrumMachineEditorBody(
        key: Key('drumPatternBody_$patternId'),
        pattern: pattern,
        tempo: project.config.tempo,
        backing: backing,
        enableLibrary: true,
        onChanged: (updated) {
          ref.read(songwriterProvider.notifier).updateDrumPattern(updated);
        },
      ),
```

- [ ] **Step 8: Add the sheet opt-in test**

`test/features/songwriter/drum_pattern_sheet_library_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/drum_pattern_sheet.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  testWidgets('drum sheet shows the Library button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(songwriterProvider.notifier).loadProject(
      const SongwriterProjectSnapshot(
        name: 'demo',
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        drumPatterns: [
          DrumPattern(
            id: 'p1',
            name: 'Beat',
            lengthTicks: 16,
            lanes: [
              DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSongwriterDrumPatternSheet(
                  context: context,
                  patternId: 'p1',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drumLibraryButton')), findsOneWidget);
  });
}
```

- [ ] **Step 9: Run the sheet test + the editor regression suites**

Run: `flutter test test/features/songwriter/drum_pattern_sheet_library_test.dart test/features/song/`
Expected: PASS — the Song feature's `DrumMachineEditor` does not pass `enableLibrary`, so no Library button appears there; the Songwriter sheet shows it.

- [ ] **Step 10: Commit**

```bash
git add lib/features/song/drum_machine_editor.dart lib/features/songwriter/drum_pattern_sheet.dart test/features/song/drum_library_test.dart test/features/songwriter/drum_pattern_sheet_library_test.dart
git commit -m "feat(drum): apply presets from the editor (Songwriter opt-in)"
```

---

## Task 4: Full-suite regression + analyze + manual smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the affected suites**

Run: `flutter test test/schema/rules/ test/features/song/ test/features/songwriter/`
Expected: PASS.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/schema/rules/drum_presets.dart lib/features/song/drum_library_sheet.dart lib/features/song/drum_machine_editor.dart lib/features/songwriter/drum_pattern_sheet.dart`
Expected: No new issues.

- [ ] **Step 3: Manual smoke check**

Run: `flutter run -d <preferred-device>`
- Open a Songwriter drum pattern → the editor sheet shows a **library_music** button in the transport row.
- Tap it → the Drum Library opens, grouped Rock / Funk / Pop / Latin / Hip-Hop / Fills.
- Tap "Four on the Floor" → the sheet closes and the grid immediately fills (kick on every beat, snare backbeat, eighth hats).
- Edit a step → still works; the change persists.
- Open the Song-feature drum editor (a drum clip) → NO library button (Song path unchanged).

- [ ] **Step 4: Final commit (only if the smoke check required a fix)**

```bash
git add -A
git commit -m "fix(drum): address preset-library smoke-test findings"
```

---

## Self-Review Notes

- **Spec coverage (Component 3, factory half):** code-defined preset library grouped by category (Task 1), browse via a picker (Task 2), copy-on-use into the project pattern keeping the id so the block stays linked and the result is editable (Task 3 `_applyPreset` → `toPattern(_pattern.id)` → `onChanged`). The "My Loops" save-system half (`DrumLoopSnapshot`, save panel) is Phase 4.
- **Why apply inside the body:** `DrumMachineEditorBody` caches `_pattern` and only re-syncs on id change. Applying via the store with the same id would not refresh the grid. Applying inside the body (`setState`) refreshes immediately and still persists through `onChanged` → `updateDrumPattern`.
- **Shared-editor safety:** `enableLibrary` defaults false; the Song wrapper omits it → no Library button, Song path untouched. Verified by the "no Library button" test and the Song suite.
- **Full-grid presets:** `buildLanes()` always emits all eight `DrumLaneId` voices, so an applied preset never shrinks the editor grid.
- **Type consistency:** `DrumPreset.toPattern(String)`, `buildLanes()`, `hits` map keyed by `DrumLaneId`; `onPick(DrumPreset)` identical across `showDrumLibrarySheet`, the picker, and `_applyPreset`. `enableLibrary` named identically in the body field, constructor, and the sheet opt-in.
- **No placeholders:** every step has complete code; preset tick values are concrete and the "Four on the Floor" kick `[0,4,8,12]` anchors the deterministic tests.

---

## Out-of-scope reminders (do NOT do here)

- No save-system changes, no `DrumLoopSnapshot`, no "My Loops" tab (Phase 4).
- No `addDrumPatternFrom` mutator yet (Phase 4 uses it for new-pattern inserts; Phase 3 applies in place via the body, keeping the id).
- No "add drum lane seeded from a preset" entry (Phase 4 can add it alongside library inserts).
- No Song-feature Library button (kept opt-in; can enable later).
- No preset editing/persistence — presets are read-only code.
