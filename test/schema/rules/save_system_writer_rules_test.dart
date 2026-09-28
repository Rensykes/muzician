import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/save_system_rules.dart';

FretboardSnapshot _snapshot() => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [],
  selectedNotes: const ['A', 'C', 'E'],
  viewMode: FretboardViewMode.exact,
);

SaveSystemState _state() => SaveSystemState(
  folders: const [
    SaveFolder(
      id: 'project',
      name: 'Project',
      createdAt: 1,
      order: 0,
      kind: SaveFolderKind.project,
      projectConfig: ProjectConfig(),
    ),
    SaveFolder(
      id: 'section-folder',
      name: 'Verse',
      parentId: 'project',
      createdAt: 2,
      order: 0,
      writerSectionId: 'section',
    ),
    SaveFolder(
      id: 'harmony-folder',
      name: 'Harmony',
      parentId: 'section-folder',
      createdAt: 3,
      order: 0,
      writerSectionId: 'section',
      writerLaneKind: SongLaneKind.harmony,
    ),
    SaveFolder(
      id: 'nested-folder',
      name: 'Nested',
      parentId: 'harmony-folder',
      createdAt: 4,
      order: 0,
    ),
    SaveFolder(
      id: 'other-project',
      name: 'Other',
      createdAt: 5,
      order: 1,
      kind: SaveFolderKind.project,
      projectConfig: ProjectConfig(),
    ),
  ],
  saves: [
    SaveEntry(
      id: 'save',
      name: 'Idea',
      folderId: 'project',
      snapshot: _snapshot(),
      createdAt: 1,
      updatedAt: 1,
      order: 0,
      origin: SaveOrigin.manual,
    ),
    SaveEntry(
      id: 'foreign-save',
      name: 'Foreign',
      folderId: 'other-project',
      snapshot: _snapshot(),
      createdAt: 1,
      updatedAt: 1,
      order: 0,
    ),
  ],
  writerLinks: const [
    WriterSaveLink(
      blockId: 'block',
      sectionId: 'section',
      folderId: 'harmony-folder',
      saveId: 'save',
      laneKind: SongLaneKind.harmony,
    ),
  ],
  hydrated: true,
);

