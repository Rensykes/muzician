import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';

void main() {
  test('FretboardSnapshot round-trips its input mode', () {
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [],
      selectedNotes: const [],
      viewMode: FretboardViewMode.exact,
      inputMode: FretboardInputMode.chord,
    );

    expect(snapshot.toJson()['inputMode'], 'chord');
    expect(
      FretboardSnapshot.fromJson(snapshot.toJson()).inputMode,
      FretboardInputMode.chord,
    );
  });

  test('missing or unknown input mode defaults to Free', () {
    const fields = <String, dynamic>{
      'instrument': 'fretboard',
      'tuning': 'standard',
      'numFrets': 12,
      'capo': 0,
      'selectedCells': [],
      'selectedNotes': [],
      'viewMode': 'exact',
    };

    expect(
      FretboardSnapshot.fromJson(fields).inputMode,
      FretboardInputMode.free,
    );
    expect(
      FretboardSnapshot.fromJson({
        ...fields,
        'inputMode': 'future-mode',
      }).inputMode,
      FretboardInputMode.free,
    );
  });
}
