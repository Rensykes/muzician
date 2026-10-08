import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/chord_diagram.dart';
import 'package:muzician/features/fretboard/chord_voicing_picker.dart';
import 'package:muzician/features/instrument_shared/chord_picker_parts.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import '../../support/test_settings_notifier.dart';

void main() {
  testWidgets('ChordPickerHeader renders title + active badge', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChordPickerHeader(
              title: 'CHORD VOICINGS',
              root: 'C',
              quality: 'm7',
            ),
          ),
        ),
      ),
    );
    expect(find.text('CHORD VOICINGS'), findsOneWidget);
    expect(find.textContaining('C'), findsWidgets);
  });

  testWidgets('RootPillRow reports taps', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? tapped;
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: RootPillRow(
              selectedRoot: 'C#',
              accent: Colors.green,
              onTap: (r) => tapped = r,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Db'), findsOneWidget);
    final naturalRootTarget = find.ancestor(
      of: find.text('C'),
      matching: find.byType(GestureDetector),
    );
    final naturalRootTargetRect = tester.getRect(naturalRootTarget.first);
    final naturalRootPill = find.descendant(
      of: naturalRootTarget.first,
      matching: find.byType(Container),
    );
    expect(naturalRootTargetRect.width, greaterThanOrEqualTo(44));
    expect(naturalRootTargetRect.height, greaterThanOrEqualTo(44));
    expect(
      tester.getRect(naturalRootPill.first).width,
      lessThan(naturalRootTargetRect.width),
      reason: 'the hit area expands while the natural-note pill stays compact',
    );
    await tester.tapAt(
      Offset(naturalRootTargetRect.left + 1, naturalRootTargetRect.center.dy),
    );
    expect(tapped, 'C');

    final rootTarget = find.ancestor(
      of: find.text('Db'),
      matching: find.byType(GestureDetector),
    );
    final rootTargetRect = tester.getRect(rootTarget.first);
    expect(rootTargetRect.width, greaterThanOrEqualTo(44));
    expect(rootTargetRect.height, greaterThanOrEqualTo(44));
    await tester.tapAt(
      Offset(rootTargetRect.right - 1, rootTargetRect.center.dy),
    );
    expect(tapped, 'C#');

    final rootList = find.descendant(
      of: find.byType(RootPillRow),
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(rootList);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    final scrollOffset = scrollState.position.pixels;
    await tester.drag(find.byType(RootPillRow), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(scrollState.position.pixels, greaterThan(scrollOffset));
  });

  testWidgets('QualityPillRow gives short labels a 44px tappable area', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QualityPillRow(
            qualities: const [('7', '7')],
            selectedQuality: '7',
            accent: Colors.green,
            onTap: (quality) => tapped = quality,
          ),
        ),
      ),
    );

    final qualityTarget = find.ancestor(
      of: find.text('7'),
      matching: find.byType(GestureDetector),
    );
    final qualityTargetRect = tester.getRect(qualityTarget.first);
    final qualityPill = find.descendant(
      of: qualityTarget.first,
      matching: find.byType(Container),
    );
    expect(qualityTargetRect.width, greaterThanOrEqualTo(44));
    expect(qualityTargetRect.height, greaterThanOrEqualTo(44));
    expect(
      tester.getRect(qualityPill.first).width,
      lessThan(qualityTargetRect.width),
      reason: 'the short quality pill stays compact inside its hit area',
    );
    await tester.tapAt(
      Offset(qualityTargetRect.right - 1, qualityTargetRect.center.dy),
    );
    expect(tapped, '7');
  });

  testWidgets('DiatonicChordsRow keeps short chips tappable and scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    (String, String)? tapped;
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: DiatonicChordsRow(
                chords: getDiatonicChords('C', 'major'),
                selectedRoot: 'C',
                selectedQuality: '',
                accent: Colors.green,
                onTap: (root, quality) => tapped = (root, quality),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('I'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    final naturalTarget = find.ancestor(
      of: find.text('I'),
      matching: find.byType(GestureDetector),
    );
    final naturalTargetRect = tester.getRect(naturalTarget.first);
    final naturalChip = find.descendant(
      of: naturalTarget.first,
      matching: find.byType(Container),
    );
    final naturalChipRect = tester.getRect(naturalChip.first);
    expect(naturalTargetRect.width, greaterThanOrEqualTo(44));
    expect(naturalTargetRect.height, greaterThanOrEqualTo(44));
    expect(naturalChipRect.width, lessThan(naturalTargetRect.width));
    await tester.tapAt(
      Offset(naturalTargetRect.right - 1, naturalTargetRect.center.dy),
    );
    expect(tapped, ('C', ''));
    expect(tester.takeException(), isNull);

    final rowList = find.descendant(
      of: find.byType(DiatonicChordsRow),
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(rowList);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    final scrollOffset = scrollState.position.pixels;
    await tester.drag(find.byType(DiatonicChordsRow), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(scrollState.position.pixels, greaterThan(scrollOffset));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Diatonic chord labels use flats but callbacks stay canonical', (
    tester,
  ) async {
    (String, String)? tapped;
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: DiatonicChordsRow(
              chords: getDiatonicChords('C#', 'major'),
              selectedRoot: 'C#',
              selectedQuality: '',
              accent: Colors.green,
              onTap: (root, quality) => tapped = (root, quality),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Db'), findsOneWidget);
    final canonicalTarget = find.ancestor(
      of: find.text('Db'),
      matching: find.byType(GestureDetector),
    );
    final canonicalTargetRect = tester.getRect(canonicalTarget.first);
    expect(canonicalTargetRect.width, greaterThanOrEqualTo(44));
    expect(canonicalTargetRect.height, greaterThanOrEqualTo(44));
    await tester.tapAt(
      Offset(canonicalTargetRect.right - 1, canonicalTargetRect.center.dy),
    );
    expect(tapped, ('C#', ''));
  });

  testWidgets('ChordPickerHeader follows the selected note spelling', (
    tester,
  ) async {
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: ChordPickerHeader(
              title: 'CHORD VOICINGS',
              root: 'C#',
              quality: 'm7b5',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Dbm7b5'), findsOneWidget);
  });

  testWidgets(
    'committed voicing survives the selectedNotes listener (no wipe)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ChordVoicingPicker()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select root C; quality defaults to maj, so voicings render.
      await tester.tap(find.text('C').first);
      await tester.pumpAndSettle();

      // Voicing cards (ChordDiagram) should now be present.
      final cards = find.byType(ChordDiagram);
      expect(cards, findsWidgets);

      // Tap the first voicing card. This calls notifier.loadVoicing(...),
      // which mutates selectedNotes synchronously and fires the
      // selectedNotes listener BEFORE the rebuild re-registers the closure.
      // With a stale committed snapshot the listener would wipe the commit:
      // deselect the card and reset _voicingCommitted to false.
      await tester.tap(cards.first);
      await tester.pumpAndSettle();

      // The commit must survive: the committed flag stays true and exactly one
      // voicing card remains selected (its index was not wiped to null).
      expect(container.read(fretboardChordCommittedProvider), isTrue);
      final selectedCards = tester
          .widgetList<ChordDiagram>(cards)
          .where((d) => d.isSelected)
          .length;
      expect(
        selectedCards,
        1,
        reason: 'committed voicing card should stay selected after commit',
      );

      // The committed chord (C) must be published to activeChordProvider.
      final active = container.read(activeChordProvider);
      expect(active, isNotNull);
      expect(active!.root, 'C');
      expect(container.read(fretboardProvider).selectedNotes, isNotEmpty);
    },
  );
}
