import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard_save_panel.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/piano/piano_save_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'native save toolbar stays compact with a linked banner at compact and wide sizes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final instrument in HarmonyLaneInstrument.values) {
        final container = ProviderContainer();
        await container.read(saveSystemProvider.notifier).hydrate();
        final saves = container.read(saveSystemProvider.notifier);
        final projectId = saves.createProject(
          'Toolbar project',
          ProjectConfig(defaultHarmonyInstrument: instrument),
        )!;
        saves.selectProject(projectId);
        final writer = container.read(songwriterProvider.notifier);
        await writer.reconcileCurrentProject();
        writer.addSection(label: 'Verse', lengthBars: 4);
        final section = container.read(songwriterProvider).sections.single;
        expect(
          writer.insertInstrumentSelectionAtBar(
            sectionId: section.id,
            startBar: 0,
            snapshot: _nativeSnapshot(instrument),
            asExactHarmony: true,
            chordSymbol: '$instrument cluster',
            saveName: '$instrument cluster',
            expectedProjectId: projectId,
          ),
          isTrue,
        );
        await writer.reconcileCurrentProject();
        final saveId = container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .saveId!;

        for (final viewport in [
          (size: const Size(390, 844), scale: 1.0),
          (size: const Size(390, 844), scale: 1.6),
          (size: const Size(1180, 820), scale: 1.0),
          (size: const Size(1180, 820), scale: 1.6),
        ]) {
          tester.view.physicalSize = viewport.size;
          tester.view.devicePixelRatio = 1;
          final panel = switch (instrument) {
            HarmonyLaneInstrument.fretboard => FretboardSavePanel(
              linkedEditSaveId: saveId,
            ),
            HarmonyLaneInstrument.piano => PianoSavePanel(
              linkedEditSaveId: saveId,
            ),
          };
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(viewport.scale)),
                  child: child!,
                ),
                home: Scaffold(body: SingleChildScrollView(child: panel)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Toolbar project'), findsOneWidget);
          expect(find.text('SAVES'), findsOneWidget);
          final linkedUpdate = find.byKey(const Key('updateLinkedSaveButton'));
          expect(linkedUpdate, findsOneWidget);
          final bannerRect = tester.getRect(linkedUpdate);
          expect(
            bannerRect.width,
            greaterThan(viewport.size.width * 0.8),
            reason: 'the linked update banner should remain full width',
          );
          expect(bannerRect.width, greaterThanOrEqualTo(44));
          expect(bannerRect.height, greaterThanOrEqualTo(44));
          expect(bannerRect.left, greaterThanOrEqualTo(0));
          expect(bannerRect.right, lessThanOrEqualTo(viewport.size.width));

          for (final key in [
            'saveBrowserGridToggle',
            'saveBrowserSaveHere',
            'saveBrowserNewFolder',
            'saveBrowserEditToggle',
          ]) {
            final control = find.byKey(Key(key));
            await tester.ensureVisible(control);
            final rect = tester.getRect(control);
            expect(rect.width, greaterThanOrEqualTo(44), reason: key);
            expect(rect.height, greaterThanOrEqualTo(44), reason: key);
            expect(
              rect.width,
              lessThan(220),
              reason: '$key should wrap at its compact content width',
            );
            expect(rect.left, greaterThanOrEqualTo(0), reason: key);
            expect(
              rect.right,
              lessThanOrEqualTo(viewport.size.width),
              reason: key,
            );
          }

          await tester.tap(find.byKey(const Key('saveBrowserEditToggle')));
          await tester.pumpAndSettle();
          expect(find.text('Done'), findsOneWidget);
          await tester.tap(find.byKey(const Key('saveBrowserEditToggle')));
          await tester.pumpAndSettle();
          expect(find.text('Edit'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    },
  );
}

FretboardSnapshot _cMajorFretboard() => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [
    FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
    FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
    FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
  ],
  selectedNotes: const ['C', 'E', 'G'],
  viewMode: FretboardViewMode.exact,
  inputMode: FretboardInputMode.chord,
);

InstrumentSnapshot _nativeSnapshot(HarmonyLaneInstrument instrument) =>
    switch (instrument) {
      HarmonyLaneInstrument.fretboard => _cMajorFretboard(),
      HarmonyLaneInstrument.piano => PianoSnapshot(
        currentRange: PianoRangeName.key88,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 39, midiNote: 60, noteName: 'C'),
          PianoCoordinate(keyIndex: 43, midiNote: 64, noteName: 'E'),
          PianoCoordinate(keyIndex: 46, midiNote: 67, noteName: 'G'),
        ],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: PianoViewMode.exact,
      ),
    };
