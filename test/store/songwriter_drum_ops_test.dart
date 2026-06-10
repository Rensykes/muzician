import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('addDrumPattern appends and returns the new id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    final id = notifier.addDrumPattern(name: 'Backbeat');
    final state = container.read(songwriterProvider);
    expect(state.drumPatterns.length, 1);
    expect(state.drumPatterns.first.id, id);
    expect(state.drumPatterns.first.name, 'Backbeat');
  });

  test('updateDrumPattern replaces a pattern by id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    final id = notifier.addDrumPattern();
    final updated = container.read(songwriterProvider).drumPatterns.single
        .copyWith(name: 'Funky');
    notifier.updateDrumPattern(updated);
    expect(
      container.read(songwriterProvider).drumPatterns.single.name,
      'Funky',
    );
  });

  test('removeDrumPattern drops the pattern AND clears refs in blocks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;

    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern();
    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    notifier.removeDrumPattern(patternId);

    final state = container.read(songwriterProvider);
    expect(state.drumPatterns, isEmpty);
    final lane = state.sections.first.lanes.firstWhere((l) => l.id == laneId);
    expect(lane.blocks.single.patternId, isNull);
  });

  test('addDrumBlock places a block referencing the pattern', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    notifier.addSection(label: 'Verse', lengthBars: 8);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern();

    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 2,
      spanBars: 4,
    );

    final block = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;

    expect(block.patternId, patternId);
    expect(block.startBar, 2);
    expect(block.spanBars, 4);
  });
}
