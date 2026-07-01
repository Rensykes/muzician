# Songwriter Section Ruler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-section ruler with a parked start playhead: tap/drag to set where playback starts, and the header Play button resumes from there.

**Architecture:** A `songwriterStartTickProvider` (Notifier<int>, default 0) holds the parked start tick and persists while idle. A new `SongwriterSectionRuler` widget renders a bar ruler per section, sets the provider on tap/drag (reusing `sectionBarGlobalTick`), draws a parked marker (via `activePositionForBar`) and overlays the live playhead (reusing `SongwriterRowPlayhead`). The header Play reads the provider for its `startTick`.

**Tech Stack:** Dart / Flutter, Riverpod `Notifier`, `CustomPaint`, `package:flutter_test`.

---

## File Structure

- `lib/store/songwriter_playback_store.dart` — **modify**: add `songwriterStartTickProvider`.
- `lib/features/songwriter/songwriter_section_ruler.dart` — **create**: the ruler widget + parked-marker + ruler painter.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — **modify**: insert the ruler above `_BarRow`.
- `lib/features/songwriter/songwriter_header.dart` — **modify**: Play reads the parked tick.
- `test/store/songwriter_playback_test.dart` — **modify**: provider tests.
- `test/features/songwriter/songwriter_section_ruler_test.dart` — **create**: ruler widget tests.

---

## Task 1: `songwriterStartTickProvider`

**Files:**
- Modify: `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_playback_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `main()` in `test/store/songwriter_playback_test.dart`:

```dart
  group('songwriterStartTickProvider', () {
    test('defaults to 0; setTick clamps negatives; reset returns to 0', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(songwriterStartTickProvider), 0);
      c.read(songwriterStartTickProvider.notifier).setTick(48);
      expect(c.read(songwriterStartTickProvider), 48);
      c.read(songwriterStartTickProvider.notifier).setTick(-5);
      expect(c.read(songwriterStartTickProvider), 0);
      c.read(songwriterStartTickProvider.notifier).reset();
      expect(c.read(songwriterStartTickProvider), 0);
    });
  });
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: FAIL — `songwriterStartTickProvider` undefined.

- [ ] **Step 3: Implement the provider**

In `lib/store/songwriter_playback_store.dart`, append at the end of the file (after `songwriterActivePositionProvider`):

```dart
/// The parked playback start tick, set by the per-section ruler and read by the
/// header Play button. Persists while idle (the transport state resets on stop).
/// 0 means "top of the song".
class SongwriterStartTickNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void setTick(int tick) => state = tick < 0 ? 0 : tick;
  void reset() => state = 0;
}

final songwriterStartTickProvider =
    NotifierProvider<SongwriterStartTickNotifier, int>(
      SongwriterStartTickNotifier.new,
    );
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/store/songwriter_playback_test.dart`
Expected: PASS (all, incl. pre-existing).

- [ ] **Step 5: Format + commit**

```bash
dart format lib/store/songwriter_playback_store.dart test/store/songwriter_playback_test.dart
git add lib/store/songwriter_playback_store.dart test/store/songwriter_playback_test.dart
git commit -m "feat(songwriter): songwriterStartTickProvider for parked playback start"
```

---

## Task 2: `SongwriterSectionRuler` widget

**Files:**
- Create: `lib/features/songwriter/songwriter_section_ruler.dart`
- Test: `test/features/songwriter/songwriter_section_ruler_test.dart`

