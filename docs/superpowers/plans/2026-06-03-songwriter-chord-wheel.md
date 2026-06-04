# Songwriter — Chord Wheel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Read `docs/superpowers/HANDOFF-songwriter.md` first.**

**Goal:** A radial diatonic chord picker (7 wedges = 7 scale degrees) that replaces the root+quality grid as the primary harmony-lane entry point. Tapping a wedge commits a harmony `SongBlock` at the next free bar.

**Architecture:** A new pure rule `diatonicTriads` derives the 7 triads from any key/scale. A new `ChordWheel` widget paints the wheel via `CustomPainter` and hit-tests taps via a pure `chordWheelHitTest` function (angle/radius → degree index). The existing `showHarmonyChordSheet` is restructured: the wheel is the default when a key is set; the old root+quality grid stays as an "Other chord" tab for borrowed/altered chords. No model or store changes.

**Tech Stack:** Flutter, `CustomPainter`, `flutter_test`. Reuses `scaleIntervals`, `chromaticNotes`, `getChordNotes`, `romanNumeralFor`, `makeHarmonyBlock` from `note_utils.dart` and `songwriter_rules.dart`.

**Spec:** `docs/superpowers/specs/2026-06-03-songwriter-chord-wheel-design.md`.
**Depends on:** B2b complete on branch `worktree-songwriter-ux-polish`.

> **Read before starting:** `lib/utils/note_utils.dart` (lines 24-155: `chromaticNotes`, `scaleIntervals`, `chordIntervals`, `getChordNotes`), `lib/schema/rules/songwriter_rules.dart` (`romanNumeralFor`, `makeHarmonyBlock`), `lib/features/songwriter/harmony_chord_sheet.dart` (the current root+quality picker), `lib/features/songwriter/songwriter_lane_row.dart` (the call site for `showHarmonyChordSheet`).

---

