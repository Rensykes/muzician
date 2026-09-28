import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'removing a shared pattern clears each linked block fallback and save',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      final projectId = saveSystem.createProject(
        'Pattern removal',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      await writer.reconcileCurrentProject();

      writer.addSection(label: 'Verse', lengthBars: 8);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final drumLaneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.drum,
      );
      final melodyLaneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.melody,
      );
      final guitarLaneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.guitarStrum,
      );
      final drumPatternId = writer.addDrumPattern(name: 'Beat');
      final melodyPatternId = writer.addMelodyPattern(name: 'Lead');
      final guitarPatternId = writer.addGuitarStrumPattern(name: 'Strum');

      for (final startBar in [0, 4]) {
        writer.addDrumBlock(
          sectionId: sectionId,
          laneId: drumLaneId,
          patternId: drumPatternId,
          startBar: startBar,
          spanBars: 2,
        );
        writer.addMelodyBlock(
          sectionId: sectionId,
          laneId: melodyLaneId,
          patternId: melodyPatternId,
          startBar: startBar,
          spanBars: 2,
        );
        writer.addGuitarStrumBlock(
          sectionId: sectionId,
          laneId: guitarLaneId,
          patternId: guitarPatternId,
          startBar: startBar,
          spanBars: 2,
        );
      }

      void expectRemovedPattern(SongLaneKind kind) {
        final project = container.read(songwriterProvider);
        final lane = project.sections.single.lanes.singleWhere(
          (candidate) => candidate.kind == kind,
        );
        expect(lane.blocks, hasLength(2));
        expect(
          lane.blocks.map((block) => block.patternId),
          everyElement(isNull),
        );

        final saveIds = lane.blocks.map((block) => block.saveId).toSet();
        expect(saveIds, hasLength(2));
        expect(saveIds, everyElement(isNotNull));
        for (final block in lane.blocks) {
          final embedded = block.embedded! as WriterBlockSnapshot;
          expect(embedded.laneKind, kind);
          final save = container
              .read(saveSystemProvider)
              .saves
              .singleWhere((save) => save.id == block.saveId);
          final canonical = save.snapshot as WriterBlockSnapshot;
          expect(canonical.laneKind, kind);
          switch (kind) {
            case SongLaneKind.drum:
              expect(embedded.drumPattern, isNull);
              expect(canonical.drumPattern, isNull);
            case SongLaneKind.melody:
              expect(embedded.melodyPattern, isNull);
              expect(canonical.melodyPattern, isNull);
            case SongLaneKind.guitarStrum:
              expect(embedded.guitarStrumPattern, isNull);
              expect(canonical.guitarStrumPattern, isNull);
            case SongLaneKind.harmony:
            case SongLaneKind.save:
            case SongLaneKind.audio:
              fail('Unexpected lane kind: $kind');
          }
        }
      }

      writer.removeDrumPattern(drumPatternId);
      expect(container.read(songwriterProvider).drumPatterns, isEmpty);
      expectRemovedPattern(SongLaneKind.drum);

      writer.removeMelodyPattern(melodyPatternId);
      expect(container.read(songwriterProvider).melodyPatterns, isEmpty);
      expectRemovedPattern(SongLaneKind.melody);

      writer.removeGuitarStrumPattern(guitarPatternId);
      expect(container.read(songwriterProvider).guitarStrumPatterns, isEmpty);
      expectRemovedPattern(SongLaneKind.guitarStrum);
    },
  );
}
