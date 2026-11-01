import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/save_system.dart';

void main() {
  test(
    'PianoRollSnapshot round-trips sound and defaults old saves to piano',
    () {
      final snap = PianoRollSnapshot(
        tempo: 120,
        numerator: 4,
        denominator: 4,
        totalMeasures: 4,
        notes: const [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        snapTicks: 1,
        highlightedNotes: const [],
        sound: PianoRollSound.organ,
      );
      final json = snap.toJson();
      expect(json['sound'], 'organ');
      expect(PianoRollSnapshot.fromJson(json).sound, PianoRollSound.organ);

      json.remove('sound');
      expect(PianoRollSnapshot.fromJson(json).sound, PianoRollSound.piano);
      expect(
        PianoRollSnapshot.fromJson({...json, 'sound': 'nonsense'}).sound,
        PianoRollSound.piano,
      );
    },
  );
}
