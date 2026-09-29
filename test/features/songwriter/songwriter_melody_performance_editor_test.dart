import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/features/piano/piano_keyboard.dart';
import 'package:muzician/features/songwriter/songwriter_melody_performance_editor.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Piano target shows MIDI keys without changing Piano selection', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patternId = _addPattern(container, midiNote: 60);
    container.read(pianoScrollToMidiProvider.notifier).state = 48;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SongwriterMelodyPerformanceEditor(patternId: patternId),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Piano'));
    await tester.pumpAndSettle();

    expect(find.text('MIDI keys in 61 Keys (C2-C7)'), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'C4, MIDI 60, melody note',
      ),
      findsOneWidget,
    );

    final keySemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'C4, MIDI 60, melody note',
    );
    await tester.ensureVisible(keySemantics);
    await tester.tap(keySemantics);
    await tester.pump();
    expect(container.read(pianoProvider).selectedKeys, isEmpty);
    expect(container.read(pianoScrollToMidiProvider), 48);
    expect(
      container
          .read(songwriterProvider)
          .melodyPerformancesByPatternId[patternId]!
          .instrument,
      HarmonyLaneInstrument.piano,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fretboard tap assigns a valid position without global edits', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patternId = _addPattern(container, midiNote: 60);
    container.read(scrollToFretProvider.notifier).state = 7;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SongwriterMelodyPerformanceEditor(patternId: patternId),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fretboard'));
    await tester.pumpAndSettle();

    expect(find.byType(GuitarFretboard), findsOneWidget);
    await tester.ensureVisible(find.byType(GuitarFretboard));
    final listener = find.descendant(
      of: find.byType(GuitarFretboard),
      matching: find.byType(Listener),
    );
    final boardOrigin = tester.getTopLeft(listener.first);
    // String index 1 is B3; fret 1 produces MIDI 60 (C4).
    await tester.tapAt(boardOrigin + const Offset(124, 93));
    await tester.pumpAndSettle();

    final performance = container
        .read(songwriterProvider)
        .melodyPerformancesByPatternId[patternId]!;
    expect(performance.instrument, HarmonyLaneInstrument.fretboard);
    expect(performance.fretboardPositionsByNoteId['note-1']?.stringIndex, 1);
    expect(performance.fretboardPositionsByNoteId['note-1']?.fret, 1);
    expect(container.read(fretboardProvider).selectedCells, isEmpty);
    expect(container.read(scrollToFretProvider), 7);

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Valid positions for C4'), findsOneWidget);
    expect(find.text('String 2 (B3), fret 1'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('incompatible Piano range gates the view and offers Piano Roll', (
    tester,
  ) async {
    _setViewport(tester, const Size(1280, 900));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pianoProvider.notifier).setRange(PianoRangeName.key88);
    final patternId = _addPattern(container, midiNote: 24);
    container
        .read(songwriterProvider.notifier)
        .setMelodyPerformanceInstrument(
          patternId: patternId,
          instrument: HarmonyLaneInstrument.piano,
        );
    container.read(pianoProvider.notifier).setRange(PianoRangeName.key49);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SongwriterMelodyPerformanceEditor(patternId: patternId),
        ),
      ),
    );

    expect(
      find.text('This instrument cannot play every pattern note.'),
      findsOneWidget,
    );
    expect(find.byType(PianoKeyboard), findsNothing);
    expect(find.text('Correct notes in Piano Roll'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _addPattern(ProviderContainer container, {required int midiNote}) {
  final notifier = container.read(songwriterProvider.notifier);
  final patternId = notifier.addMelodyPattern(name: 'Test melody');
  final pattern = container
      .read(songwriterProvider)
      .melodyPatterns
      .singleWhere((candidate) => candidate.id == patternId);
  notifier.updateMelodyPattern(
    pattern.copyWith(
      notes: [
        NotePatternNote(
          id: 'note-1',
          midiNote: midiNote,
          startTick: 0,
          durationTicks: 240,
        ),
      ],
    ),
  );
  return patternId;
}
