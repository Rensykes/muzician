import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/features/instrument_shared/instrument_screen.dart';
import 'package:muzician/features/piano/piano_keyboard.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_settings_notifier.dart';

const _landscapeSize = Size(874, 402);
const _landscapeSafePadding = EdgeInsets.fromLTRB(62, 0, 62, 20.5);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _appFor(
  ProviderContainer container, {
  required Size size,
  required Widget screen,
  double textScale = 1,
}) {
  final landscape = size.width > size.height;
  final padding = landscape
      ? _landscapeSafePadding
      : const EdgeInsets.fromLTRB(0, 59, 0, 34);
  final bottomNavigationHeight = landscape ? 80.5 : 94.0;

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          padding: padding,
          viewPadding: padding,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: screen,
          bottomNavigationBar: SizedBox(height: bottomNavigationHeight),
        ),
      ),
    ),
  );
}

Widget _fretboardScreen(
  ProviderContainer container, {
  VoidCallback? onChordPanelRequested,
}) {
  final state = container.read(fretboardProvider);
  final notifier = container.read(fretboardProvider.notifier);
  return InstrumentScreen(
    binding: fretboardBinding,
    title: 'Fretboard',
    appBarChipLabel: null,
    appBarActions: [IconBtn(icon: Icons.help_outline_rounded, onTap: () {})],
    modeSegment: ModeSegment<FretboardInputMode>(
      current: state.inputMode,
      onSelect: notifier.setInputMode,
      options: const [
        (FretboardInputMode.free, Icons.touch_app_rounded, 'Free'),
        (FretboardInputMode.chord, Icons.library_music_rounded, 'Chord'),
      ],
    ),
    board: const GlassFrame(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GuitarFretboard(hideToolbar: true, palette: FretboardPalette.wood),
    ),
    boardHeight: fretboardBoardHeight,
    emptyTitle: 'Tap the fretboard to begin',
    emptySubtitle: 'Selected notes turn into detected chords and scales here.',
    onChordPanelRequested: onChordPanelRequested ?? () {},
    onScalePanelRequested: () {},
    scaleHasValue: false,
    chordHasValue: false,
    detectionKey: const ValueKey('fret-detect'),
  );
}

Widget _pianoScreen(
  ProviderContainer container, {
  VoidCallback? onChordPanelRequested,
}) {
  return InstrumentScreen(
    binding: pianoBinding,
    title: 'Piano',
    appBarChipLabel: null,
    appBarActions: [IconBtn(icon: Icons.help_outline_rounded, onTap: () {})],
    board: const GlassFrame(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: PianoKeyboard(hideToolbar: true),
    ),
    boardHeight: pianoKeyboardHeight,
    emptyTitle: 'Tap the keyboard to begin',
    emptySubtitle: 'Selected notes turn into detected chords and scales here.',
    onChordPanelRequested: onChordPanelRequested ?? () {},
    onScalePanelRequested: () {},
    scaleHasValue: false,
    chordHasValue: false,
    detectionKey: const ValueKey('piano-detect'),
  );
}

