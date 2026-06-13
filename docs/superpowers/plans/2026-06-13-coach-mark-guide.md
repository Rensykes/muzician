# Interactive Coach-Mark Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A help-button-launched coach-mark tour for the Song and Writer pages — a spotlight overlay that highlights real UI elements one at a time with a tooltip.

**Architecture:** A page-agnostic overlay engine (`coach_overlay.dart`) inserts a single `OverlayEntry` that dims the screen, punches a rounded spotlight around the current target widget (located via `GlobalKey` → `RenderBox`), and shows a glass tooltip card with Back/Skip/Next. Each page declares a `List<CoachStep>` and attaches the keys at its composition sites; a `?` header button calls `startCoachTour`. Steps whose target is unmounted are skipped.

**Tech Stack:** Flutter, `OverlayEntry`, `CustomPainter` (`Path.combine`), `flutter_test`. Spec: `docs/superpowers/specs/2026-06-13-coach-mark-guide-design.md`.

**Verified facts:**
- No coach package; app already uses `OverlayEntry` (`lib/features/songwriter/songwriter_undo.dart`).
- Theme (`lib/theme/muzician_theme.dart`): `surface` `0xFF0A0F1E`, `glassBorder`, `sky`, `textPrimary`, `textSecondary`, `textDim`.
- Song screen `lib/features/song/song_screen.dart` — `_SongScreenState` (ConsumerStatefulWidget); header Row has Add-Track `IconButton`, Save `IconButton`, a `PopupMenuButton<String>` (New/Import/Export); transport via `_SongTransportStrip(project, playback)`; timeline via `Expanded(child: … SongArrangerTimeline …)`; compact mode at `MediaQuery.sizeOf(context).height < 500`.
- Writer: `SongwriterHeader` (ConsumerWidget, `lib/features/songwriter/songwriter_header.dart`) with `IconBtn` from `lib/features/_mockup_shell.dart` (`IconBtn({key, required icon, required onTap, color})`); sheet `SongwriterScreenSheet` (`lib/features/songwriter/songwriter_screen_sheet.dart`) composes `SongwriterHeader`, an `Expanded` body `ListView`, and `_AddSectionRule`.

**Key-ownership rule:** the widget that *builds* a target wraps it in `KeyedSubtree(key: globalKey, child: …)` (or sets `key:` directly on an `IconButton`/`PopupMenuButton`). Headers only *trigger* the tour.

