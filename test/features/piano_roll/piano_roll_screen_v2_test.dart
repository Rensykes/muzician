import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_screen_v2.dart';
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
}
