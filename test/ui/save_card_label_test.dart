import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/ui/save_card_label.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;

FretboardSnapshot _snap({
  PendingChord? chord,
  PendingScale? scale,
  List<String> notes = const [],
}) => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [],
  selectedNotes: notes,
  viewMode: FretboardViewMode.exact,
  pendingChord: chord,
  pendingScale: scale,
);

void main() {
  test('chord wins', () {
    final l = saveCardLabel(
      _snap(
        chord: const PendingChord(root: 'C', quality: 'maj7', symbol: 'Cmaj7'),
      ),
    );
    expect(l.kind, SaveCardLabelKind.chord);
    expect(l.text, 'Cmaj7');
  });

  test('recognized save chords use the selected spelling and keep bass', () {
    final label = saveCardLabel(
      _snap(
        chord: const PendingChord(root: 'D#', quality: 'm', symbol: 'D#m/A#'),
      ),
      spelling: NoteSpelling.flats,
    );

    expect(label.text, 'Ebm/Bb');
  });

  test('flat chord roots retain verified identity in both spellings', () {
    const flatRoot = PendingChord(root: 'Bb', quality: '', symbol: 'Bb');
    const sharpRoot = PendingChord(root: 'A#', quality: '', symbol: 'A#');

    expect(saveCardLabel(_snap(chord: flatRoot)).text, 'A#');
    expect(
      saveCardLabel(_snap(chord: flatRoot), spelling: NoteSpelling.flats).text,
      'Bb',
    );
    expect(saveCardLabel(_snap(chord: sharpRoot)).text, 'A#');
    expect(
      saveCardLabel(_snap(chord: sharpRoot), spelling: NoteSpelling.flats).text,
      'Bb',
    );
  });

  test('scale when no chord', () {
    final l = saveCardLabel(
      _snap(
        scale: const PendingScale(root: 'A', scaleName: 'Dorian'),
      ),
    );
    expect(l.kind, SaveCardLabelKind.scale);
    expect(l.text, 'A Dorian');
  });

  test('notes when no chord/scale', () {
    final l = saveCardLabel(_snap(notes: const ['C', 'E', 'G']));
    expect(l.kind, SaveCardLabelKind.notes);
    expect(l.notes, ['C', 'E', 'G']);
  });

  test('highlight fallback when empty', () {
    final l = saveCardLabel(_snap());
    expect(l.kind, SaveCardLabelKind.highlight);
    expect(l.text, 'Highlight');
  });

  test('Writer block labels use its chord symbol', () {
    final l = saveCardLabel(
      const WriterBlockSnapshot(
        laneKind: SongLaneKind.harmony,
        chordSymbol: 'Am7',
      ),
    );
    expect(l.kind, SaveCardLabelKind.chord);
    expect(l.text, 'Am7');
  });

  test('Writer exact labels stay literal while recognized labels format', () {
    final exact = saveCardLabel(
      const WriterBlockSnapshot(
        laneKind: SongLaneKind.harmony,
        chordSymbol: 'D# idea',
      ),
      spelling: NoteSpelling.flats,
    );
    final recognized = saveCardLabel(
      const WriterBlockSnapshot(
        laneKind: SongLaneKind.harmony,
        chordSymbol: 'D#m/A#',
        chordRootPc: 3,
        chordQuality: 'm',
      ),
      spelling: NoteSpelling.flats,
    );

    expect(exact.text, 'D# idea');
    expect(recognized.text, 'Ebm/Bb');
  });

  test('silent Writer block has a readable label', () {
    final l = saveCardLabel(
      const WriterBlockSnapshot(laneKind: SongLaneKind.harmony, isSilent: true),
    );
    expect(l.kind, SaveCardLabelKind.writerBlock);
    expect(l.text, 'Lyrics');
  });
}
