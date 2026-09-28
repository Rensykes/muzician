import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart'
    show tileLaneBlocks;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'detected chord inserts a harmony block without a library save',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(saveSystemProvider.notifier).hydrate();
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 8);
      final sectionId = container.read(songwriterProvider).sections.single.id;

      final inserted = writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 2,
        chordSymbol: 'Cmaj7',
        chordQuality: 'maj7',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G', 'B'],
      );

      expect(inserted, isTrue);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      final block = lane.blocks.single;
      expect(lane.kind, SongLaneKind.harmony);
      expect(block.startBar, 2);
      expect(block.chordSymbol, 'Cmaj7');
      expect(block.chordQuality, 'maj7');
      expect(block.chordRootPc, 0);
      expect(block.chordNotes, ['C', 'E', 'G', 'B']);
      expect(block.saveId, isNull);
      expect(block.embedded, isNull);
      expect(container.read(saveSystemProvider).saves, isEmpty);
    },
  );

  test(
    'exact piano selection embeds its snapshot without a library save',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(saveSystemProvider.notifier).hydrate();
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Chorus', lengthBars: 8);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final snapshot = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 24, midiNote: 60, noteName: 'C'),
          PianoCoordinate(keyIndex: 28, midiNote: 64, noteName: 'E'),
        ],
        selectedNotes: const ['C', 'E'],
        viewMode: PianoViewMode.exact,
      );

      final inserted = writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 0,
        snapshot: snapshot,
      );

      expect(inserted, isTrue);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      final block = lane.blocks.single;
      expect(lane.kind, SongLaneKind.save);
      expect(block.saveId, isNull);
      expect(block.embedded?.toJson(), snapshot.toJson());
      expect(container.read(saveSystemProvider).saves, isEmpty);
    },
  );

  test(
    'replacing an expanded chord placement updates its source in place',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(saveSystemProvider.notifier).hydrate();
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 8);
      final sectionId = container.read(songwriterProvider).sections.single.id;

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: sectionId,
          startBar: 0,
          chordSymbol: 'F',
          chordQuality: '',
          chordRootPc: 5,
          chordNotes: const ['F', 'A', 'C'],
        ),
        isTrue,
      );
      final initialSection = container.read(songwriterProvider).sections.single;
      final initialLane = initialSection.lanes.single;
      final source = initialLane.blocks.single;
      writer.setBlockLyric(
        sectionId: sectionId,
        laneId: initialLane.id,
        blockId: source.id,
        verseIndex: 0,
        text: 'Keep this lyric',
      );
      writer.setLaneRepeat(
        sectionId: sectionId,
        laneId: initialLane.id,
        repeat: 4,
      );

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: sectionId,
          startBar: 3,
          chordSymbol: 'Cmaj7',
          chordQuality: 'maj7',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G', 'B'],
          replaceBlockId: source.id,
        ),
        isTrue,
      );

      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      final updatedSource = lane.blocks.single;
      expect(updatedSource.id, source.id);
      expect(updatedSource.startBar, source.startBar);
      expect(updatedSource.spanBars, source.spanBars);
      expect(updatedSource.lyrics, ['Keep this lyric']);
      expect(lane.repeat, 4);
      expect(
        tileLaneBlocks(
          lane,
          sectionLengthBars: section.lengthBars,
        ).map((block) => (block.startBar, block.chordSymbol)).toList(),
        [(0, 'Cmaj7'), (1, 'Cmaj7'), (2, 'Cmaj7'), (3, 'Cmaj7')],
      );
    },
  );

  test(
    'replacing an expanded voicing updates every copy with the snapshot',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      await saveSystem.hydrate();
      final projectId = saveSystem.createProject(
        'Writer project',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      final originalSnapshot = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 24, midiNote: 60, noteName: 'C'),
          PianoCoordinate(keyIndex: 28, midiNote: 64, noteName: 'E'),
        ],
        selectedNotes: const ['C', 'E'],
        viewMode: PianoViewMode.exact,
      );
      final originalSaveId = saveSystem.saveSnapshot(
        'Original piano voicing',
        projectId,
        originalSnapshot,
      )!;
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Chorus', lengthBars: 8);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final newSnapshot = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const ['D', 'F#', 'A'],
        viewMode: PianoViewMode.exact,
      );

      final laneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.save,
      );
      writer.addSaveBlock(
        sectionId: sectionId,
        laneId: laneId,
        saveId: originalSaveId,
        startBar: 1,
        spanBars: 1,
      );
      final initialSection = container.read(songwriterProvider).sections.single;
      final initialLane = initialSection.lanes.single;
      final source = initialLane.blocks.single;
      writer.setBlockLyric(
        sectionId: sectionId,
        laneId: initialLane.id,
        blockId: source.id,
        verseIndex: 0,
        text: 'Keep this lyric',
      );
      writer.setLaneRepeat(
        sectionId: sectionId,
        laneId: initialLane.id,
        repeat: 3,
      );

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: sectionId,
          startBar: 3,
          snapshot: newSnapshot,
          replaceBlockId: source.id,
        ),
        isTrue,
      );

      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      final updatedSource = lane.blocks.single;
      expect(updatedSource.id, source.id);
      expect(updatedSource.startBar, source.startBar);
      expect(updatedSource.spanBars, source.spanBars);
      expect(updatedSource.lyrics, ['Keep this lyric']);
      expect(updatedSource.saveId, isNotNull);
      expect(updatedSource.chordSymbol, isNull);
      expect(updatedSource.chordQuality, isNull);
      expect(updatedSource.chordRootPc, isNull);
      expect(updatedSource.chordNotes, isEmpty);
      expect(lane.repeat, 3);
      final expanded = tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      );
      expect(expanded.map((block) => block.startBar), [1, 3, 5]);
      expect(
        expanded.map((block) => block.saveId),
        everyElement(updatedSource.saveId),
      );
      for (final block in expanded) {
        expect(block.embedded?.toJson(), equals(newSnapshot.toJson()));
      }

      final saveState = container.read(saveSystemProvider);
      final link = saveState.writerLinks.singleWhere(
        (link) => link.blockId == updatedSource.id,
      );
      final canonicalSave = saveState.saves.singleWhere(
        (save) => save.id == updatedSource.saveId,
      );
      final sectionFolder = saveState.folders.singleWhere(
        (folder) => folder.id == link.folderId,
      );
      expect(updatedSource.saveId, originalSaveId);
      expect(link.saveId, originalSaveId);
      expect(link.sectionId, sectionId);
      expect(canonicalSave.snapshot.toJson(), newSnapshot.toJson());
      expect(canonicalSave.folderId, projectId);
      expect(canonicalSave.origin, SaveOrigin.manual);
      expect(sectionFolder.writerSectionId, sectionId);
      expect(sectionFolder.parentId, projectId);
    },
  );
}