Context: reuses `sectionBarGlobalTick(sections, config, sectionId, localBar, {instanceIndex})` and `activePositionForBar(sections, globalBar) → SongwriterActivePosition?{sectionId, instanceIndex, localBar}` (both in `songwriter_playback_rules.dart`), `songwriterProvider` (project state; `.sections`, `.config`), `songwriterStartTickProvider` (Task 1), and `SongwriterRowPlayhead` (existing, `songwriter_playhead.dart`). `SongwriterConfig` has `ticksPerBeat` + `beatsPerBar`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/songwriter/songwriter_section_ruler_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/songwriter/songwriter_section_ruler.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  testWidgets('tapping a ruler bar parks the start tick at that bar', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(
          label: 'A',
          lengthBars: 4,
        );
    final section = container.read(songwriterProvider).sections.first;
    final cfg = container.read(songwriterProvider).config;
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SongwriterSectionRuler(section: section, instanceIndex: 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 4 bars over 400px → 100px/bar. Tap at localX 250 → bar 2.
    final topLeft = tester.getTopLeft(
      find.byKey(Key('sectionRuler_${section.id}_0')),
    );
    await tester.tapAt(topLeft + const Offset(250, 9));
    await tester.pump();

    expect(container.read(songwriterStartTickProvider), 2 * measureTicks);
  });

  testWidgets('parked marker shows only when the start tick is in this section', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 2);
    sw.addSection(label: 'B', lengthBars: 2);
    final sections = container.read(songwriterProvider).sections;
    final cfg = container.read(songwriterProvider).config;
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
    // Park in section B (global bar 2).
    container.read(songwriterStartTickProvider.notifier).setTick(
          2 * measureTicks,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 400,
                  child: SongwriterSectionRuler(
                    section: sections[0],
                    instanceIndex: 0,
                  ),
                ),
                SizedBox(
                  width: 400,
                  child: SongwriterSectionRuler(
                    section: sections[1],
                    instanceIndex: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Marker in B (parked there), not in A.
    expect(find.byKey(const Key('sectionRulerMarker')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/features/songwriter/songwriter_section_ruler_test.dart`
Expected: FAIL — `SongwriterSectionRuler` / file does not exist.

- [ ] **Step 3: Implement the widget**

Create `lib/features/songwriter/songwriter_section_ruler.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart' show SongSection;
import '../../schema/rules/songwriter_playback_rules.dart'
    show activePositionForBar, sectionBarGlobalTick;
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import 'songwriter_playhead.dart';

/// A bar ruler at the top of a section card. Tapping/dragging parks the playback
/// start ([songwriterStartTickProvider]); the header Play button resumes from
/// it. Draws a parked marker at the set bar and overlays the live
/// [SongwriterRowPlayhead] during playback.
class SongwriterSectionRuler extends ConsumerWidget {
  const SongwriterSectionRuler({
    super.key,
    required this.section,
    required this.instanceIndex,
  });
  final SongSection section;
  final int instanceIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(
      songwriterProvider.select((p) => p.sections),
    );
    final config = ref.watch(songwriterProvider.select((p) => p.config));
    final startTick = ref.watch(songwriterStartTickProvider);
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final measureTicks = config.ticksPerBeat * config.beatsPerBar;

    int? markerBar;
    final pos = activePositionForBar(sections, startTick ~/ measureTicks);
    if (pos != null &&
        pos.sectionId == section.id &&
        pos.instanceIndex == instanceIndex) {
      markerBar = pos.localBar;
    }

    void setStartFromDx(double dx, double width) {
      final cell = width / bars;
      final b = (dx / cell).floor().clamp(0, bars - 1);
      ref
          .read(songwriterStartTickProvider.notifier)
          .setTick(
            sectionBarGlobalTick(
              sections,
              config,
              section.id,
              b,
              instanceIndex: instanceIndex,
            ),
          );
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final cell = w / bars;
        return GestureDetector(
          key: Key('sectionRuler_${section.id}_$instanceIndex'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setStartFromDx(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => setStartFromDx(d.localPosition.dx, w),
          child: SizedBox(
            height: 18,
            width: w,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RulerPainter(
                      bars: bars,
                      lineColor: Colors.white.withValues(alpha: 0.18),
                      numberColor: MuzicianTheme.textMuted,
                    ),
                  ),
                ),
                if (markerBar != null)
                  Positioned(
                    left: markerBar * cell,
                    top: 0,
                    bottom: 0,
                    child: const SizedBox(
                      key: Key('sectionRulerMarker'),
                      width: 10,
                      child: CustomPaint(painter: _MarkerPainter()),
                    ),
                  ),
                Positioned.fill(
                  child: SongwriterRowPlayhead(
                    sectionId: section.id,
                    instanceIndex: instanceIndex,
                    rowStartBar: 0,
                    barsInRow: bars,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.bars,
    required this.lineColor,
    required this.numberColor,
  });
  final int bars;
  final Color lineColor;
  final Color numberColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars < 1 ? 1 : bars;
    final cell = size.width / n;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final x = i * cell;
      if (i > 0) canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(color: numberColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, 2));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.bars != bars ||
      old.lineColor != lineColor ||
      old.numberColor != numberColor;
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = MuzicianTheme.sky;
    // A small downward flag at the top-left plus a full-height line.
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(8, 0)
      ..lineTo(0, 7)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, size.height),
      p..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => false;
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/features/songwriter/songwriter_section_ruler_test.dart`
Expected: PASS (both).

- [ ] **Step 5: Analyze + format + commit**

Run: `flutter analyze lib/features/songwriter/songwriter_section_ruler.dart` → No issues.

```bash
dart format lib/features/songwriter/songwriter_section_ruler.dart test/features/songwriter/songwriter_section_ruler_test.dart
git add lib/features/songwriter/songwriter_section_ruler.dart test/features/songwriter/songwriter_section_ruler_test.dart
git commit -m "feat(songwriter): SongwriterSectionRuler — tap/drag to park the start"
```

---

## Task 3: Wire the ruler + header Play

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
- Modify: `lib/features/songwriter/songwriter_header.dart`

- [ ] **Step 1: Insert the ruler above `_BarRow`**

In `lib/features/songwriter/songwriter_screen_sheet.dart`, in the section-instance `build` (the `Column` whose `children:` begins with the optional `if (section.repeat > 1)` label then `_BarRow(`), insert the ruler before `_BarRow(`:

```dart
        SongwriterSectionRuler(
          section: section,
          instanceIndex: instanceIndex,
        ),
        const SizedBox(height: 6),
        _BarRow(
```

Add the import at the top of the file:

```dart
import 'songwriter_section_ruler.dart';
```

- [ ] **Step 2: Header Play reads the parked tick**

In `lib/features/songwriter/songwriter_header.dart`, change the Play button `onTap` body:

```dart
              onTap: () {
                final t = ref.read(songwriterPlaybackProvider.notifier);
                playing ? t.stopPlayback() : t.startPlayback();
              },
```
to:
```dart
              onTap: () {
                final t = ref.read(songwriterPlaybackProvider.notifier);
                if (playing) {
                  t.stopPlayback();
                } else {
                  t.startPlayback(
                    startTick: ref.read(songwriterStartTickProvider),
                  );
                }
              },
```

`songwriterStartTickProvider` is exported from `songwriter_playback_store.dart`, which the header already imports (it uses `songwriterPlaybackProvider`); no new import needed.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/songwriter/songwriter_screen_sheet.dart lib/features/songwriter/songwriter_header.dart`
Expected: No issues.

- [ ] **Step 4: Format + commit**

```bash
dart format lib/features/songwriter/songwriter_screen_sheet.dart lib/features/songwriter/songwriter_header.dart
git add lib/features/songwriter/songwriter_screen_sheet.dart lib/features/songwriter/songwriter_header.dart
git commit -m "feat(songwriter): section ruler in the card + header Play from parked start"
```

---

## Task 4: Full suite + analyze

**Files:** none (verification only)

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: PASS (no regressions).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: No new issues. (A pre-existing `info` in `test/store/songwriter_scatter_test.dart` is unrelated.)

- [ ] **Step 3: Manual device check (not automated)**

Open a section → tap/drag its ruler → the parked marker moves to that bar → press header Play → playback starts from that bar. During playback the live playhead sweeps the ruler. Verify a section with only audio/drum lanes (no chord lane) now has a working start control.

---

## Self-Review (completed during planning)

- **Spec coverage:** parked-start state → Task 1. Ruler widget (bar cells, tap/drag set, parked marker, live playhead) → Task 2. Per-section insertion → Task 3 Step 1. Header Play reads parked tick → Task 3 Step 2. Keep bar-menu "Play from here" → untouched (no task removes it). Testing → Tasks 1, 2, 4.
- **Placeholder scan:** none — all steps have concrete code/commands.
- **Type consistency:** `songwriterStartTickProvider` / `SongwriterStartTickNotifier.setTick/reset` defined in Task 1 and used in Tasks 2–3; `SongwriterSectionRuler({section, instanceIndex})` defined in Task 2 and constructed identically in Task 3; `sectionBarGlobalTick(...)`, `activePositionForBar(...)`, `SongwriterRowPlayhead(sectionId, instanceIndex, rowStartBar, barsInRow)` match their sources.
