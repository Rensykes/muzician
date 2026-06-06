// test/store/songwriter_voicing_accept_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(saveSystemProvider.notifier);
    return c;
  }

  ({String sectionId, String harmonyLaneId, String harmonyBlockId})
      seedSongWithHarmonyBlock(ProviderContainer c) {
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );
    return (sectionId: s, harmonyLaneId: l, harmonyBlockId: 'hb1');
  }

  test('accept creates SaveEntry in auto-created folder + save lane + block',
      () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);
    final voicing = suggestVoicings(chordRootPc: 0, quality: '').first;

    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: voicing,
        );

    final saves = c.read(saveSystemProvider);
    expect(saves.folders.any((f) => f.name == 'Untitled song'), isTrue);
    final projectFolder =
        saves.folders.firstWhere((f) => f.name == 'Untitled song');
    expect(projectFolder.parentId, isNull);
    final newSave = saves.saves.firstWhere(
      (s) => s.folderId == projectFolder.id,
    );
    expect(newSave.name, contains('C'));

    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLane = section.lanes.firstWhere(
      (l) => l.kind == SongLaneKind.save,
    );
    final block = saveLane.blocks.single;
    expect(block.saveId, newSave.id);
    expect(block.startBar, 0);
    expect(block.spanBars, 2);
  });

  test('second accept reuses the same folder and the same save lane',
      () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: voicings[0],
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
    c.read(songwriterProvider.notifier).setBlockPlacement(
          sectionId: ids.sectionId,
          laneId: c
              .read(songwriterProvider)
              .sections
              .firstWhere((s) => s.id == ids.sectionId)
              .lanes
              .firstWhere((l) => l.kind == SongLaneKind.save)
              .id,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: voicings[1],
        );

    final folders = c
        .read(saveSystemProvider)
        .folders
        .where((f) => f.name == 'Untitled song')
        .toList();
    expect(folders.length, 1, reason: 'folder must not be duplicated');

    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLanes =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList();
    expect(saveLanes.length, 1, reason: 'save lane must be reused');
    expect(saveLanes.single.blocks.length, 2);
  });
}
