# Drum Sequencer Fills (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-lane "fill" utilities to the shared drum machine editor — *every-N steps* (with offset) and *Euclidean* (K hits over the pattern length), plus clear-lane — so users can populate a drum lane without tapping every cell.

**Architecture:** Two pure functions in a new rules file (`drum_fill_rules.dart`) compute tick lists; they have no Flutter dependency and are unit-tested in isolation. The shared `DrumMachineEditorBody` (used by both the Song feature and the Songwriter drum sheet) gains a per-lane menu button that opens a small bottom sheet; applying a fill replaces that lane's `activeTicks` and emits via the existing `onChanged` callback. No persistence or model changes.

**Tech Stack:** Dart, Flutter, Riverpod, `flutter_test`. No new packages.

**Spec:** `docs/superpowers/specs/2026-06-23-songwriter-drum-loops-design.md` (Component 2).

---

## File Structure

**Created:**
- `lib/schema/rules/drum_fill_rules.dart` — pure `everyN` + `euclid` tick generators.
- `test/schema/rules/drum_fill_rules_test.dart` — unit tests for the generators.
- `test/features/song/drum_fill_menu_test.dart` — widget test for the per-lane fill menu on `DrumMachineEditorBody`.

**Modified:**
- `lib/features/song/drum_machine_editor.dart` — thread a per-lane menu callback from `_DrumMachineEditorBodyState` → `_DrumGrid` → `_LaneLabelsColumn` → `_LaneLabel`; add the `_LaneFillSheet` widget and the apply logic.

---

## Task 1: Pure fill generators (`everyN`, `euclid`)

**Files:**
- Create: `lib/schema/rules/drum_fill_rules.dart`
- Test: `test/schema/rules/drum_fill_rules_test.dart`

- [ ] **Step 1: Write the failing test**

`test/schema/rules/drum_fill_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/drum_fill_rules.dart';

void main() {
  group('everyN', () {
    test('every 4 ticks over 16 fills the beats', () {
      expect(everyN(16, 4), [0, 4, 8, 12]);
    });

    test('offset shifts the start', () {
      expect(everyN(16, 4, offset: 2), [2, 6, 10, 14]);
    });

    test('step 1 fills every tick', () {
      final ticks = everyN(16, 1);
      expect(ticks.length, 16);
      expect(ticks.first, 0);
      expect(ticks.last, 15);
    });

    test('step larger than length yields only the offset start', () {
      expect(everyN(16, 32), [0]);
      expect(everyN(16, 32, offset: 4), [4]);
    });

    test('zero / negative guards return empty', () {
      expect(everyN(16, 0), isEmpty);
      expect(everyN(0, 4), isEmpty);
    });

    test('offset at or beyond length yields empty', () {
      expect(everyN(16, 4, offset: 16), isEmpty);
    });
  });

  group('euclid', () {
    test('4 over 16 is evenly spaced', () {
      expect(euclid(16, 4), [0, 4, 8, 12]);
    });

    test('classic 3 over 8 (tresillo)', () {
      expect(euclid(8, 3), [0, 3, 6]);
    });

    test('5 over 16', () {
      expect(euclid(16, 5), [0, 3, 6, 9, 12]);
    });

    test('hits >= length fills everything', () {
      expect(euclid(4, 4), [0, 1, 2, 3]);
      expect(euclid(4, 5), [0, 1, 2, 3]);
    });

    test('single hit lands on 0', () {
      expect(euclid(4, 1), [0]);
    });

    test('rotation shifts and re-sorts', () {
      expect(euclid(16, 4, rotation: 1), [1, 5, 9, 13]);
    });

    test('zero / negative guards return empty', () {
      expect(euclid(16, 0), isEmpty);
      expect(euclid(0, 4), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/drum_fill_rules_test.dart`
Expected: FAIL — `drum_fill_rules.dart` does not exist / `everyN` and `euclid` undefined.

- [ ] **Step 3: Write the implementation**

