import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_lane_row.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('renders a clip tile for an audio block', (tester) async {
    const section = SongSection(
      id: 'sec',
      lengthBars: 4,
      order: 0,
      lanes: [
        SongLane(
          id: 'ln',
          kind: SongLaneKind.audio,
          order: 0,
          blocks: [
            SongBlock(id: 'bl', startBar: 0, spanBars: 2, audioClipId: 'c1'),
          ],
        ),
      ],
    );
    const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000);
    const asset = AudioAsset(
      id: 'a1',
      durationMs: 4000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [10, 20, 30],
      sourceLabel: 'Recording',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioLaneRow(
              section: section,
              lane: section.lanes.single,
              instanceIndex: 0,
              clipsById: const {'c1': clip},
              assetsById: const {'a1': asset},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sheetAudioTile_c1')), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
  });

  testWidgets('renders an empty tappable cell when no block', (tester) async {
    const section = SongSection(
      id: 'sec',
      lengthBars: 2,
      order: 0,
      lanes: [SongLane(id: 'ln', kind: SongLaneKind.audio, order: 0)],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioLaneRow(
              section: section,
              lane: section.lanes.single,
              instanceIndex: 0,
              clipsById: const {},
              assetsById: const {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sheetAudioEmpty_ln_0')), findsOneWidget);
  });

  testWidgets('audio block displays and edits its canonical save name', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.audio,
      label: 'Audio',
    );
    writer.addAudioAsset(
      const AudioAsset(
        id: 'audio-asset',
        durationMs: 4000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30],
        sourceLabel: 'Recording',
      ),
    );
    final clipId = writer.addAudioClip(
      assetId: 'audio-asset',
      durationMs: 4000,
    );
    writer.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 2,
    );
    await writer.reconcileCurrentProject();

    var section = container.read(songwriterProvider).sections.single;
    var lane = section.lanes.singleWhere(
      (candidate) => candidate.kind == SongLaneKind.audio,
    );
    final blockId = lane.blocks.single.id;
    final saveId = lane.blocks.single.saveId!;
    final saveName = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((save) => save.id == saveId)
        .name;

    Future<void> pumpRow() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SongwriterAudioLaneRow(
                section: section,
                lane: lane,
                instanceIndex: 0,
                clipsById: {
                  for (final clip
                      in container.read(songwriterProvider).audioClips)
                    clip.id: clip,
                },
                assetsById: {
                  for (final asset
                      in container.read(songwriterProvider).audioAssets)
                    asset.id: asset,
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpRow();
    expect(find.text('Recording'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Actions for $saveName',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('writerBlockActions_$blockId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerRename_$blockId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('writerBlockNameField')),
      'Intro',
    );
    await tester.tap(find.byKey(const Key('writerBlockNameSave')));
    await tester.pumpAndSettle();

    expect(find.text('Intro'), findsOneWidget);
    expect(
      container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId)
          .name,
      'Intro',
    );

    await tester.tap(find.byKey(Key('writerBlockActions_$blockId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerMakeUnique_$blockId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('writerBlockNameField')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('writerBlockNameField')),
      'Intro unique',
    );
    await tester.tap(find.byKey(const Key('writerBlockNameSave')));
    await tester.pumpAndSettle();

    section = container.read(songwriterProvider).sections.single;
    lane = section.lanes.singleWhere(
      (candidate) => candidate.kind == SongLaneKind.audio,
    );
    final uniqueSaveId = lane.blocks.single.saveId!;
    expect(uniqueSaveId, isNot(saveId));
    expect(
      container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == uniqueSaveId)
          .name,
      'Intro unique',
    );
  });

  testWidgets('audio block exposes feedback for a missing linked save', (
    tester,
  ) async {
    const section = SongSection(
      id: 'sec',
      lengthBars: 2,
      order: 0,
      lanes: [
        SongLane(
          id: 'audio-lane',
          kind: SongLaneKind.audio,
          order: 0,
          blocks: [
            SongBlock(
              id: 'broken-audio',
              startBar: 0,
              spanBars: 1,
              audioClipId: 'clip',
              saveId: 'missing-save',
            ),
          ],
        ),
      ],
    );
    const clip = AudioClip(id: 'clip', assetId: 'asset', trimEndMs: 4000);
    const asset = AudioAsset(
      id: 'asset',
      durationMs: 4000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [10, 20, 30],
      sourceLabel: 'Recording',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioLaneRow(
              section: section,
              lane: section.lanes.single,
              instanceIndex: 0,
              clipsById: const {'clip': clip},
              assetsById: const {'asset': asset},
            ),
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Audio block Recording, broken save reference',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('writerBrokenReference_broken-audio')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Broken Reference'), findsOneWidget);
    expect(find.text('This block references a deleted save.'), findsOneWidget);
  });
}