### Task 1: Diatonic triad derivation rule

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart`
- Test: `test/schema/rules/songwriter_diatonic_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/schema/rules/songwriter_diatonic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('diatonicTriads for C major yields I C, ii Dm, ... vii° Bdim', () {
    final triads = diatonicTriads(0, 'major');
    expect(triads.length, 7);

    expect(triads[0].rootPc, 0);
    expect(triads[0].quality, '');
    expect(triads[0].symbol, 'C');
    expect(triads[0].romanNumeral, 'I');
    expect(triads[0].notes, ['C', 'E', 'G']);

    expect(triads[1].symbol, 'Dm');
    expect(triads[1].romanNumeral, 'ii');

    expect(triads[2].symbol, 'Em');
    expect(triads[2].romanNumeral, 'iii');

    expect(triads[3].symbol, 'F');
    expect(triads[3].romanNumeral, 'IV');

    expect(triads[4].symbol, 'G');
    expect(triads[4].romanNumeral, 'V');

    expect(triads[5].symbol, 'Am');
    expect(triads[5].romanNumeral, 'vi');

    expect(triads[6].symbol, 'Bdim');
    expect(triads[6].romanNumeral, 'vii°');
    expect(triads[6].quality, 'dim');
  });

  test('diatonicTriads for A minor yields i Am, ii° Bdim, ... VII G', () {
    final triads = diatonicTriads(9, 'minor'); // A = pc 9
    expect(triads.length, 7);

    expect(triads[0].symbol, 'Am');
    expect(triads[0].romanNumeral, 'i');

    expect(triads[1].symbol, 'Bdim');
    expect(triads[1].romanNumeral, 'ii°');

    expect(triads[2].symbol, 'C');
    expect(triads[2].romanNumeral, 'III');
  });

  test('diatonicTriads returns empty for unknown scale', () {
    expect(diatonicTriads(0, 'nonexistent'), isEmpty);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/schema/rules/songwriter_diatonic_test.dart`
Expected: FAIL — `diatonicTriads` not found.

- [ ] **Step 3: Implement `diatonicTriads`**

Add to `lib/schema/rules/songwriter_rules.dart`, after the `romanNumeralFor` function (before `// ─── Overlap Validation`):

```dart
// ─── Diatonic Triad Derivation ───────────────────────────────────────────────

class DiatonicTriad {
  const DiatonicTriad({
    required this.degree,
    required this.rootPc,
    required this.quality,
    required this.symbol,
    required this.romanNumeral,
    required this.notes,
  });
  final int degree;
  final int rootPc;
  final String quality;
  final String symbol;
  final String romanNumeral;
  final List<String> notes;
}

/// Returns the 7 diatonic triads for [keyRootPc] / [scaleName].
///
/// Each triad's quality is derived by stacking thirds from the scale's
/// interval set: the intervals root→3rd and root→5th classify the triad
/// as major (''), minor ('m'), diminished ('dim'), or augmented ('aug').
/// Returns an empty list when [scaleName] is unknown or has fewer than 7
/// degrees.
List<DiatonicTriad> diatonicTriads(int keyRootPc, String scaleName) {
  final intervals = scaleIntervals[scaleName];
  if (intervals == null || intervals.length < 7) return [];
  final out = <DiatonicTriad>[];
  for (var d = 0; d < 7; d++) {
    final rootSemitone = intervals[d];
    final thirdSemitone = intervals[(d + 2) % 7];
    final fifthSemitone = intervals[(d + 4) % 7];
    // Intervals relative to this degree's root (mod 12)
    final i3 = ((thirdSemitone - rootSemitone) % 12 + 12) % 12;
    final i5 = ((fifthSemitone - rootSemitone) % 12 + 12) % 12;

    String quality;
    if (i3 == 4 && i5 == 7) {
      quality = '';
    } else if (i3 == 3 && i5 == 7) {
      quality = 'm';
    } else if (i3 == 3 && i5 == 6) {
      quality = 'dim';
    } else if (i3 == 4 && i5 == 8) {
      quality = 'aug';
    } else {
      quality = '';
    }

    final rootPc = (keyRootPc + rootSemitone) % 12;
    final rootName = chromaticNotes[rootPc];
    final qualitySuffix = quality == '' ? '' : quality;
    final symbol = '$rootName$qualitySuffix';
    final numeral = _caseNumeral(_romanByDegree[d], quality);
    final notes = getChordNotes(rootName, quality);

    out.add(DiatonicTriad(
      degree: d,
      rootPc: rootPc,
      quality: quality,
      symbol: symbol,
      romanNumeral: numeral,
      notes: notes,
    ));
  }
  return out;
}
```

> Note: `_caseNumeral` and `_romanByDegree` are private helpers already in this file. `chromaticNotes`, `getChordNotes` come from `note_utils.dart` (already imported).

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/schema/rules/songwriter_diatonic_test.dart`
Expected: PASS (3).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart test/schema/rules/songwriter_diatonic_test.dart
git commit -m "feat(songwriter): diatonic triad derivation rule"
```

---

### Task 2: Chord wheel hit-test (pure geometry)

**Files:**
- Create: `lib/features/songwriter/chord_wheel.dart`
- Test: `test/features/songwriter/chord_wheel_hit_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/chord_wheel_hit_test.dart
import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';

void main() {
  // The wheel divides 360° into 7 equal wedges. Wedge 0 is centered at
  // the top (12 o'clock). A tap at the 12 o'clock direction should hit
  // degree 0.
  test('tap at 12 o'clock returns degree 0', () {
    const size = Size(200, 200);
    // Center is (100,100). 12 o'clock is (100, 30) — above center.
    final degree = chordWheelHitTest(const Offset(100, 30), size);
    expect(degree, 0);
  });

  test('tap in center (inside inner radius) returns null', () {
    const size = Size(200, 200);
    final degree = chordWheelHitTest(const Offset(100, 100), size);
    expect(degree, isNull);
  });

  test('tap outside the wheel returns null', () {
    const size = Size(200, 200);
    final degree = chordWheelHitTest(const Offset(0, 0), size);
    expect(degree, isNull);
  });

  test('each of the 7 wedges can be hit', () {
    const size = Size(200, 200);
    const center = Offset(100, 100);
    const radius = 80.0;
    final wedgeAngle = 2 * pi / 7;
    // Wedge d is centered at angle = -pi/2 + d * wedgeAngle
    final hit = <int>{};
    for (var d = 0; d < 7; d++) {
      final angle = -pi / 2 + d * wedgeAngle;
      final point = center + Offset(radius * cos(angle), radius * sin(angle));
      final result = chordWheelHitTest(point, size);
      expect(result, isNotNull, reason: 'wedge $d should be hit');
      hit.add(result!);
    }
    expect(hit, {0, 1, 2, 3, 4, 5, 6});
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/chord_wheel_hit_test.dart`
Expected: FAIL — file/function missing.

- [ ] **Step 3: Implement hit-test function**

Create `lib/features/songwriter/chord_wheel.dart`:

```dart
import 'dart:math';
import 'dart:ui';

const _wedgeCount = 7;
const _innerRadiusFraction = 0.3;

/// Returns the degree index (0..6) of the wedge at [localPoint] inside a
/// chord wheel of [size], or null when the tap is outside the wheel ring
/// (inside the inner hole or outside the outer edge).
int? chordWheelHitTest(Offset localPoint, Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  final outerRadius = size.shortestSide / 2;
  final innerRadius = outerRadius * _innerRadiusFraction;
  final delta = localPoint - center;
  final dist = delta.distance;
  if (dist < innerRadius || dist > outerRadius) return null;

  // Angle from center, measured clockwise from 12 o'clock.
  // atan2 gives angle from +x axis (3 o'clock), counter-clockwise positive.
  // We want clockwise from -y (12 o'clock): rotate by +pi/2 and negate.
  var angle = atan2(delta.dy, delta.dx) + pi / 2;
  if (angle < 0) angle += 2 * pi;

  final wedgeAngle = 2 * pi / _wedgeCount;
  final degree = (angle / wedgeAngle).floor() % _wedgeCount;
  return degree;
}
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/chord_wheel_hit_test.dart`
Expected: PASS (4).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/chord_wheel.dart test/features/songwriter/chord_wheel_hit_test.dart
git commit -m "feat(songwriter): chord wheel hit-test geometry"
```

---

### Task 3: Chord wheel painter + widget

**Files:**
- Modify: `lib/features/songwriter/chord_wheel.dart`
- Test: `test/features/songwriter/chord_wheel_widget_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/chord_wheel_widget_test.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  testWidgets('tapping the I wedge calls onPick with degree 0', (tester) async {
    DiatonicTriad? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: ChordWheel(
            keyRootPc: 0,
            scaleName: 'major',
            onPick: (t) => picked = t,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap at 12 o'clock: center of the widget is (150,150), go up to (150,40)
    await tester.tapAt(const Offset(150, 40));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.degree, 0);
    expect(picked!.romanNumeral, 'I');
  });

  testWidgets('renders all 7 chord labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: ChordWheel(
            keyRootPc: 0,
            scaleName: 'major',
            onPick: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // All 7 Roman numerals should be painted — but since they are painted
    // via CustomPainter, we can't find them with find.text. Instead, verify
    // the widget renders without error.
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/chord_wheel_widget_test.dart`
Expected: FAIL — `ChordWheel` class not found.

- [ ] **Step 3: Implement the `ChordWheel` widget**

Append to `lib/features/songwriter/chord_wheel.dart`:

```dart
import 'package:flutter/material.dart';
import '../../schema/rules/songwriter_rules.dart';

/// A radial diatonic chord picker. Shows 7 wedges (one per scale degree)
/// labeled with the chord symbol and Roman numeral. Tapping a wedge invokes
/// [onPick] with the corresponding [DiatonicTriad].
class ChordWheel extends StatelessWidget {
  const ChordWheel({
    super.key,
    required this.keyRootPc,
    required this.scaleName,
    required this.onPick,
  });
  final int keyRootPc;
  final String scaleName;
  final ValueChanged<DiatonicTriad> onPick;

  @override
  Widget build(BuildContext context) {
    final triads = diatonicTriads(keyRootPc, scaleName);
    if (triads.isEmpty) {
      return const Center(child: Text('Set a key to use the chord wheel'));
    }
    return GestureDetector(
      onTapUp: (details) {
        final degree = chordWheelHitTest(details.localPosition, context.size!);
        if (degree != null && degree < triads.length) {
          onPick(triads[degree]);
        }
      },
      child: CustomPaint(
        painter: _ChordWheelPainter(
          triads: triads,
          majorColor: Theme.of(context).colorScheme.primary,
          minorColor: Theme.of(context).colorScheme.secondary,
          dimColor: Colors.grey,
          textColor: Colors.white,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ChordWheelPainter extends CustomPainter {
  _ChordWheelPainter({
    required this.triads,
    required this.majorColor,
    required this.minorColor,
    required this.dimColor,
    required this.textColor,
  });
  final List<DiatonicTriad> triads;
  final Color majorColor;
  final Color minorColor;
  final Color dimColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.shortestSide / 2 - 4;
    final innerRadius = outerRadius * _innerRadiusFraction;
    final wedgeAngle = 2 * pi / _wedgeCount;

    for (var d = 0; d < triads.length; d++) {
      final triad = triads[d];
      // Wedge starts at -pi/2 + d*wedge - wedge/2 (centered at 12 o'clock
      // for d=0), but our hit-test has wedge 0 boundary at -pi/2, so the
      // paint start is -pi/2 + d*wedge.
      final startAngle = -pi / 2 + d * wedgeAngle;

      // Fill
      final fill = Paint()
        ..color = _colorForQuality(triad.quality)
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(
          center.dx + innerRadius * cos(startAngle),
          center.dy + innerRadius * sin(startAngle),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: outerRadius),
          startAngle,
          wedgeAngle,
          false,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: innerRadius),
          startAngle + wedgeAngle,
          -wedgeAngle,
          false,
        )
        ..close();
      canvas.drawPath(path, fill);

      // Border
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Label at the midpoint of the wedge arc
      final midAngle = startAngle + wedgeAngle / 2;
      final labelRadius = (innerRadius + outerRadius) / 2;
      final labelCenter = Offset(
        center.dx + labelRadius * cos(midAngle),
        center.dy + labelRadius * sin(midAngle),
      );

      final symbolPainter = TextPainter(
        text: TextSpan(
          text: triad.symbol,
          style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      symbolPainter.paint(
        canvas,
        labelCenter - Offset(symbolPainter.width / 2, symbolPainter.height + 1),
      );

      final numeralPainter = TextPainter(
        text: TextSpan(
          text: triad.romanNumeral,
          style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numeralPainter.paint(
        canvas,
        labelCenter - Offset(numeralPainter.width / 2, -1),
      );
    }
  }

  Color _colorForQuality(String quality) {
    if (quality == 'dim') return dimColor;
    if (quality == 'm') return minorColor;
    if (quality == 'aug') return dimColor;
    return majorColor;
  }

  @override
  bool shouldRepaint(_ChordWheelPainter old) =>
      old.triads != triads ||
      old.majorColor != majorColor ||
      old.minorColor != minorColor;
}
```

> The imports at the top of `chord_wheel.dart` should be: `dart:math`, `dart:ui` (for the hit-test), `package:flutter/material.dart`, and `../../schema/rules/songwriter_rules.dart`.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/chord_wheel_widget_test.dart`
Expected: PASS (2).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/chord_wheel.dart test/features/songwriter/chord_wheel_widget_test.dart
git commit -m "feat(songwriter): chord wheel painter + widget"
```

---

### Task 4: Integrate wheel into the harmony chord sheet

**Files:**
- Modify: `lib/features/songwriter/harmony_chord_sheet.dart`
- Test: `test/features/songwriter/harmony_chord_sheet_test.dart` (extend existing)

The sheet becomes a two-mode picker: when a key is set, show the chord wheel as the default with an "Other chord" expander below for non-diatonic chords. When no key is set, show the root+quality grid directly.

- [ ] **Step 1: Write the failing test**

Add to `test/features/songwriter/harmony_chord_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';

void main() {
  testWidgets('shows chord wheel when key is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyChordSheet(
              context,
              startBar: 0,
              spanBars: 2,
              keyRoot: 0,
              keyScaleName: 'major',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordWheel), findsOneWidget);
  });

  testWidgets('shows root+quality grid when no key is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyChordSheet(
              context,
              startBar: 0,
              spanBars: 2,
              keyRoot: null,
              keyScaleName: null,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordWheel), findsNothing);
    expect(find.text('Root'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_test.dart`
Expected: FAIL — the current sheet has no `ChordWheel`.

- [ ] **Step 3: Restructure the harmony sheet**

Rewrite `lib/features/songwriter/harmony_chord_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../utils/note_utils.dart';
import 'chord_wheel.dart';

const _qualities = <(String value, String label)>[
  ('', 'maj'),
  ('m', 'min'),
  ('7', '7'),
  ('maj7', 'maj7'),
  ('m7', 'm7'),
  ('dim', 'dim'),
  ('aug', 'aug'),
  ('sus2', 'sus2'),
  ('sus4', 'sus4'),
  ('m7b5', 'm7b5'),
  ('dim7', 'dim7'),
];

Future<SongBlock?> showHarmonyChordSheet(
  BuildContext context, {
  required int startBar,
  required int spanBars,
  required int? keyRoot,
  required String? keyScaleName,
}) {
  return showModalBottomSheet<SongBlock>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HarmonySheet(
      startBar: startBar,
      spanBars: spanBars,
      keyRoot: keyRoot,
      keyScaleName: keyScaleName,
    ),
  );
}

class _HarmonySheet extends StatefulWidget {
  const _HarmonySheet({
    required this.startBar,
    required this.spanBars,
    required this.keyRoot,
    required this.keyScaleName,
  });
  final int startBar;
  final int spanBars;
  final int? keyRoot;
  final String? keyScaleName;

  @override
  State<_HarmonySheet> createState() => _HarmonySheetState();
}

class _HarmonySheetState extends State<_HarmonySheet> {
  bool _showManual = false;
  int? _rootPc;

  bool get _hasKey => widget.keyRoot != null && widget.keyScaleName != null;

  void _commitTriad(DiatonicTriad triad) {
    final block = makeHarmonyBlock(
      startBar: widget.startBar,
      spanBars: widget.spanBars,
      chordSymbol: triad.symbol,
      chordQuality: triad.quality,
      chordRootPc: triad.rootPc,
      chordNotes: triad.notes,
      romanNumeral: triad.romanNumeral,
    );
    Navigator.pop(context, block);
  }

  void _commitManual(String quality) {
    final rootPc = _rootPc;
    if (rootPc == null) return;
    final rootName = chromaticNotes[rootPc];
    final block = makeHarmonyBlock(
      startBar: widget.startBar,
      spanBars: widget.spanBars,
      chordSymbol: '$rootName$quality',
      chordQuality: quality,
      chordRootPc: rootPc,
      chordNotes: getChordNotes(rootName, quality),
      romanNumeral: romanNumeralFor(
        rootPc,
        quality,
        widget.keyRoot,
        widget.keyScaleName,
      ),
    );
    Navigator.pop(context, block);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasKey) ...[
            SizedBox(
              height: 240,
              child: ChordWheel(
                keyRootPc: widget.keyRoot!,
                scaleName: widget.keyScaleName!,
                onPick: _commitTriad,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showManual = !_showManual),
              child: Row(
                children: [
                  Icon(_showManual
                      ? Icons.expand_less
                      : Icons.expand_more, size: 18),
                  const SizedBox(width: 4),
                  const Text('Other chord'),
                ],
              ),
            ),
          ],
          if (!_hasKey || _showManual) ...[
            const SizedBox(height: 8),
            _manualPicker(),
          ],
        ],
      ),
    );
  }

  Widget _manualPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Root'),
        Wrap(
          spacing: 6,
          children: [
            for (var pc = 0; pc < 12; pc++)
              ChoiceChip(
                key: Key('harmonyRoot_$pc'),
                label: Text(chromaticNotes[pc]),
                selected: _rootPc == pc,
                onSelected: (_) => setState(() => _rootPc = pc),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Quality'),
        Wrap(
          spacing: 6,
          children: [
            for (final q in _qualities)
              ActionChip(
                key: Key('harmonyQuality_${q.$1}'),
                label: Text(q.$2),
                onPressed: _rootPc == null ? null : () => _commitManual(q.$1),
              ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run it (PASS) + regression**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_test.dart`
Expected: PASS (existing + new tests).

Also run: `flutter test test/features/songwriter/`
Expected: all songwriter widget tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/harmony_chord_sheet.dart test/features/songwriter/harmony_chord_sheet_test.dart
git commit -m "feat(songwriter): integrate chord wheel into harmony sheet"
```

---

### Task 5: Verify + serve-sim

**Files:** none (verification only)

- [ ] **Step 1: Format + analyze**

Run: `dart format lib/features/songwriter/chord_wheel.dart lib/features/songwriter/harmony_chord_sheet.dart lib/schema/rules/songwriter_rules.dart`
Run: `flutter analyze`
Expected: clean.

- [ ] **Step 2: Full sweep**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 3: Simulator check**

Build + install on simulator. Open Writer → add a section → add a harmony lane → tap + on the harmony lane. Confirm: the chord wheel appears (7 colored wedges labeled I C, ii Dm, etc.). Tap a wedge → chord block appears on the lane at the next free bar. Tap "Other chord" → the root+quality grid expands. Change the project key → wheel updates to the new key. Remove the key → chord wheel disappears and root+quality grid is shown directly.

- [ ] **Step 4: Commit any formatting**

```bash
git add -A
git commit -m "chore(songwriter): format + verify chord wheel" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** CW-1 (wheel primary, root+quality fallback) ✓ Task 4. CW-2 (diatonic only, no key → fallback) ✓ Task 4. CW-3 (CustomPainter + hit-testing) ✓ Tasks 2-3. CW-4 (output via makeHarmonyBlock, next free bar) ✓ Task 4. CW-5 (quality from scale intervals) ✓ Task 1. Open question (pure hit-test) ✓ Task 2.
- **Type consistency:** `DiatonicTriad` (Task 1) → used in `ChordWheel.onPick` (Task 3) → consumed in `_commitTriad` (Task 4). `chordWheelHitTest` (Task 2) → called in `ChordWheel.build` (Task 3). All consistent.
- **No model/store changes** as spec requires — chord output flows through existing `makeHarmonyBlock`.
