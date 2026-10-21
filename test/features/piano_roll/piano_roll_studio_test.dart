import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_grid.dart';
import 'package:muzician/features/piano_roll/piano_roll_hum_recorder.dart';
import 'package:muzician/features/piano_roll/piano_roll_save_panel.dart';
import 'package:muzician/features/piano_roll/piano_roll_save_stack_loader.dart';
import 'package:muzician/features/instrument_shared/shared_scale_picker.dart';
import 'package:muzician/features/piano_roll/piano_roll_screen_v2.dart';
import 'package:muzician/features/piano_roll/piano_roll_stack_builder.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/piano_roll_playback.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:muzician/ui/transport_strip.dart' as transport;

const _toolLabels = {
  PianoRollTool.draw: 'Draw',
  PianoRollTool.select: 'Select',
  PianoRollTool.scissors: 'Split',
  PianoRollTool.paint: 'Paint',
  PianoRollTool.delete: 'Delete',
};

const _note = PianoRollNote(
  id: 'note',
  midiNote: 80,
  pitchClass: 'G#',
  noteWithOctave: 'G#5',
  startTick: 0,
  durationTicks: 4,
);
const _initial = PianoRollState(
  config: PianoRollConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 4,
  ),
  notes: [_note],
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
  selectedColumnTick: 0,
);

class _Roll extends PianoRollNotifier {
  _Roll(this.initial);
  final PianoRollState initial;
  @override
  PianoRollState build() => initial;
}

class _Playback extends PianoRollPlaybackNotifier {
  _Playback(this.initial);
  final PianoRollPlaybackState initial;
  @override
  PianoRollPlaybackState build() => initial;
}

ProviderContainer _container({
  PianoRollState initial = _initial,
  PianoRollPlaybackState playback = const PianoRollPlaybackState(),
}) => ProviderContainer(
  overrides: [
    pianoRollProvider.overrideWith(() => _Roll(initial)),
    pianoRollPlaybackProvider.overrideWith(() => _Playback(playback)),
  ],
);

