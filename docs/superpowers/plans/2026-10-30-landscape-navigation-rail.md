# Landscape Navigation Rail and Instrument Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On landscape viewports, replace the bottom navigation bar with a compact left rail. On tall wide viewports, give Fretboard/Piano a full-width, modestly scaled canvas with a multi-column inspector dock below it.

**Architecture:** A new `lib/ui/app_navigation.dart` owns the destination model, the bottom bar (moved from `main.dart`) and the new rail. `_AppShell` chooses between them with `useNavigationRail(size)` and keeps the workspace `IndexedStack` under a `GlobalKey`, so switching never recreates workspaces. `_StudioInstrumentWorkspace` gains a `dock` layout tier. The canvas is wrapped in a new `ScaledInstrumentBoard` (a `FittedBox` transform), so painters and gestures stay untouched. Inspector panels get per-panel `GlobalKey`s so their state survives tier changes.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-30-landscape-navigation-rail-design.md`

**Repository rules (read before starting):** `AGENTS.md`, `.github/instructions/dart-n-flutter.instructions.md`, `DESIGN.md` sections "Shared workspace structure" and "Fretboard and Piano". Studio UI resolves colors with `StudioPalette.of(context)`. Keep 44px minimum targets. Do not touch the legacy (non-Studio) instrument branch, Piano Roll, Writer or Song internals.

**Task order:** Tasks 1 and 2 are independent and may run in parallel. Task 3 depends on Task 2. Task 4 depends on Tasks 1–3.

**Verification commands used throughout:**
- Format: `dart format <changed paths>`
- Analyze: `flutter analyze`
- Tests: `flutter test <path>`

---

### Task 1: Adaptive navigation (rail ↔ bottom bar)

**Files:**
- Create: `lib/ui/app_navigation.dart`
- Create: `test/ui/app_navigation_test.dart`
- Create: `test/main_navigation_rail_test.dart`
- Modify: `lib/main.dart`. This touches the `Scaffold` returned at the end of `_AppShellState.build` (currently ~lines 233–320, `body:` + `bottomNavigationBar:`) and deletes the `_NavTab` class (~lines 572–653).

- [ ] **Step 1: Write the failing unit/widget tests**

Create `test/ui/app_navigation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:muzician/ui/app_navigation.dart';

List<AppNavDestination> _destinations(List<int> taps) => [
  AppNavDestination(
    tabIndex: 0,
    icon: Icons.music_note,
    label: 'Fretboard',
    onTap: () => taps.add(0),
  ),
  AppNavDestination(
    tabIndex: 1,
    icon: Icons.piano,
    label: 'Piano',
    onTap: () => taps.add(1),
  ),
  AppNavDestination(
    tabIndex: 2,
    icon: Icons.bar_chart_rounded,
    label: 'Roll',
    onTap: () => taps.add(2),
  ),
  const AppNavDestination(
    tabIndex: 3,
    icon: Icons.article_outlined,
    label: 'Song',
    semanticHint: 'Temporarily unavailable',
  ),
  AppNavDestination(
    tabIndex: 4,
    icon: Icons.edit_outlined,
    label: 'Writer',
    onTap: () => taps.add(4),
  ),
  AppNavDestination(
    tabIndex: 5,
    icon: Icons.settings_outlined,
    label: 'Settings',
    onTap: () => taps.add(5),
    pinnedToBottom: true,
  ),
];

