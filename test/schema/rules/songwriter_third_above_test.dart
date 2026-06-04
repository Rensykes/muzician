// test/schema/rules/songwriter_third_above_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';

void main() {
  test('C major in C major key → targets E, G, B', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7], // C, E, G
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [4, 7, 11]); // E, G, B
    expect(s.label, '3rd above (E, G, B)');
  });

  test('A minor (A, C, E) in C major key → targets C, E, G', () {
    final s = suggestThirdAbove(
      chordRootPc: 9,
      chordQuality: 'm',
      chordTonePcs: const [9, 0, 4], // A, C, E
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [0, 4, 7]); // C, E, G
  });

  test('Bdim (B, D, F) in C major key → targets D, F, A', () {
    final s = suggestThirdAbove(
      chordRootPc: 11,
      chordQuality: 'dim',
      chordTonePcs: const [11, 2, 5], // B, D, F
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [2, 5, 9]); // D, F, A
  });

  test('G major (G, B, D) in F major key → drops non-diatonic B', () {
    final s = suggestThirdAbove(
      chordRootPc: 7,
      chordQuality: '',
      chordTonePcs: const [7, 11, 2], // G, B, D
      keyRootPc: 5, // F
      keyScaleName: 'major',
    );
    expect(s, isNotNull);
    expect(s!.targetPcs, [10, 5]); // Bb, F
  });

  test('no key → null', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7],
      keyRootPc: null,
      keyScaleName: null,
    );
    expect(s, isNull);
  });

  test('unknown scale → null', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7],
      keyRootPc: 0,
      keyScaleName: 'nonexistent',
    );
    expect(s, isNull);
  });

  test('chord fully non-diatonic → null', () {
    final s = suggestThirdAbove(
      chordRootPc: 6,
      chordQuality: '',
      chordTonePcs: const [6, 10, 1], // F#, A#, C#
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(s, isNull);
  });

  test('thirdAboveToSnapshot round-trip', () {
    final s = suggestThirdAbove(
      chordRootPc: 0,
      chordQuality: '',
      chordTonePcs: const [0, 4, 7],
      keyRootPc: 0,
      keyScaleName: 'major',
    )!;
    final snap = thirdAboveToSnapshot(s);
    expect(snap.currentRange, PianoRangeName.key49);
    expect(snap.viewMode, PianoViewMode.exact);
    expect(snap.selectedNotes, ['E', 'G', 'B']);
    expect(snap.selectedKeys.length, 3);
    // key49 startMidi=36 → keyIndex = midi - 36 → 28, 31, 35 for E,G,B
    final byMidi = {for (final k in snap.selectedKeys) k.midiNote: k};
    expect(byMidi[64]!.keyIndex, 28);
    expect(byMidi[64]!.noteName, 'E');
    expect(byMidi[67]!.keyIndex, 31);
    expect(byMidi[71]!.keyIndex, 35);
  });
}
