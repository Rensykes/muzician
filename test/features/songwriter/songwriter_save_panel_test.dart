import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_save_panel.dart';
import 'package:muzician/features/_mockup_shell.dart';

const _testStrumPattern = GuitarStrumPattern(
  id: 'test-strum-pattern',
  name: 'Down-up pattern',
  lengthTicks: 16,
  events: [GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down)],
);
const _testStrumSnapshot = WriterBlockSnapshot(
  laneKind: SongLaneKind.guitarStrum,
  guitarStrumPattern: _testStrumPattern,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('save panel captures the current songwriter project', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'V', lengthBars: 8);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterSavePanel())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600)); // drain debounce
    await tester.pumpAndSettle();

    final snap = songwriterCaptureForTest(container);
    expect(snap.instrument, 'songwriter');
    expect(snap.sections.single.label, 'V');
  });

  testWidgets('song versions and section blocks use separate tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _writerPanelContainer();
    addTearDown(container.dispose);
    SaveEntry? usedEntry;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterSavePanel(
              onUseInWriter: (entry) {
                usedEntry = entry;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Song versions'), findsOneWidget);
    expect(find.text('Section blocks'), findsOneWidget);
    expect(find.text('Saved song'), findsOneWidget);
    expect(find.text('Free strum'), findsNothing);

    await tester.tap(find.text('Section blocks'));
    await tester.pumpAndSettle();
    expect(find.text('Free strum'), findsOneWidget);
    expect(find.text('Free idea'), findsOneWidget);
    expect(find.text('Saved song'), findsNothing);

    await tester.tap(find.text('Free strum'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('useWriterSaveButton')));
    await tester.tap(find.byKey(const Key('useWriterSaveButton')));
    await tester.pumpAndSettle();
    expect(usedEntry?.id, 'free-block');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Writer save panel fits compact and wide viewports', (
    tester,
  ) async {
    final container = _writerPanelContainer();
    addTearDown(container.dispose);

    for (final size in [
      const Size(390, 844),
      const Size(800, 600),
      const Size(1180, 820),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SongwriterSavePanel())),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('Writer save sheet scrolls its save rows at short height', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        saveSystemProvider.overrideWith(
          () => _SeededSaveSystemNotifier(_manyWriterSavesState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    for (final viewport in [
      const Size(390, 300),
      const Size(390, 844),
      const Size(800, 600),
      const Size(1180, 820),
    ]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    key: const Key('openWriterSaveSheet'),
                    onPressed: () => showWidgetSheet(
                      context: context,
                      title: 'Browse saves',
                      scrollBody: false,
                      child: const SongwriterSavePanel(initialTabIndex: 1),
                    ),
                    child: const Text('Open saves'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('openWriterSaveSheet')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'viewport $viewport');

      if (viewport.height == 300) {
        final sheet = find
            .ancestor(
              of: find.text('Browse saves'),
              matching: find.byType(ClipRRect),
            )
            .first;
        final sheetRect = tester.getRect(sheet);
        final browserViewport = tester.getRect(find.byType(TabBarView));
        final verticalScrollables = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        );
        expect(verticalScrollables, findsOneWidget);
        await tester.drag(find.text('SAVES'), const Offset(0, -180));
        await tester.pumpAndSettle();
        await tester.drag(find.text('Save 00'), const Offset(0, -700));
        await tester.pumpAndSettle();
        await tester.drag(find.text('Save 10'), const Offset(0, -700));
        await tester.pumpAndSettle();

        final lastSaveRect = tester.getRect(find.text('Save 19'));
        expect(lastSaveRect.top, greaterThanOrEqualTo(sheetRect.top));
        expect(lastSaveRect.bottom, lessThanOrEqualTo(sheetRect.bottom));
        expect(lastSaveRect.top, greaterThanOrEqualTo(browserViewport.top));
        expect(lastSaveRect.bottom, lessThanOrEqualTo(browserViewport.bottom));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('root Writer block uses an explicit section and bar choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final saveId = saveSystem.saveSnapshot(
      'Free strum',
      projectId,
      _testStrumSnapshot,
    )!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterSavePanel())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Section blocks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free strum'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('useWriterSaveButton')));
    await tester.tap(find.byKey(const Key('useWriterSaveButton')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('writerSaveDestinationSection')),
      findsOneWidget,
    );
    expect(find.text('New Guitar strum lane will be created'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmUseWriterSave')));
    await tester.pumpAndSettle();

    final section = container
        .read(songwriterProvider)
        .sections
        .singleWhere((section) => section.id == sectionId);
    final lane = section.lanes.singleWhere(
      (candidate) => candidate.kind == SongLaneKind.guitarStrum,
    );
    final block = lane.blocks.single;
    expect(block.startBar, 0);
    expect(block.saveId, saveId);
    expect(
      container.read(saveSystemProvider).writerLinks.single.saveId,
      saveId,
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free strum'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed free strum');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId)
          .name,
      'Renamed free strum',
    );
  });

  testWidgets('legacy raw Harmony saves cannot be used in Writer', (
    tester,
  ) async {
    final fixture = _writerUseFixture(includeLegacyHarmony: true);
    addTearDown(fixture.container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: const MaterialApp(home: Scaffold(body: SongwriterSavePanel())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Section blocks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Legacy chord'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('useWriterSaveButton')), findsNothing);
    final project = fixture.container.read(songwriterProvider);
    expect(
      project.sections
          .expand((section) => section.lanes)
          .expand((lane) => lane.blocks),
      isEmpty,
    );
    expect(
      fixture.container
          .read(saveSystemProvider)
          .writerLinks
          .where((link) => link.saveId == 'legacy-harmony-block'),
      isEmpty,
    );
  });

  testWidgets(
    'invalid Writer destination bars show inline feedback and keep the value',
    (tester) async {
      const barFieldKey = Key('writerSaveDestinationBar');
      const confirmKey = Key('confirmUseWriterSave');
      for (final size in [const Size(390, 844), const Size(1180, 820)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final fixture = _writerUseFixture();
        addTearDown(fixture.container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: const MaterialApp(
              home: Scaffold(body: SongwriterSavePanel()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Section blocks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Free strum'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('useWriterSaveButton')),
        );
        await tester.tap(find.byKey(const Key('useWriterSaveButton')));
        await tester.pumpAndSettle();

        for (final invalidBar in ['0', '5']) {
          await tester.enterText(find.byKey(barFieldKey), invalidBar);
          await tester.tap(find.byKey(confirmKey));
          await tester.pumpAndSettle();

          expect(
            tester.state<FormFieldState<String>>(find.byKey(barFieldKey)).value,
            invalidBar,
          );
          expect(find.text('Enter a bar from 1 to 4.'), findsOneWidget);
          expect(
            fixture.container
                .read(songwriterProvider)
                .sections
                .expand((section) => section.lanes)
                .expand((lane) => lane.blocks),
            isEmpty,
          );
        }

        await tester.enterText(find.byKey(barFieldKey), '2');
        await tester.pumpAndSettle();
        expect(find.text('Enter a bar from 1 to 4.'), findsNothing);
        await tester.tap(find.byKey(confirmKey));
        await tester.pumpAndSettle();

        final blocks = fixture.container
            .read(songwriterProvider)
            .sections
            .expand((section) => section.lanes)
            .expand((lane) => lane.blocks);
        expect(blocks.single.startBar, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'a section Writer save can be reused in another section with one canonical save',
    (tester) async {
      for (final size in [const Size(390, 844), const Size(1180, 820)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final fixture = _sectionReuseFixture();
        addTearDown(fixture.container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: const MaterialApp(
              home: Scaffold(body: SongwriterSavePanel()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Section blocks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verse'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shared strum'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('useWriterSaveButton')),
        );
        await tester.tap(find.byKey(const Key('useWriterSaveButton')));
        await tester.pumpAndSettle();

        final sectionField = find.byKey(
          const Key('writerSaveDestinationSection'),
        );
        await tester.tap(sectionField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chorus').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmUseWriterSave')));
        await tester.pumpAndSettle();

        final writer = fixture.container.read(songwriterProvider);
        final chorus = writer.sections.singleWhere(
          (section) => section.id == fixture.chorusSectionId,
        );
        final strumLane = chorus.lanes.singleWhere(
          (lane) => lane.id == fixture.chorusStrumLaneId,
        );
        expect(strumLane.blocks.single.saveId, fixture.saveId);

        final saveState = fixture.container.read(saveSystemProvider);
        final links = saveState.writerLinks
            .where((link) => link.saveId == fixture.saveId)
            .toList();
        expect(links, hasLength(2));
        expect(links.map((link) => link.sectionId).toSet(), {
          fixture.verseSectionId,
          fixture.chorusSectionId,
        });
        expect(
          saveState.saves.where((save) => save.id == fixture.saveId),
          hasLength(1),
        );

        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shared strum'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Shared strum renamed');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          fixture.container
              .read(saveSystemProvider)
              .saves
              .singleWhere((save) => save.id == fixture.saveId)
              .name,
          'Shared strum renamed',
        );
        expect(
          fixture.container
              .read(saveSystemProvider)
              .writerLinks
              .where((link) => link.saveId == fixture.saveId),
          hasLength(2),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'Use in Writer preserves the selected strum lane harmony anchor',
    (tester) async {
      for (final size in [const Size(390, 844), const Size(1180, 820)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final fixture = _strumAnchorFixture();
        addTearDown(fixture.container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: const MaterialApp(
              home: Scaffold(body: SongwriterSavePanel()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Section blocks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Strum idea'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('useWriterSaveButton')),
        );
        await tester.tap(find.byKey(const Key('useWriterSaveButton')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            ValueKey('writerSaveDestinationLane_${fixture.sectionId}'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Secondary strum (lane 2)'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmUseWriterSave')));
        await tester.pumpAndSettle();

        final section = fixture.container
            .read(songwriterProvider)
            .sections
            .singleWhere((candidate) => candidate.id == fixture.sectionId);
        final lane = section.lanes.singleWhere(
          (candidate) => candidate.id == fixture.strumLaneId,
        );
        expect(lane.anchorLaneId, fixture.secondaryHarmonyLaneId);
        expect(lane.blocks.single.saveId, fixture.saveId);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'Use in Writer selects a same-kind lane and resets it when section changes',
    (tester) async {
      for (final size in [const Size(390, 844), const Size(1180, 820)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final fixture = _writerUseFixture();
        addTearDown(fixture.container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: const MaterialApp(
              home: Scaffold(body: SongwriterSavePanel()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Section blocks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Free strum'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('useWriterSaveButton')),
        );
        await tester.tap(find.byKey(const Key('useWriterSaveButton')));
        await tester.pumpAndSettle();

        final verseLaneField = find.byKey(
          ValueKey('writerSaveDestinationLane_${fixture.verseSectionId}'),
        );
        await tester.tap(verseLaneField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verse overlay (lane 2)'));
        await tester.pumpAndSettle();

        final sectionField = find.byKey(
          const Key('writerSaveDestinationSection'),
        );
        await tester.tap(sectionField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chorus').last);
        await tester.pumpAndSettle();
        expect(find.text('Chorus lead (lane 1)'), findsOneWidget);
        expect(
          find.byKey(
            ValueKey('writerSaveDestinationLane_${fixture.chorusSectionId}'),
          ),
          findsOneWidget,
        );

        await tester.tap(sectionField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verse').last);
        await tester.pumpAndSettle();
        expect(find.text('Verse primary (lane 1)'), findsOneWidget);

        await tester.tap(verseLaneField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verse overlay (lane 2)'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmUseWriterSave')));
        await tester.pumpAndSettle();

        final verse = fixture.container
            .read(songwriterProvider)
            .sections
            .singleWhere((section) => section.id == fixture.verseSectionId);
        final strumLanes = verse.lanes
            .where((lane) => lane.kind == SongLaneKind.guitarStrum)
            .toList();
        expect(strumLanes[0].id, fixture.primaryLaneId);
        expect(strumLanes[0].blocks, isEmpty);
        expect(strumLanes[1].id, fixture.overlayLaneId);
        expect(strumLanes[1].blocks.single.saveId, fixture.saveId);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}

_WriterUseFixture _writerUseFixture({bool includeLegacyHarmony = false}) {
  const verseSectionId = 'verse';
  const chorusSectionId = 'chorus';
  const primaryLaneId = 'verse-primary';
  const overlayLaneId = 'verse-overlay';
  const saveId = 'free-block';
  const verseHarmonyLaneId = 'verse-harmony';
  const chorusHarmonyLaneId = 'chorus-harmony';
  const writerState = SongwriterProjectSnapshot(
    config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    guitarStrumPatterns: [_testStrumPattern],
    sections: [
      SongSection(
        id: verseSectionId,
        label: 'Verse',
        lengthBars: 4,
        order: 0,
        lanes: [
          SongLane(
            id: verseHarmonyLaneId,
            kind: SongLaneKind.harmony,
            label: 'Verse harmony',
            order: 0,
          ),
          SongLane(
            id: primaryLaneId,
            kind: SongLaneKind.guitarStrum,
            label: 'Verse primary',
            order: 1,
            anchorLaneId: verseHarmonyLaneId,
          ),
          SongLane(
            id: overlayLaneId,
            kind: SongLaneKind.guitarStrum,
            label: 'Verse overlay',
            order: 2,
            anchorLaneId: verseHarmonyLaneId,
          ),
        ],
      ),
      SongSection(
        id: chorusSectionId,
        label: 'Chorus',
        lengthBars: 4,
        order: 1,
        lanes: [
          SongLane(
            id: chorusHarmonyLaneId,
            kind: SongLaneKind.harmony,
            label: 'Chorus harmony',
            order: 0,
          ),
          SongLane(
            id: 'chorus-lead',
            kind: SongLaneKind.guitarStrum,
            label: 'Chorus lead',
            order: 1,
            anchorLaneId: chorusHarmonyLaneId,
          ),
        ],
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      saveSystemProvider.overrideWith(
        () => _SeededSaveSystemNotifier(
          _writerPanelSaveState(includeLegacyHarmony: includeLegacyHarmony),
        ),
      ),
      songwriterProvider.overrideWith(
        () => _SeededSongwriterNotifier(writerState),
      ),
    ],
  );

  return _WriterUseFixture(
    container: container,
    verseSectionId: verseSectionId,
    chorusSectionId: chorusSectionId,
    primaryLaneId: primaryLaneId,
    overlayLaneId: overlayLaneId,
    saveId: saveId,
  );
}

class _WriterUseFixture {
  final ProviderContainer container;
  final String verseSectionId;
  final String chorusSectionId;
  final String primaryLaneId;
  final String overlayLaneId;
  final String saveId;

  const _WriterUseFixture({
    required this.container,
    required this.verseSectionId,
    required this.chorusSectionId,
    required this.primaryLaneId,
    required this.overlayLaneId,
    required this.saveId,
  });
}

_SectionReuseFixture _sectionReuseFixture() {
  const verseSectionId = 'verse';
  const chorusSectionId = 'chorus';
  const saveId = 'shared-writer-strum';
  const strumLaneId = 'verse-strum';
  const chorusStrumLaneId = 'chorus-strum';
  const writerPattern = GuitarStrumPattern(
    id: 'shared-strum-pattern',
    name: 'Down-up groove',
    lengthTicks: 16,
    events: [GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down)],
  );
  const writerSnapshot = WriterBlockSnapshot(
    laneKind: SongLaneKind.guitarStrum,
    guitarStrumPattern: writerPattern,
  );
  const writerState = SongwriterProjectSnapshot(
    config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    guitarStrumPatterns: [writerPattern],
    sections: [
      SongSection(
        id: verseSectionId,
        label: 'Verse',
        lengthBars: 4,
        order: 0,
        lanes: [
          SongLane(
            id: 'verse-harmony',
            kind: SongLaneKind.harmony,
            label: 'Verse harmony',
            order: 0,
          ),
          SongLane(
            id: strumLaneId,
            kind: SongLaneKind.guitarStrum,
            label: 'Verse strum',
            order: 1,
            anchorLaneId: 'verse-harmony',
            blocks: [
              SongBlock(
                id: 'verse-strum-block',
                startBar: 0,
                spanBars: 1,
                saveId: saveId,
                embedded: writerSnapshot,
                patternId: 'shared-strum-pattern',
              ),
            ],
          ),
        ],
      ),
      SongSection(
        id: chorusSectionId,
        label: 'Chorus',
        lengthBars: 4,
        order: 1,
        lanes: [
          SongLane(
            id: 'chorus-harmony',
            kind: SongLaneKind.harmony,
            label: 'Chorus harmony',
            order: 0,
          ),
          SongLane(
            id: chorusStrumLaneId,
            kind: SongLaneKind.guitarStrum,
            label: 'Chorus strum',
            order: 1,
            anchorLaneId: 'chorus-harmony',
          ),
        ],
      ),
    ],
  );
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const verseFolder = SaveFolder(
    id: 'verse-folder',
    name: 'Verse',
    parentId: 'project',
    createdAt: 2,
    order: 0,
    writerSectionId: verseSectionId,
  );
  const chorusFolder = SaveFolder(
    id: 'chorus-folder',
    name: 'Chorus',
    parentId: 'project',
    createdAt: 3,
    order: 1,
    writerSectionId: chorusSectionId,
  );
  const save = SaveEntry(
    id: saveId,
    name: 'Shared strum',
    folderId: 'verse-folder',
    snapshot: writerSnapshot,
    createdAt: 4,
    updatedAt: 4,
    order: 0,
    origin: SaveOrigin.writer,
  );
  final container = ProviderContainer(
    overrides: [
      saveSystemProvider.overrideWith(
        () => _SeededSaveSystemNotifier(
          const SaveSystemState(
            folders: [project, verseFolder, chorusFolder],
            saves: [save],
            writerLinks: [
              WriterSaveLink(
                blockId: 'verse-strum-block',
                sectionId: verseSectionId,
                folderId: 'verse-folder',
                saveId: saveId,
                laneKind: SongLaneKind.guitarStrum,
              ),
            ],
            hydrated: true,
            selectedProjectId: 'project',
          ),
        ),
      ),
      songwriterProvider.overrideWith(
        () => _SeededSongwriterNotifier(writerState),
      ),
    ],
  );
  return _SectionReuseFixture(
    container: container,
    verseSectionId: verseSectionId,
    chorusSectionId: chorusSectionId,
    chorusStrumLaneId: chorusStrumLaneId,
    saveId: saveId,
  );
}

class _SectionReuseFixture {
  final ProviderContainer container;
  final String verseSectionId;
  final String chorusSectionId;
  final String chorusStrumLaneId;
  final String saveId;

  const _SectionReuseFixture({
    required this.container,
    required this.verseSectionId,
    required this.chorusSectionId,
    required this.chorusStrumLaneId,
    required this.saveId,
  });
}

_StrumAnchorFixture _strumAnchorFixture() {
  const sectionId = 'verse';
  const secondaryHarmonyLaneId = 'harmony-secondary';
  const strumLaneId = 'strum-secondary';
  const saveId = 'strum-save';
  const pattern = GuitarStrumPattern(
    id: 'strum-pattern',
    name: 'Down-up pattern',
    lengthTicks: 16,
    events: [GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down)],
  );
  const writerSnapshot = WriterBlockSnapshot(
    laneKind: SongLaneKind.guitarStrum,
    guitarStrumPattern: pattern,
  );
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const writerState = SongwriterProjectSnapshot(
    config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    sections: [
      SongSection(
        id: sectionId,
        label: 'Verse',
        lengthBars: 4,
        order: 0,
        lanes: [
          SongLane(
            id: 'harmony-primary',
            kind: SongLaneKind.harmony,
            label: 'Primary harmony',
            order: 0,
          ),
          SongLane(
            id: secondaryHarmonyLaneId,
            kind: SongLaneKind.harmony,
            label: 'Secondary harmony',
            order: 1,
          ),
          SongLane(
            id: 'strum-primary',
            kind: SongLaneKind.guitarStrum,
            label: 'Primary strum',
            order: 2,
          ),
          SongLane(
            id: strumLaneId,
            kind: SongLaneKind.guitarStrum,
            label: 'Secondary strum',
            order: 3,
            anchorLaneId: secondaryHarmonyLaneId,
          ),
        ],
      ),
    ],
  );
  const save = SaveEntry(
    id: saveId,
    name: 'Strum idea',
    folderId: 'project',
    snapshot: writerSnapshot,
    createdAt: 2,
    updatedAt: 2,
    order: 0,
  );
  final container = ProviderContainer(
    overrides: [
      saveSystemProvider.overrideWith(
        () => _SeededSaveSystemNotifier(
          const SaveSystemState(
            folders: [project],
            saves: [save],
            hydrated: true,
            selectedProjectId: 'project',
          ),
        ),
      ),
      songwriterProvider.overrideWith(
        () => _SeededSongwriterNotifier(writerState),
      ),
    ],
  );
  return _StrumAnchorFixture(
    container: container,
    sectionId: sectionId,
    secondaryHarmonyLaneId: secondaryHarmonyLaneId,
    strumLaneId: strumLaneId,
    saveId: saveId,
  );
}

class _StrumAnchorFixture {
  final ProviderContainer container;
  final String sectionId;
  final String secondaryHarmonyLaneId;
  final String strumLaneId;
  final String saveId;

  const _StrumAnchorFixture({
    required this.container,
    required this.sectionId,
    required this.secondaryHarmonyLaneId,
    required this.strumLaneId,
    required this.saveId,
  });
}

ProviderContainer _writerPanelContainer() {
  return ProviderContainer(
    overrides: [
      saveSystemProvider.overrideWith(
        () => _SeededSaveSystemNotifier(_writerPanelSaveState()),
      ),
    ],
  );
}

SaveSystemState _writerPanelSaveState({bool includeLegacyHarmony = false}) {
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const version = SaveEntry(
    id: 'song-version',
    name: 'Saved song',
    folderId: 'project',
    snapshot: SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    ),
    createdAt: 2,
    updatedAt: 2,
    order: 0,
  );
  const freeBlock = SaveEntry(
    id: 'free-block',
    name: 'Free strum',
    folderId: 'project',
    snapshot: _testStrumSnapshot,
    createdAt: 3,
    updatedAt: 3,
    order: 1,
  );
  const legacyHarmonyBlock = SaveEntry(
    id: 'legacy-harmony-block',
    name: 'Legacy chord',
    folderId: 'project',
    snapshot: WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      chordSymbol: 'C',
      chordQuality: '',
      chordRootPc: 0,
      chordNotes: ['C', 'E', 'G'],
    ),
    createdAt: 4,
    updatedAt: 4,
    order: 2,
  );
  return SaveSystemState(
    folders: const [project],
    saves: [
      version,
      if (!includeLegacyHarmony) freeBlock,
      if (includeLegacyHarmony) legacyHarmonyBlock,
    ],
    hydrated: true,
    selectedProjectId: 'project',
  );
}

SaveSystemState _manyWriterSavesState() {
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  return SaveSystemState(
    folders: const [project],
    saves: List.generate(
      20,
      (index) => SaveEntry(
        id: 'save-${index.toString().padLeft(2, '0')}',
        name: 'Save ${index.toString().padLeft(2, '0')}',
        folderId: 'project',
        snapshot: const WriterBlockSnapshot(
          laneKind: SongLaneKind.harmony,
          chordSymbol: 'Am7',
        ),
        createdAt: index + 2,
        updatedAt: index + 2,
        order: index,
      ),
    ),
    hydrated: true,
    selectedProjectId: 'project',
  );
}

class _SeededSaveSystemNotifier extends SaveSystemNotifier {
  final SaveSystemState seed;

  _SeededSaveSystemNotifier(this.seed);

  @override
  SaveSystemState build() => seed;
}

class _SeededSongwriterNotifier extends SongwriterNotifier {
  final SongwriterProjectSnapshot seed;

  _SeededSongwriterNotifier(this.seed);

  @override
  SongwriterProjectSnapshot build() => seed;
}
