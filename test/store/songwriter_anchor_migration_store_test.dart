import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:muzician/store/writer_save_sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SongwriterProjectSnapshot legacySnapshot({String name = 'Legacy Writer'}) =>
      SongwriterProjectSnapshot(
        name: name,
        config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        strumAnchorMigrationVersion: 0,
        sections: const [
          SongSection(
            id: 'section',
            lengthBars: 4,
            order: 0,
            lanes: [
              SongLane(
                id: 'primary-guitar',
                kind: SongLaneKind.harmony,
                order: 0,
                blocks: [],
              ),
              SongLane(
                id: 'strum',
                kind: SongLaneKind.guitarStrum,
                order: 1,
                blocks: [],
              ),
            ],
          ),
        ],
      );

  Future<(ProviderContainer, String, SongwriterNotifier)> makeProject() async {
    final container = ProviderContainer();
    final saveNotifier = container.read(saveSystemProvider.notifier);
    final projectId = saveNotifier.createProject(
      'Current project',
      const ProjectConfig(tempo: 120),
    )!;
    saveNotifier.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    await container.read(writerSaveSyncProvider.notifier).drain();
    return (container, projectId, writer);
  }

  for (final dirty in [false, true]) {
    test(
      'migrates session, named Save, and binding baseline; dirty=$dirty',
      () async {
        final (container, projectId, writer) = await makeProject();
        addTearDown(container.dispose);
        final baseline = legacySnapshot();
        final live = dirty
            ? baseline.copyWith(name: 'Unsaved Writer')
            : baseline;
        writer.state = live;
        final activeSaveId = container
            .read(saveSystemProvider.notifier)
            .saveSnapshot('Named Writer Save', projectId, baseline)!;
        container.read(writerSaveBindingProvider.notifier).commitState({
          projectId: WriterSaveBinding(
            activeSaveId: activeSaveId,
            materializedBaselineJson: jsonEncode(baseline.toJson()),
          ),
        });

        expect(container.read(writerDirtyProvider), dirty);
        await writer.migratePersistedStrumAnchors();

        SongwriterProjectSnapshot migrated(SongwriterProjectSnapshot snapshot) {
          expect(
            snapshot.strumAnchorMigrationVersion,
            strumAnchorMigrationCurrentVersion,
          );
          expect(
            snapshot.sections.single.lanes
                .singleWhere((lane) => lane.kind == SongLaneKind.guitarStrum)
                .anchorLaneId,
            'primary-guitar',
          );
          return snapshot;
        }

        migrated(container.read(songwriterSessionsProvider)[projectId]!);
        migrated(container.read(songwriterProvider));
        final named =
            container
                    .read(saveSystemProvider)
                    .saves
                    .singleWhere((save) => save.id == activeSaveId)
                    .snapshot
                as SongwriterProjectSnapshot;
        migrated(named);
        final migratedBaseline = SongwriterProjectSnapshot.fromJson(
          jsonDecode(
                container
                    .read(writerSaveBindingProvider)[projectId]!
                    .materializedBaselineJson!,
              )
              as Map<String, dynamic>,
        );
        migrated(migratedBaseline);
        expect(container.read(writerDirtyProvider), dirty);
      },
    );
  }

  test('legacy no-source migration persists its version marker', () async {
    final (container, projectId, writer) = await makeProject();
    addTearDown(container.dispose);
    final legacy = SongwriterProjectSnapshot(
      name: 'No guitar source',
      config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      strumAnchorMigrationVersion: 0,
      sections: const [
        SongSection(
          id: 'section',
          lengthBars: 2,
          order: 0,
          lanes: [
            SongLane(
              id: 'piano',
              kind: SongLaneKind.harmony,
              order: 0,
              harmonyInstrument: HarmonyLaneInstrument.piano,
              blocks: [],
            ),
            SongLane(
              id: 'strum',
              kind: SongLaneKind.guitarStrum,
              order: 1,
              blocks: [],
            ),
          ],
        ),
      ],
    );
    writer.state = legacy;
    container.read(songwriterSessionsProvider.notifier).commitState({
      projectId: legacy,
    });

    await writer.migratePersistedStrumAnchors();

    final migrated = container.read(songwriterSessionsProvider)[projectId]!;
    expect(
      migrated.strumAnchorMigrationVersion,
      strumAnchorMigrationCurrentVersion,
    );
    expect(migrated.sections.single.lanes.last.anchorLaneId, isNull);
  });
}