`lib/schema/rules/drum_fill_rules.dart`:

```dart
/// Pure tick generators for drum-lane "fill" utilities.
///
/// Both functions return a sorted list of active ticks in `[0, lengthTicks)`.
/// They have no Flutter dependency and are the single source of truth for the
/// sequencer fill menu in the drum machine editor.
library;

/// Active ticks at [offset], [offset]+[step], [offset]+2·[step], … while
/// `< lengthTicks`. Returns empty when [lengthTicks] or [step] is non-positive,
/// or when [offset] is at/beyond [lengthTicks].
List<int> everyN(int lengthTicks, int step, {int offset = 0}) {
  if (lengthTicks <= 0 || step <= 0) return const [];
  final start = offset < 0 ? 0 : offset;
  final out = <int>[];
  for (var t = start; t < lengthTicks; t += step) {
    out.add(t);
  }
  return out;
}

/// Euclidean rhythm: distributes [hits] pulses as evenly as possible across
/// [lengthTicks] slots using Bjorklund's algorithm, then rotates the result by
/// [rotation] slots. Returns sorted active ticks.
///
/// `euclid(8, 3) == [0, 3, 6]`, `euclid(16, 4) == [0, 4, 8, 12]`.
List<int> euclid(int lengthTicks, int hits, {int rotation = 0}) {
  if (lengthTicks <= 0 || hits <= 0) return const [];
  if (hits >= lengthTicks) {
    return [for (var i = 0; i < lengthTicks; i++) i];
  }

  // Bjorklund: repeatedly fold the remainder groups into the front groups
  // until at most one remainder group is left.
  var groups = <List<int>>[for (var i = 0; i < hits; i++) <int>[1]];
  var remainders = <List<int>>[
    for (var i = 0; i < lengthTicks - hits; i++) <int>[0],
  ];

  while (remainders.length > 1) {
    final count = groups.length < remainders.length
        ? groups.length
        : remainders.length;
    final newGroups = <List<int>>[];
    for (var i = 0; i < count; i++) {
      newGroups.add(<int>[...groups[i], ...remainders[i]]);
    }
    final newRemainders = <List<int>>[];
    if (groups.length > count) {
      newRemainders.addAll(groups.sublist(count));
    } else if (remainders.length > count) {
      newRemainders.addAll(remainders.sublist(count));
    }
    groups = newGroups;
    remainders = newRemainders;
  }

  final pattern = <int>[
    for (final g in [...groups, ...remainders]) ...g,
  ];

  final ticks = <int>[];
  for (var i = 0; i < pattern.length; i++) {
    if (pattern[i] == 1) ticks.add(i);
  }

  if (rotation != 0 && ticks.isNotEmpty) {
    final r = rotation % lengthTicks;
    return ticks.map((t) => (t + r) % lengthTicks).toList()..sort();
  }
  return ticks;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/drum_fill_rules_test.dart`
Expected: PASS (all groups green).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/drum_fill_rules.dart test/schema/rules/drum_fill_rules_test.dart
git commit -m "feat(drum): pure everyN + euclid fill generators"
```

---

## Task 2: Per-lane fill menu in `DrumMachineEditorBody`

This task threads a `onLaneMenu(DrumLaneId)` callback down to each lane label, adds a menu button, and opens a `_LaneFillSheet` that applies a fill by replacing the lane's `activeTicks`.

**Files:**
- Modify: `lib/features/song/drum_machine_editor.dart`
- Test: `test/features/song/drum_fill_menu_test.dart`

- [ ] **Step 1: Write the failing widget test**

`test/features/song/drum_fill_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';

DrumPattern _emptyPattern() => const DrumPattern(
  id: 'p1',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.closedHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.openHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.clap, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.lowTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.highTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.crash, activeTicks: []),
  ],
);

