import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('makeSilentBlock sets isSilent and seeds an empty lyric line', () {
    final b = makeSilentBlock(startBar: 2, spanBars: 1, verseCount: 2);
    expect(b.isSilent, isTrue);
    expect(b.chordSymbol, isNull);
    expect(b.lyrics, ['', '']);
    expect(b.startBar, 2);
  });

  test('setBlockLyric writes one verse and leaves others untouched', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );
    final blockId = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single.id;

    n.setBlockLyric(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 1,
      text: 'second verse line',
    );

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.lyrics.length, 2);
    expect(block.lyrics[0], '');
    expect(block.lyrics[1], 'second verse line');
  });

  test('setBlockLyric clears the verse when text is null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );
    final blockId = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single.id;

    n.setBlockLyric(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 0,
      text: 'temp',
    );
    n.setBlockLyric(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 0,
      text: null,
    );

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.lyrics, isEmpty);
  });

  test('addSilentBlock places a silent block on the harmony lane', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;

    n.addSilentBlock(
      sectionId: sectionId,
      laneId: laneId,
      startBar: 2,
      spanBars: 1,
    );

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.isSilent, isTrue);
    expect(block.chordSymbol, isNull);
    expect(block.startBar, 2);
  });

  test('setSectionRepeat grows lyrics list on each harmony block', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ).copyWith(lyrics: ['first']),
    );

    n.setSectionRepeat(sectionId, 3);

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.lyrics, ['first', '', '']);
  });

  test('setSectionRepeat does NOT shrink existing lyrics', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ).copyWith(lyrics: ['a', 'b', 'c']),
    );

    n.setSectionRepeat(sectionId, 1);

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.lyrics, ['a', 'b', 'c']);
  });
}
