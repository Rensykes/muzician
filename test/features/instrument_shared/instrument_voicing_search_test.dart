import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/chord_diagram.dart';
import 'package:muzician/features/piano/piano_chord_diagram.dart';
import 'package:muzician/features/instrument_shared/instrument_voicing_search.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/utils/note_utils.dart' show noteToPC;
import 'package:shared_preferences/shared_preferences.dart';

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

int _resultCount(WidgetTester tester) =>
    int.parse(_text(tester, 'voicingResultCount').split(' ').first);

void _selectQuery(ProviderContainer container, bool guitar) {
  if (guitar) {
    final store = container.read(fretboardProvider.notifier);
    store.toggleCell(0, 0, 'E');
    store.toggleCell(1, 1, 'C');
  } else {
    container.read(pianoProvider.notifier).loadExactMidis([60, 64]);
  }
}

Object _selection(ProviderContainer container, bool guitar) => guitar
    ? container.read(fretboardProvider).selectedCells
    : container.read(pianoProvider).selectedKeys;

Future<void> _pumpSearch(
  WidgetTester tester,
  ProviderContainer container, {
  required bool guitar,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: StudioTheme.data(AppThemeVariant.studio),
        home: Scaffold(
          body: SingleChildScrollView(
            child: InstrumentVoicingSearch(guitar: guitar),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectDisplayedVoicingsInCMajor(WidgetTester tester, bool guitar) {
  const allowed = {0, 2, 4, 5, 7, 9, 11};
  if (guitar) {
    final diagrams = tester.widgetList<ChordDiagram>(find.byType(ChordDiagram));
    expect(diagrams, isNotEmpty);
    for (final diagram in diagrams) {
      for (
        var string = 0;
        string < diagram.voicing.positions.length;
        string++
      ) {
        final fret = diagram.voicing.positions[string];
        if (fret == null) continue;
        expect(
          allowed,
          contains((noteToPC[diagram.openNotes[string]]! + fret) % 12),
        );
      }
    }
  } else {
    final diagrams = tester.widgetList<PianoChordDiagram>(
      find.byType(PianoChordDiagram),
    );
    expect(diagrams, isNotEmpty);
    for (final diagram in diagrams) {
      expect(
        diagram.midis.map((midi) => midi % 12),
        everyElement(isIn(allowed)),
      );
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final guitar in [true, false]) {
    testWidgets(
      '${guitar ? 'Guitar' : 'Piano'} local scale filters notes and refreshes on change or clear',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        _selectQuery(container, guitar);
        final selection = _selection(container, guitar);
        await _pumpSearch(
          tester,
          container,
          guitar: guitar,
          size: const Size(390, 800),
        );
        final unfilteredCount = _resultCount(tester);
        expect(unfilteredCount, greaterThan(0));
        final scale = container.read(
          (guitar ? activeScaleProvider : pianoActiveScaleProvider).notifier,
        );
        scale.state = (root: 'C', scaleName: 'major');
        await tester.pumpAndSettle();
        final filteredCount = _resultCount(tester);
        expect(filteredCount, greaterThan(0));
        expect(filteredCount, lessThan(unfilteredCount));
        _expectDisplayedVoicingsInCMajor(tester, guitar);

        // The same captured E cannot belong to C minor or C-sharp major.
        scale.state = (root: 'C', scaleName: 'minor');
        await tester.pumpAndSettle();
        expect(_resultCount(tester), 0);
        scale.state = (root: 'C', scaleName: 'major');
        await tester.pumpAndSettle();
        expect(_resultCount(tester), filteredCount);
        scale.state = (root: 'C#', scaleName: 'major');
        await tester.pumpAndSettle();
        expect(_resultCount(tester), 0);
        scale.state = null;
        await tester.pumpAndSettle();
        expect(_resultCount(tester), unfilteredCount);
        expect(_text(tester, 'voicingNoteQuery'), 'Containing C · E');
        expect(_selection(container, guitar), same(selection));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${guitar ? 'Guitar' : 'Piano'} project scale overrides local scale and keeps By chord available',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final saves = container.read(saveSystemProvider.notifier);
        final projectId = saves.createProject(
          'Scale test',
          const ProjectConfig(),
        )!;
        saves.selectProject(projectId);
        _selectQuery(container, guitar);
        await _pumpSearch(
          tester,
          container,
          guitar: guitar,
          size: const Size(1024, 768),
        );
        final unfilteredCount = _resultCount(tester);
        const cMajor = ProjectConfig(keyRootPc: 0, keyScaleName: 'major');
        final localScale = container.read(
          (guitar ? activeScaleProvider : pianoActiveScaleProvider).notifier,
        );
        localScale.state = (root: 'C', scaleName: 'minor');
        saves.updateProjectConfig(projectId, cMajor);
        await tester.pumpAndSettle();
        final filteredCount = _resultCount(tester);
        expect(filteredCount, greaterThan(0));
        expect(filteredCount, lessThan(unfilteredCount));
        _expectDisplayedVoicingsInCMajor(tester, guitar);

        saves.updateProjectConfig(
          projectId,
          cMajor.copyWith(keyScaleName: 'minor'),
        );
        await tester.pumpAndSettle();
        expect(_resultCount(tester), 0);
        saves.updateProjectConfig(projectId, cMajor);
        await tester.pumpAndSettle();
        expect(_resultCount(tester), filteredCount);
        saves.updateProjectConfig(projectId, cMajor.copyWith(keyRootPc: 1));
        await tester.pumpAndSettle();
        expect(_resultCount(tester), 0);
        saves.updateProjectConfig(projectId, const ProjectConfig());
        await tester.pumpAndSettle();
        // With the project key cleared, the local C minor filter still applies.
        expect(_resultCount(tester), 0);
        localScale.state = null;
        await tester.pumpAndSettle();
        expect(_resultCount(tester), unfilteredCount);
        saves.updateProjectConfig(projectId, cMajor);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byType(guitar ? ChordDiagram : PianoChordDiagram).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Chord outside the key'), findsNothing);
        expect(find.text('✓ Applied'), findsOneWidget);
        expect(_text(tester, 'voicingNoteQuery'), 'Containing C · E');
        expect(_resultCount(tester), filteredCount);

        await tester.tap(find.byKey(const Key('voicingsByChord')));
        await tester.pumpAndSettle();
        final selectors = find.byType(DropdownButton<String>);
        tester.widget<DropdownButton<String>>(selectors.first).onChanged!('D');
        tester.widget<DropdownButton<String>>(selectors.last).onChanged!('');
        await tester.pumpAndSettle();
        expect(_resultCount(tester), greaterThan(0));
        await tester.tap(
          find.byType(guitar ? ChordDiagram : PianoChordDiagram).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Chord outside the key'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${guitar ? 'Guitar' : 'Piano'} query survives application and mode changes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        if (guitar) {
          final store = container.read(fretboardProvider.notifier);
          store.toggleCell(0, 0, 'E');
          store.toggleCell(1, 1, 'C');
        } else {
          container.read(pianoProvider.notifier).loadExactMidis([60, 64]);
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: StudioTheme.data(AppThemeVariant.studio),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: InstrumentVoicingSearch(guitar: guitar),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final originalQuery = _text(tester, 'voicingNoteQuery');
        final originalCount = _text(tester, 'voicingResultCount');
        expect(originalQuery, 'Containing C · E');
        final carousel = find.byKey(const Key('voicingCarousel'));
        expect(
          tester.widget<ListView>(carousel).scrollDirection,
          Axis.horizontal,
        );
        await tester.drag(carousel, const Offset(-200, 0));
        await tester.pumpAndSettle();
        final controller = tester.widget<ListView>(carousel).controller!;
        final offset = controller.offset;
        expect(offset, greaterThan(0));
        final diagram = find
            .byType(guitar ? ChordDiagram : PianoChordDiagram)
            .hitTestable()
            .first;
        await tester.tap(diagram);
        await tester.pumpAndSettle();
        expect(_text(tester, 'voicingNoteQuery'), originalQuery);
        expect(_text(tester, 'voicingResultCount'), originalCount);
        expect(controller.offset, closeTo(offset, .01));
        expect(find.text('✓ Applied'), findsOneWidget);
        expect(
          container.read(
            guitar
                ? fretboardChordCommittedProvider
                : pianoChordCommittedProvider,
          ),
          isTrue,
        );

        await tester.tap(find.byKey(const Key('voicingsByChord')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('voicingNoteQuery')), findsNothing);
        // By chord has independent root/quality controls, even with a note query.
        final root = find.byType(DropdownButton<String>).first;
        tester.widget<DropdownButton<String>>(root).onChanged!('D');
        await tester.pumpAndSettle();
        final dCount = _text(tester, 'voicingResultCount');
        expect(dCount, isNot(startsWith('0 ')));
        await tester.tap(find.byKey(const Key('voicingsFromNotes')));
        await tester.pumpAndSettle();
        expect(_text(tester, 'voicingNoteQuery'), originalQuery);
        expect(_text(tester, 'voicingResultCount'), originalCount);
        await tester.tap(find.byKey(const Key('voicingsByChord')));
        await tester.pumpAndSettle();
        expect(tester.widget<DropdownButton<String>>(root).value, 'D');
        expect(_text(tester, 'voicingResultCount'), dCount);
        await tester.tap(find.byKey(const Key('voicingsFromNotes')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('voicingsUseCurrentNotes')));
        await tester.pumpAndSettle();
        expect(_text(tester, 'voicingNoteQuery'), isNot(originalQuery));

        if (guitar) {
          container.read(fretboardProvider.notifier).clearSelectedNotes();
          container.read(fretboardProvider.notifier).toggleCell(0, 1, 'F');
        } else {
          container.read(pianoProvider.notifier).clearSelectedNotes();
          container.read(pianoProvider.notifier).toggleKey(29, 65, 'F');
        }
        await tester.pumpAndSettle();
        expect(_text(tester, 'voicingNoteQuery'), 'Containing F');
        expect(find.text('✓ Applied'), findsNothing);
        expect(
          container.read(
            guitar
                ? fretboardChordCommittedProvider
                : pianoChordCommittedProvider,
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'pending detected chord selects By chord without applying notes',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pianoProvider.notifier).loadExactMidis([60, 64]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioTheme.data(AppThemeVariant.studio),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: InstrumentVoicingSearch(guitar: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selection = container.read(pianoProvider).selectedKeys;
      container.read(pianoPendingChordProvider.notifier).state = (
        root: 'F',
        quality: 'maj7',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voicingNoteQuery')), findsNothing);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'F',
      );
      expect(container.read(pianoProvider).selectedKeys, same(selection));
      expect(container.read(pianoPendingChordProvider), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
