import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_grid.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/piano_roll_playback.dart';
import 'package:muzician/store/piano_roll_playback_store.dart';
import 'package:muzician/store/piano_roll_store.dart';

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

void main() {
  testWidgets('draws a playback playhead on the grid while playing', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _FakePianoRollNotifier(_defaultPRState),
        ),
        pianoRollPlaybackProvider.overrideWith(
          () => _FakePlaybackNotifier(
            const PianoRollPlaybackState(
              status: PianoRollPlaybackStatus.playing,
              startTick: 4,
              currentTick: 4,
              endTickExclusive: 64,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 320,
              child: PianoRollGrid(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('piano-roll-grid-paint')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('piano-roll-grid-paint')),
      paints..something((method, arguments) {
        if (method != #drawLine) {
          return false;
        }

        final p1 = arguments[0] as Offset;
        final p2 = arguments[1] as Offset;

        return p1 == const Offset(126, 0) &&
            p2 == const Offset(126, 666);
      }),
    );
  });
}
