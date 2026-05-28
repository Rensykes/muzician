import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_screen_v2.dart';
import 'package:muzician/features/piano_roll/piano_roll_stack_builder.dart';
import 'package:muzician/features/piano_roll/piano_roll_hum_recorder.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/piano_roll_playback.dart';

class _FakePianoRollNotifier extends PianoRollNotifier {
  _FakePianoRollNotifier(this._initial);
  final PianoRollState _initial;
  @override
  PianoRollState build() => _initial;
}

class _SpyPianoRollNotifier extends PianoRollNotifier {
  _SpyPianoRollNotifier(this._initial);
  final PianoRollState _initial;
  int? selectedTickCall;

  @override
  PianoRollState build() => _initial;

  @override
  void selectNotesAtTick(int tick) {
    selectedTickCall = tick;
    final ids = state.notes
        .where(
          (note) =>
              note.startTick <= tick &&
              tick < note.startTick + note.durationTicks,
        )
        .map((note) => note.id)
        .toSet();
    state = state.copyWith(selectedNoteIds: ids);
  }
}

class _FakePlaybackNotifier extends PianoRollPlaybackNotifier {
  _FakePlaybackNotifier(this._initial);
  final PianoRollPlaybackState _initial;
  @override
  PianoRollPlaybackState build() => _initial;
}

const _defaultPRState = PianoRollState(
  config: PianoRollConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 4,
  ),
  notes: [],
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
);
const _columnNote = PianoRollNote(
  id: 'n1',
  midiNote: 60,
  pitchClass: 'C',
  noteWithOctave: 'C4',
  startTick: 0,
  durationTicks: 4,
);

Widget _wrapV2(ProviderContainer container, {Size? surfaceSize}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: surfaceSize != null
          ? Scaffold(
              body: SizedBox(
                width: surfaceSize.width,
                height: surfaceSize.height,
                child: const PianoRollScreenV2(),
              ),
            )
          : const Scaffold(body: PianoRollScreenV2()),
    ),
  );
}

void main() {
  // ── Landscape layout test ──────────────────────────────────────────────

  testWidgets('landscape layout has grid and utility surface visible', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Use a landscape-sized surface (width > 600 triggers landscape).
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    // In landscape, both the grid and the utility panel should be visible.
    expect(
      find.byKey(const ValueKey('piano-roll-grid-paint')),
      findsOneWidget,
      reason: 'Grid should be visible in landscape layout',
    );
    expect(
      find.byKey(const ValueKey('v2-utility-panel')),
      findsOneWidget,
      reason: 'Utility panel should be visible in landscape layout',
    );
    expect(
      find.text('Multi-select'),
      findsNothing,
      reason: 'Selection actions should not show without selected notes/column',
    );
  });

  // ── Portrait layout test ───────────────────────────────────────────────

  testWidgets('portrait layout has grid as primary surface', (tester) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Portrait size (width < 600 triggers portrait).
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    // Grid should be the primary surface.
    expect(
      find.byKey(const ValueKey('piano-roll-grid-paint')),
      findsOneWidget,
      reason: 'Grid should be visible in portrait layout',
    );

    // Portrait action bar (chips + selection status) must exist below the
    // grid. The previous inline expander stack was replaced by modal sheets,
    // so the panels container key was renamed.
    expect(
      find.byKey(const ValueKey('v2-portrait-actionbar')),
      findsOneWidget,
      reason: 'Portrait action bar should exist below the grid',
    );
    expect(
      find.byIcon(Icons.help_outline_rounded),
      findsOneWidget,
      reason: 'Portrait shell should expose a local help action',
    );
  });

  testWidgets('portrait help action opens shared help on Piano Roll tab', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.help_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Gestures & Features'), findsOneWidget);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller?.index, 2);
  });

  testWidgets('portrait status prioritizes selected note count', (
    tester,
  ) async {
    final selectedState = _defaultPRState.copyWith(
      notes: const [_columnNote],
      selectedColumnTick: () => 0,
      selectedNoteIds: const {'n1'},
    );
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(selectedState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    expect(find.text('Selected  •  1 note'), findsOneWidget);
    expect(find.byIcon(Icons.deselect_rounded), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.delete_outline_rounded), findsAtLeastNWidgets(1));
  });

  testWidgets('landscape utility panel exposes selection management section', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    expect(find.byKey(const ValueKey('v2-utility-panel')), findsOneWidget);
    expect(find.text('No column selected'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
  });

  testWidgets('portrait compact select-at-column action updates selection', (
    tester,
  ) async {
    final initialState = _defaultPRState.copyWith(
      notes: const [_columnNote],
      selectedColumnTick: () => 0,
    );
    final spyNotifier = _SpyPianoRollNotifier(initialState);
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(() => spyNotifier),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    final selectColumnFinder = find.bySemanticsLabel('Select column');
    expect(selectColumnFinder, findsOneWidget);

    await tester.tap(selectColumnFinder);
    await tester.pump();

    expect(spyNotifier.selectedTickCall, 0);
    expect(find.text('Selected  •  1 note'), findsOneWidget);
  });

  testWidgets('portrait stack builder sheet dismisses after adding a stack', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    await tester.tap(find.text('Stack Builder'));
    await tester.pumpAndSettle();

    expect(find.byType(PianoRollStackBuilder), findsOneWidget);
    expect(find.text('Add Stack'), findsOneWidget);

    await tester.tap(find.text('Add Stack'));
    await tester.pumpAndSettle();

    expect(find.byType(PianoRollStackBuilder), findsNothing);
    expect(container.read(pianoRollProvider).notes, isNotEmpty);
  });

  // ── Hum recorder web gating test ───────────────────────────────────────

  testWidgets('hum recorder shows web message when isWeb is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: PianoRollHumRecorderPanel(isWeb: true)),
        ),
      ),
    );
    await tester.pump();

    // Should show "not supported" message instead of record button.
    expect(
      find.text('Hum to MIDI not supported on web'),
      findsOneWidget,
      reason: 'Web mode should show not-supported message',
    );
    expect(
      find.byType(FilledButton),
      findsNothing,
      reason: 'Record button should be hidden on web',
    );
  });

  testWidgets('hum recorder shows record button when isWeb is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: PianoRollHumRecorderPanel(isWeb: false)),
        ),
      ),
    );
    await tester.pump();

    // Should show the standard hum recorder UI (record button).
    expect(
      find.text('Hum to MIDI'),
      findsOneWidget,
      reason: 'Hum to MIDI header should appear',
    );
    expect(
      find.text('Record'),
      findsOneWidget,
      reason: 'Record button should be visible on mobile',
    );
  });

  testWidgets('tool segment exposes Select mode', (tester) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    expect(find.bySemanticsLabel('Select'), findsOneWidget);
  });

  testWidgets('column selection action uses secondary wording', (tester) async {
    final initial = _defaultPRState.copyWith(selectedColumnTick: () => 0);
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(() => _FakePianoRollNotifier(initial)),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrapV2(container));
    await tester.pump();

    expect(find.text('Multi-select'), findsNothing);
  });
}
