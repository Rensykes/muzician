import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  FretboardSnapshot snap(List<String> notes) => FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: notes,
        viewMode: FretboardViewMode.exact,
      );

  test('embedded wins; else looked up by saveId; else null', () {
    final saves = [
      SaveEntry(
        id: 's1',
        name: 'A',
        folderId: 'f',
        snapshot: snap(['C']),
        createdAt: 0,
        updatedAt: 0,
        order: 0,
      ),
    ];
    final byId = resolveBlockSnapshot(
      const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1'),
      saves,
    );
    expect(byId, isNotNull);
    expect(byId!.selectedNotes, ['C']);

    final embedded = snap(['E']);
    final byEmbed = resolveBlockSnapshot(
      SongBlock(
          id: 'b', startBar: 0, spanBars: 1, saveId: 's1', embedded: embedded),
      saves,
    );
    expect(byEmbed, embedded);

    expect(
      resolveBlockSnapshot(
        const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 'missing'),
        saves,
      ),
      isNull,
    );
  });
}