Future<void> _pump(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    StudioThemeSource(
      variant: AppThemeVariant.studio,
      child: MaterialApp(
        theme: StudioTheme.data(AppThemeVariant.studio),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('useNavigationRail', () {
    for (final (size, expected) in const [
      (Size(390, 844), false),
      (Size(844, 390), true),
      (Size(1024, 768), true),
      (Size(1440, 900), true),
      (Size(599, 400), false),
      (Size(700, 800), false),
    ]) {
      test('$size -> $expected', () {
        expect(useNavigationRail(size), expected);
      });
    }
  });

  testWidgets('rail lists workspaces, pins Settings, disables Song', (
    tester,
  ) async {
    final taps = <int>[];
    await _pump(
      tester,
      const Size(1440, 900),
      Row(
        children: [
          StudioNavigationRail(
            destinations: _destinations(taps),
            selectedIndex: 4,
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );

    expect(find.byKey(const Key('studioNavigationRail')), findsOneWidget);
    for (final label in [
      'Fretboard',
      'Piano',
      'Roll',
      'Song',
      'Writer',
      'Settings',
    ]) {
      expect(find.byKey(ValueKey('nav_$label')), findsOneWidget);
    }
    final writerBottom = tester
        .getRect(find.byKey(const ValueKey('nav_Writer')))
        .bottom;
    final settingsTop = tester
        .getRect(find.byKey(const ValueKey('nav_Settings')))
        .top;
    expect(settingsTop, greaterThan(writerBottom + 100));

    final railWidth = tester
        .getSize(find.byKey(const Key('studioNavigationRail')))
        .width;
    expect(railWidth, kStudioRailWidth);
    final itemSize = tester.getSize(find.byKey(const ValueKey('nav_Piano')));
    expect(itemSize.height, greaterThanOrEqualTo(44));
    expect(itemSize.width, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const ValueKey('nav_Piano')));
    await tester.tap(find.byKey(const ValueKey('nav_Song')));
    await tester.tap(find.byKey(const ValueKey('nav_Settings')));
    expect(taps, [1, 5]);

    final semantics = tester.ensureSemantics();
    final song = tester.getSemantics(find.byKey(const ValueKey('nav_Song')));
    expect(song.hint, 'Temporarily unavailable');
    semantics.dispose();
  });

  testWidgets('rail scrolls instead of overflowing on short landscape', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(740, 300),
      Row(
        children: [
          StudioNavigationRail(destinations: _destinations([]), selectedIndex: 0),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('nav_Fretboard')), findsOneWidget);
  });

  testWidgets('bottom bar renders all destinations with nav keys', (
    tester,
  ) async {
    final taps = <int>[];
    await _pump(
      tester,
      const Size(390, 844),
      Align(
        alignment: Alignment.bottomCenter,
        child: StudioBottomNavBar(
          destinations: _destinations(taps),
          selectedIndex: 0,
        ),
      ),
    );
    expect(find.byKey(const Key('studioBottomNavBar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav_Writer')));
    expect(taps, [4]);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ui/app_navigation_test.dart`
Expected: FAIL. Compilation error: `app_navigation.dart` not found.

- [ ] **Step 3: Implement `lib/ui/app_navigation.dart`**

The item visuals are moved verbatim from `_NavTab` in `lib/main.dart`. Keep the lock badge, tooltip, semantics and colors.

```dart
import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';

/// Logical width of the landscape navigation rail, excluding safe-area inset.
const double kStudioRailWidth = 80;

/// Landscape viewports at least 600 wide use the rail; others use the bar.
bool useNavigationRail(Size size) =>
    size.width >= 600 && size.width > size.height;

@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.tabIndex,
    required this.icon,
    required this.label,
    this.onTap,
    this.semanticHint,
    this.pinnedToBottom = false,
  });

  final int tabIndex;
  final IconData icon;
  final String label;

  /// Null renders the destination disabled with a lock badge.
  final VoidCallback? onTap;
  final String? semanticHint;

  /// Rail only: render below the workspace destinations.
  final bool pinnedToBottom;
}

class StudioBottomNavBar extends StatelessWidget {
  const StudioBottomNavBar({
    super.key = const Key('studioBottomNavBar'),
    required this.destinations,
    required this.selectedIndex,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StudioPalette.of(context).surface.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: Color(0x4094A3B8), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final destination in destinations)
                Expanded(
                  child: _NavItem(
                    destination: destination,
                    active: destination.tabIndex == selectedIndex,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioNavigationRail extends StatelessWidget {
  const StudioNavigationRail({
    super.key = const Key('studioNavigationRail'),
    required this.destinations,
    required this.selectedIndex,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;

  static const double _itemHeight = 56;

  @override
  Widget build(BuildContext context) {
    Widget item(AppNavDestination destination) => SizedBox(
      height: _itemHeight,
      width: double.infinity,
      child: _NavItem(
        destination: destination,
        active: destination.tabIndex == selectedIndex,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: StudioPalette.of(context).surface.withValues(alpha: 0.96),
        border: const Border(
          right: BorderSide(color: Color(0x4094A3B8), width: 0.5),
        ),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: kStudioRailWidth,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      for (final d in destinations)
                        if (!d.pinnedToBottom) item(d),
                      const Spacer(),
                      for (final d in destinations)
                        if (d.pinnedToBottom) item(d),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.active});

  final AppNavDestination destination;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    final onTap = destination.onTap;
    final hint = destination.semanticHint;
    final tab = Semantics(
      key: ValueKey('nav_${destination.label}'),
      button: true,
      enabled: onTap != null,
      selected: active,
      label: destination.label,
      hint: hint,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onTap == null)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(destination.icon, size: 24, color: palette.textMuted),
                    Positioned(
                      right: -2,
                      bottom: -1,
                      child: Icon(
                        Icons.lock_outline,
                        size: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                )
              else
                Icon(
                  destination.icon,
                  size: 24,
                  color: active ? palette.sky : palette.textMuted,
                ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? palette.sky : palette.textMuted,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return hint == null
        ? tab
        : Tooltip(message: hint, excludeFromSemantics: true, child: tab);
  }
}
```

Note: `selected: active` is a small accessibility addition. Check whether any existing test asserts the old semantics flags of `nav_*` (e.g. `test/main_startup_test.dart` around the `nav_Song` assertions near line 204). If one asserts exact flags, update the expectation to include `isSelected` only when that tab is active.

- [ ] **Step 4: Run unit/widget tests to verify they pass**

Run: `flutter test test/ui/app_navigation_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Write the failing shell test**

Create `test/main_navigation_rail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $finder.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'landscape uses the rail, portrait the bar, and switching keeps workspaces',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
      await _pumpUntil(tester, find.byType(IndexedStack));

      expect(find.byKey(const Key('studioNavigationRail')), findsOneWidget);
      expect(find.byKey(const Key('studioBottomNavBar')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('nav_Roll')));
      await tester.pump(const Duration(milliseconds: 100));
      final stack = find.byType(IndexedStack).first;
      expect(tester.widget<IndexedStack>(stack).index, 2);
      final elementBefore = tester.element(stack);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('studioNavigationRail')), findsNothing);
      expect(find.byKey(const Key('studioBottomNavBar')), findsOneWidget);
      final stackAfter = find.byType(IndexedStack).first;
      expect(tester.widget<IndexedStack>(stackAfter).index, 2);
      expect(identical(tester.element(stackAfter), elementBefore), isTrue);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('studioNavigationRail')), findsOneWidget);
      expect(
        identical(tester.element(find.byType(IndexedStack).first), elementBefore),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/main_navigation_rail_test.dart`
Expected: FAIL. `studioNavigationRail` is not found.

- [ ] **Step 7: Integrate into `lib/main.dart`**

1. Add `import 'ui/app_navigation.dart';` next to the other `ui/` imports.
2. In `_AppShellState`, add a field: `final _workspaceStackKey = GlobalKey(debugLabel: 'workspaceStack');`
3. Add this method to `_AppShellState`:

```dart
  List<AppNavDestination> _navDestinations() => [
    AppNavDestination(
      tabIndex: 0,
      icon: Icons.music_note,
      label: 'Fretboard',
      onTap: () => _setTab(0),
    ),
    AppNavDestination(
      tabIndex: 1,
      icon: Icons.piano,
      label: 'Piano',
      onTap: () => _setTab(1),
    ),
    AppNavDestination(
      tabIndex: 2,
      icon: Icons.bar_chart_rounded,
      label: 'Roll',
      onTap: () => _setTab(2),
    ),
    const AppNavDestination(
      tabIndex: songWorkspaceTabIndex,
      icon: Icons.article_outlined,
      label: 'Song',
      semanticHint: 'Temporarily unavailable',
    ),
    AppNavDestination(
      tabIndex: 4,
      icon: Icons.edit_outlined,
      label: 'Writer',
      onTap: () => _setTab(4),
    ),
    AppNavDestination(
      tabIndex: 5,
      icon: Icons.settings_outlined,
      label: 'Settings',
      onTap: () => _setTab(5),
      pinnedToBottom: true,
    ),
  ];
```

`songWorkspaceTabIndex` comes from `store/app_bootstrap.dart`, which `main.dart` already imports. If it is imported with a `show` clause, add the symbol to it.

4. Replace the `return Scaffold(...)` at the end of `build` with the following. The `IndexedStack` children list is unchanged; copy it exactly from the current code.

```dart
    final showNavigation =
        !(_hydrating || _recoveryRequired != null || _startupFailure != null);
    final railMode =
        showNavigation && useNavigationRail(MediaQuery.sizeOf(context));
    final destinations = _navDestinations();
    final workspaces = KeyedSubtree(
      key: _workspaceStackKey,
      child: IndexedStack(
        index: _tabIndex,
        children: [
          // ...existing six children, unchanged...
        ],
      ),
    );
    return Scaffold(
      body: !showNavigation
          ? _buildStartupView()
          : railMode
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioNavigationRail(
                  destinations: destinations,
                  selectedIndex: _tabIndex,
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    child: workspaces,
                  ),
                ),
              ],
            )
          : workspaces,
      bottomNavigationBar: showNavigation && !railMode
          ? StudioBottomNavBar(
              destinations: destinations,
              selectedIndex: _tabIndex,
            )
          : null,
    );
```

5. Delete the `_NavTab` class and its `// ── Nav Tab ──` header comment from `main.dart`.

- [ ] **Step 8: Run shell + existing navigation tests**

Run: `flutter test test/main_navigation_rail_test.dart test/ui/app_navigation_test.dart test/main_startup_test.dart test/features/instrument_shared/linked_instrument_edit_target_test.dart test/features/instrument_shared/studio_instrument_app_test.dart test/theme/studio_workspace_integration_test.dart test/theme/studio_route_theme_test.dart`
Expected: PASS. The default test surface is 800×600 (landscape), so many existing app tests now render the rail. They should still pass because `nav_*` keys are unchanged. If a test fails only because it measured bottom-bar geometry or assumed a bottom bar, set that test's viewport explicitly to a portrait size (e.g. `Size(390, 844)`) rather than changing production code. Report every such test change.

- [ ] **Step 9: Format, analyze, commit**

```bash
dart format lib/ui/app_navigation.dart lib/main.dart test/ui/app_navigation_test.dart test/main_navigation_rail_test.dart
flutter analyze
git add lib/ui/app_navigation.dart lib/main.dart test/ui/app_navigation_test.dart test/main_navigation_rail_test.dart
git commit -m "feat(shell): use a navigation rail on landscape viewports

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
Expected: `flutter analyze` reports no issues. Include any adjusted existing tests in the commit.

---

### Task 2: `ScaledInstrumentBoard` and `dockCanvasScale`

**Files:**
- Create: `lib/features/instrument_shared/scaled_instrument_board.dart`
- Create: `test/features/instrument_shared/scaled_instrument_board_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/scaled_instrument_board.dart';

void main() {
  group('dockCanvasScale', () {
    for (final (height, expected) in const [
      (600.0, 1.0),
      (640.0, 1.0),
      (840.0, 1.125),
      (1040.0, 1.25),
      (1400.0, 1.25),
    ]) {
      test('$height -> $expected', () {
        expect(dockCanvasScale(height), closeTo(expected, 1e-9));
      });
    }
  });

  testWidgets('scales child to fill width and maps taps to child space', (
    tester,
  ) async {
    Offset? tapped;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 500,
            height: 250,
            child: ScaledInstrumentBoard(
              scale: 1.25,
              baseHeight: 200,
              child: GestureDetector(
                key: const Key('board'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => tapped = details.localPosition,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    // Child is laid out at 400x200 logical and painted at 500x250.
    expect(tester.getSize(find.byKey(const Key('board'))), const Size(400, 200));
    expect(
      tester.getRect(find.byKey(const Key('board'))),
      const Rect.fromLTWH(0, 0, 500, 250),
    );

    await tester.tapAt(const Offset(250, 125));
    expect(tapped, isNotNull);
    expect(tapped!.dx, closeTo(200, 0.01));
    expect(tapped!.dy, closeTo(100, 0.01));
  });

  testWidgets('scale 1.0 is an identity layout', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 120,
            child: ScaledInstrumentBoard(
              scale: 1,
              baseHeight: 120,
              child: const SizedBox.expand(key: Key('board')),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('board'))), const Size(300, 120));
  });
}
```

Note: `tester.getSize` returns the untransformed render-box size, and `tester.getRect` returns global painted bounds. If `getRect` reports differently in this Flutter version, assert the painted size with `tester.getBottomRight(...)` == `Offset(500, 250)` instead.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/instrument_shared/scaled_instrument_board_test.dart`
Expected: FAIL. File not found.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/widgets.dart';

/// Canvas scale for the Fretboard/Piano dock tier: 1.0 at a 640px body,
/// growing linearly to 1.25 at 1040px and above.
double dockCanvasScale(double bodyHeight) =>
    1 + 0.25 * ((bodyHeight - 640) / 400).clamp(0.0, 1.0);

/// Lays [child] out at `maxWidth / scale` × [baseHeight] and paints it scaled
/// to fill the available width. `FittedBox` transforms hit testing, so
/// painters and gesture code stay in unscaled coordinates.
class ScaledInstrumentBoard extends StatelessWidget {
  const ScaledInstrumentBoard({
    super.key,
    required this.scale,
    required this.baseHeight,
    required this.child,
  });

  final double scale;
  final double baseHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: constraints.maxWidth / scale,
          height: baseHeight,
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/instrument_shared/scaled_instrument_board_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/instrument_shared/scaled_instrument_board.dart test/features/instrument_shared/scaled_instrument_board_test.dart
flutter analyze
git add lib/features/instrument_shared/scaled_instrument_board.dart test/features/instrument_shared/scaled_instrument_board_test.dart
git commit -m "feat(instruments): add scaled instrument board helper

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Fretboard/Piano dock tier

**Depends on:** Task 2.

**Files:**
- Modify: `lib/features/instrument_shared/instrument_screen.dart`. Changes are confined to `_StudioInstrumentWorkspaceState` (~lines 354–720).
- Modify: `test/features/instrument_shared/instrument_screen_v2_layout_test.dart`

Context for the implementer: `_StudioInstrumentWorkspaceState.build` builds `header`, `compactHeader`, `canvas` (a `KeyedSubtree(_canvasStateKey)` around `SizedBox(key: studioInstrumentCanvas, height: 212|226)`), `controls`, `selection`, `content`, and `buildInspector(...)`. A `LayoutBuilder` then picks `wide` (side inspector) or compact. The test harness in `instrument_screen_v2_layout_test.dart` adds a fake 56px bottom bar and 24px top padding, so the body height is `size.height - 80`.

- [ ] **Step 1: Write/adjust failing tests**

In `instrument_screen_v2_layout_test.dart`:

1. Add the import `import 'package:muzician/features/instrument_shared/scaled_instrument_board.dart';`.
2. In the existing parameterized test "canvas stays fixed while the inspector scrolls", replace `expect(before.height, guitar ? 212 : 226);` and the `if/else if/else` layout block with:

```dart
          final base = guitar ? 212.0 : 226.0;
          final bodyHeight = size.height - 80;
          // Mirrors the production tier: wide && !shortLandscape && body >= 640.
          final dock = size.width >= 700 && bodyHeight >= 640;
          expect(
            before.height,
            closeTo(dock ? base * dockCanvasScale(bodyHeight) : base, 0.01),
          );
          if (size == const Size(844, 390)) {
            expect(before.bottom, lessThanOrEqualTo(size.height - 56));
            expect(
              find.byKey(const Key('studioInstrumentContentScroll')),
              findsOneWidget,
            );
          } else if (dock) {
            expect(
              find.byKey(const Key('studioInstrumentDockLayout')),
              findsOneWidget,
            );
            expect(before.width, greaterThan(size.width - 64));
          } else if (size.width >= 700) {
            expect(
              find.byKey(const Key('studioInstrumentContentScroll')),
              findsOneWidget,
            );
          } else {
            expect(
              find.byKey(const Key('studioInstrumentCompactLayout')),
              findsOneWidget,
            );
          }
```

   Then add `Size(1024, 600)` (side tier) and `Size(1440, 900)` (three-column dock) to the size list. For 1440×900 the existing `_scrollPanel(tester, 'instrumentInspectorVoicingsScroll')` still works, because the Voicings scroll keeps its key in the dock.

3. Add these new tests inside `main()`:

```dart
  testWidgets('wide tall layout shows three dock columns without tabs', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final theme = ValueNotifier(AppThemeVariant.studio);
    addTearDown(theme.dispose);
    await _pumpScreen(
      tester,
      container,
      size: const Size(1440, 900),
      guitar: true,
      theme: theme,
    );

    expect(find.byKey(const Key('instrumentDock')), findsOneWidget);
    for (final label in ['Notes', 'Voicings', 'Setup']) {
      expect(
        find.byKey(Key('instrumentInspector${label}Scroll')),
        findsOneWidget,
      );
      expect(find.byKey(Key('instrumentInspector$label')), findsNothing);
    }
    expect(find.byKey(const Key('instrumentScale')), findsOneWidget);
    expect(find.byKey(const Key('instrumentLibrary')), findsOneWidget);
    expect(find.text('Setup item 0'), findsOneWidget);
    expect(find.text('Voicing item 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('instrumentInspectorToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Voicing item 0'), findsNothing);
    expect(find.byKey(const Key('instrumentLibrary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel state survives dock, side and compact tier changes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final theme = ValueNotifier(AppThemeVariant.studio);
    addTearDown(theme.dispose);
    final voicingsKey = GlobalKey<_PanelProbeState>();
    final setupKey = GlobalKey<_PanelProbeState>();

    Future<void> pumpAt(Size size) => _pumpScreen(
      tester,
      container,
      size: size,
      guitar: true,
      theme: theme,
      voicingsKey: voicingsKey,
      setupKey: setupKey,
    );

    await pumpAt(const Size(1440, 900));
    final voicingsState = voicingsKey.currentState;
    final setupState = setupKey.currentState;
    await _scrollPanel(tester, 'instrumentInspectorVoicingsScroll');
    final offset = _scrollOffset(tester, 'instrumentInspectorVoicingsScroll');
    expect(offset, greaterThan(0));

    await pumpAt(const Size(1024, 600)); // side tier, Voicings tab default
    expect(identical(voicingsKey.currentState, voicingsState), isTrue);
    expect(
      _scrollOffset(tester, 'instrumentInspectorVoicingsScroll'),
      offset,
    );

    await pumpAt(const Size(1024, 768)); // tabbed dock
    expect(identical(voicingsKey.currentState, voicingsState), isTrue);

    await pumpAt(const Size(1440, 900)); // back to three columns
    expect(identical(voicingsKey.currentState, voicingsState), isTrue);
    expect(identical(setupKey.currentState, setupState), isTrue);
    expect(
      _scrollOffset(tester, 'instrumentInspectorVoicingsScroll'),
      offset,
    );
    expect(tester.takeException(), isNull);
  });
```

`setupKey.currentState` is null while Setup is not the active tab in tabbed mode only if `IndexedStack` disposes it. It does not (`IndexedStack` keeps all children mounted), so identity holds.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/instrument_shared/instrument_screen_v2_layout_test.dart`
Expected: FAIL. `studioInstrumentDockLayout` / `instrumentDock` not found.

- [ ] **Step 3: Implement the dock tier in `_StudioInstrumentWorkspaceState`**

1. Add the import at the top of `instrument_screen.dart`: `import 'scaled_instrument_board.dart';`
2. Add the state field below `_selectionStateKey`:

```dart
  final _panelKeys = List.generate(
    3,
    (index) => GlobalKey(debugLabel: 'instrumentPanel$index'),
  );
```

3. Replace the `canvas` local with a builder. The board is always wrapped, so its subtree is stable across tiers:

```dart
    final baseCanvasHeight = s.modeSegment == null ? 226.0 : 212.0;
    Widget buildCanvas(double scale) => KeyedSubtree(
      key: _canvasStateKey,
      child: SizedBox(
        key: const Key('studioInstrumentCanvas'),
        height: baseCanvasHeight * scale,
        child: ScaledInstrumentBoard(
          scale: scale,
          baseHeight: baseCanvasHeight,
          child: s.board,
        ),
      ),
    );
```

   Remove the old `canvas` local. Construct `content` lazily: turn it into `Widget buildContent(Widget canvas) => Column(... children: [?controls, canvas, ?s.auditionControls, selection])`. Replace each use of `canvas`/`content` in the existing `wide` and compact branches with `buildCanvas(1)` / `buildContent(buildCanvas(1))`. Each build must call `buildCanvas` exactly once, because `_canvasStateKey` is a GlobalKey.

4. In `buildInspector`, change `buildPanel` so each panel's scroll view sits under its GlobalKey:

```dart
      Widget buildPanel(int index, Widget child) => KeyedSubtree(
        key: _panelKeys[index],
        child: SingleChildScrollView(
          key: ValueKey(
            'instrumentInspector${const ['Notes', 'Voicings', 'Setup'][index]}Scroll',
          ),
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: ValueKey('instrumentPanelContent$index'),
                child: child,
              ),
            ],
          ),
        ),
      );
```

   Then hoist `buildPanel` and the three panel bodies out of `buildInspector` so the dock can reuse them. Define, before `buildInspector`:

```dart
    Widget panelBody(int index) => switch (index) {
      0 => notes.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select notes on the instrument to inspect chords and compatible scales.',
                style: TextStyle(color: p.textSecondary, height: 1.4),
              ),
            )
          : SharedDetectionPanel(
              key: s.detectionKey,
              binding: s.binding,
              onChordPanelRequested: _showVoicings,
              embedded: true,
            ),
      1 => s.voicingsBuilder == null
          ? TextButton(
              onPressed: s.onChordPanelRequested,
              child: const Text('Open chord voicings'),
            )
          : Builder(builder: s.voicingsBuilder!),
      _ => s.setupBuilder == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Builder(builder: s.setupBuilder!),
            ),
    };
```

   and use `buildPanel(i, panelBody(i))` in the inspector's `IndexedStack`. The rendered output must stay identical to today.

5. Hoist the Scale and Library buttons out of the inspector footer into locals, and use them in both the footer and the dock header:

```dart
    Widget scaleButton() => TextButton.icon(
      key: const Key('instrumentScale'),
      onPressed: s.onScalePanelRequested,
      icon: Icon(
        s.scaleOffKey ? Icons.warning_amber_rounded : Icons.stacked_line_chart,
        size: 18,
        color: s.scaleOffKey ? p.orange : p.emerald,
      ),
      label: Text(s.scaleLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    Widget libraryButton() => TextButton.icon(
      key: const Key('instrumentLibrary'),
      onPressed: s.onSaveRequested,
      icon: const Icon(Icons.bookmarks_outlined, size: 18),
      label: const Text('Library', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
```

   In the footer, replace the two inline buttons with `Expanded(child: scaleButton())` and `Expanded(child: libraryButton())`.

6. Add the three-column dock builder (after `buildInspector`):

```dart
    Widget buildDock() {
      Widget column(int index, String title) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: buildPanel(index, panelBody(index))),
        ],
      );
      final divider = VerticalDivider(width: 1, color: p.glassBorder);
      return Container(
        key: const Key('instrumentDock'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: p.dialogBg,
          border: Border.all(color: p.glassBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  scaleButton(),
                  const SizedBox(width: 8),
                  libraryButton(),
                  const Spacer(),
                  IconButton(
                    key: const Key('instrumentInspectorToggle'),
                    tooltip: _expanded ? 'Collapse inspector' : 'Expand inspector',
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.glassBorder),
            Expanded(
              child: Offstage(
                offstage: !_expanded,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: column(0, 'Notes')),
                    divider,
                    Expanded(flex: 4, child: column(1, 'Voicings')),
                    divider,
                    Expanded(flex: 3, child: column(2, 'Setup')),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
```

   `Offstage` keeps the panels mounted while collapsed, matching the tabbed inspector. Step 7 shrinks the collapsed dock to its header row; when expanded, the dock fills the `Expanded` area.

7. In the body `LayoutBuilder`, compute the tier before the existing `if (wide)` branch:

```dart
            final dock =
                wide && !shortLandscape && constraints.maxHeight >= 640;
            if (dock) {
              final scale = dockCanvasScale(constraints.maxHeight);
              final threeColumns = constraints.maxWidth >= 1100;
              final dockArea = threeColumns
                  ? (_expanded
                        ? buildDock()
                        : Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              // Header row only; grows with scaled text.
                              height: 64 + (textScale - 14) * 2,
                              child: buildDock(),
                            ),
                          ))
                  : inspector;
              return Column(
                key: const Key('studioInstrumentDockLayout'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  ?controls,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: buildCanvas(scale),
                  ),
                  ?s.auditionControls,
                  selection,
                  Expanded(child: dockArea),
                ],
              );
            }
```

   `textScale` already exists in that builder (`MediaQuery.textScalerOf(context).scale(14)`). `inspector` is the existing `KeyedSubtree(_inspectorStateKey, ...)`. It must only be referenced in branches that do not also call `buildDock()`; this holds because each branch returns early.

   Check the horizontal padding: the existing wide `content` column places the canvas with whatever padding `s.board` (a `GlassFrame`) brings. Compare `buildCanvas(1)` placement in the side tier, and match the dock tier's left/right inset to it so the canvas edges align with the header text (DESIGN.md: wide outer inset 24 is acceptable). Adjust the `Padding` above accordingly, and keep the test assertion `before.width > size.width - 64` satisfied.

8. Collapsed-state guard: in the side and compact tiers, the existing behavior is unchanged.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/instrument_shared/instrument_screen_v2_layout_test.dart test/features/instrument_shared/studio_instrument_workspace_test.dart test/features/instrument_shared/instrument_screen_layout_test.dart test/features/instrument_shared/studio_instrument_app_test.dart`
Expected: PASS. If a pre-existing test fails because it ran at a size that now resolves to the dock tier (body height ≥ 640 and width ≥ 700), first confirm that the new behavior is the intended spec behavior. Then update only that test's expectation, and report it.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/instrument_shared/instrument_screen.dart test/features/instrument_shared/instrument_screen_v2_layout_test.dart
flutter analyze
git add lib/features/instrument_shared/instrument_screen.dart test/features/instrument_shared/
git commit -m "feat(instruments): add full-width canvas with inspector dock on tall wide layouts

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Documentation, full verification and visual check

**Depends on:** Tasks 1–3.

**Files:**
- Modify: `DESIGN.md` ("Shared workspace structure" paragraph, ~line 64; "Fretboard and Piano" section)
- Modify: `README.md` (Features navigation paragraph, ~line 23)
- Modify: `AGENTS.md` ("Instrument UX V2…" paragraph)
- Modify: `docs/instrument-ux-v2/PROGRESS.md`. Append a short dated entry.

- [ ] **Step 1: Update `DESIGN.md`**

In "Shared workspace structure", replace the sentence "Use an adaptive rail only when it improves space, otherwise keep the existing bottom layout with safe-area handling." with:

```markdown
Landscape viewports at least 600px wide use a compact left navigation rail (80px, icon + label, Settings pinned at the bottom, Song disabled); portrait and narrow viewports keep the bottom bar with safe-area handling. Switching between rail and bar never recreates workspaces.
```

In "Shared workspace structure", replace "Wide and short landscape use a side inspector, keeping native musical geometry useful." with:

```markdown
Short landscape and wide layouts under 640px body height use a side inspector. Wide layouts with at least 640px body height use a dock: the canvas spans the full width, scaled from 1.0× at 640px to at most 1.25× at 1040px, with audition and selection beneath it, and the inspector dock fills the remaining height. At 1100px content width or wider the dock shows Notes, Voicings and Setup side by side, with Scale, Library and collapse in its header; narrower docks keep the tabbed inspector. Panel state persists across all tiers.
```

- [ ] **Step 2: Update `README.md`**

Replace "The bottom navigation is labeled" with "The navigation (a bottom bar in portrait, a left rail in landscape) is labeled". Keep the rest of the sentence.

- [ ] **Step 3: Update `AGENTS.md`**

In the "Instrument UX V2 …" paragraph, after "Keep panels mounted across collapse, tab, theme and layout changes.", add:

```markdown
Wide tall layouts use a full-width scaled canvas (`ScaledInstrumentBoard`) and an inspector dock; panels keep per-panel GlobalKeys across tiers. The shell uses a left rail on landscape ≥600px (`lib/ui/app_navigation.dart`); keep `nav_<Label>` keys on both rail and bar.
```

- [ ] **Step 4: Append a dated entry to `docs/instrument-ux-v2/PROGRESS.md`**

```markdown
## 2026-10-30 — Landscape rail and instrument dock

- Shell: landscape ≥600px uses a left navigation rail; portrait keeps the bottom bar.
- Fretboard/Piano: wide layouts with ≥640px body height get a full-width scaled canvas (≤1.25×) and an inspector dock (three columns at ≥1100px).
```

- [ ] **Step 5: Full verification**

Run: `dart format --output=none --set-exit-if-changed lib test`
Expected: exit 0.

Run: `flutter analyze`
Expected: "No issues found!"

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Visual verification**

Run `flutter run -d chrome` (or `flutter run -d macos`). Check each of 1440×900, 1024×768, 844×390 and 390×844, for each of Fretboard, Piano, Roll and Writer:
- 1440×900: rail on the left, no bottom bar. The Fretboard/Piano canvas spans the full width, scaled about 1.16×, with a three-column dock below. Roll and Writer fill the height beside the rail.
- 1024×768: rail; tabbed dock under a full-width canvas.
- 844×390: rail; the side-inspector short-landscape layout is unchanged and nothing overflows. The rail scrolls if needed.
- 390×844: bottom bar; layouts identical to before.
- Switch the Studio theme (Settings) at 1440×900 and confirm the dock, rail and panels keep their state.
Capture screenshots at 1440×900 and 390×844 for the PR description.

- [ ] **Step 7: Commit**

```bash
git add DESIGN.md README.md AGENTS.md docs/instrument-ux-v2/PROGRESS.md
git commit -m "docs: describe landscape navigation rail and instrument dock

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
