import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

VoicingSuggestion firstVoicingForC() =>
    suggestVoicings(chordRootPc: 0, quality: '').first;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Accept actions are project-scoped: they save into the selected
  // section's Writer folder, so every test runs with a real project selected.
  ProviderContainer freshContainer({
    HarmonyLaneInstrument defaultInstrument = HarmonyLaneInstrument.fretboard,
  }) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final saveSystem = c.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Untitled song',
      ProjectConfig(defaultHarmonyInstrument: defaultInstrument),
    )!;
    saveSystem.selectProject(projectId);
    return c;
  }

  ({String sectionId, String harmonyLaneId, String harmonyBlockId})
  seedSongWithHarmonyBlock(ProviderContainer c) {
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    final l = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1',
        startBar: 0,
        spanBars: 2,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
        romanNumeral: 'I',
      ),
    );
    return (sectionId: s, harmonyLaneId: l, harmonyBlockId: 'hb1');
  }

  ThirdAboveSuggestion freshSuggestion() => suggestThirdAbove(
    chordRootPc: 0,
    chordQuality: '',
    chordTonePcs: const [0, 4, 7],
    keyRootPc: 0,
    keyScaleName: 'major',
  )!;

  test(
    'accept creates SaveEntry in the Writer section folder + save lane + block',
    () async {
      final c = freshContainer(defaultInstrument: HarmonyLaneInstrument.piano);
      final ids = seedSongWithHarmonyBlock(c);

      await c
          .read(songwriterProvider.notifier)
          .acceptThirdAboveSuggestion(
            sectionId: ids.sectionId,
            harmonyBlockId: ids.harmonyBlockId,
            suggestion: freshSuggestion(),
          );

      final section = c
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == ids.sectionId);
      final saveLane = section.lanes.firstWhere(
        (l) => l.kind == SongLaneKind.save,
      );
      expect(saveLane.anchorLaneId, isNull);
      final block = saveLane.blocks.single;
      final saves = c.read(saveSystemProvider);
      final link = saves.writerLinks.singleWhere(
        (link) => link.blockId == block.id,
      );
      final sectionFolder = saves.folders.singleWhere(
        (folder) => folder.id == link.folderId,
      );
      final newSave = saves.saves.singleWhere(
        (save) => save.id == block.saveId,
      );
      expect(newSave.name, contains('C'));
      expect(newSave.name, contains('3rd above'));
      expect(newSave.origin, SaveOrigin.writer);
      expect(newSave.folderId, sectionFolder.id);
      expect(sectionFolder.writerSectionId, ids.sectionId);
      expect(sectionFolder.writerLaneKind, SongLaneKind.save);
      final sectionRoot = saves.folders.singleWhere(
        (folder) =>
            folder.writerSectionId == ids.sectionId &&
            folder.writerLaneKind == null,
      );
      expect(sectionFolder.parentId, sectionRoot.id);
      expect(sectionRoot.parentId, saves.selectedProjectId);
      expect(link.sectionId, ids.sectionId);
      expect(link.saveId, newSave.id);
      expect(block.saveId, newSave.id);
      expect(block.startBar, 0);
      expect(block.spanBars, 2);
    },
  );

  test('second accept reuses both folder and save lane', () async {
    final c = freshContainer(defaultInstrument: HarmonyLaneInstrument.piano);
    final ids = seedSongWithHarmonyBlock(c);

    await c
        .read(songwriterProvider.notifier)
        .acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );
    final firstBlockId = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .blocks
        .single
        .id;
    final saveLaneId = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .id;
    c
        .read(songwriterProvider.notifier)
        .setBlockPlacement(
          sectionId: ids.sectionId,
          laneId: saveLaneId,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    await c
        .read(songwriterProvider.notifier)
        .acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final folders = c
        .read(saveSystemProvider)
        .folders
        .where(
          (folder) =>
              folder.writerSectionId == ids.sectionId &&
              folder.writerLaneKind == SongLaneKind.save,
        )
        .toList();
    expect(folders.length, 1, reason: 'folder must not duplicate');
    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLanes = section.lanes
        .where((l) => l.kind == SongLaneKind.save)
        .toList();
    expect(saveLanes.length, 1, reason: 'save lane must be reused');
    expect(saveLanes.single.blocks.length, 2);
  });

  test(
    'voicing accept + 3rd-above accept both land in the section folder',
    () async {
      final c = freshContainer();
      final ids = seedSongWithHarmonyBlock(c);

      await c
          .read(songwriterProvider.notifier)
          .acceptVoicingSuggestion(
            sectionId: ids.sectionId,
            harmonyBlockId: ids.harmonyBlockId,
            suggestion: firstVoicingForC(),
          );
      final saveLaneId = c
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == ids.sectionId)
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.save)
          .id;
      final firstBlockId = c
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == ids.sectionId)
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.save)
          .blocks
          .single
          .id;
      c
          .read(songwriterProvider.notifier)
          .setBlockPlacement(
            sectionId: ids.sectionId,
            laneId: saveLaneId,
            blockId: firstBlockId,
            startBar: 4,
            spanBars: 2,
          );
      final pianoLaneId = c
          .read(songwriterProvider.notifier)
          .addLane(
            sectionId: ids.sectionId,
            kind: SongLaneKind.harmony,
            harmonyInstrument: HarmonyLaneInstrument.piano,
          );
      c
          .read(songwriterProvider.notifier)
          .addHarmonyBlock(
            sectionId: ids.sectionId,
            laneId: pianoLaneId,
            block: const SongBlock(
              id: 'piano-hb1',
              startBar: 0,
              spanBars: 2,
              chordSymbol: 'C',
              chordQuality: '',
              chordRootPc: 0,
              chordNotes: ['C', 'E', 'G'],
            ),
          );
      await c
          .read(songwriterProvider.notifier)
          .acceptThirdAboveSuggestion(
            sectionId: ids.sectionId,
            harmonyBlockId: 'piano-hb1',
            suggestion: freshSuggestion(),
          );

      final saveState = c.read(saveSystemProvider);
      final folders = saveState.folders
          .where(
            (folder) =>
                folder.writerSectionId == ids.sectionId &&
                folder.writerLaneKind == SongLaneKind.save,
          )
          .toList();
      expect(folders.length, 1, reason: 'section folder must be unique');
      final section = c
          .read(songwriterProvider)
          .sections
          .singleWhere((section) => section.id == ids.sectionId);
      final saveLanes = section.lanes
          .where((lane) => lane.kind == SongLaneKind.save)
          .toList();
      expect(saveLanes, hasLength(2));
      expect(
        saveLanes
            .singleWhere((lane) => lane.anchorLaneId == pianoLaneId)
            .blocks,
        hasLength(1),
      );
      final suggestionBlocks = saveLanes.expand((lane) => lane.blocks).toList();
      expect(suggestionBlocks, hasLength(2));
      final suggestionSaves = suggestionBlocks
          .map(
            (block) =>
                saveState.saves.singleWhere((save) => save.id == block.saveId),
          )
          .toList();
      expect(
        suggestionSaves.map((save) => save.folderId),
        everyElement(folders.single.id),
      );
      expect(
        suggestionSaves.where((save) => save.name.contains('3rd above')),
        hasLength(1),
      );
      expect(
        saveState.writerLinks
            .where(
              (link) =>
                  suggestionBlocks.any((block) => block.id == link.blockId),
            )
            .map((link) => link.folderId),
        everyElement(folders.single.id),
      );
      expect(
        saveState.writerLinks.where(
          (link) => suggestionBlocks.any((block) => block.id == link.blockId),
        ),
        hasLength(2),
      );
    },
  );

  test(
    'overlap preflight: bailing out does NOT create an orphan SaveEntry',
    () async {
      final c = freshContainer(defaultInstrument: HarmonyLaneInstrument.piano);
      final ids = seedSongWithHarmonyBlock(c);

      await c
          .read(songwriterProvider.notifier)
          .acceptThirdAboveSuggestion(
            sectionId: ids.sectionId,
            harmonyBlockId: ids.harmonyBlockId,
            suggestion: freshSuggestion(),
          );

      final savesBefore = c.read(saveSystemProvider).saves.length;
      final blocksBefore = c
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == ids.sectionId)
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.save)
          .blocks
          .length;

      await c
          .read(songwriterProvider.notifier)
          .acceptThirdAboveSuggestion(
            sectionId: ids.sectionId,
            harmonyBlockId: ids.harmonyBlockId,
            suggestion: freshSuggestion(),
          );

      expect(
        c.read(saveSystemProvider).saves.length,
        savesBefore,
        reason: 'no orphan SaveEntry on overlap',
      );
      final blocksAfter = c
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == ids.sectionId)
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.save)
          .blocks
          .length;
      expect(blocksAfter, blocksBefore, reason: 'no new block on overlap');
    },
  );
}
