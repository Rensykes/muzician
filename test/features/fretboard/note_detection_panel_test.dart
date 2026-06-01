import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/shared_detection_panel.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/fretboard_store.dart';

class FakeFretboardNotifier extends FretboardNotifier {
  FakeFretboardNotifier(this._initial);

  final FretboardState _initial;

  @override
  FretboardState build() => _initial;
}

void main() {
  testWidgets('shows slash chord label but writes canonical pending chord', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        fretboardProvider.overrideWith(
          () => FakeFretboardNotifier(
            const FretboardState(
              currentTuning: TuningName.standard,
              numFrets: 12,
              capo: 0,
              highlightedNotes: [],
              selectedNotes: ['C', 'E', 'G'],
              selectedCells: [
                FretCoordinate(stringIndex: 5, fret: 12, noteName: 'E'),
                FretCoordinate(stringIndex: 4, fret: 10, noteName: 'C'),
                FretCoordinate(stringIndex: 3, fret: 12, noteName: 'G'),
              ],
              viewMode: FretboardViewMode.exact,
              inputMode: FretboardInputMode.free,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SharedDetectionPanel(binding: fretboardBinding),
          ),
        ),
      ),
    );

    expect(find.text('C/E'), findsOneWidget);
    await tester.tap(find.text('C/E'));
    await tester.pump();
    expect(container.read(pendingChordProvider), (root: 'C', quality: ''));
  });
}
