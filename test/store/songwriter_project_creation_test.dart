import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/save_system_rules.dart'
    show saveSystemStorageKey;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:muzician/store/writer_save_sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProjectCreationStorage implements WriterSaveSyncStorage {
  final values = <String, String>{};
  final failNextKeys = <String>[];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (failNextKeys.isNotEmpty && failNextKeys.first == key) {
      failNextKeys.removeAt(0);
      throw StateError('simulated project-creation storage failure');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProviderContainer, String, SongwriterNotifier)> makeProject() async {
    final container = ProviderContainer();
    final saves = container.read(saveSystemProvider.notifier);
    final projectId = saves.createProject(
      'Current project',
      const ProjectConfig(tempo: 108),
    )!;
    saves.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    return (container, projectId, writer);
  }

  test(
    'pre-acceptance failure leaves project state untouched and releases fence',
    () async {
      final storage = _ProjectCreationStorage();
      final container = ProviderContainer(
        overrides: [writerSaveSyncStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final saveNotifier = container.read(saveSystemProvider.notifier);
      final oldProjectId = saveNotifier.createProject(
        'Current project',
        const ProjectConfig(tempo: 120),
      )!;
      saveNotifier.selectProject(oldProjectId);
      final writer = container.read(songwriterProvider.notifier);
      await container.read(writerSaveSyncProvider.notifier).drain();
      writer.addSection(label: 'Current session', lengthBars: 4);
      final beforeState = container.read(songwriterProvider);
      final beforeFolderIds = container
          .read(saveSystemProvider)
          .folders
          .map((folder) => folder.id)
          .toSet();
      await container.read(writerSaveSyncProvider.notifier).drain();
      storage.failNextKeys.add(writerSaveSyncJournalStorageKey);

      final result = await writer.createSaveProject(
        name: 'Should not publish',
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
        disposition: WriterProjectCreationDisposition.keep,
      );

      expect(result.status, WriterProjectCreationStatus.storageFailure);
      expect(
        container.read(saveSystemProvider).selectedProjectId,
        oldProjectId,
      );
      expect(
        container
            .read(saveSystemProvider)
            .folders
            .map((folder) => folder.id)
            .toSet(),
        beforeFolderIds,
      );
      expect(container.read(songwriterProvider), beforeState);
      expect(container.read(writerProjectWriteFenceProvider), isFalse);
    },
  );

  test(
    'accepted replay failure keeps project unpublished and recovery fence held',
    () async {
      final storage = _ProjectCreationStorage();
      final container = ProviderContainer(
        overrides: [writerSaveSyncStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final saveNotifier = container.read(saveSystemProvider.notifier);
      final oldProjectId = saveNotifier.createProject(
        'Current project',
        const ProjectConfig(tempo: 120),
      )!;
      saveNotifier.selectProject(oldProjectId);
      final writer = container.read(songwriterProvider.notifier);
      await container.read(writerSaveSyncProvider.notifier).drain();
      writer.addSection(label: 'Current session', lengthBars: 4);
      final beforeState = container.read(songwriterProvider);
      final beforeFolderIds = container
          .read(saveSystemProvider)
          .folders
          .map((folder) => folder.id)
          .toSet();
      await container.read(writerSaveSyncProvider.notifier).drain();
      storage.failNextKeys.addAll([
        songwriterSessionsStorageKey,
        saveSystemStorageKey,
      ]);

      final result = await writer.createSaveProject(
        name: 'Needs recovery',
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
        disposition: WriterProjectCreationDisposition.keep,
      );

      expect(result.status, WriterProjectCreationStatus.recoveryRequired);
      expect(
        container.read(saveSystemProvider).selectedProjectId,
        oldProjectId,
      );
      expect(
        container
            .read(saveSystemProvider)
            .folders
            .map((folder) => folder.id)
            .toSet(),
        beforeFolderIds,
      );
      expect(container.read(songwriterProvider), beforeState);
      expect(container.read(writerSaveSyncProvider), isTrue);
      expect(container.read(writerProjectWriteFenceProvider), isTrue);
      expect(
        storage.values.containsKey(writerSaveSyncJournalStorageKey),
        isTrue,
      );
    },
  );

  test('creation requires the selected folder to be a project', () async {
    final (container, _, writer) = await makeProject();
    addTearDown(container.dispose);
    final saveNotifier = container.read(saveSystemProvider.notifier);
    final dumpId = saveNotifier.ensureDumpFolder();
    saveNotifier.selectProject(dumpId);
    final folderCount = container.read(saveSystemProvider).folders.length;

    final result = await writer.createSaveProject(
      name: 'Writer project',
      defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
    );

    expect(result.status, WriterProjectCreationStatus.noSelectedProject);
    expect(container.read(saveSystemProvider).folders, hasLength(folderCount));
    expect(container.read(saveSystemProvider).selectedProjectId, dumpId);
  });

  test(
    'dirty creation requests disposition without changing the project',
    () async {
      final (container, oldProjectId, writer) = await makeProject();
      addTearDown(container.dispose);
      writer.addSection(label: 'Keep or discard', lengthBars: 4);
      final oldFolderCount = container.read(saveSystemProvider).folders.length;
      final oldSession = container.read(songwriterProvider);

      final result = await writer.createSaveProject(
        name: 'Prompt target',
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
      );

      expect(result.status, WriterProjectCreationStatus.dispositionRequired);
      expect(
        container.read(saveSystemProvider).selectedProjectId,
        oldProjectId,
      );
      expect(container.read(saveSystemProvider).folders.length, oldFolderCount);
      expect(container.read(songwriterProvider), oldSession);
    },
  );

  test(
    'clean creation defaults to Keep and retains the outgoing session',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final oldProjectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Clean project', const ProjectConfig(tempo: 120))!;
      container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
      final writer = container.read(songwriterProvider.notifier);
      expect(container.read(writerDirtyProvider), isFalse);

      final result = await writer.createSaveProject(
        name: 'Default Keep target',
        defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
      );

      expect(result.succeeded, isTrue);
      expect(
        container.read(songwriterSessionsProvider)[oldProjectId],
        isNotNull,
      );
      expect(
        container.read(saveSystemProvider).selectedProjectId,
        result.projectId,
      );
    },
  );

  test(
    'Keep creates an independent project and retains the outgoing session',
    () async {
      final (container, oldProjectId, writer) = await makeProject();
      addTearDown(container.dispose);
      writer.addSection(label: 'Verse', lengthBars: 8);
      writer.setTempo(132);

      final result = await writer.createSaveProject(
        name: 'New project',
        defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
        disposition: WriterProjectCreationDisposition.keep,
      );

      expect(result.succeeded, isTrue);
      final newProjectId = result.projectId!;
      final saveState = container.read(saveSystemProvider);
      final newFolder = saveState.folders.singleWhere(
        (folder) => folder.id == newProjectId,
      );
      expect(
        newFolder.projectConfig!.defaultHarmonyInstrument,
        HarmonyLaneInstrument.piano,
      );
      expect(saveState.selectedProjectId, newProjectId);
      expect(container.read(songwriterProvider).sections, isEmpty);
      expect(container.read(songwriterProvider).config.tempo, 120);

      container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
      expect(container.read(songwriterProvider).config.tempo, 132);
      expect(container.read(songwriterProvider).sections.single.label, 'Verse');
    },
  );

  test(
    'Discard without a valid active Writer Save clears only the session link',
    () async {
      final (container, oldProjectId, writer) = await makeProject();
      addTearDown(container.dispose);
      writer.addSection(label: 'Discard me', lengthBars: 4);
      final retainedSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'Independent save',
            oldProjectId,
            PianoSnapshot(
              currentRange: PianoRangeName.key61,
              selectedKeys: const [],
              selectedNotes: const [],
              viewMode: PianoViewMode.exact,
            ),
          );

      final result = await writer.createSaveProject(
        name: 'Discard target',
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
        disposition: WriterProjectCreationDisposition.discard,
      );

      expect(result.succeeded, isTrue);
      expect(
        container.read(songwriterSessionsProvider).containsKey(oldProjectId),
        isFalse,
      );
      expect(
        container.read(writerSaveBindingProvider).containsKey(oldProjectId),
        isFalse,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .any((save) => save.id == retainedSaveId),
        isTrue,
      );

      container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
      expect(container.read(songwriterProvider).sections, isEmpty);
    },
  );

  test(
    'Discard restores a valid named Writer Save and rebaselines its binding',
    () async {
      final (container, oldProjectId, writer) = await makeProject();
      addTearDown(container.dispose);
      writer.addSection(label: 'Saved section', lengthBars: 4);
      final saved = writer.materializeCurrentContent();
      final activeSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('Active Writer Save', oldProjectId, saved)!;
      container.read(writerSaveBindingProvider.notifier).commitState({
        oldProjectId: WriterSaveBinding(
          activeSaveId: activeSaveId,
          materializedBaselineJson: jsonEncode(saved.toJson()),
        ),
      });
      writer.addSection(label: 'Unsaved section', lengthBars: 2);

      final result = await writer.createSaveProject(
        name: 'Restore target',
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
        disposition: WriterProjectCreationDisposition.discard,
      );

      expect(result.succeeded, isTrue);
      final binding = container.read(writerSaveBindingProvider)[oldProjectId]!;
      expect(binding.activeSaveId, activeSaveId);
      expect(binding.alwaysOverwrite, isFalse);
      expect(binding.materializedBaselineJson, isNotNull);
      expect(
        container
            .read(songwriterSessionsProvider)[oldProjectId]!
            .sections
            .map((section) => section.label),
        ['Saved section'],
      );
      container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
      expect(
        container
            .read(songwriterProvider)
            .sections
            .map((section) => section.label),
        ['Saved section'],
      );
      expect(container.read(writerDirtyProvider), isFalse);
    },
  );

  test(
    'Discard forks changed canonical block content from the named baseline',
    () async {
      final (container, oldProjectId, writer) = await makeProject();
      addTearDown(container.dispose);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final laneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
      );
      writer.addHarmonyBlock(
        sectionId: sectionId,
        laneId: laneId,
        block: const SongBlock(
          id: 'canonical-block',
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
        ),
      );
      final namedVersion = writer.materializeCurrentContent();
      final originalBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single;
      final originalSaveId = originalBlock.saveId!;
      final activeSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('Active Writer Save', oldProjectId, namedVersion)!;
      container.read(writerSaveBindingProvider.notifier).commitState({
        oldProjectId: WriterSaveBinding(
          activeSaveId: activeSaveId,
          materializedBaselineJson: jsonEncode(namedVersion.toJson()),
        ),
      });
      final saveNotifier = container.read(saveSystemProvider.notifier);
      final originalCanonical = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == originalSaveId);
      final canonicalSnapshot =
          originalCanonical.snapshot as HarmonyChordSnapshot;
      final changedCanonical = originalCanonical.copyWith(
        snapshot: HarmonyChordSnapshot(
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
          writerBlock: const WriterBlockSnapshot(
            laneKind: SongLaneKind.harmony,
            chordSymbol: 'D',
            chordQuality: '',
            chordRootPc: 2,
            chordNotes: ['D', 'F#', 'A'],
          ),
          instrumentState: canonicalSnapshot.instrumentState,
        ),
      );
      saveNotifier.state = container
          .read(saveSystemProvider)
          .copyWith(
            saves: [
              for (final save in container.read(saveSystemProvider).saves)
                if (save.id == originalSaveId) changedCanonical else save,
            ],
          );
      writer.addSection(label: 'Unsaved section', lengthBars: 2);

      final result = await writer.createSaveProject(
        name: 'Discard with changed chord',
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
        disposition: WriterProjectCreationDisposition.discard,
      );

      expect(result.succeeded, isTrue);
      final restored = container.read(
        songwriterSessionsProvider,
      )[oldProjectId]!;
      expect(restored.sections.map((section) => section.label), ['Verse']);
      final restoredBlock = restored.sections.single.lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single;
      expect(restoredBlock.saveId, isNot(originalSaveId));
      final saves = container.read(saveSystemProvider).saves;
      expect(
        (saves.singleWhere((save) => save.id == originalSaveId).snapshot
                as HarmonyChordSnapshot)
            .writerBlock
            .chordSymbol,
        'D',
      );
      expect(
        (saves.singleWhere((save) => save.id == restoredBlock.saveId).snapshot
                as HarmonyChordSnapshot)
            .writerBlock
            .chordSymbol,
        'C',
      );
      expect(
        container.read(writerSaveBindingProvider)[oldProjectId]!.activeSaveId,
        activeSaveId,
      );
      container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
      expect(container.read(songwriterProvider).sections.single.label, 'Verse');
      expect(container.read(writerDirtyProvider), isFalse);
    },
  );

  test('Cancel creates no project and preserves current state', () async {
    final (container, oldProjectId, writer) = await makeProject();
    addTearDown(container.dispose);
    writer.addSection(label: 'Keep', lengthBars: 4);
    final beforeFolders = container.read(saveSystemProvider).folders;
    final beforeProject = container.read(songwriterProvider);

    final result = await writer.createSaveProject(
      name: 'Cancelled project',
      defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
      disposition: WriterProjectCreationDisposition.cancel,
    );

    expect(result.status, WriterProjectCreationStatus.cancelled);
    expect(container.read(saveSystemProvider).folders, same(beforeFolders));
    expect(container.read(saveSystemProvider).selectedProjectId, oldProjectId);
    expect(container.read(songwriterProvider), same(beforeProject));
  });
}
