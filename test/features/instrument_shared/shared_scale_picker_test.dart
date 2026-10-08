import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/shared_scale_picker.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_settings_notifier.dart';

// Label for the Major scale pill, from scaleGroups[ScaleCategory.common].
const _majorLabel = 'Major';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAtSize(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Fretboard binding: selecting root+scale shows named chip', (
    tester,
  ) async {
    await _pump(tester, SharedScalePicker(binding: fretboardBinding));
    final rootTarget = find.byKey(const ValueKey('sharedScaleRoot_C'));
    final rootArtwork = find.byKey(const ValueKey('sharedScaleRootArtwork_C'));
    final scaleTarget = find.byKey(const ValueKey('sharedScaleType_major'));
    final scaleArtwork = find.byKey(
      const ValueKey('sharedScaleTypeArtwork_major'),
    );
    expect(tester.getSize(rootTarget).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(rootArtwork).height, lessThan(44));
    expect(tester.getSize(scaleTarget).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(scaleArtwork).height, lessThan(44));
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_majorLabel).first);
    await tester.pumpAndSettle();
    expect(find.text('C major'), findsOneWidget);
    expect(find.text('✕'), findsOneWidget);
  });

  testWidgets('Piano binding: selecting root+scale shows named chip', (
    tester,
  ) async {
    await _pump(tester, SharedScalePicker(binding: pianoBinding));
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_majorLabel).first);
    await tester.pumpAndSettle();
    expect(find.text('C major'), findsOneWidget);
    expect(find.text('✕'), findsOneWidget);
  });

  testWidgets(
    'local clear target resets scale state and preserves project configuration',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final projectId = container
          .read(saveSystemProvider.notifier)
          .createProject(
            'Saved project',
            const ProjectConfig(keyRootPc: 7, keyScaleName: 'major'),
          )!;
      expect(container.read(selectedProjectProvider), isNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SharedScalePicker(binding: fretboardBinding)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rootTarget = find.byKey(const ValueKey('sharedScaleRoot_C'));
      await tester.tapAt(
        tester.getRect(rootTarget).bottomRight - const Offset(1, 1),
      );
      await tester.pumpAndSettle();
      final majorTarget = find.byKey(const ValueKey('sharedScaleType_major'));
      await tester.tapAt(
        tester.getRect(majorTarget).bottomRight - const Offset(1, 1),
      );
      await tester.pumpAndSettle();

      expect(container.read(fretboardBinding.activeScale), (
        root: 'C',
        scaleName: 'major',
      ));
      expect(container.read(fretboardProvider).highlightedNotes, isNotEmpty);

      final semantics = tester.ensureSemantics();
      const clearLabel = 'Clear scale selection';
      final clearTarget = find.byKey(const Key('sharedScaleLocalClear'));
      expect(find.bySemanticsLabel(clearLabel), findsOneWidget);
      expect(tester.getSize(clearTarget), const Size(44, 44));
      final clearBounds = tester.getRect(clearTarget);
      await tester.tapAt(clearBounds.bottomRight - const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(container.read(fretboardBinding.activeScale), isNull);
      expect(container.read(fretboardProvider).highlightedNotes, isEmpty);
      expect(find.byKey(const Key('sharedScaleLocalClear')), findsNothing);
      expect(container.read(selectedProjectProvider), isNull);
      final savedProject = container
          .read(projectsListProvider)
          .singleWhere((project) => project.id == projectId);
      expect(savedProject.projectConfig?.keyRootPc, 7);
      expect(savedProject.projectConfig?.keyScaleName, 'major');

      final dRootTarget = find.byKey(const ValueKey('sharedScaleRoot_D'));
      await tester.tapAt(
        tester.getRect(dRootTarget).bottomRight - const Offset(1, 1),
      );
      await tester.pumpAndSettle();
      expect(container.read(fretboardBinding.activeScale), isNull);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('flat root labels keep canonical scale state', (tester) async {
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SharedScalePicker(binding: fretboardBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dbRootTarget = find.byKey(const ValueKey('sharedScaleRoot_C#'));
    final rootBounds = tester.getRect(dbRootTarget);
    expect(rootBounds.width, greaterThanOrEqualTo(44));
    expect(rootBounds.height, greaterThanOrEqualTo(44));
    await tester.tapAt(rootBounds.bottomRight - const Offset(1, 1));
    await tester.pumpAndSettle();
    final majorTarget = find.byKey(const ValueKey('sharedScaleType_major'));
    final scaleBounds = tester.getRect(majorTarget);
    expect(scaleBounds.width, greaterThanOrEqualTo(44));
    expect(scaleBounds.height, greaterThanOrEqualTo(44));
    await tester.tapAt(scaleBounds.bottomRight - const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.text('Db major'), findsOneWidget);
    expect(container.read(fretboardBinding.activeScale), (
      root: 'C#',
      scaleName: 'major',
    ));
    expect(container.read(fretboardProvider).highlightedNotes, contains('C#'));
  });

  testWidgets(
    'natural root and scale targets stay compact and at least 44 by 44',
    (tester) async {
      for (final size in [const Size(320, 800), const Size(1024, 800)]) {
        await _pumpAtSize(
          tester,
          SharedScalePicker(binding: fretboardBinding),
          size: size,
          textScale: 1.6,
        );

        final rootTarget = find.byKey(const ValueKey('sharedScaleRoot_C'));
        final rootArtwork = find.byKey(
          const ValueKey('sharedScaleRootArtwork_C'),
        );
        final scaleTarget = find.byKey(const ValueKey('sharedScaleType_major'));
        final scaleArtwork = find.byKey(
          const ValueKey('sharedScaleTypeArtwork_major'),
        );
        final rootBounds = tester.getSize(rootTarget);
        final rootArtworkBounds = tester.getSize(rootArtwork);
        final scaleBounds = tester.getSize(scaleTarget);
        final scaleArtworkBounds = tester.getSize(scaleArtwork);

        expect(rootBounds.width, greaterThanOrEqualTo(44));
        expect(rootBounds.height, greaterThanOrEqualTo(44));
        expect(scaleBounds.width, greaterThanOrEqualTo(44));
        expect(scaleBounds.height, greaterThanOrEqualTo(44));
        expect(rootBounds.width, lessThan(100));
        expect(rootBounds.width, closeTo(rootArtworkBounds.width, 0.1));
        expect(rootArtworkBounds.height, lessThanOrEqualTo(rootBounds.height));
        expect(
          scaleArtworkBounds.height,
          lessThanOrEqualTo(scaleBounds.height),
        );
        expect(scaleBounds.width, closeTo(scaleArtworkBounds.width, 0.1));
        expect(
          scaleBounds.width,
          lessThan(
            tester.getSize(find.byKey(const Key('sharedScaleTypeList'))).width,
          ),
        );
        expect(tester.takeException(), isNull);

        if (size.width == 320) {
          final rootRect = tester.getRect(rootTarget);
          await tester.tapAt(rootRect.bottomRight - const Offset(1, 1));
          await tester.pumpAndSettle();
          final scaleRect = tester.getRect(scaleTarget);
          await tester.tapAt(scaleRect.bottomRight - const Offset(1, 1));
          await tester.pumpAndSettle();
          expect(find.text('C major'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'category tabs expose 44-pixel semantic targets and select their scale groups',
    (tester) async {
      final semantics = tester.ensureSemantics();

      for (final size in [const Size(320, 800), const Size(1024, 800)]) {
        await _pumpAtSize(
          tester,
          SharedScalePicker(binding: fretboardBinding),
          size: size,
          textScale: 1.6,
        );

        for (final category in ScaleCategory.values) {
          final target = find.byKey(
            ValueKey('sharedScaleCategory_${category.name}'),
          );
          final targetSize = tester.getSize(target);
          expect(targetSize.width, greaterThanOrEqualTo(44));
          expect(targetSize.height, greaterThanOrEqualTo(44));
          expect(
            find.bySemanticsLabel(scaleCategoryLabels[category]!),
            findsOneWidget,
          );

          final bounds = tester.getRect(target);
          await tester.tapAt(bounds.bottomRight - const Offset(1, 1));
          await tester.pumpAndSettle();

          final expectedScale = scaleGroups[category]!.first.$1;
          expect(
            find.byKey(ValueKey('sharedScaleType_$expectedScale')),
            findsOneWidget,
          );
          final semanticsData = tester.getSemantics(target).getSemanticsData();
          expect(semanticsData.flagsCollection.isButton, isTrue);
          expect(semanticsData.flagsCollection.isSelected, ui.Tristate.isTrue);
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      }
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('root and scale rows stay horizontally reachable', (
    tester,
  ) async {
    await _pumpAtSize(
      tester,
      SharedScalePicker(binding: fretboardBinding),
      size: const Size(320, 800),
      textScale: 1.6,
    );

    final rootList = find.byKey(const Key('sharedScaleRootList'));
    await tester.drag(rootList, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    final bTarget = find.byKey(const ValueKey('sharedScaleRoot_B'));
    final rootViewport = tester.getRect(rootList);
    final bBounds = tester.getRect(bTarget);
    expect(bBounds.left, greaterThanOrEqualTo(rootViewport.left));
    expect(bBounds.right, lessThanOrEqualTo(rootViewport.right));
    await tester.tapAt(bBounds.center);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Modes'));
    await tester.pumpAndSettle();
    final scaleList = find.byKey(const Key('sharedScaleTypeList'));
    await tester.drag(scaleList, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    final locrianTarget = find.byKey(const ValueKey('sharedScaleType_locrian'));
    final scaleViewport = tester.getRect(scaleList);
    final locrianBounds = tester.getRect(locrianTarget);
    expect(locrianBounds.left, greaterThanOrEqualTo(scaleViewport.left));
    expect(locrianBounds.right, lessThanOrEqualTo(scaleViewport.right));
    await tester.tapAt(locrianBounds.center);
    await tester.pumpAndSettle();

    expect(find.text('B locrian'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
