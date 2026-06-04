import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

VoicingSuggestion firstVoicingForC() =>
    suggestVoicings(chordRootPc: 0, quality: '').first;

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

  ThirdAboveSuggestion freshSuggestion() => suggestThirdAbove(
        chordRootPc: 0,
        chordQuality: '',
        chordTonePcs: const [0, 4, 7],
        keyRootPc: 0,
        keyScaleName: 'major',
      )!;

  test('accept creates SaveEntry in auto-created "Songwriter harmonies" '
      'folder + save lane + block', () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);

    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final saves = c.read(saveSystemProvider);
    final folder = saves.folders
        .where((f) => f.name == 'Songwriter harmonies')
        .toList();
    expect(folder.length, 1);
    expect(folder.single.parentId, isNull);
    final newSave = saves.saves.firstWhere(
      (s) => s.folderId == folder.single.id,
    );
    expect(newSave.name, contains('C'));
    expect(newSave.name, contains('3rd above'));

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

  test('second accept reuses both folder and save lane', () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);

    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
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
    c.read(songwriterProvider.notifier).setBlockPlacement(
          sectionId: ids.sectionId,
          laneId: saveLaneId,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final folders = c
        .read(saveSystemProvider)
        .folders
        .where((f) => f.name == 'Songwriter harmonies')
        .toList();
    expect(folders.length, 1, reason: 'folder must not duplicate');
    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLanes =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList();
    expect(saveLanes.length, 1, reason: 'save lane must be reused');
    expect(saveLanes.single.blocks.length, 2);
  });

  test('harmonies and voicings folders coexist when both accept flows fire',
      () async {
    final c = freshContainer();
    final ids = seedSongWithHarmonyBlock(c);

    await c.read(songwriterProvider.notifier).acceptVoicingSuggestion(
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
    c.read(songwriterProvider.notifier).setBlockPlacement(
          sectionId: ids.sectionId,
          laneId: saveLaneId,
          blockId: firstBlockId,
          startBar: 4,
          spanBars: 2,
        );
    await c.read(songwriterProvider.notifier).acceptThirdAboveSuggestion(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          suggestion: freshSuggestion(),
        );

    final folderNames = c
        .read(saveSystemProvider)
        .folders
        .map((f) => f.name)
        .toSet();
    expect(folderNames, containsAll(['Songwriter voicings', 'Songwriter harmonies']));
  });
}
