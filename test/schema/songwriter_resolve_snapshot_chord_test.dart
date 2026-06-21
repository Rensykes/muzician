import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

FretboardSnapshot _fret({
  List<String> selectedNotes = const [],
  PendingChord? pendingChord,
}) {
  return FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 15,
    capo: 0,
    selectedCells: const [],
    selectedNotes: selectedNotes,
    viewMode: FretboardViewMode.exact,
    pendingChord: pendingChord,
  );
}

void main() {
  group('resolveSnapshotChord', () {
    test('null snapshot → null', () {
      expect(resolveSnapshotChord(null), isNull);
    });

    test('prefers explicit pendingChord', () {
      final snap = _fret(
        selectedNotes: const ['C', 'E', 'G'],
        pendingChord: const PendingChord(root: 'F', quality: '', symbol: 'F'),
      );
      final r = resolveSnapshotChord(snap);
      expect(r, isNotNull);
      expect(r!.rootPc, 5); // F
      expect(r.quality, '');
      expect(r.symbol, 'F');
    });

    test('detects chord from notes when no pendingChord', () {
      // F major triad: F A C
      final snap = _fret(selectedNotes: const ['F', 'A', 'C']);
      final r = resolveSnapshotChord(snap);
      expect(r, isNotNull);
      expect(r!.rootPc, 5); // F
      expect(r.quality, '');
      expect(r.symbol, 'F');
    });

    test('detects an extended chord (add9) from notes', () {
      // Fadd9: F A C G
      final snap = _fret(selectedNotes: const ['F', 'A', 'C', 'G']);
      final r = resolveSnapshotChord(snap);
      expect(r, isNotNull);
      expect(r!.rootPc, 5); // F
      expect(r.quality, 'add9');
    });

    test('returns null when notes match no known chord', () {
      // Two random non-chord notes
      final snap = _fret(selectedNotes: const ['C', 'C#']);
      expect(resolveSnapshotChord(snap), isNull);
    });

    test('end-to-end: detected chord → roman numeral in C major', () {
      final snap = _fret(selectedNotes: const ['F', 'A', 'C']);
      final r = resolveSnapshotChord(snap)!;
      final roman = romanNumeralFor(r.rootPc, r.quality, 0, 'major');
      expect(roman, 'IV');
    });

    test('end-to-end: G major detected → V in C major', () {
      final snap = _fret(selectedNotes: const ['G', 'B', 'D']);
      final r = resolveSnapshotChord(snap)!;
      final roman = romanNumeralFor(r.rootPc, r.quality, 0, 'major');
      expect(roman, 'V');
    });
  });
}
