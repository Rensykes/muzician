// test/schema/rules/songwriter_library_match_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_library_match_rules.dart';

SaveEntry _save({
  required String id,
  required String name,
  required List<String> selectedNotes,
  PendingChord? pendingChord,
  required int updatedAt,
}) {
  final snap = FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: const [],
    selectedNotes: selectedNotes,
    viewMode: FretboardViewMode.exact,
    pendingChord: pendingChord,
  );
  return SaveEntry(
    id: id,
    name: name,
    folderId: 'f',
    snapshot: snap,
    createdAt: 0,
    updatedAt: updatedAt,
    order: 0,
  );
}

PendingChord _pc(String symbol, {String root = 'C', String quality = ''}) =>
    PendingChord(symbol: symbol, root: root, quality: quality);

void main() {
  const cMajorBlock = SongBlock(
    id: 'hb1', startBar: 0, spanBars: 2,
    chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
    chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
  );

  test('chord match: save note-set equals chord tones (pitch-class set)', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'C voicing', selectedNotes: ['C', 'E', 'G'],
          updatedAt: 100,
        ),
        _save(
          id: 's2', name: 'D voicing', selectedNotes: ['D', 'F#', 'A'],
          updatedAt: 200,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.length, 1);
    expect(m.chordMatches.single.entry.id, 's1');
    expect(m.chordMatches.single.kind, LibraryMatchKind.chord);
  });

  test('chord match ignores octave and repetition', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        // C3,E3,G3,C4 + a duplicate G → pitch-class set {C,E,G}.
        _save(
          id: 's1', name: 'C wide',
          selectedNotes: ['C3', 'E3', 'G3', 'C4', 'G4'],
          updatedAt: 100,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.single.entry.id, 's1');
  });

  test('a superset chord (Cmaj7) does NOT match a C triad', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'Cmaj7', selectedNotes: ['C', 'E', 'G', 'B'],
          updatedAt: 100,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches, isEmpty);
    // It still fits the C major scale, so it lands in the scale bucket.
    expect(m.scaleMatches.single.entry.id, 's1');
  });

  test('scale match: every selectedNote is in the key scale', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'CMaj scale highlight',
          selectedNotes: ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
          updatedAt: 100,
        ),
        _save(
          id: 's2', name: 'Has F#', selectedNotes: ['F#', 'G'],
          updatedAt: 200,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches, isEmpty);
    expect(m.scaleMatches.length, 1);
    expect(m.scaleMatches.single.entry.id, 's1');
    expect(m.scaleMatches.single.kind, LibraryMatchKind.scale);
  });

  test('save that matches both chord and scale only appears in chord bucket',
      () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 's1', name: 'C voicing', selectedNotes: ['C', 'E', 'G'],
          updatedAt: 100,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.length, 1);
    expect(m.scaleMatches, isEmpty);
  });

  test('no key and no chordSymbol → empty buckets', () {
    const block = SongBlock(id: 'hb', startBar: 0, spanBars: 1);
    final m = matchLibrary(
      harmonyBlock: block,
      searchableSaves: [
        _save(
          id: 's1', name: 'C voicing', selectedNotes: ['C', 'E', 'G'],
          pendingChord: _pc('C'),
          updatedAt: 100,
        ),
      ],
      keyRootPc: null,
      keyScaleName: null,
    );
    expect(m.chordMatches, isEmpty);
    expect(m.scaleMatches, isEmpty);
  });

  test('save with empty selectedNotes is not scale-matched', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(id: 's1', name: 'empty', selectedNotes: const [], updatedAt: 100),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.scaleMatches, isEmpty);
  });

  test('chord bucket sorted by updatedAt desc', () {
    final m = matchLibrary(
      harmonyBlock: cMajorBlock,
      searchableSaves: [
        _save(
          id: 'old', name: 'C old', selectedNotes: ['C', 'E', 'G'],
          pendingChord: _pc('C'),
          updatedAt: 100,
        ),
        _save(
          id: 'new', name: 'C new', selectedNotes: ['C', 'E', 'G'],
          pendingChord: _pc('C'),
          updatedAt: 500,
        ),
        _save(
          id: 'mid', name: 'C mid', selectedNotes: ['C', 'E', 'G'],
          pendingChord: _pc('C'),
          updatedAt: 300,
        ),
      ],
      keyRootPc: 0,
      keyScaleName: 'major',
    );
    expect(m.chordMatches.map((x) => x.entry.id).toList(),
        ['new', 'mid', 'old']);
  });
}
