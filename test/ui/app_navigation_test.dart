import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  AppNavDestination(
    tabIndex: 3,
    icon: Icons.edit_outlined,
    label: 'Writer',
    onTap: () => taps.add(3),
  ),
  AppNavDestination(
    tabIndex: 4,
    icon: Icons.settings_outlined,
    label: 'Settings',
    onTap: () => taps.add(4),
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
      (Size(667, 375), false),
      (Size(680, 400), true),
      (Size(679, 400), false),
      (Size(700, 800), false),
    ]) {
      test('$size -> $expected', () {
        expect(useNavigationRail(size), expected);
      });
    }
  });

  testWidgets('rail lists workspaces and pins Settings', (tester) async {
    final taps = <int>[];
    await _pump(
      tester,
      const Size(1440, 900),
      Row(
        children: [
          StudioNavigationRail(
            destinations: _destinations(taps),
            selectedIndex: 3,
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );

    expect(find.byKey(const Key('studioNavigationRail')), findsOneWidget);
    for (final label in ['Fretboard', 'Piano', 'Roll', 'Writer', 'Settings']) {
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
    await tester.tap(find.byKey(const ValueKey('nav_Writer')));
    await tester.tap(find.byKey(const ValueKey('nav_Settings')));
    expect(taps, [1, 3, 4]);
  });

  testWidgets('a destination without onTap is disabled with a hint', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1440, 900),
      Row(
        children: [
          StudioNavigationRail(
            destinations: const [
              AppNavDestination(
                tabIndex: 0,
                icon: Icons.lock_outline,
                label: 'Locked',
                semanticHint: 'Unavailable in this fixture',
              ),
            ],
            selectedIndex: 0,
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );

    final semantics = tester.ensureSemantics();
    final locked = tester
        .getSemantics(find.byKey(const ValueKey('nav_Locked')))
        .getSemanticsData();
    expect(locked.hint, 'Unavailable in this fixture');
    expect(locked.hasAction(SemanticsAction.tap), isFalse);
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
          StudioNavigationRail(
            destinations: _destinations([]),
            selectedIndex: 0,
          ),
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
    expect(taps, [3]);
  });
}
