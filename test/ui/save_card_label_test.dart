import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/ui/save_card_label.dart';

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
    final l = saveCardLabel(_snap(
      chord: const PendingChord(root: 'C', quality: 'maj7', symbol: 'Cmaj7'),
    ));
    expect(l.kind, SaveCardLabelKind.chord);
    expect(l.text, 'Cmaj7');
  });

  test('scale when no chord', () {
    final l = saveCardLabel(_snap(
      scale: const PendingScale(root: 'A', scaleName: 'Dorian'),
    ));
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
}