Future<void> _pumpBody(
  WidgetTester tester,
  void Function(DrumPattern) onChanged,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: _emptyPattern(),
            tempo: 120,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every-beat fill sets the kick lane to [0,4,8,12]', (
    tester,
  ) async {
    DrumPattern? captured;
    await _pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fillEvery_4')));
    await tester.pumpAndSettle();

    final kick =
        captured!.lanes.firstWhere((l) => l.laneId == DrumLaneId.kick);
    expect(kick.activeTicks, [0, 4, 8, 12]);
  });

  testWidgets('euclid fill sets the snare lane to [0,3,6]', (tester) async {
    DrumPattern? captured;
    await _pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('laneFillMenu_snare')));
    await tester.pumpAndSettle();
    // Lower hits from the default (4) to 3 via the minus stepper, then apply.
    await tester.tap(find.byKey(const Key('euclidHitsMinus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fillEuclidApply')));
    await tester.pumpAndSettle();

    final snare =
        captured!.lanes.firstWhere((l) => l.laneId == DrumLaneId.snare);
    // 3 hits over 16 ticks → Bjorklund spacing 5,5,6.
    expect(snare.activeTicks, [0, 5, 10]);
  });

  testWidgets('clear-lane empties the lane', (tester) async {
    DrumPattern? captured;
    await _pumpBody(tester, (p) => captured = p);

    // First fill kick via every-beat.
    await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fillEvery_4')));
    await tester.pumpAndSettle();
    expect(
      captured!.lanes
          .firstWhere((l) => l.laneId == DrumLaneId.kick)
          .activeTicks,
      isNotEmpty,
    );

    // Then clear it.
    await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fillClear')));
    await tester.pumpAndSettle();
    expect(
      captured!.lanes
          .firstWhere((l) => l.laneId == DrumLaneId.kick)
          .activeTicks,
      isEmpty,
    );
  });
}
```

> Note on the euclid expectation: with `lengthTicks = 16` and `hits = 3`, `euclid(16, 3) == [0, 5, 10]` (Bjorklund spacing 5,5,6). Verify against the Task 1 implementation if you change the default hits value.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/song/drum_fill_menu_test.dart`
Expected: FAIL — `laneFillMenu_kick` button not found (no menu wired yet).

- [ ] **Step 3: Add the import for the fill generators**

In `lib/features/song/drum_machine_editor.dart`, add to the import block at the top (after the existing `import '../../models/song_project.dart';`):

```dart
import '../../schema/rules/drum_fill_rules.dart';
import '../_mockup_shell.dart';
```

- [ ] **Step 4: Add apply + open-sheet logic to `_DrumMachineEditorBodyState`**

In `_DrumMachineEditorBodyState` (class begins at the `late DrumPattern _pattern;` field), add these two methods directly below the existing `_toggle` method:

```dart
void _applyLaneTicks(DrumLaneId laneId, List<int> ticks) {
  final lanes = _pattern.lanes.map((l) {
    if (l.laneId != laneId) return l;
    return l.copyWith(activeTicks: ticks);
  }).toList();
  setState(() => _pattern = _pattern.copyWith(lanes: lanes));
  widget.onChanged(_pattern);
}

void _openLaneFill(DrumLaneId laneId) {
  showWidgetSheet(
    context: context,
    title: 'Fill lane',
    child: _LaneFillSheet(
      lengthTicks: _pattern.lengthTicks,
      ticksPerBeat: TimeSignature(
        beatsPerMeasure: 4,
        beatUnit: widget.beatUnit,
      ).ticksPerBeat,
      onApply: (ticks) => _applyLaneTicks(laneId, ticks),
    ),
  );
}
```

- [ ] **Step 5: Pass the callback into `_DrumGrid`**

In the same `build` method, the `_DrumGrid(...)` call currently passes `pattern`, `timeSig`, `playheadTick`, `onToggle`. Add the menu callback:

```dart
child: _DrumGrid(
  pattern: _pattern,
  timeSig: timeSig,
  playheadTick: playing ? playback.currentTick : null,
  onToggle: (laneId, tick) {
    HapticFeedback.lightImpact();
    _toggle(laneId, tick);
  },
  onLaneMenu: _openLaneFill,
),
```