Future<void> _expectEmptyGuidanceVisibleAboveDock(
  WidgetTester tester, {
  required String title,
  required String subtitle,
}) async {
  final titleFinder = find.text(title);
  final subtitleFinder = find.text(subtitle);
  await tester.ensureVisible(subtitleFinder);
  await tester.pumpAndSettle();

  final dockTop = tester.getRect(find.byType(DockedToolbar)).top;
  final titleRect = tester.getRect(titleFinder);
  final subtitleRect = tester.getRect(subtitleFinder);
  expect(titleRect.top, greaterThanOrEqualTo(0));
  expect(titleRect.bottom, lessThanOrEqualTo(dockTop));
  expect(subtitleRect.top, greaterThanOrEqualTo(0));
  expect(subtitleRect.bottom, lessThanOrEqualTo(dockTop));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('portrait keeps the full fretboard and empty guidance visible', (
    tester,
  ) async {
    const size = Size(390, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appFor(container, size: size, screen: _fretboardScreen(container)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GuitarFretboard), findsOneWidget);
    expect(find.text('Tap the fretboard to begin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait empty fretboard guidance fits at 1.6 text', (
    tester,
  ) async {
    const size = Size(390, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appFor(
        container,
        size: size,
        textScale: 1.6,
        screen: _fretboardScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    await _expectEmptyGuidanceVisibleAboveDock(
      tester,
      title: 'Tap the fretboard to begin',
      subtitle: 'Selected notes turn into detected chords and scales here.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait selected fretboard detection fits at 1.6 text', (
    tester,
  ) async {
    const size = Size(390, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(fretboardProvider.notifier)
        .setInputMode(FretboardInputMode.chord);
    container.read(fretboardProvider.notifier).toggleCell(3, 1, 'D#');

    await tester.pumpWidget(
      _appFor(
        container,
        size: size,
        textScale: 1.6,
        screen: _fretboardScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait empty piano guidance fits at 1.6 text', (tester) async {
    const size = Size(390, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appFor(
        container,
        size: size,
        textScale: 1.6,
        screen: _pianoScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    await _expectEmptyGuidanceVisibleAboveDock(
      tester,
      title: 'Tap the keyboard to begin',
      subtitle: 'Selected notes turn into detected chords and scales here.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow portrait keeps scaled fretboard guidance reachable', (
    tester,
  ) async {
    const size = Size(320, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appFor(
        container,
        size: size,
        textScale: 1.6,
        screen: _fretboardScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    await _expectEmptyGuidanceVisibleAboveDock(
      tester,
      title: 'Tap the fretboard to begin',
      subtitle: 'Selected notes turn into detected chords and scales here.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow portrait keeps scaled piano guidance reachable', (
    tester,
  ) async {
    const size = Size(320, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appFor(
        container,
        size: size,
        textScale: 1.6,
        screen: _pianoScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    await _expectEmptyGuidanceVisibleAboveDock(
      tester,
      title: 'Tap the keyboard to begin',
      subtitle: 'Selected notes turn into detected chords and scales here.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait selected piano detection fits at 1.6 text', (
    tester,
  ) async {
    const size = Size(390, 844);
    _setViewport(tester, size);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pianoProvider.notifier).loadExactMidis([60]);

    await tester.pumpWidget(
      _appFor(
        container,
        size: size,
        textScale: 1.6,
        screen: _pianoScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('empty guidance fits short and threshold landscape at 1.6 text', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    _setViewport(tester, _landscapeSize);
    await tester.pumpWidget(
      _appFor(
        container,
        size: _landscapeSize,
        textScale: 1.6,
        screen: _fretboardScreen(container),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Tap the fretboard to begin'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the fretboard to begin'), findsOneWidget);
    final shortHintRect = tester.getRect(
      find.text('Tap the fretboard to begin'),
    );
    expect(shortHintRect.top, greaterThanOrEqualTo(0));
    expect(shortHintRect.bottom, lessThanOrEqualTo(241.5));
    expect(tester.takeException(), isNull);

    const thresholdScreenSize = Size(
      874,
      44 + 60 + fretboardBoardHeight + 160 + 80 + 80.5,
    );
    _setViewport(tester, thresholdScreenSize);
    await tester.pumpWidget(
      _appFor(
        container,
        size: thresholdScreenSize,
        textScale: 1.6,
        screen: _fretboardScreen(container),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tap the fretboard to begin'), findsOneWidget);
    final thresholdHintRect = tester.getRect(
      find.text('Tap the fretboard to begin'),
    );
    expect(thresholdHintRect.top, greaterThanOrEqualTo(0));
    expect(thresholdHintRect.bottom, lessThanOrEqualTo(576));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short landscape keeps fretboard gestures, detection, and dock reachable at 1.6 text',
    (tester) async {
      _setViewport(tester, _landscapeSize);
      var chordPanelRequests = 0;
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => TestSettingsNotifier(initialSpelling: NoteSpelling.flats),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(fretboardProvider.notifier)
          .setInputMode(FretboardInputMode.chord);
      container.read(fretboardProvider.notifier).toggleCell(3, 1, 'D#');

      await tester.pumpWidget(
        _appFor(
          container,
          size: _landscapeSize,
          textScale: 1.6,
          screen: _fretboardScreen(
            container,
            onChordPanelRequested: () => chordPanelRequests++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GuitarFretboard), findsOneWidget);
      expect(container.read(fretboardProvider).selectedCells, hasLength(1));
      expect(tester.takeException(), isNull);

      final listener = find.descendant(
        of: find.byType(GuitarFretboard),
        matching: find.byType(Listener),
      );
      final listenerOrigin = tester.getTopLeft(listener.first);
      final fretboardViewport = Rect.fromLTWH(0, 0, 874, 241.5);
      final tapPoint = listenerOrigin + const Offset(124, 93);
      expect(fretboardViewport.contains(tapPoint), isTrue);
      await tester.tapAt(tapPoint);
      await tester.pumpAndSettle();

      expect(container.read(fretboardProvider).selectedCells, hasLength(2));

      final horizontalScroll = find
          .byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          )
          .first;
      final boardScrollable = find.descendant(
        of: horizontalScroll,
        matching: find.byType(Scrollable),
      );
      final beforeScrollOffset = tester
          .state<ScrollableState>(boardScrollable)
          .position
          .pixels;
      await tester.dragFrom(tapPoint, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(boardScrollable).position.pixels,
        greaterThan(beforeScrollOffset),
      );
      expect(horizontalScroll, findsOneWidget);

      await tester.ensureVisible(find.text('DETECTION'));
      await tester.pumpAndSettle();
      expect(find.text('DETECTION'), findsOneWidget);
      final detectionHeaderRect = tester.getRect(find.text('DETECTION'));
      expect(detectionHeaderRect.top, greaterThanOrEqualTo(0));
      expect(detectionHeaderRect.bottom, lessThanOrEqualTo(241.5));
      expect(find.text('Eb'), findsOneWidget);

      final dockChord = find.descendant(
        of: find.byType(DockedToolbar),
        matching: find.text('Chord'),
      );
      await tester.tap(dockChord);
      await tester.pump();
      expect(chordPanelRequests, 1);

      await tester.ensureVisible(find.text('Free'));
      await tester.pumpAndSettle();
      final modeTarget = find.ancestor(
        of: find.text('Free'),
        matching: find.byType(GestureDetector),
      );
      await tester.ensureVisible(modeTarget.first);
      await tester.pumpAndSettle();
      final modeTargetRect = tester.getRect(modeTarget.first);
      expect(modeTargetRect.width, greaterThanOrEqualTo(44));
      expect(modeTargetRect.height, greaterThanOrEqualTo(44));
      await tester.tapAt(
        Offset(modeTargetRect.center.dx, modeTargetRect.top + 1),
      );
      await tester.pump();
      expect(
        container.read(fretboardProvider).inputMode,
        FretboardInputMode.free,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short landscape keeps the piano keyboard and dock interactive', (
    tester,
  ) async {
    _setViewport(tester, _landscapeSize);
    var chordPanelRequests = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pianoProvider.notifier).loadExactMidis([60]);

    await tester.pumpWidget(
      _appFor(
        container,
        size: _landscapeSize,
        textScale: 1.6,
        screen: _pianoScreen(
          container,
          onChordPanelRequested: () => chordPanelRequests++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PianoKeyboard), findsOneWidget);
    expect(container.read(pianoProvider).selectedKeys, hasLength(1));
    expect(tester.takeException(), isNull);

    final d4 = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'D4, MIDI 62',
    );
    final d4Center = tester.getCenter(d4);
    await tester.tapAt(d4Center);
    await tester.pumpAndSettle();
    expect(container.read(pianoProvider).selectedKeys, hasLength(2));

    final pianoScrollable = find.descendant(
      of: find.byType(PianoKeyboard),
      matching: find.byType(Scrollable),
    );
    final beforeScrollOffset = tester
        .state<ScrollableState>(pianoScrollable.first)
        .position
        .pixels;
    await tester.dragFrom(d4Center, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(pianoScrollable.first).position.pixels,
      greaterThan(beforeScrollOffset),
    );

    await tester.ensureVisible(find.text('DETECTION'));
    await tester.pumpAndSettle();
    expect(find.text('DETECTION'), findsOneWidget);

    final dockChord = find.descendant(
      of: find.byType(DockedToolbar),
      matching: find.text('Chord'),
    );
    await tester.tap(dockChord);
    await tester.pump();
    expect(chordPanelRequests, 1);
    expect(tester.takeException(), isNull);
  });
}