void main() {
  test('v3 serialization round-trips Writer section and link metadata', () {
    final state = _state();
    final raw = serialiseState(
      folders: state.folders,
      saves: state.saves,
      writerLinks: state.writerLinks,
      selectedProjectId: 'project',
    );

    final restored = deserialiseState(raw)!;
    expect(restored.writerLinks.single.blockId, 'block');
    expect(restored.writerLinks.single.laneKind, SongLaneKind.harmony);
    expect(
      restored.folders
          .where((folder) => folder.id == 'section-folder')
          .single
          .writerSectionId,
      'section',
    );
    expect(
      restored.saves.where((save) => save.id == 'save').single.origin,
      SaveOrigin.manual,
    );
  });

  test('old v3 JSON defaults Writer fields and origin safely', () {
    final raw = jsonEncode({
      'folders': [
        {
          'id': 'project',
          'name': 'Project',
          'parentId': null,
          'createdAt': 1,
          'order': 0,
          'kind': 'project',
        },
      ],
      'saves': [
        {
          'id': 'save',
          'name': 'Idea',
          'folderId': 'project',
          'snapshot': _snapshot().toJson(),
          'createdAt': 1,
          'updatedAt': 1,
          'order': 0,
        },
      ],
      'selectedProjectId': 'project',
    });

    final restored = deserialiseState(raw)!;
    expect(restored.writerLinks, isEmpty);
    expect(restored.folders.single.writerSectionId, isNull);
    expect(restored.saves.single.origin, SaveOrigin.manual);
  });

  test('link and folder helpers stay scoped to the selected project', () {
    final state = _state();

    expect(resolveSaveInProject(state, 'project', 'save')?.id, 'save');
    expect(resolveSaveInProject(state, 'project', 'foreign-save'), isNull);
    expect(
      getWriterSectionFolder(state, 'project', 'section')?.id,
      'section-folder',
    );
    final laneFolder = state.folders.singleWhere(
      (folder) => folder.id == 'harmony-folder',
    );
    expect(
      isWriterLaneCategoryFolder(
        state.folders,
        laneFolder,
        projectId: 'project',
        sectionId: 'section',
        laneKind: SongLaneKind.harmony,
      ),
      isTrue,
    );
    expect(
      getWriterLaneCategoryFolder(
        state,
        projectId: 'project',
        sectionId: 'section',
        laneKind: SongLaneKind.harmony,
      )?.id,
      'harmony-folder',
    );
    expect(getWriterLinksForSection(state, 'project', 'section'), hasLength(1));
    expect(getWriterLinksForSave(state, 'project', 'save'), hasLength(1));
    expect(
      isWriterManagedFolderOrDescendant(state.folders, 'nested-folder'),
      isTrue,
    );
    expect(
      isWriterManagedFolderOrDescendant(state.folders, 'other-project'),
      isFalse,
    );
  });

  test('lane category factory reuses IDs and assigns a stable kind order', () {
    final state = _state();
    final sectionFolder = getWriterSectionFolder(state, 'project', 'section')!;
    final existing = getOrCreateWriterLaneFolder(
      state,
      projectId: 'project',
      sectionId: 'section',
      laneKind: SongLaneKind.harmony,
      sectionFolder: sectionFolder,
    );
    expect(existing.id, 'harmony-folder');

    final rootOnly = state.copyWith(
      folders: state.folders
          .where(
            (folder) =>
                folder.id != 'harmony-folder' && folder.id != 'nested-folder',
          )
          .toList(),
    );
    final created = getOrCreateWriterLaneFolder(
      rootOnly,
      projectId: 'project',
      sectionId: 'section',
      laneKind: SongLaneKind.harmony,
      sectionFolder: sectionFolder,
    );
    expect(created.parentId, sectionFolder.id);
    expect(created.writerSectionId, 'section');
    expect(created.writerLaneKind, SongLaneKind.harmony);
    expect(created.order, SongLaneKind.harmony.index);
  });

  test('legacy Made Unique is distinct from a linked fallback cache', () {
    final state = _state();
    final detached = SongBlock(
      id: 'block',
      startBar: 0,
      spanBars: 1,
      saveId: 'save',
      embedded: _snapshot(),
    );
    expect(isLegacyDetachedWriterBlock(detached, const []), isTrue);
    expect(isLegacyDetachedWriterBlock(detached, state.writerLinks), isFalse);
    expect(
      isLegacyDetachedWriterBlock(
        detached.copyWith(clearSaveId: true),
        const [],
      ),
      isFalse,
    );
  });

  test('Writer saves retain their physical folder while it still exists', () {
    final state = _state();
    final writerSave = state.saves.first.copyWith(
      folderId: 'harmony-folder',
      origin: SaveOrigin.writer,
    );
    final link = state.writerLinks.single;

    expect(
      writerSaveFolderForLinks(
        state,
        projectId: 'project',
        save: writerSave,
        links: [link],
      ),
      'harmony-folder',
    );
    expect(
      writerSaveFolderForLinks(
        state,
        projectId: 'project',
        save: writerSave,
        links: [link],
      ),
      'harmony-folder',
    );
    expect(
      writerSaveFolderForLinks(
        state,
        projectId: 'project',
        save: state.saves.first,
        links: [link],
      ),
      'project',
    );
  });

  test(
    'deleted Writer owner rehomes by section order, then to project root',
    () {
      final base = _state();
      const earlySection = SaveFolder(
        id: 'early-section-folder',
        name: 'Verse',
        parentId: 'project',
        createdAt: 10,
        order: 0,
        writerSectionId: 'early-section',
      );
      const earlyHarmony = SaveFolder(
        id: 'early-harmony-folder',
        name: 'Harmony',
        parentId: 'early-section-folder',
        createdAt: 11,
        order: 0,
        writerSectionId: 'early-section',
        writerLaneKind: SongLaneKind.harmony,
      );
      final writerSave = base.saves.first.copyWith(
        folderId: 'harmony-folder',
        origin: SaveOrigin.writer,
      );
      final ownerRemoved = base.copyWith(
        folders: [...base.folders, earlySection, earlyHarmony]
            .where(
              (folder) =>
                  folder.id != 'harmony-folder' && folder.id != 'nested-folder',
            )
            .toList(),
        saves: [writerSave],
      );
      const earlyLink = WriterSaveLink(
        blockId: 'early-block',
        sectionId: 'early-section',
        folderId: 'early-harmony-folder',
        saveId: 'save',
        laneKind: SongLaneKind.harmony,
      );

      expect(
        writerSaveFolderForLinks(
          ownerRemoved,
          projectId: 'project',
          save: writerSave,
          links: [earlyLink],
        ),
        'early-harmony-folder',
      );
      expect(
        writerSaveFolderForLinks(
          ownerRemoved,
          projectId: 'project',
          save: writerSave,
          links: const [],
        ),
        'project',
      );
    },
  );
}