- [ ] **Step 6: Thread the callback through `_DrumGrid` and `_LaneLabelsColumn`**

In `_DrumGrid`, add the field + constructor param:

```dart
class _DrumGrid extends StatefulWidget {
  final DrumPattern pattern;
  final TimeSignature timeSig;
  final int? playheadTick;
  final void Function(DrumLaneId laneId, int tick) onToggle;
  final void Function(DrumLaneId laneId) onLaneMenu;

  const _DrumGrid({
    required this.pattern,
    required this.timeSig,
    required this.playheadTick,
    required this.onToggle,
    required this.onLaneMenu,
  });

  @override
  State<_DrumGrid> createState() => _DrumGridState();
}
```

In `_DrumGridState.build`, the `_LaneLabelsColumn(...)` call passes `lanes`, `labels`, `colors`. Add the callback:

```dart
_LaneLabelsColumn(
  lanes: widget.pattern.lanes,
  labels: _laneLabels,
  colors: _laneColors,
  onLaneMenu: widget.onLaneMenu,
),
```

- [ ] **Step 7: Add the menu button to the lane labels**

Replace the whole `_LaneLabelsColumn` class with this version (adds `onLaneMenu` and forwards a per-lane `onMenu` to each `_LaneLabel`):

```dart
class _LaneLabelsColumn extends StatelessWidget {
  final List<DrumLaneSequence> lanes;
  final Map<DrumLaneId, String> labels;
  final Map<DrumLaneId, Color> colors;
  final void Function(DrumLaneId laneId) onLaneMenu;

  const _LaneLabelsColumn({
    required this.lanes,
    required this.labels,
    required this.colors,
    required this.onLaneMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kLabelColumnWidth,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        children: [
          // Spacer aligned with beat header.
          const SizedBox(height: 22),
          for (var i = 0; i < lanes.length; i++)
            _LaneLabel(
              label: labels[lanes[i].laneId] ?? lanes[i].laneId.name,
              color: colors[lanes[i].laneId] ?? MuzicianTheme.textSecondary,
              activeCount: lanes[i].activeTicks.length,
              isEven: i % 2 == 0,
              menuKey: Key('laneFillMenu_${lanes[i].laneId.name}'),
              onMenu: () => onLaneMenu(lanes[i].laneId),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: Render the menu button inside `_LaneLabel`**

Replace the whole `_LaneLabel` class with this version (adds the `menuKey` + `onMenu` button; the active-count text still shows when present):

```dart
class _LaneLabel extends StatelessWidget {
  final String label;
  final Color color;
  final int activeCount;
  final bool isEven;
  final Key menuKey;
  final VoidCallback onMenu;

