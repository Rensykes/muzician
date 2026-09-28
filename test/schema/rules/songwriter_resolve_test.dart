import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart'
    show writerSaveEntryForBlock;
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/song_from_writer_rules.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  const projectFolders = [
    SaveFolder(
      id: 'project-a',
      name: 'Project A',
      createdAt: 0,
      order: 0,
      kind: SaveFolderKind.project,
    ),
    SaveFolder(
      id: 'f',
      name: 'A saves',
      parentId: 'project-a',
      createdAt: 0,
      order: 0,
    ),
    SaveFolder(
      id: 'project-b',
      name: 'Project B',
      createdAt: 0,
      order: 1,
      kind: SaveFolderKind.project,
    ),
  ];

  FretboardSnapshot snap(List<String> notes) => FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: const [],
    selectedNotes: notes,
    viewMode: FretboardViewMode.exact,
  );

  test('canonical save wins; embedded is used as an offline fallback', () {
    final saves = [
      SaveEntry(
        id: 's1',
        name: 'A',
        folderId: 'f',
        snapshot: snap(['C']),
        createdAt: 0,
        updatedAt: 0,
        order: 0,
      ),
    ];
    final byId = resolveBlockSnapshot(
      const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1'),
      saves,
      projectId: 'project-a',
      folders: projectFolders,
    );
    expect(byId, isNotNull);
    expect(byId!.selectedNotes, ['C']);

    final embedded = snap(['E']);
    final byEmbed = resolveBlockSnapshot(
      SongBlock(
        id: 'b',
        startBar: 0,
        spanBars: 1,
        saveId: 's1',
        embedded: embedded,
      ),
      saves,
      projectId: 'project-a',
      folders: projectFolders,
    );
    expect(byEmbed, saves.single.snapshot);

    final offline = resolveBlockSnapshot(
      SongBlock(
        id: 'b',
        startBar: 0,
        spanBars: 1,
        saveId: 'missing',
        embedded: embedded,
      ),
      saves,
      projectId: 'project-a',
      folders: projectFolders,
    );
    expect(offline, embedded);

    expect(
      resolveBlockSnapshot(
        const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 'missing'),
        saves,
        projectId: 'project-a',
        folders: projectFolders,
      ),
      isNull,
    );
  });

  test('foreign project save references stay broken and silent', () {
    final foreignSave = SaveEntry(
      id: 'save-b',
      name: 'Project B voicing',
      folderId: 'project-b',
      snapshot: PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C4'),
        ],
        selectedNotes: const ['C'],
        viewMode: PianoViewMode.exact,
      ),
      createdAt: 0,
      updatedAt: 0,
      order: 0,
    );
    const block = SongBlock(
      id: 'stale-block',
      startBar: 0,
      spanBars: 1,
      saveId: 'save-b',
    );
    final saveState = SaveSystemState(
      folders: projectFolders,
      saves: [foreignSave],
      hydrated: true,
      selectedProjectId: 'project-a',
    );
    final writer = SongwriterProjectSnapshot(
      config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: const [
        SongSection(
          id: 'section-a',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'save-lane',
              kind: SongLaneKind.save,
              order: 0,
              blocks: [block],
            ),
          ],
        ),
      ],
    );

    expect(
      resolveBlockSnapshot(
        block,
        saveState.saves,
        projectId: saveState.selectedProjectId,
        folders: saveState.folders,
      ),
      isNull,
    );
    expect(writerSaveEntryForBlock(saveState, block), isNull);
    expect(
      flattenPlaybackEvents(
        writer,
        saveState.saves,
        projectId: saveState.selectedProjectId,
        folders: saveState.folders,
      ),
      isEmpty,
    );

    final song = songFromSongwriter(
      writer,
      saveState.saves,
      projectId: saveState.selectedProjectId,
      folders: saveState.folders,
    );
    expect(
      song.tracks.where((track) => track.type == SongTrackType.note),
      isEmpty,
    );
    expect(song.notePatterns, isEmpty);
  });
}
