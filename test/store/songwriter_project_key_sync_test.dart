import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('project key sync recomputes Writer Roman numerals without history', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);

    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
    );
    writer.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 2,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );

    writer.syncProjectConfig(
      tempo: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      keyRoot: 7,
      keyScaleName: 'major',
    );

    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    expect(block.romanNumeral, 'IV');
    expect(writer.canUndo, isFalse);
  });
}