  const _LaneLabel({
    required this.label,
    required this.color,
    required this.activeCount,
    required this.isEven,
    required this.menuKey,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kLaneHeight,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (activeCount > 0)
            Text(
              '$activeCount',
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          IconButton(
            key: menuKey,
            tooltip: 'Fill lane',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            iconSize: 16,
            color: MuzicianTheme.textMuted,
            icon: const Icon(Icons.tune),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: Add the `_LaneFillSheet` widget**

Append this widget at the end of `lib/features/song/drum_machine_editor.dart`:

```dart
/// Bottom-sheet controls for filling a single drum lane.
///
/// Offers musical "every-N" presets (derived from [ticksPerBeat]) with a start
/// offset, a Euclidean generator (hits + rotation), and clear-lane. Each action
/// emits the resulting tick list via [onApply] and closes the sheet.
class _LaneFillSheet extends StatefulWidget {
  final int lengthTicks;
  final int ticksPerBeat;
  final void Function(List<int> ticks) onApply;

  const _LaneFillSheet({
    required this.lengthTicks,
    required this.ticksPerBeat,
    required this.onApply,
  });

  @override
  State<_LaneFillSheet> createState() => _LaneFillSheetState();
}

class _LaneFillSheetState extends State<_LaneFillSheet> {
  int _offset = 0;
  late int _hits;
  int _rotation = 0;

  @override
  void initState() {
    super.initState();
    // Default to one hit per beat, clamped to the pattern length.
    final beats = (widget.lengthTicks / widget.ticksPerBeat).floor();
    _hits = beats < 1 ? 1 : beats;
  }

  /// Distinct, ascending every-N step options derived from the beat size.
  List<int> get _stepOptions {
    final beat = widget.ticksPerBeat;
    final raw = <int>{
      1,
      if (beat ~/ 2 >= 1) beat ~/ 2,
      beat,
      beat * 2,
    }.where((s) => s <= widget.lengthTicks).toList()
      ..sort();
    return raw;
  }

  String _stepLabel(int step) {
    final beat = widget.ticksPerBeat;
    if (step == 1) return 'Every step';
    if (step == beat ~/ 2) return 'Every ½ beat';
    if (step == beat) return 'Every beat';
    if (step == beat * 2) return 'Every 2 beats';
    return 'Every $step steps';
  }

  void _applyAndClose(List<int> ticks) {
    widget.onApply(ticks);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FillSectionLabel('Every'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in _stepOptions)
                ActionChip(
                  key: Key('fillEvery_$step'),
                  label: Text(_stepLabel(step)),
                  backgroundColor: MuzicianTheme.orange.withValues(alpha: 0.18),
                  side: BorderSide(
                    color: MuzicianTheme.orange.withValues(alpha: 0.5),
                  ),
                  labelStyle: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  onPressed: () =>
                      _applyAndClose(everyN(widget.lengthTicks, step,
                          offset: _offset)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _StepperRow(
            label: 'Offset',
            value: _offset,
            minusKey: const Key('offsetMinus'),
            plusKey: const Key('offsetPlus'),
            onMinus: _offset > 0 ? () => setState(() => _offset--) : null,
            onPlus: _offset < widget.lengthTicks - 1
                ? () => setState(() => _offset++)
                : null,
          ),
          const Divider(height: 28, color: Colors.white24),
          const _FillSectionLabel('Euclidean'),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Hits',
            value: _hits,
            minusKey: const Key('euclidHitsMinus'),
            plusKey: const Key('euclidHitsPlus'),
            onMinus: _hits > 1 ? () => setState(() => _hits--) : null,
            onPlus: _hits < widget.lengthTicks
                ? () => setState(() => _hits++)
                : null,
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Rotate',
            value: _rotation,
            minusKey: const Key('euclidRotMinus'),
            plusKey: const Key('euclidRotPlus'),
            onMinus: _rotation > 0 ? () => setState(() => _rotation--) : null,
            onPlus: _rotation < widget.lengthTicks - 1
                ? () => setState(() => _rotation++)
                : null,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('fillEuclidApply'),
              style: FilledButton.styleFrom(
                backgroundColor: MuzicianTheme.orange,
              ),
              onPressed: () => _applyAndClose(
                euclid(widget.lengthTicks, _hits, rotation: _rotation),
              ),
              child: const Text('Apply Euclidean'),
            ),
          ),
          const Divider(height: 28, color: Colors.white24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('fillClear'),
              onPressed: () => _applyAndClose(const []),
              child: const Text('Clear lane'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FillSectionLabel extends StatelessWidget {
  final String text;
  const _FillSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: MuzicianTheme.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final Key minusKey;
  final Key plusKey;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _StepperRow({
    required this.label,
    required this.value,
    required this.minusKey,
    required this.plusKey,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          key: minusKey,
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline),
          color: MuzicianTheme.textSecondary,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          key: plusKey,
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline),
          color: MuzicianTheme.textSecondary,
        ),
      ],
    );
  }
}
```

- [ ] **Step 10: Run the widget test to verify it passes**

Run: `flutter test test/features/song/drum_fill_menu_test.dart`
Expected: PASS (3/3).

If the euclid expectation in the test fails, print the actual value and reconcile it against `euclid(16, 3)` from Task 1 (the math is deterministic — update the expected list to match the implementation, do not change the algorithm).

- [ ] **Step 11: Run the existing drum editor tests for regressions**

Run: `flutter test test/features/song/drum_machine_editor_test.dart test/features/songwriter/songwriter_sheet_drum_lane_test.dart`
Expected: PASS — the `_DrumGrid` / `_LaneLabelsColumn` / `_LaneLabel` changes are additive; the Song-feature `DrumMachineEditor` and Songwriter sheet drive `DrumMachineEditorBody` unchanged apart from the new (always-present) menu button.

If a test asserts an exact widget count in the lane label column that now includes the extra `IconButton`, update that assertion to match the new tree.

- [ ] **Step 12: Commit**

```bash
git add lib/features/song/drum_machine_editor.dart test/features/song/drum_fill_menu_test.dart
git commit -m "feat(drum): per-lane every-N + Euclidean fill menu"
```

---

## Task 3: Full-suite regression + manual smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the drum + songwriter + rules suites**

Run: `flutter test test/schema/rules/ test/features/song/ test/features/songwriter/ test/store/drum_pattern_playback_store_test.dart`
Expected: PASS.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/schema/rules/drum_fill_rules.dart lib/features/song/drum_machine_editor.dart`
Expected: No new issues.

- [ ] **Step 3: Manual smoke check**

Run: `flutter run -d <preferred-device>`
- Open a drum pattern (Song feature drum clip, or a Songwriter drum lane block).
- Tap the **tune** icon on the Kick lane → the fill sheet opens.
- Tap **Every beat** → kick cells light up on beats 1/2/3/4; the sheet closes.
- Reopen on Snare → set **Hits** to 3 → **Apply Euclidean** → three evenly spaced snare hits.
- Reopen on Kick → **Clear lane** → kick empties.
- Confirm the Song-feature drum editor behaves identically (shared body).

- [ ] **Step 4: Final commit (if smoke check required any fix)**

```bash
git add -A
git commit -m "fix(drum): address fill-menu smoke-test findings"
```

---

## Self-Review Notes

- **Spec coverage (Component 2):** every-N with offset (Task 1 `everyN` + chips), Euclidean with rotation (Task 1 `euclid` + Apply), clear-lane (Task 2 `fillClear`), per-lane placement (menu button per lane), musical labels derived from `ticksPerBeat` (`_stepLabel`). Pure ops are Flutter-free and independently tested (Task 1).
- **Shared-editor safety:** the fill menu lives in `DrumMachineEditorBody`, so both the Song `DrumMachineEditor` and the Songwriter drum sheet inherit it. The change is additive — no caller signature changes. (`onLaneMenu` is internal to the file.)
- **Replace vs merge:** fills replace the target lane's `activeTicks` (predictable sequencer behavior); Clear lane covers removal. No merge mode — out of scope.
- **Type consistency:** `everyN(int, int, {int offset})` and `euclid(int, int, {int rotation})` are referenced identically in the sheet. `_applyLaneTicks(DrumLaneId, List<int>)`, `onLaneMenu(DrumLaneId)`, `onApply(List<int>)` match across `_DrumMachineEditorBodyState` → `_DrumGrid` → `_LaneLabelsColumn` → `_LaneLabel` → `_LaneFillSheet`.
- **ticksPerBeat:** `ticksPerBeatForUnit(beatUnit) == beatUnit == 8 ? 2 : 4`; the sheet derives step options from the live value, so 6/8 patterns (ticksPerBeat = 2) still produce sensible chips.
- **No placeholders:** all code blocks are complete; the only deferred decision is reconciling the euclid test expectation against the deterministic implementation (Step 10 note), not a code gap.

---

## Out-of-scope reminders (do NOT do here)

- No backing audition (Phase 2), no presets/library (Phases 3–4).
- No new model fields, no persistence changes.
- No Song-feature behavior changes beyond inheriting the menu.
- No velocity/accents/swing.
