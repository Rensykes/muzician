// test/schema/rules/songwriter_voicing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';

void main() {
  test('C major returns 4 shapes sorted by lowest fret, C-shape at fret 0', () {
    final v = suggestVoicings(chordRootPc: 0, quality: '');
    expect(v.length, 4);
    expect(v.first.shape, CagedShape.c);
    expect(v.first.lowestFret, 0);
    expect(v.first.label, 'C-shape (open)');
    final frets = v.map((s) => s.lowestFret).toList();
    final sorted = [...frets]..sort();
    expect(frets, sorted);
  });

  test('A major includes A-shape at fret 0', () {
    final v = suggestVoicings(chordRootPc: 9, quality: '');
    final aShape = v.firstWhere((s) => s.shape == CagedShape.a);
    expect(aShape.lowestFret, 0);
    expect(aShape.label, 'A-shape (open)');
  });

  test('C minor returns 2 shapes (Am at 3, Em at 8); Dm skipped (max fret 13 > 12)', () {
    final v = suggestVoicings(chordRootPc: 0, quality: 'm');
    expect(v.length, 2);
    final byShape = {for (final s in v) s.shape: s.lowestFret};
    expect(byShape[CagedShape.a], 3);
    expect(byShape[CagedShape.e], 8);
  });

  test('unsupported quality returns empty', () {
    expect(suggestVoicings(chordRootPc: 0, quality: 'dim'), isEmpty);
    expect(suggestVoicings(chordRootPc: 0, quality: '7'), isEmpty);
  });

  test('shape whose transpose pushes top fret past 12 is skipped', () {
    final v = suggestVoicings(chordRootPc: 0, quality: '');
    final hasDShape = v.any((s) => s.shape == CagedShape.d);
    expect(hasDShape, isFalse);
  });

  test('voicingToSnapshot produces snapshot with chord pitch classes', () {
    final v = suggestVoicings(chordRootPc: 0, quality: '').first;
    final snap = voicingToSnapshot(v);
    expect(snap.tuning, TuningName.standard);
    expect(snap.numFrets, 12);
    expect(snap.capo, 0);
    expect(snap.viewMode, FretboardViewMode.exact);
    expect(snap.selectedNotes.toSet(), {'C', 'E', 'G'});
    expect(snap.selectedCells.length, 5);
  });

  test('voicingToSnapshot sets pendingChord from source chord so library '
      'match can rediscover it', () {
    final cMajor = suggestVoicings(chordRootPc: 0, quality: '').first;
    final cSnap = voicingToSnapshot(cMajor);
    expect(cSnap.pendingChord, isNotNull);
    expect(cSnap.pendingChord!.symbol, 'C');
    expect(cSnap.pendingChord!.root, 'C');
    expect(cSnap.pendingChord!.quality, '');

    final aMinor = suggestVoicings(chordRootPc: 9, quality: 'm').first;
    final aSnap = voicingToSnapshot(aMinor);
    expect(aSnap.pendingChord!.symbol, 'Am');
    expect(aSnap.pendingChord!.root, 'A');
    expect(aSnap.pendingChord!.quality, 'm');
  });

  test('all cell stringIndex values are 0-based (0..5)', () {
    final v = suggestVoicings(chordRootPc: 0, quality: '');
    for (final s in v) {
      for (final c in s.cells) {
        expect(c.stringIndex, inInclusiveRange(0, 5),
            reason: 'stringIndex must be 0-based to match the rest of the codebase');
      }
    }
  });

  test('open-string cells encode the correct pitch class', () {
    // C-shape major for C: stringIndex 5 (low E) is muted (null in openShape).
    // stringIndex 4 (A) plays fret 3 → C. stringIndex 3 (D) plays fret 2 → E.
    final v = suggestVoicings(chordRootPc: 0, quality: '').first;
    final byStringIndex = {for (final c in v.cells) c.stringIndex: c};
    expect(byStringIndex[4]!.fret, 3);
    expect(byStringIndex[4]!.noteName, 'C');
    expect(byStringIndex[3]!.fret, 2);
    expect(byStringIndex[3]!.noteName, 'E');
  });
}
