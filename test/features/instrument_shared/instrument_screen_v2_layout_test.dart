import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/features/instrument_shared/instrument_screen.dart';
import 'package:muzician/features/instrument_shared/scaled_instrument_board.dart';
import 'package:muzician/features/piano/piano_keyboard.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _screen({
  required bool guitar,
  GlobalKey<_PanelProbeState>? voicingsKey,
  GlobalKey<_PanelProbeState>? setupKey,
  VoidCallback? onSave,
}) => Consumer(
  builder: (context, ref, _) {
    final fretboard = ref.watch(fretboardProvider);
    return InstrumentScreen(
      binding: guitar ? fretboardBinding : pianoBinding,
      title: guitar ? 'Fretboard' : 'Piano',
      appBarChipLabel: null,
      appBarActions: const [],
      projectContext: const Text('Project'),
      modeSegment: guitar
          ? ModeSegment<FretboardInputMode>(
              current: fretboard.inputMode,
              onSelect: ref.read(fretboardProvider.notifier).setInputMode,
              options: const [
                (FretboardInputMode.free, Icons.touch_app, 'Free'),
                (FretboardInputMode.chord, Icons.library_music, 'Chord'),
              ],
            )
          : null,
      instrumentContext: guitar ? 'Standard tuning · Capo off' : '61 keys',
      board: GlassFrame(
        padding: const EdgeInsets.all(4),
        child: guitar
            ? const GuitarFretboard(
                hideToolbar: true,
                palette: FretboardPalette.graphite,
              )
            : const PianoKeyboard(hideToolbar: true),
      ),
      boardHeight: guitar ? fretboardBoardHeight : pianoKeyboardHeight,
      emptyTitle: guitar ? 'Tap the fretboard to begin' : 'Tap the keyboard',
      emptySubtitle: 'Selected notes turn into detected chords and scales.',
      onChordPanelRequested: () {},
      onScalePanelRequested: () {},
      onSaveRequested: onSave ?? () {},
      scaleHasValue: false,
      chordHasValue: false,
      detectionKey: ValueKey(guitar ? 'fret-detect' : 'piano-detect'),
      voicingsBuilder: (_) =>
          _PanelProbe(key: voicingsKey, label: 'Voicing item'),
      setupBuilder: (_) => _PanelProbe(key: setupKey, label: 'Setup item'),
    );
  },
);

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container, {
  required Size size,
  required bool guitar,
  required ValueNotifier<AppThemeVariant> theme,
  double textScale = 1,
  GlobalKey<_PanelProbeState>? voicingsKey,
  GlobalKey<_PanelProbeState>? setupKey,
  VoidCallback? onSave,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<AppThemeVariant>(
        valueListenable: theme,
        builder: (_, variant, _) => StudioThemeSource(
          variant: variant,
          child: MaterialApp(
            theme: StudioTheme.data(variant),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                devicePixelRatio: 1,
                padding: const EdgeInsets.only(top: 24),
                viewPadding: const EdgeInsets.only(top: 24),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: _screen(
                  guitar: guitar,
                  voicingsKey: voicingsKey,
                  setupKey: setupKey,
                  onSave: onSave,
                ),
                bottomNavigationBar: const SizedBox(height: 56),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _scrollOffset(WidgetTester tester, String keyName) {
  final scrollView = find.byKey(Key(keyName));
  final scrollable = find.descendant(
    of: scrollView,
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable.first).position.pixels;
}

Future<void> _scrollPanel(WidgetTester tester, String keyName) async {
  await tester.drag(find.byKey(Key(keyName)), const Offset(0, -220));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final guitar in [true, false]) {
    for (final size in [
      const Size(390, 844),
      const Size(1024, 768),
      const Size(844, 390),
      const Size(1024, 600),
      const Size(1440, 900),
    ]) {
      testWidgets(
        '${guitar ? 'Fretboard' : 'Piano'} canvas stays fixed while the inspector scrolls at $size',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          final theme = ValueNotifier(AppThemeVariant.studio);
          addTearDown(theme.dispose);
          await _pumpScreen(
            tester,
            container,
            size: size,
            guitar: guitar,
            theme: theme,
          );

          final canvas = find.byKey(const Key('studioInstrumentCanvas'));
          final before = tester.getRect(canvas);
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

          await _scrollPanel(tester, 'instrumentInspectorVoicingsScroll');
          expect(
            _scrollOffset(tester, 'instrumentInspectorVoicingsScroll'),
            greaterThan(0),
          );
          expect(tester.getRect(canvas), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
    expect(_scrollOffset(tester, 'instrumentInspectorVoicingsScroll'), offset);

    await pumpAt(const Size(1024, 768)); // tabbed dock
    expect(identical(voicingsKey.currentState, voicingsState), isTrue);

    await pumpAt(const Size(1440, 900)); // back to three columns
    expect(identical(voicingsKey.currentState, voicingsState), isTrue);
    expect(identical(setupKey.currentState, setupState), isTrue);
    expect(_scrollOffset(tester, 'instrumentInspectorVoicingsScroll'), offset);
    expect(tester.takeException(), isNull);
  });

  for (final guitar in [true, false]) {
    for (final size in [const Size(1440, 900), const Size(1024, 768)]) {
      testWidgets(
        '${guitar ? 'Fretboard' : 'Piano'} dock has no overflow at 2x text and $size',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          final theme = ValueNotifier(AppThemeVariant.studio);
          addTearDown(theme.dispose);
          await _pumpScreen(
            tester,
            container,
            size: size,
            guitar: guitar,
            theme: theme,
            textScale: 2,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(const Key('instrumentInspectorToggle')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('instrumentInspectorToggle')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'compact large text keeps canvas visible and retains panel state across tabs, collapse, and theme changes',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(theme.dispose);
      final voicingsKey = GlobalKey<_PanelProbeState>();
      final setupKey = GlobalKey<_PanelProbeState>();
      await _pumpScreen(
        tester,
        container,
        size: const Size(320, 844),
        guitar: true,
        theme: theme,
        textScale: 1.5,
        voicingsKey: voicingsKey,
        setupKey: setupKey,
      );

      final canvas = find.byKey(const Key('studioInstrumentCanvas'));
      final canvasRect = tester.getRect(canvas);
      final originalVoicingsState = voicingsKey.currentState;
      expect(originalVoicingsState, isNotNull);
      expect(canvasRect.bottom, lessThanOrEqualTo(844 - 56));
      expect(tester.takeException(), isNull);

      await _scrollPanel(tester, 'instrumentInspectorVoicingsScroll');
      final voicingsOffset = _scrollOffset(
        tester,
        'instrumentInspectorVoicingsScroll',
      );
      expect(voicingsOffset, greaterThan(0));
      expect(tester.getRect(canvas), canvasRect);

      await tester.tap(find.byKey(const Key('instrumentInspectorSetup')));
      await tester.pumpAndSettle();
      final originalSetupState = setupKey.currentState;
      expect(originalSetupState, isNotNull);
      await _scrollPanel(tester, 'instrumentInspectorSetupScroll');
      final setupOffset = _scrollOffset(
        tester,
        'instrumentInspectorSetupScroll',
      );
      expect(setupOffset, greaterThan(0));

      await tester.tap(find.byKey(const Key('instrumentInspectorToggle')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand inspector'), findsOneWidget);
      expect(setupKey.currentState, same(originalSetupState));
      expect(voicingsKey.currentState, same(originalVoicingsState));

      await tester.tap(find.byKey(const Key('instrumentInspectorToggle')));
      await tester.pumpAndSettle();
      expect(setupKey.currentState, same(originalSetupState));
      expect(
        _scrollOffset(tester, 'instrumentInspectorSetupScroll'),
        closeTo(setupOffset, 0.01),
      );

      theme.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      expect(setupKey.currentState, same(originalSetupState));
      expect(
        _scrollOffset(tester, 'instrumentInspectorSetupScroll'),
        closeTo(setupOffset, 0.01),
      );
      expect(tester.getRect(canvas), canvasRect);

      await tester.tap(find.byKey(const Key('instrumentInspectorVoicings')));
      await tester.pumpAndSettle();
      expect(voicingsKey.currentState, same(originalVoicingsState));
      expect(
        _scrollOffset(tester, 'instrumentInspectorVoicingsScroll'),
        closeTo(voicingsOffset, 0.01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selection actions still save after rotating with sheet open', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final theme = ValueNotifier(AppThemeVariant.studio);
    addTearDown(theme.dispose);
    container.read(pianoProvider.notifier).loadExactMidis([60]);
    var saves = 0;
    await _pumpScreen(
      tester,
      container,
      size: const Size(390, 844),
      guitar: false,
      theme: theme,
      onSave: () => saves++,
    );
    await tester.tap(find.byKey(const Key('instrumentSelectionActions')));
    await tester.pumpAndSettle();
    await _pumpScreen(
      tester,
      container,
      size: const Size(844, 390),
      guitar: false,
      theme: theme,
      onSave: () => saves++,
    );
    await tester.tap(find.byKey(const Key('instrumentSaveIdea')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byKey(const Key('instrumentSelectionSheet')), findsNothing);
    expect(container.read(pianoProvider).selectedNotes, ['C']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode menus wrap descriptions at 320px and double text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.data(AppThemeVariant.studio),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: InstrumentModeMenu<FretboardInputMode>(
                label: 'Input mode',
                current: FretboardInputMode.free,
                onSelect: (_) {},
                options: const [
                  (
                    FretboardInputMode.free,
                    'Free',
                    'Multiple notes per string',
                  ),
                  (FretboardInputMode.chord, 'Chord', 'One note per string'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Input mode: Free'));
    await tester.pumpAndSettle();
    final description = find.text('Multiple notes per string');
    expect(tester.getRect(description).right, lessThanOrEqualTo(320));
    expect(tester.getRect(description).left, greaterThanOrEqualTo(0));
    expect(tester.getSize(description).height, greaterThan(30));
    final check = find.byIcon(Icons.check_rounded);
    expect(tester.getRect(check).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selection actions have one stable home across tabs and collapse',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(theme.dispose);
      container.read(pianoProvider.notifier).loadExactMidis([60]);
      await _pumpScreen(
        tester,
        container,
        size: const Size(390, 700),
        guitar: false,
        theme: theme,
      );

      final canvas = find.byKey(const Key('studioInstrumentCanvas'));
      final canvasRect = tester.getRect(canvas);
      final actions = find.byKey(const Key('instrumentSelectionActions'));
      final actionsRect = tester.getRect(actions);
      expect(actionsRect.height, 44);
      expect(find.text('1 note'), findsOneWidget);
      expect(find.text('Exact selection'), findsNothing);
      expect(find.byKey(const Key('instrumentSaveIdea')), findsNothing);
      for (final tab in ['Notes', 'Voicings', 'Setup']) {
        await tester.tap(find.byKey(Key('instrumentInspector$tab')));
        await tester.pumpAndSettle();
        expect(tester.getRect(actions), actionsRect);
        expect(
          find.byKey(
            const Key('instrumentSelectionTitle'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(tester.getRect(canvas), canvasRect);
      }
      await tester.tap(find.byKey(const Key('instrumentInspectorToggle')));
      await tester.pumpAndSettle();
      expect(tester.getRect(actions), actionsRect);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.text('Exact selection'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('instrumentSelectionSheet')),
          matching: find.text('C4'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('instrumentSaveIdea')), findsOneWidget);
      expect(
        find.byKey(const Key('addInstrumentSelectionToWriter')),
        findsOneWidget,
      );
      theme.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      expect(
        StudioPalette.of(
          tester.element(find.byKey(const Key('instrumentSelectionSheet'))),
        ),
        StudioPalette.studioMuzician,
      );
      await tester.tap(find.byTooltip('Close selection actions'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand inspector'), findsOneWidget);
      expect(tester.getRect(canvas), canvasRect);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PanelProbe extends StatefulWidget {
  const _PanelProbe({super.key, required this.label});
  final String label;

  @override
  State<_PanelProbe> createState() => _PanelProbeState();
}

class _PanelProbeState extends State<_PanelProbe> {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < 24; index++)
        SizedBox(
          height: 72,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${widget.label} $index'),
          ),
        ),
    ],
  );
}
