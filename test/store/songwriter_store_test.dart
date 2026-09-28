import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add section, add lane, add block', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 8);
    final sectionId = c.read(songwriterProvider).sections.single.id;

    final laneId = n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.save,
      label: 'Guitar',
    );

    n.addSaveBlock(
      sectionId: sectionId,
      laneId: laneId,
      saveId: 'save-1',
      startBar: 0,
      spanBars: 4,
    );

    final lane = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId);
    final block = lane.blocks.single;
    expect(block.saveId, 'save-1');
    expect(block.spanBars, 4);
  });

  test('overlapping block add is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    final l = n.addLane(sectionId: s, kind: SongLaneKind.save);
    n.addSaveBlock(
      sectionId: s,
      laneId: l,
      saveId: 'a',
      startBar: 0,
      spanBars: 4,
    );
    n.addSaveBlock(
      sectionId: s,
      laneId: l,
      saveId: 'b',
      startBar: 2,
      spanBars: 4,
    );
    expect(
      c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == l)
          .blocks
          .length,
      1,
    );
  });

  test('rejected overlap insert is a no-op: no notify, same state instance', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    final l = n.addLane(sectionId: s, kind: SongLaneKind.save);
    n.addSaveBlock(
      sectionId: s,
      laneId: l,
      saveId: 'a',
      startBar: 0,
      spanBars: 4,
    );

    final before = c.read(songwriterProvider);
    var notifications = 0;
    final sub = c.listen(songwriterProvider, (_, _) => notifications++);
    addTearDown(sub.close);

    // Overlapping insert -> rejected by blocksOverlap -> must not touch state.
    n.addSaveBlock(
      sectionId: s,
      laneId: l,
      saveId: 'b',
      startBar: 2,
      spanBars: 4,
    );

    expect(notifications, 0);
    expect(identical(c.read(songwriterProvider), before), isTrue);
  });

  test('clearing the key removes stale roman numerals from harmony blocks', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);

    n.setKey(0, 'major'); // C major
    n.addSection(label: 'V', lengthBars: 4);
    final s = c.read(songwriterProvider).sections.single.id;
    final l = n.addLane(sectionId: s, kind: SongLaneKind.harmony);

    // Add a harmony block for C (I in C major) with a precomputed numeral.
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 2,
        chordSymbol: 'C',
        chordQuality: '', // major = empty quality string
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
        romanNumeral: 'I',
      ),
    );

    // Recompute under the current key should keep 'I'.
    n.setKey(0, 'major');
    expect(
      c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == l)
          .blocks
          .single
          .romanNumeral,
      'I',
    );

    // Clearing the key should null out the numeral.
    n.setKey(null, null);
    expect(
      c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == l)
          .blocks
          .single
          .romanNumeral,
      isNull,
    );
  });
}