**Consolidated step lists** (stable anchors only — matches the spec's "fall back to always-present anchors"):
- **Song (4):** transport · timeline (ruler + lanes + clips) · Add Track · overflow ⋮.
- **Writer (3):** header (key/tempo/play/metronome/⋮) · sheet body (bars → chords, section ⋯) · Add section.

---

### Task 1: Coach-mark overlay engine

**Files:**
- Create: `lib/ui/core/coach_overlay.dart`
- Test: `test/ui/coach_overlay_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/ui/core/coach_overlay.dart';

void main() {
  testWidgets('tour shows steps, advances, and dismisses', (tester) async {
    final keyA = GlobalKey();
    final keyB = GlobalKey();
    late List<CoachStep> steps;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              steps = [
                CoachStep(key: keyA, title: 'First', body: 'Step one body'),
                CoachStep(key: keyB, title: 'Second', body: 'Step two body'),
              ];
              return Column(
                children: [
                  Container(key: keyA, width: 80, height: 40),
                  Container(key: keyB, width: 80, height: 40),
                  ElevatedButton(
                    onPressed: () => startCoachTour(context, steps),
                    child: const Text('go'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('a step with an unmounted key is skipped', (tester) async {
    final keyA = GlobalKey();
    final ghost = GlobalKey(); // never attached to a widget
    final keyC = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                Container(key: keyA, width: 80, height: 40),
                Container(key: keyC, width: 80, height: 40),
                ElevatedButton(
                  onPressed: () => startCoachTour(context, [
                    CoachStep(key: keyA, title: 'A', body: 'a'),
                    CoachStep(key: ghost, title: 'Ghost', body: 'g'),
                    CoachStep(key: keyC, title: 'C', body: 'c'),
                  ]),
                  child: const Text('go'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    // Ghost skipped → lands on C.
    expect(find.text('C'), findsOneWidget);
    expect(find.text('Ghost'), findsNothing);
  });

  testWidgets('no-op when every key is unmounted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => startCoachTour(context, [
                CoachStep(key: GlobalKey(), title: 'X', body: 'x'),
              ]),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('X'), findsNothing);
  });
}
```

- [ ] **Step 2: Run — expect FAIL (file missing)**

Run: `flutter test test/ui/coach_overlay_test.dart`
Expected: compile error, `coach_overlay.dart` not found.

- [ ] **Step 3: Implement the engine**

Create `lib/ui/core/coach_overlay.dart`:

```dart
/// Help-button coach-mark tour: a spotlight overlay that walks the user
/// through real on-screen elements one step at a time.
library;

import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// One step: highlights [key]'s widget with a [title]/[body] tooltip.
class CoachStep {
  const CoachStep({required this.key, required this.title, required this.body});
  final GlobalKey key;
  final String title;
  final String body;
}

/// Starts a coach tour over the current screen. No-op when [steps] is empty or
/// no step's target is currently mounted.
void startCoachTour(BuildContext context, List<CoachStep> steps) {
  final mountable = steps
      .where((s) => s.key.currentContext != null)
      .toList(growable: false);
  if (mountable.isEmpty) return;
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachTour(steps: mountable, onDismiss: entry.remove),
  );
  overlay.insert(entry);
}

class _CoachTour extends StatefulWidget {
  const _CoachTour({required this.steps, required this.onDismiss});
  final List<CoachStep> steps;
  final VoidCallback onDismiss;

  @override
  State<_CoachTour> createState() => _CoachTourState();
}

class _CoachTourState extends State<_CoachTour> {
  int _index = 0;
  Size? _startSize;

  Rect? _rectFor(CoachStep step) {
    final ctx = step.key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _advance() {
    var next = _index + 1;
    while (next < widget.steps.length && _rectFor(widget.steps[next]) == null) {
      next++;
    }
    if (next >= widget.steps.length) {
      widget.onDismiss();
    } else {
      setState(() => _index = next);
    }
  }

  void _back() {
    var prev = _index - 1;
    while (prev >= 0 && _rectFor(widget.steps[prev]) == null) {
      prev--;
    }
    if (prev >= 0) setState(() => _index = prev);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _startSize ??= size;
    if (_startSize != size) {
      // Layout changed (e.g. rotation): bail rather than show stale rects.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDismiss());
      return const SizedBox.shrink();
    }
    final step = widget.steps[_index];
    final rect = _rectFor(step);
    if (rect == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
      return const SizedBox.shrink();
    }
    final spot = rect.inflate(8);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _advance,
            child: CustomPaint(painter: _ScrimPainter(spot)),
          ),
        ),
        _buildCard(size, spot, step),
      ],
    );
  }

  Widget _buildCard(Size size, Rect spot, CoachStep step) {
    const cardWidth = 300.0;
    final placeBelow = spot.bottom + 12 + 170 < size.height;
    var left = spot.center.dx - cardWidth / 2;
    left = left.clamp(12.0, size.width - cardWidth - 12);
    final isFirst = _index == 0;
    final isLast = _index == widget.steps.length - 1;
    return Positioned(
      top: placeBelow ? spot.bottom + 12 : null,
      bottom: placeBelow ? null : size.height - spot.top + 12,
      left: left,
      width: cardWidth,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MuzicianTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MuzicianTheme.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < widget.steps.length; i++) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? MuzicianTheme.sky
                            : MuzicianTheme.textDim,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Skip'),
                  ),
                  if (!isFirst)
                    TextButton(onPressed: _back, child: const Text('Back')),
                  FilledButton(
                    onPressed: isLast ? widget.onDismiss : _advance,
                    child: Text(isLast ? 'Done' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.spot);
  final Rect spot;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(spot, const Radius.circular(12)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, scrim, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(spot, const Radius.circular(12)),
      Paint()
        ..color = MuzicianTheme.sky
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.spot != spot;
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `flutter test test/ui/coach_overlay_test.dart`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/core/coach_overlay.dart test/ui/coach_overlay_test.dart
git commit -m "feat(ui): coach-mark overlay engine"
```

---

### Task 2: Song tour — steps, keys, launch button

**Files:**
- Create: `lib/features/song/song_coach_steps.dart`
- Modify: `lib/features/song/song_screen.dart`
- Test: `test/features/song/song_coach_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_screen.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('help button starts the Song coach tour', (tester) async {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('songHelpButton')));
    await tester.pumpAndSettle();

    // First Song step is the transport.
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect FAIL (no `songHelpButton`)**

Run: `flutter test test/features/song/song_coach_test.dart`

- [ ] **Step 3: Create the step list**

Create `lib/features/song/song_coach_steps.dart`:

```dart
/// Coach-tour steps for the Song page.
library;

import 'package:flutter/widgets.dart';

import '../../ui/core/coach_overlay.dart';

/// The GlobalKeys the Song screen attaches to its tour targets.
class SongCoachKeys {
  SongCoachKeys();
  final transport = GlobalKey();
  final timeline = GlobalKey();
  final addTrack = GlobalKey();
  final overflow = GlobalKey();
}

List<CoachStep> songCoachSteps(SongCoachKeys k) => [
  CoachStep(
    key: k.transport,
    title: 'Transport',
    body:
        'Play, loop, and practice here. Drag the ruler for a loop region; the '
        'chips set practice tempo (½×/¾×), metronome, count-in, and snap.',
  ),
  CoachStep(
    key: k.timeline,
    title: 'Timeline',
    body:
        'Long-press a lane to add a clip; tap a clip to open the action bar '
        '(split, transpose, trim, duplicate, move). Tap the ruler to seek, '
        'double-tap it to drop a marker.',
  ),
  CoachStep(
    key: k.addTrack,
    title: 'Add tracks',
    body: 'Create note, drum, or audio tracks.',
  ),
  CoachStep(
    key: k.overflow,
    title: 'More',
    body: 'Start a new song, import an arrangement from Writer, or export a WAV.',
  ),
];
```

- [ ] **Step 4: Wire keys + the help button into `song_screen.dart`**

Add imports near the existing feature imports:

```dart
import '../../ui/core/coach_overlay.dart';
import 'song_coach_steps.dart';
```

In `_SongScreenState`, add a field:

```dart
  final _coachKeys = SongCoachKeys();
```

Attach keys at the composition sites:
- Add-Track `IconButton`: add `key: _coachKeys.addTrack`.
- The `PopupMenuButton<String>` (New/Import/Export): add `key: _coachKeys.overflow`.
- Transport: wrap the existing `_SongTransportStrip(project: project, playback: playback)` as
  `KeyedSubtree(key: _coachKeys.transport, child: _SongTransportStrip(project: project, playback: playback))`.
- Timeline body: wrap the `Expanded(child: …)` that holds the arranger/empty-state in
  `KeyedSubtree(key: _coachKeys.timeline, child: Expanded(…))` — i.e. put the
  `KeyedSubtree` *outside* the `Expanded` is invalid (Expanded must be a direct
  child of the Column); instead put it *inside*: `Expanded(child: KeyedSubtree(key: _coachKeys.timeline, child: <the current child>))`.

Add the help `IconButton` to the header Row, immediately before the Add-Track
button (full layout). It is keyed so the test and tour can find it:

```dart
                  IconButton(
                    key: const Key('songHelpButton'),
                    tooltip: 'Guide',
                    icon: const Icon(
                      Icons.help_outline_rounded,
                      color: MuzicianTheme.sky,
                    ),
                    onPressed: () =>
                        startCoachTour(context, songCoachSteps(_coachKeys)),
                  ),
```

(The header already renders in both full and compact modes via the same Row, so
the single button covers landscape too.)

- [ ] **Step 5: Run — expect PASS**

Run: `flutter test test/features/song/song_coach_test.dart && flutter test test/features/song/`
Expected: new test passes; existing Song tests unaffected.

- [ ] **Step 6: Commit**

```bash
git add lib/features/song/song_coach_steps.dart lib/features/song/song_screen.dart test/features/song/song_coach_test.dart
git commit -m "feat(song): coach-mark tour + help button"
```

---

### Task 3: Writer tour — steps, keys, launch button

**Files:**
- Create: `lib/features/songwriter/songwriter_coach_steps.dart`
- Modify: `lib/features/songwriter/songwriter_header.dart`, `lib/features/songwriter/songwriter_screen_sheet.dart`
- Test: `test/features/songwriter/songwriter_coach_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('help button starts the Writer coach tour', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('writerHelpButton')));
    await tester.pumpAndSettle();

    expect(find.text('Header'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect FAIL (no `writerHelpButton`)**

Run: `flutter test test/features/songwriter/songwriter_coach_test.dart`

- [ ] **Step 3: Create the step list**

Create `lib/features/songwriter/songwriter_coach_steps.dart`:

```dart
/// Coach-tour steps for the Writer page.
library;

import 'package:flutter/widgets.dart';

import '../../ui/core/coach_overlay.dart';

/// The GlobalKeys the Writer sheet attaches to its tour targets.
class WriterCoachKeys {
  WriterCoachKeys();
  final header = GlobalKey();
  final body = GlobalKey();
  final addSection = GlobalKey();
}

List<CoachStep> writerCoachSteps(WriterCoachKeys k) => [
  CoachStep(
    key: k.header,
    title: 'Header',
    body:
        'Set the key and tempo, play the arrangement, and toggle the '
        'metronome. The ⋮ menu has save / load and structure editing.',
  ),
  CoachStep(
    key: k.body,
    title: 'Sections',
    body:
        'Tap a bar to drop a chord from the wheel. A section’s ⋮ menu adds '
        'drum lanes and sets repeats.',
  ),
  CoachStep(
    key: k.addSection,
    title: 'Build structure',
    body: 'Add sections to lay out the whole song, verse by chorus.',
  ),
];
```

- [ ] **Step 4: Add an `onStartTour` hook + help button to the header**

In `lib/features/songwriter/songwriter_header.dart`, add a field to
`SongwriterHeader`:

```dart
  final VoidCallback? onStartTour;
```

and add it to the constructor:

```dart
  const SongwriterHeader({
    super.key,
    this.onOpenSaveLoad,
    this.onOpenStructure,
    this.onStartTour,
  });
```

In the title row (the non-compact branch), add a help `IconBtn` just before the
existing `IconBtn(icon: Icons.more_vert, …)`:

```dart
                  if (onStartTour != null)
                    IconBtn(
                      key: const Key('writerHelpButton'),
                      icon: Icons.help_outline_rounded,
                      onTap: onStartTour!,
                    ),
```

In compact mode the title row is hidden, so also pass the help trigger through
the config strip: extend `_WriterConfigStrip` with `final VoidCallback? onHelp;`
(constructor param) and, in its `Row`, before the `if (onOverflow != null)`
block, add:

```dart
            if (onHelp != null)
              IconBtn(
                key: const Key('writerHelpButton'),
                icon: Icons.help_outline_rounded,
                onTap: onHelp!,
              ),
```

Wire it from `SongwriterHeader.build` where `_WriterConfigStrip(...)` is
constructed: pass `onHelp: compact ? onStartTour : null` (so the button shows in
the strip only in compact mode — the title row already has it otherwise). Keep
exactly one `writerHelpButton` in the tree per layout.

- [ ] **Step 5: Own the keys + trigger in the sheet**

In `lib/features/songwriter/songwriter_screen_sheet.dart`:

Add imports:

```dart
import '../../ui/core/coach_overlay.dart';
import 'songwriter_coach_steps.dart';
```

`SongwriterScreenSheet` is a `ConsumerWidget`; convert it to a
`ConsumerStatefulWidget` so it can own stable keys (mirror the standard
Flutter stateful pattern). Add:

```dart
  final _coachKeys = WriterCoachKeys();
```

Wire targets:
- Wrap the `SongwriterHeader(…)` in `KeyedSubtree(key: _coachKeys.header, child: SongwriterHeader(… onStartTour: () => startCoachTour(context, writerCoachSteps(_coachKeys)) …))`.
- Wrap the body `Expanded`'s child (the `LayoutBuilder`) in
  `KeyedSubtree(key: _coachKeys.body, child: <LayoutBuilder…>)` (inside the
  `Expanded`, since `Expanded` must stay a direct child of the `Column`).
- Wrap the `_AddSectionRule(key: const Key('songwriterAddSection'), …)` in
  `KeyedSubtree(key: _coachKeys.addSection, child: _AddSectionRule(…))`.

- [ ] **Step 6: Run — expect PASS**

Run: `flutter test test/features/songwriter/songwriter_coach_test.dart && flutter test test/features/songwriter/`
Expected: new test passes; existing Writer tests unaffected (the header-overflow
test and sheet tests still find their widgets).

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_coach_steps.dart lib/features/songwriter/songwriter_header.dart lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_coach_test.dart
git commit -m "feat(songwriter): coach-mark tour + help button"
```

---

### Task 4: Phase gate

- [ ] **Step 1: Full verification**

Run: `flutter analyze && flutter test`
Expected: analyze clean; full suite green.

- [ ] **Step 2: serve-sim verification**

Boot the app (serve-sim). Song tab: tap the `?` button → spotlight frames the
transport; Next steps through timeline → Add Track → overflow; Skip/Done closes.
Writer tab: `?` → header → sections → add-section. Rotate to landscape, re-open
each tour, confirm the card stays on-screen and the spotlight tracks the right
elements.

- [ ] **Step 3: Docs**

Append a short "Interactive guide" note to `docs/song_writer_guide.md`: a `?`
button in the Song and Writer headers launches a step-through coach tour of the
page.

- [ ] **Step 4: Commit**

```bash
git add docs/song_writer_guide.md
git commit -m "docs: note the in-app coach-mark guide"
```
