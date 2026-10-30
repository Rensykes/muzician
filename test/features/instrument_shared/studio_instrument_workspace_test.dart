import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/features/fretboard/fretboard_feature.dart';
import 'package:muzician/features/instrument_shared/instrument_screen.dart';
import 'package:muzician/features/instrument_shared/scaled_instrument_board.dart';
import 'package:muzician/features/instrument_shared/shared_detection_panel.dart';
import 'package:muzician/features/instrument_shared/chord_picker_parts.dart';
import 'package:muzician/features/piano/piano_chord_diagram.dart';
import 'package:muzician/features/instrument_shared/harmony_save_edit_dialog.dart';
import 'package:muzician/features/piano/piano_feature.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:muzician/ui/project_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _screen({
  required bool guitar,
  VoidCallback? onSave,
  VoidCallback? onScale,
}) => Consumer(
  builder: (context, ref, _) {
    final fret = ref.watch(fretboardProvider);
    return InstrumentScreen(
      binding: guitar ? fretboardBinding : pianoBinding,
      title: guitar ? 'Fretboard' : 'Piano',
      appBarChipLabel: null,
      appBarActions: const [],
      projectContext: const ProjectChip(),
      modeSegment: guitar
          ? ModeSegment<FretboardInputMode>(
              current: fret.inputMode,
              onSelect: ref.read(fretboardProvider.notifier).setInputMode,
              options: const [
                (FretboardInputMode.free, Icons.touch_app, 'Free'),
                (FretboardInputMode.chord, Icons.library_music, 'Chord'),
              ],
            )
          : null,
      instrumentContext: guitar
          ? 'Standard · Capo off'
          : '61 keys · Exact MIDI keys',
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
      emptyTitle: guitar
          ? 'Tap the fretboard to begin'
          : 'Tap the keyboard to begin',
      emptySubtitle:
          'Selected notes turn into detected chords and scales here.',
      onChordPanelRequested: () {},
      onScalePanelRequested: onScale ?? () {},
      onSaveRequested: onSave ?? () {},
      onHandoffCompleted: () {},
      scaleHasValue: false,
      chordHasValue: false,
      detectionKey: ValueKey(guitar ? 'fret-detect' : 'piano-detect'),
      voicingsBuilder: (_) =>
          guitar ? const ChordVoicingPicker() : const PianoChordPicker(),
      setupBuilder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: guitar
            ? const Column(children: [TuningSelector(), CapoControl()])
            : const PianoRangeSelector(),
      ),
    );
  },
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required Size size,
  required bool guitar,
  double textScale = 1,
  ValueNotifier<AppThemeVariant>? variant,
  VoidCallback? onSave,
  VoidCallback? onScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = variant ?? ValueNotifier(AppThemeVariant.studio);
  if (variant == null) addTearDown(theme.dispose);
  final screen = _screen(guitar: guitar, onSave: onSave, onScale: onScale);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<AppThemeVariant>(
        valueListenable: theme,
        builder: (_, value, _) => StudioThemeSource(
          variant: value,
          child: MaterialApp(
            theme: StudioTheme.data(value),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(body: screen),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final guitar in [true, false]) {
    for (final size in [
      const Size(390, 844),
      const Size(844, 390),
      const Size(1024, 768),
      const Size(760, 768),
    ]) {
      testWidgets(
        '${guitar ? 'Fretboard' : 'Piano'} Studio fits $size and inspector stays usable',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await _pump(tester, container, size: size, guitar: guitar);
          expect(find.text(guitar ? 'Fretboard' : 'Piano'), findsOneWidget);
          // Mirrors the production tier: wide && !shortLandscape && body >= 640.
          final dock = size.width >= 700 && size.height >= 640;
          final baseHeight = guitar ? 212.0 : 226.0;
          expect(
            tester
                .getSize(find.byKey(const Key('studioInstrumentCanvas')))
                .height,
            closeTo(
              dock ? baseHeight * dockCanvasScale(size.height) : baseHeight,
              0.01,
            ),
          );
          expect(
            find.byType(guitar ? ChordVoicingPicker : PianoChordPicker),
            findsOneWidget,
          );
          if (dock) {
            expect(
              find.byKey(const Key('studioInstrumentDockLayout')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('studioInstrumentContentScroll')),
              findsNothing,
            );
          } else if (size.width >= 700 ||
              (size.width > size.height && size.height < 500)) {
            expect(
              find.byKey(const Key('studioInstrumentContentScroll')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('studioInstrumentCompactLayout')),
              findsNothing,
            );
          } else {
            expect(
              find.byKey(const Key('studioInstrumentCompactLayout')),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const Key('studioInstrumentPageScroll')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('instrumentInspectorVoicingsScroll')),
            findsOneWidget,
          );
          await _tap(tester, const Key('instrumentInspectorSetup'));
          expect(
            find.byType(guitar ? CapoControl : PianoRangeSelector),
            findsOneWidget,
          );
          if (guitar) {
            await tester.ensureVisible(find.byTooltip('Raise capo'));
            await tester.tap(find.byTooltip('Raise capo'));
            await tester.pumpAndSettle();
            expect(container.read(fretboardProvider).capo, 1);
          }
          await _tap(tester, const Key('instrumentInspectorToggle'));
          expect(
            find.byType(guitar ? CapoControl : PianoRangeSelector),
            findsNothing,
          );
          await _tap(tester, const Key('instrumentInspectorToggle'));
          expect(
            find.byType(guitar ? CapoControl : PianoRangeSelector),
            findsOneWidget,
          );
          await _tap(tester, const Key('instrumentInspectorNotes'));
          expect(
            find.text(
              'Select notes on the instrument to inspect chords and compatible scales.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'narrow large text keeps long project, full title and piano controls reachable',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saves = container.read(saveSystemProvider.notifier);
      final id = saves.createProject(
        'A very long rehearsal project name for the autumn sessions',
        const ProjectConfig(),
      )!;
      saves.selectProject(id);
      container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
      await _pump(
        tester,
        container,
        size: const Size(320, 844),
        guitar: false,
        textScale: 1.5,
      );
      expect(find.text('Piano'), findsOneWidget);
      await _tap(tester, const Key('instrumentInspectorSetup'));
      await tester.ensureVisible(find.byType(PianoRangeSelector));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final guitar in [true, false]) {
    for (final size in [
      const Size(390, 844),
      const Size(844, 390),
      const Size(1024, 768),
      const Size(320, 844),
    ]) {
      testWidgets(
        '${guitar ? 'Fretboard' : 'Piano'} populated Studio fits $size',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          if (guitar) {
            final fret = container.read(fretboardProvider.notifier);
            fret.setInputMode(FretboardInputMode.chord);
            fret.toggleCell(0, 8, 'C');
            fret.toggleCell(2, 0, 'G');
            fret.toggleCell(3, 2, 'E');
          } else {
            container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
          }
          await _pump(
            tester,
            container,
            size: size,
            guitar: guitar,
            textScale: size.width == 320 ? 1.5 : 1,
          );
          expect(
            find.byKey(const Key('instrumentSelectionTitle')),
            findsOneWidget,
          );
          if (size == const Size(390, 844)) {
            final canvas = find.byKey(const Key('studioInstrumentCanvas'));
            final before = tester.getRect(canvas);
            final preview = find
                .byType(guitar ? ChordDiagram : PianoChordDiagram)
                .first;
            await tester.ensureVisible(preview);
            await tester.pumpAndSettle();
            expect(tester.getRect(canvas), before);
            expect(find.text('INSPECTOR'), findsNothing);
            await _tap(tester, const Key('voicingsByChord'));
            expect(find.byType(StudioChordSelectors), findsOneWidget);
          }
          await _tap(tester, const Key('instrumentInspectorNotes'));
          await tester.ensureVisible(find.text('DETECTION'));
          await tester.pumpAndSettle();
          expect(find.text('DETECTION'), findsOneWidget);
          final detection = find.byType(SharedDetectionPanel);
          expect(
            find.descendant(
              of: detection,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SingleChildScrollView &&
                    widget.scrollDirection == Axis.vertical,
              ),
            ),
            findsNothing,
          );
          final lastResultRow = find
              .descendant(
                of: detection,
                matching: find.byType(SingleChildScrollView),
              )
              .last;
          expect(
            tester.getBottomLeft(detection).dy -
                tester.getBottomLeft(lastResultRow).dy,
            closeTo(8, 0.01),
          );
          await tester.ensureVisible(find.text('Clear'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Clear'));
          await tester.pumpAndSettle();
          expect(
            container.read(
              guitar
                  ? fretboardBinding.selectedNotes
                  : pianoBinding.selectedNotes,
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'instrument name dialog stays live and preserves input through theme change',
    (tester) async {
      final variant = ValueNotifier(AppThemeVariant.studio);
      addTearDown(variant.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<AppThemeVariant>(
          valueListenable: variant,
          builder: (_, value, _) => StudioThemeSource(
            variant: value,
            child: MaterialApp(
              theme: StudioTheme.data(value),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showStandaloneHarmonySaveNameDialog(
                      context,
                      initialName: 'Exact rehearsal',
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('standaloneHarmonySaveNameField'));
      await tester.enterText(input, 'My exact notes');
      final element = input.evaluate().single;
      variant.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      expect(input.evaluate().single, same(element));
      expect(
        tester.widget<TextField>(input).controller!.text,
        'My exact notes',
      );
      expect(StudioPalette.of(element), StudioPalette.studioMuzician);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Free explains handoff and Chord enables exact transfer without clearing selection',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(fretboardProvider.notifier)
          .setInputMode(FretboardInputMode.free);
      container.read(fretboardProvider.notifier).toggleCell(0, 0, 'E');
      var saves = 0;
      var scales = 0;
      await _pump(
        tester,
        container,
        size: const Size(390, 844),
        guitar: true,
        onSave: () => saves++,
        onScale: () => scales++,
      );
      await _tap(tester, const Key('instrumentSelectionActions'));
      expect(
        find.byKey(const Key('writerHandoffUnavailableReason')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('addInstrumentSelectionToWriter')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, const Key('instrumentSaveIdea'));
      expect(saves, 1);
      await _tap(tester, const Key('instrumentScale'));
      expect(scales, 1);
      final cells = container.read(fretboardProvider).selectedCells;
      container
          .read(fretboardProvider.notifier)
          .setInputMode(FretboardInputMode.chord);
      await tester.pumpAndSettle();
      expect(container.read(fretboardProvider).selectedCells, same(cells));
      await _tap(tester, const Key('instrumentSelectionActions'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('addInstrumentSelectionToWriter')),
            )
            .onPressed,
        isNotNull,
      );
      await _tap(tester, const Key('addInstrumentSelectionToWriter'));
      expect(find.text('Add exact notes as Harmony'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact piano carousel and utility footer stay reachable above navigation',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
      await _pump(tester, container, size: const Size(402, 722), guitar: false);
      final canvas = find.byKey(const Key('studioInstrumentCanvas'));
      final before = tester.getRect(canvas);
      await tester.ensureVisible(find.byType(PianoChordDiagram).first);
      await tester.pumpAndSettle();
      expect(tester.getRect(canvas), before);
      expect(
        tester.getBottomRight(find.byKey(const Key('instrumentLibrary'))).dy,
        lessThan(722),
      );
      expect(
        tester
            .widget<ListView>(find.byKey(const Key('voicingCarousel')))
            .scrollDirection,
        Axis.horizontal,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact fretboard maps first and last string taps and rejects scroll drags',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pump(tester, container, size: const Size(390, 844), guitar: true);
      final canvas = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_FretboardPainter',
      );
      final origin = tester.getTopLeft(canvas);
      await tester.tapAt(origin + const Offset(58, 36));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + const Offset(58, 176));
      await tester.pumpAndSettle();
      expect(
        container
            .read(fretboardProvider)
            .selectedCells
            .map((c) => c.stringIndex)
            .toSet(),
        {0, 5},
      );
      final before = container.read(fretboardProvider).selectedCells;
      await tester.dragFrom(
        origin + const Offset(220, 92),
        const Offset(-140, 0),
      );
      await tester.pumpAndSettle();
      expect(container.read(fretboardProvider).selectedCells, same(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Studio scale filtering keeps physical black keys opaque', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pianoProvider.notifier).setHighlightedNotes(['C', 'E', 'G']);
    await _pump(tester, container, size: const Size(390, 844), guitar: false);
    final blackKey = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'C#2, MIDI 37',
    );
    final opacity = find
        .ancestor(of: blackKey, matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    final keyBody = find
        .descendant(
          of: blackKey,
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        )
        .first;
    expect(
      (tester.widget<Container>(keyBody).decoration! as BoxDecoration).color!
          .toARGB32(),
      0xFF0F172A,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'theme switch repaints fretboard and retains picker, notes and focus',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(theme.dispose);
      final notifier = container.read(fretboardProvider.notifier);
      notifier.setInputMode(FretboardInputMode.chord);
      notifier.toggleCell(0, 0, 'E');
      notifier.toggleFocusedNote('E');
      await _pump(
        tester,
        container,
        size: const Size(1024, 768),
        guitar: true,
        variant: theme,
      );
      final pickerState = tester.state(find.byType(ChordVoicingPicker));
      final state = container.read(fretboardProvider);
      final paintFinder = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_FretboardPainter',
      );
      final oldPainter = tester.widget<CustomPaint>(paintFinder).painter!;
      theme.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      final newPainter = tester.widget<CustomPaint>(paintFinder).painter!;
      expect(newPainter.shouldRepaint(oldPainter), isTrue);
      expect(container.read(fretboardProvider), same(state));
      expect(tester.state(find.byType(ChordVoicingPicker)), same(pickerState));
      expect(tester.takeException(), isNull);
    },
  );
}
