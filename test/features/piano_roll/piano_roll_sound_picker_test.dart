import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_screen_v2.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/piano_roll_playback.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/theme/studio_theme.dart';

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

ProviderContainer _buildContainer() => ProviderContainer(
  overrides: [
    pianoRollProvider.overrideWith(
      () => _FakePianoRollNotifier(_defaultPRState),
    ),
    pianoRollPlaybackProvider.overrideWith(
      () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
    ),
  ],
);

// Mirrors the Studio harness used by piano_roll_studio_test.dart: the Roll
// Settings tooltip (and therefore the sound picker) only renders in the
// Studio header layout, so the screen must be hosted under a Studio theme.
Widget _host(
  ProviderContainer container, {
  AppThemeVariant variant = AppThemeVariant.studio,
  bool showSound = true,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: StudioThemeSource(
      variant: variant,
      child: MaterialApp(
        theme: StudioTheme.data(variant),
        home: Scaffold(
          body: StudioRouteTheme(
            isStudio: true,
            child: PianoRollScreenV2(showSound: showSound),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Roll Settings lists every sound and selecting one updates the roll',
    (tester) async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container));
      await tester.pump();

      await tester.tap(find.byTooltip('Roll Settings').first);
      await tester.pumpAndSettle();

      for (final sound in PianoRollSound.values) {
        expect(find.text(sound.label), findsOneWidget);
      }

      await tester.tap(find.text('Organ'));
      await tester.pumpAndSettle();

      expect(container.read(pianoRollProvider).sound, PianoRollSound.organ);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Roll Settings sound picker fits compact and wide viewports at 2x text scale',
    (tester) async {
      for (final viewport in const [Size(390, 844), Size(1280, 800)]) {
        final container = _buildContainer();
        addTearDown(container.dispose);

        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: viewport,
              textScaler: const TextScaler.linear(2.0),
            ),
            child: _host(container),
          ),
        );
        await tester.pump();

        await tester.tap(find.byTooltip('Roll Settings').first);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'Roll Settings sound picker should not overflow at '
              '${viewport.width}×${viewport.height} / 2x text scale',
        );

        for (final sound in PianoRollSound.values) {
          expect(find.text(sound.label), findsOneWidget);
        }

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Roll Settings hides the Sound section when showSound is false', (
    tester,
  ) async {
    final container = _buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, showSound: false));
    await tester.pump();

    await tester.tap(find.byTooltip('Roll Settings').first);
    await tester.pumpAndSettle();

    expect(find.text('Sound'), findsNothing);
    for (final sound in PianoRollSound.values) {
      expect(find.text(sound.label), findsNothing);
    }
    // The rest of Roll Settings (metronome) still renders.
    expect(find.text('Metronome'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