Widget _host(
  ProviderContainer container,
  ValueNotifier<AppThemeVariant> theme, {
  bool legacy = false,
  bool embedded = false,
  ProviderContainer? isolated,
}) => UncontrolledProviderScope(
  container: container,
  child: ValueListenableBuilder<AppThemeVariant>(
    valueListenable: theme,
    builder: (context, variant, _) => StudioThemeSource(
      variant: variant,
      child: MaterialApp(
        theme: StudioTheme.data(variant),
        home: Scaffold(
          body: StudioRouteTheme(
            isStudio: !legacy,
            child: UncontrolledProviderScope(
              container: isolated ?? container,
              child: PianoRollScreenV2(
                showBackground: !embedded,
                showScale: !embedded,
                showSavePanels: !embedded,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _tab(WidgetTester tester, int tab) async {
  final target = find.byKey(ValueKey('studio-inspector-$tab'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  for (final size in const [
    Size(390, 844),
    Size(844, 390),
    Size(844, 310),
    Size(390, 450),
    Size(1024, 768),
  ]) {
    for (final variant in AppThemeVariant.values) {
      testWidgets(
        'Studio Roll fits $size in ${variant.name} with expanded inspector',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final container = _container();
          final theme = ValueNotifier(variant);
          addTearDown(container.dispose);
          addTearDown(theme.dispose);
          await tester.pumpWidget(_host(container, theme));
          await tester.pumpAndSettle();
          expect(find.text('Piano Roll'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('studio-piano-roll')),
            findsOneWidget,
          );
          expect(find.byType(PianoRollStackBuilder), findsOneWidget);
          expect(
            tester.getSize(find.byType(PianoRollGrid)).height,
            greaterThan(120),
          );
          expect(tester.takeException(), isNull);
          await _tab(tester, 2);
          await tester.ensureVisible(find.text('+1 Oct'));
          await tester.tap(find.text('+1 Oct'));
          await tester.pump();
          expect(container.read(pianoRollProvider).pitchRangeStart, 60);
          await tester.ensureVisible(find.text('8t'));
          await tester.tap(find.text('8t'));
          await tester.pump();
          expect(container.read(pianoRollProvider).snapTicks, 8);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Collapse inspector'));
          await tester.pump();
          expect(find.byTooltip('Expand inspector'), findsOneWidget);
          expect(
            tester.getSize(find.byType(PianoRollGrid)).height,
            greaterThan(120),
          );
        },
      );
    }
  }

  for (final size in const [Size(390, 700), Size(1024, 768), Size(834, 1210)]) {
    testWidgets(
      'Studio builder fields and Add stack fit without scrolling at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = _container();
        final theme = ValueNotifier(AppThemeVariant.studio);
        addTearDown(container.dispose);
        addTearDown(theme.dispose);
        await tester.pumpWidget(_host(container, theme));
        await tester.pumpAndSettle();
        final inspector = tester.getRect(
          find.byKey(const ValueKey('studio-roll-inspector')),
        );
        final add = find.byKey(const ValueKey('studio-add-stack'));
        expect(tester.getRect(add).bottom, lessThanOrEqualTo(inspector.bottom));
        expect(add.hitTestable(), findsOneWidget);
        for (final field in ['root', 'quality', 'inversion', 'duration']) {
          final target = find.byKey(ValueKey('studio-stack-$field'));
          expect(target.hitTestable(), findsOneWidget);
          expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        }
        final ruler = tester.getRect(
          find.byKey(const ValueKey('piano-roll-ruler-paint')),
        );
        final grid = tester.getRect(
          find.byKey(const ValueKey('piano-roll-grid-paint')),
        );
        expect(grid.top, closeTo(ruler.bottom, 1));
        final duration = find.byKey(const ValueKey('studio-stack-duration'));
        await tester.tap(duration);
        await tester.pumpAndSettle();
        final chooserElement = tester.element(find.byType(SimpleDialog));
        theme.value = AppThemeVariant.studioMuzician;
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(SimpleDialog)), same(chooserElement));
        expect(StudioPalette.of(chooserElement), StudioPalette.studioMuzician);
        await tester.tap(find.text('1/2').last);
        await tester.pumpAndSettle();
        final before = container.read(pianoRollProvider).notes.length;
        await tester.tap(add);
        await tester.pump();
        final notes = container.read(pianoRollProvider).notes;
        expect(notes.length, greaterThan(before));
        if (size.width < 700) {
          final scroll = tester
              .widgetList<SingleChildScrollView>(
                find.descendant(
                  of: find.byType(PianoRollGrid),
                  matching: find.byType(SingleChildScrollView),
                ),
              )
              .where((widget) => widget.scrollDirection == Axis.vertical)
              .last
              .controller!;
          expect(scroll.offset, greaterThan(0));
          expect(
            450 - scroll.offset,
            lessThanOrEqualTo(scroll.position.viewportDimension),
          );
        }
        expect(
          notes
              .where((note) => note.id != 'note')
              .every((note) => note.durationTicks == 8),
          isTrue,
        );
        expect(
          tester.getSize(find.byType(PianoRollGrid)).height,
          greaterThan(180),
        );
        final summary = find.byKey(const ValueKey('studio-column-summary'));
        expect(summary.hitTestable(), findsOneWidget);
        final selectColumn = find.descendant(
          of: summary,
          matching: find.byTooltip('Select column'),
        );
        await tester.tap(selectColumn);
        await tester.pump();
        expect(container.read(pianoRollProvider).selectedNoteIds, isNotEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all five Studio tools and Quick work on compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = _container();
    final theme = ValueNotifier(AppThemeVariant.studio);
    addTearDown(container.dispose);
    addTearDown(theme.dispose);
    await tester.pumpWidget(_host(container, theme));
    for (final label in ['Quick', 'Scale', 'Hum recorder', 'Save', 'Import']) {
      final target = find.byTooltip(label);
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.getRect(target).right, lessThanOrEqualTo(390));
    }
    for (final tool in PianoRollTool.values) {
      final target = find.byKey(ValueKey('studio-tool-${tool.name}'));
      expect(target.hitTestable(), findsOneWidget);
      expect(find.byTooltip(_toolLabels[tool]!).hitTestable(), findsOneWidget);
      final snap = find.byKey(const ValueKey('studio-roll-snap'));
      expect(snap.hitTestable(), findsOneWidget);
      expect(tester.getRect(snap).right, lessThanOrEqualTo(390));
      await tester.tap(target);
      await tester.pump();
      expect(container.read(pianoRollProvider).activeTool, tool);
      expect(
        tester
            .getSize(
              find.descendant(of: target, matching: find.byType(TextButton)),
            )
            .height,
        greaterThanOrEqualTo(44),
      );
    }
    container.read(pianoRollProvider.notifier).selectNote('note');
    container.read(pianoRollProvider.notifier).selectColumn(8);
    await tester.pump();
    final count = container.read(pianoRollProvider).notes.length;
    await tester.tap(find.text('Quick'));
    await tester.pump();
    expect(container.read(pianoRollProvider).notes.length, greaterThan(count));
  });

  testWidgets(
    'Studio Selection distinguishes column from note selection and deletes explicitly',
    (tester) async {
      final container = _container();
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(container.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(_host(container, theme));
      await _tab(tester, 1);
      expect(container.read(pianoRollProvider).selectedNoteIds, isEmpty);
      expect(container.read(pianoRollProvider).selectedColumnTick, 0);
      await tester.tap(find.text('Select column'));
      await tester.pump();
      expect(container.read(pianoRollProvider).selectedNoteIds, {'note'});
      await tester.tap(find.text('Clear selection'));
      await tester.pump();
      expect(container.read(pianoRollProvider).selectedNoteIds, isEmpty);
      expect(container.read(pianoRollProvider).selectedColumnTick, 0);
      await tester.tap(find.text('Select column'));
      await tester.pump();
      await tester.tap(find.text('Delete selection'));
      await tester.pump();
      expect(container.read(pianoRollProvider).notes, isEmpty);
    },
  );

  testWidgets(
    'live Studio theme preserves grid, open builder wizard and notes; painters repaint',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = _container(
        initial: _initial.copyWith(
          selectedNoteIds: {'note'},
          activeTool: PianoRollTool.paint,
        ),
        playback: const PianoRollPlaybackState(
          status: PianoRollPlaybackStatus.playing,
          startTick: 4,
          currentTick: 8,
          endTickExclusive: 64,
        ),
      );
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(container.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(_host(container, theme));
      await tester.tap(find.text('Custom'));
      await tester.pump();
      await tester.tap(find.text('Add note'));
      await tester.pump();
      final gridState = tester.state(find.byType(PianoRollGrid));
      final builderState = tester.state(find.byType(PianoRollStackBuilder));
      final rollState = container.read(pianoRollProvider);
      final playbackState = container.read(pianoRollPlaybackProvider);
      final gridScroll = tester
          .widgetList<SingleChildScrollView>(
            find.descendant(
              of: find.byType(PianoRollGrid),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .lastWhere((widget) => widget.scrollDirection == Axis.horizontal)
          .controller!;
      gridScroll.jumpTo(70);
      await tester.pump();
      final painters = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(PianoRollGrid),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((widget) => widget.painter)
          .whereType<CustomPainter>()
          .toList();
      theme.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(PianoRollGrid)), same(gridState));
      expect(
        tester.state(find.byType(PianoRollStackBuilder)),
        same(builderState),
      );
      expect(
        find.byKey(const ValueKey('stack-builder-advanced-wizard')),
        findsOneWidget,
      );
      expect(container.read(pianoRollProvider), same(rollState));
      expect(container.read(pianoRollPlaybackProvider), same(playbackState));
      expect(gridScroll.offset, 70);
      final after = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(PianoRollGrid),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((widget) => widget.painter)
          .whereType<CustomPainter>()
          .toList();
      expect(after, hasLength(3));
      for (var i = 0; i < after.length; i++) {
        expect(after[i].shouldRepaint(painters[i]), isTrue);
        expect((after[i] as dynamic).palette, StudioPalette.studioMuzician);
      }
    },
  );

  testWidgets(
    'empty Studio Roll fits narrow text scaling and leaves tools reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = _container(
        initial: _initial.copyWith(notes: [], selectedColumnTick: () => null),
      );
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(container.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(_host(container, theme));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PianoRollGrid)).height,
        greaterThan(120),
      );
      await _tab(tester, 2);
      await tester.ensureVisible(find.text('+1 Oct'));
      await tester.tap(find.text('+1 Oct'));
      await tester.pump();
      expect(container.read(pianoRollProvider).pitchRangeStart, 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact utilities open real panels and open Hum sheet follows live theme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = _container();
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(container.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(_host(container, theme));
      for (final (label, panelType) in <(String, Type)>[
        ('Scale', SharedScalePicker),
        ('Save', PianoRollSavePanel),
        ('Import', PianoRollSaveStackLoader),
        ('Hum recorder', PianoRollHumRecorderPanel),
      ]) {
        final action = find.byTooltip(label);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        final panel = find.byType(panelType);
        expect(panel, findsOneWidget);
        if (label == 'Hum recorder') {
          final panelState = tester.state(panel);
          final notes = container.read(pianoRollProvider);
          theme.value = AppThemeVariant.studioMuzician;
          await tester.pumpAndSettle();
          expect(tester.state(panel), same(panelState));
          expect(
            StudioPalette.of(tester.element(panel)),
            StudioPalette.studioMuzician,
          );
          expect(container.read(pianoRollProvider), same(notes));
        }
        Navigator.of(tester.element(panel)).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final legacy in [false, true]) {
    testWidgets(
      'Roll utility and tempo sheets keep isolated ${legacy ? "Song" : "Studio"} container',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = _container();
        final isolated = _container(
          initial: _initial.copyWith(
            config: _initial.config.copyWith(tempo: 154),
          ),
        );
        final theme = ValueNotifier(AppThemeVariant.studio);
        addTearDown(root.dispose);
        addTearDown(isolated.dispose);
        addTearDown(theme.dispose);
        await tester.pumpWidget(
          _host(
            root,
            theme,
            legacy: legacy,
            embedded: true,
            isolated: isolated,
          ),
        );
        final originalRoot = root.read(pianoRollProvider);
        final hum = legacy
            ? find.text('Record')
            : find.byTooltip('Hum recorder');
        await tester.ensureVisible(hum);
        await tester.tap(hum);
        await tester.pumpAndSettle();
        final panel = find.byType(PianoRollHumRecorderPanel);
        expect(
          ProviderScope.containerOf(tester.element(panel)),
          same(isolated),
        );
        theme.value = AppThemeVariant.studioMuzician;
        await tester.pumpAndSettle();
        expect(
          ProviderScope.containerOf(tester.element(panel)),
          same(isolated),
        );
        expect(
          StudioPalette.of(tester.element(panel)),
          legacy ? StudioPalette.legacy : StudioPalette.studioMuzician,
        );
        Navigator.of(tester.element(panel)).pop();
        await tester.pumpAndSettle();
        final bpm = find.text('154');
        await tester.ensureVisible(bpm);
        await tester.tap(bpm);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<transport.BpmSheet>(find.byType(transport.BpmSheet))
              .currentBpm,
          154,
        );
        await tester.enterText(find.byType(TextField), '160');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(isolated.read(pianoRollProvider).config.tempo, 160);
        expect(root.read(pianoRollProvider), same(originalRoot));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'embedded Studio capabilities and legacy Song layout remain scoped',
    (tester) async {
      final container = _container();
      final theme = ValueNotifier(AppThemeVariant.studio);
      addTearDown(container.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(_host(container, theme, embedded: true));
      expect(find.byKey(const ValueKey('studio-piano-roll')), findsOneWidget);
      expect(find.text('Scale'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Import'), findsNothing);
      expect(find.byTooltip('Hum recorder'), findsOneWidget);
      await tester.pumpWidget(
        _host(container, theme, legacy: true, embedded: true),
      );
      expect(find.byKey(const ValueKey('studio-piano-roll')), findsNothing);
      expect(find.text('Roll'), findsOneWidget);
      final painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('piano-roll-grid-paint')),
          )
          .painter;
      expect((painter as dynamic).palette, StudioPalette.legacy);
      theme.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      expect(
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('piano-roll-grid-paint')),
                    )
                    .painter
                as dynamic)
            .palette,
        StudioPalette.legacy,
      );
    },
  );
}
