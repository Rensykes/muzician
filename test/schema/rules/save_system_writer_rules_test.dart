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
      id: 'nested-folder',
      name: 'Nested',
      parentId: 'section-folder',
      createdAt: 3,
      order: 0,
    ),
    SaveFolder(
      id: 'other-project',
      name: 'Other',
      createdAt: 4,
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
      folderId: 'section-folder',
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

  test('Writer-origin save rehomes by section; manual origin stays put', () {
    final state = _state();
    final writerSave = state.saves.first.copyWith(origin: SaveOrigin.writer);
    final link = state.writerLinks.single;

    expect(
      writerSaveFolderForLinks(
        state,
        projectId: 'project',
        save: writerSave,
        links: [link],
      ),
      'section-folder',
    );
    expect(
      writerSaveFolderForLinks(
        state,
        projectId: 'project',
        save: writerSave,
        links: const [],
      ),
      'project',
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
}
