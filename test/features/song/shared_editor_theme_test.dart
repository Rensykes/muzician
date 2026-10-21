import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/features/song/song_note_pattern_editor.dart';
import 'package:muzician/features/song/song_pattern_editor_launcher.dart';
import 'package:muzician/features/piano_roll/piano_roll_screen_v2.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/theme/studio_theme.dart';

final _pattern = DrumPattern(
  id: 'beat',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    for (final id in DrumLaneId.values)
      DrumLaneSequence(laneId: id, activeTicks: const []),
  ],
);

Finder _steps() => find.byWidgetPredicate(
  (widget) =>
      widget is GestureDetector &&
      widget.child is Container &&
      (widget.child! as Container).margin != null,
);

Widget _host(ValueNotifier<AppThemeVariant> variant, Widget home) =>
    ValueListenableBuilder<AppThemeVariant>(
      valueListenable: variant,
      child: home,
      builder: (context, value, child) => StudioThemeSource(
        variant: value,
        child: MaterialApp(theme: StudioTheme.data(value), home: child),
      ),
    );

void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1024, 768)]) {
    testWidgets('Studio drum targets and scrolling fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DrumPattern? edited;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: StudioTheme.data(AppThemeVariant.studio),
            home: Scaffold(
              body: DrumMachineEditorBody(
                pattern: _pattern,
                tempo: 120,
                enableLibrary: true,
                backing: (
                  loopTicks: 16,
                  notesByTick: {
                    0: [60, 64, 67],
                  },
                ),
                onChanged: (value) => edited = value,
              ),
            ),
          ),
        ),
      );
      final step =
          tester.widget<GestureDetector>(_steps().first).child! as Container;
      expect(step.constraints!.minWidth, 44);
      expect(step.constraints!.minHeight, 44);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      await tester.tap(_steps().first);
      await tester.pump();
      expect(edited!.lanes.first.activeTicks, [0]);
      expect(find.byKey(const Key('drumLibraryButton')), findsOneWidget);
      // In short landscape, lower rows remain reachable with a vertical drag.
      if (size.height < 500) {
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        expect(find.text('Crash').hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final legacy in [false, true]) {
    testWidgets(
      'nested drum fill keeps ${legacy ? 'legacy' : 'live Studio'} scope',
      (tester) async {
        final variant = ValueNotifier(AppThemeVariant.studio);
        addTearDown(variant.dispose);
        await tester.pumpWidget(
          ProviderScope(
            child: _host(
              variant,
              StudioRouteTheme(
                isStudio: !legacy,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showWidgetSheet(
                        context: context,
                        title: 'Drums',
                        child: DrumMachineEditorBody(
                          pattern: _pattern,
                          tempo: 120,
                          onChanged: (_) {},
                        ),
                      ),
                      child: const Text('Open drums'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open drums'));
        await tester.pumpAndSettle();
        final step =
            tester.widget<GestureDetector>(_steps().first).child! as Container;
        expect(step.constraints!.minWidth, legacy ? 32 : 44);
        await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('offsetPlus')));
        await tester.pump();
        final fillElement = tester.element(find.byKey(const Key('offsetPlus')));
        expect(
          StudioPalette.of(fillElement),
          legacy ? StudioPalette.legacy : StudioPalette.studio,
        );
        final stateBefore = tester.state(
          find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_LaneFillSheet',
          ),
        );
        variant.value = AppThemeVariant.studioMuzician;
        await tester.pumpAndSettle();
        expect(
          StudioPalette.of(fillElement),
          legacy ? StudioPalette.legacy : StudioPalette.studioMuzician,
        );
        expect(
          tester.state(
            find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_LaneFillSheet',
            ),
          ),
          same(stateBefore),
        );
        final offsetRow = find
            .ancestor(
              of: find.byKey(const Key('offsetPlus')),
              matching: find.byType(Row),
            )
            .first;
        expect(
          find.descendant(of: offsetRow, matching: find.text('1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final type in [SongTrackType.note, SongTrackType.drum]) {
    testWidgets('Song $type fullscreen route stays legacy after theme switch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(songProjectProvider.notifier);
      final track = store.addTrack(type);
      final id = type == SongTrackType.note
          ? store.createEmptyNotePatternClip(trackId: track, startTick: 0)
          : store.createEmptyDrumPatternClip(trackId: track, startTick: 0);
      final clip = container
          .read(songProjectProvider)
          .clips
          .firstWhere((clip) => clip.id == id);
      final variant = ValueNotifier(AppThemeVariant.studio);
      addTearDown(variant.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _host(
            variant,
            Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => openClipEditor(context, ref, clip),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      final editor = find.byType(
        type == SongTrackType.note ? SongNotePatternEditor : DrumMachineEditor,
      );
      expect(StudioPalette.of(tester.element(editor)), StudioPalette.legacy);
      if (type == SongTrackType.note) {
        final roll = tester.widget<PianoRollScreenV2>(
          find.byType(PianoRollScreenV2),
        );
        expect(roll.showBackground, isFalse);
        expect(roll.showSavePanels, isFalse);
        expect(roll.showScale, isFalse);
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
        await tester.pumpAndSettle();
      }
      variant.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      expect(StudioPalette.of(tester.element(editor)), StudioPalette.legacy);
      if (type == SongTrackType.drum) {
        expect(
          StudioPalette.of(tester.element(find.byKey(const Key('offsetPlus')))),
          StudioPalette.legacy,
        );
      } else {
        expect(
          StudioPalette.of(tester.element(find.text('Roll Settings'))),
          StudioPalette.legacy,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
