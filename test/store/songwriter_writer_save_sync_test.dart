import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/save_system_rules.dart'
    show deserialiseState, saveSystemStorageKey, serialiseSaveSystemState;
import 'package:muzician/schema/rules/songwriter_audio_rules.dart'
    show songwriterSchedulableAudioClips;
import 'package:muzician/schema/rules/fretboard_rules.dart' show tunings;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/app_bootstrap.dart' show hydrateStores;
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:muzician/store/writer_save_sync_store.dart'
    show
        WriterSaveSyncJournal,
        WriterSaveSyncStorage,
        writerSaveBindingsStorageKey,
        writerSaveSyncJournalStorageKey,
        writerSaveSyncProvider,
        writerSaveSyncStorageProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/utils/note_utils.dart'
    show chromaticNotes, noteToPC, toSharp;

class _InterruptedNewStorage implements WriterSaveSyncStorage {
  final values = <String, String>{};
  bool interruptNextSaveSystemWrite = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (interruptNextSaveSystemWrite && key == saveSystemStorageKey) {
      interruptNextSaveSystemWrite = false;
      throw StateError('simulated interruption after journal write');
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

HarmonyChordSnapshot chord(
  String symbol,
  int rootPc, {
  String quality = '',
  List<String>? notes,
  List<String> defaultLyrics = const [],
}) {
  final chordNotes =
      notes ??
      switch ((symbol, quality)) {
        ('C', '') => const ['C', 'E', 'G'],
        ('D', '') => const ['D', 'F#', 'A'],
        ('Am7', 'm7') => const ['A', 'C', 'E', 'G'],
        ('Dm7', 'm7') => const ['D', 'F', 'A', 'C'],
        _ => throw ArgumentError('Unsupported test chord: $symbol$quality'),
      };
  final writerBlock = WriterBlockSnapshot(
    laneKind: SongLaneKind.harmony,
    chordSymbol: symbol,
    chordQuality: quality,
    chordRootPc: rootPc,
    chordNotes: chordNotes,
    defaultLyrics: defaultLyrics,
  );
  final pitchClasses = <int>{
    for (final note in chordNotes) noteToPC[toSharp(note)]!,
  };
  final usedStrings = <int>{};
  final selectedCells = <FretCoordinate>[];
  for (final pitchClass in pitchClasses) {
    final match = <(int, int)>[];
    for (var stringIndex = 0; stringIndex < 6; stringIndex++) {
      if (usedStrings.contains(stringIndex)) continue;
      final openMidi =
          tunings[TuningName.standard]!.strings[stringIndex].midiNote;
      for (var fret = 0; fret <= 12; fret++) {
        if (((openMidi + fret) % 12) == pitchClass) {
          match.add((stringIndex, fret));
          break;
        }
      }
    }
    if (match.isEmpty) throw StateError('No test fretboard realization.');
    final (stringIndex, fret) = match.first;
    usedStrings.add(stringIndex);
    final note = chordNotes.firstWhere(
      (candidate) => noteToPC[toSharp(candidate)] == pitchClass,
    );
    selectedCells.add(
      FretCoordinate(stringIndex: stringIndex, fret: fret, noteName: note),
    );
  }
  return HarmonyChordSnapshot(
    harmonyInstrument: HarmonyLaneInstrument.fretboard,
    writerBlock: writerBlock,
    instrumentState: FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: selectedCells,
      selectedNotes: chordNotes,
      viewMode: FretboardViewMode.exact,
      pendingChord: PendingChord(
        root: chromaticNotes[rootPc % 12],
        quality: quality,
        symbol: symbol,
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ProviderContainer, String, SongwriterNotifier)> makeProject() async {
    final container = ProviderContainer();
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Writer sync',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    await writer.reconcileCurrentProject();
    return (container, projectId, writer);
  }

  test(
    'startup preserves only genuine canonical and fallback conflicts',
    () async {
      const cases = [
        (
          canonical: 'Am7',
          fallback: 'Dm7',
          hasConflict: true,
          hasEmbeddedFallback: true,
        ),
        (
          canonical: 'Dm7',
          fallback: 'Am7',
          hasConflict: true,
          hasEmbeddedFallback: true,
        ),
        (
          canonical: 'Am7',
          fallback: 'Am7',
          hasConflict: false,
          hasEmbeddedFallback: false,
        ),
      ];
      for (final scenario in cases) {
        const projectId = 'conflict-project';
        const sectionFolderId = 'conflict-section-folder';
        const sectionId = 'conflict-section';
        const blockId = 'conflict-block';
        const canonicalSaveId = 'conflict-canonical-save';
        final canonicalRootPc = scenario.canonical == 'Am7' ? 9 : 2;
        final fallbackRootPc = scenario.fallback == 'Am7' ? 9 : 2;
        final canonical = chord(
          scenario.canonical,
          canonicalRootPc,
          quality: 'm7',
          notes: scenario.canonical == 'Am7'
              ? const ['A', 'C', 'E', 'G']
              : const ['D', 'F', 'A', 'C'],
          defaultLyrics: const ['canonical seed'],
        );
        final fallback = chord(
          scenario.fallback,
          fallbackRootPc,
          quality: 'm7',
          notes: scenario.fallback == 'Am7'
              ? const ['A', 'C', 'E', 'G']
              : const ['D', 'F', 'A', 'C'],
          defaultLyrics: const ['fallback seed'],
        );
        final draft = SongwriterProjectSnapshot(
          config: const SongwriterConfig(
            tempo: 120,
            beatsPerBar: 4,
            beatUnit: 4,
          ),
          sections: [
            SongSection(
              id: sectionId,
              label: 'Verse',
              lengthBars: 4,
              order: 0,
              lanes: [
                SongLane(
                  id: 'conflict-harmony',
                  kind: SongLaneKind.harmony,
                  order: 0,
                  blocks: [
                    SongBlock(
                      id: blockId,
                      startBar: 0,
                      spanBars: 1,
                      saveId: canonicalSaveId,
                      embedded: scenario.hasEmbeddedFallback ? fallback : null,
                      chordSymbol: scenario.fallback,
                      chordQuality: 'm7',
                      chordRootPc: fallbackRootPc,
                      chordNotes: scenario.fallback == 'Am7'
                          ? const ['A', 'C', 'E', 'G']
                          : const ['D', 'F', 'A', 'C'],
                      lyrics: scenario.hasEmbeddedFallback
                          ? const []
                          : const ['local placement lyric'],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final saveSystem = SaveSystemState(
          folders: const [
            SaveFolder(
              id: projectId,
              name: 'Conflict project',
              createdAt: 1,
              order: 0,
              kind: SaveFolderKind.project,
            ),
            SaveFolder(
              id: sectionFolderId,
              name: 'Verse',
              parentId: projectId,
              createdAt: 2,
              order: 0,
              writerSectionId: sectionId,
            ),
          ],
          saves: [
            SaveEntry(
              id: canonicalSaveId,
              name: 'Saved chord',
              folderId: sectionFolderId,
              snapshot: canonical,
              createdAt: 1,
              updatedAt: 1,
              order: 0,
              origin: SaveOrigin.writer,
            ),
          ],
          writerLinks: const [
            WriterSaveLink(
              blockId: blockId,
              sectionId: sectionId,
              folderId: sectionFolderId,
              saveId: canonicalSaveId,
              laneKind: SongLaneKind.harmony,
            ),
          ],
          selectedProjectId: projectId,
          hydrated: true,
        );
        SharedPreferences.setMockInitialValues(<String, Object>{
          saveSystemStorageKey: serialiseSaveSystemState(saveSystem),
          songwriterSessionsStorageKey: jsonEncode({projectId: draft.toJson()}),
        });
        final container = ProviderContainer();
        var containerDisposed = false;
        try {
          container.read(songwriterProvider);
          await hydrateStores(container.read);
          final writer = container.read(songwriterProvider.notifier);
          final recoveredBlock = container
              .read(songwriterProvider)
              .sections
              .single
              .lanes
              .single
              .blocks
              .single;
          final firstSaveState = container.read(saveSystemProvider);
          final recoveredSaveId = recoveredBlock.saveId!;
          final originalSave = firstSaveState.saves.singleWhere(
            (save) => save.id == canonicalSaveId,
          );
          final recoveredSave = firstSaveState.saves.singleWhere(
            (save) => save.id == recoveredSaveId,
          );

          if (scenario.hasConflict) {
            expect(recoveredBlock.saveId, isNot(canonicalSaveId));
            expect(recoveredBlock.chordSymbol, scenario.fallback);
            expect(recoveredBlock.embedded?.toJson(), fallback.toJson());
            expect(originalSave.snapshot.toJson(), canonical.toJson());
            expect(recoveredSave.snapshot.toJson(), fallback.toJson());
            expect(recoveredSave.recoveredFromSaveId, canonicalSaveId);
            expect(firstSaveState.writerLinks, hasLength(1));
            expect(firstSaveState.writerLinks.single.saveId, recoveredSaveId);
            expect(
              container.read(writerReconciliationConflictsProvider),
              hasLength(1),
            );
          } else {
            expect(recoveredBlock.saveId, canonicalSaveId);
            expect(recoveredBlock.lyrics, ['local placement lyric']);
            expect(firstSaveState.saves, hasLength(1));
            expect(
              container.read(writerReconciliationConflictsProvider),
              isEmpty,
            );
          }

          await writer.reconcileCurrentProject();
          final secondSaveState = container.read(saveSystemProvider);
          final secondBlock = container
              .read(songwriterProvider)
              .sections
              .single
              .lanes
              .single
              .blocks
              .single;
          expect(
            secondBlock.saveId,
            scenario.hasConflict ? recoveredSaveId : canonicalSaveId,
          );
          expect(
            secondSaveState.saves,
            hasLength(scenario.hasConflict ? 2 : 1),
          );
          expect(secondSaveState.writerLinks, hasLength(1));
          expect(
            container.read(writerReconciliationConflictsProvider),
            hasLength(scenario.hasConflict ? 1 : 0),
            reason: 'an unreviewed recovery notice stays available',
          );
          if (scenario.hasConflict) {
            container.dispose();
            containerDisposed = true;

            final relaunched = ProviderContainer();
            try {
              relaunched.read(songwriterProvider);
              await hydrateStores(relaunched.read);
              expect(
                relaunched.read(writerReconciliationConflictsProvider),
                hasLength(1),
                reason: 'an unreviewed recovery notice survives relaunch',
              );
              final relaunchedWriter = relaunched.read(
                songwriterProvider.notifier,
              );
              await relaunchedWriter.acknowledgeWriterReconciliationConflicts(
                projectId,
              );
              expect(
                relaunched.read(writerReconciliationConflictsProvider),
                isEmpty,
              );
              expect(
                relaunched
                    .read(saveSystemProvider)
                    .saves
                    .singleWhere((save) => save.id == recoveredSaveId)
                    .recoveredFromSaveId,
                isNull,
              );
            } finally {
              relaunched.dispose();
            }

            final afterReview = ProviderContainer();
            try {
              afterReview.read(songwriterProvider);
              await hydrateStores(afterReview.read);
              expect(
                afterReview.read(writerReconciliationConflictsProvider),
                isEmpty,
                reason: 'review clears the durable recovery notice',
              );
            } finally {
              afterReview.dispose();
            }
          }
        } finally {
          if (!containerDisposed) container.dispose();
        }
      }
    },
  );

  test('every Writer block is linked into its section folder', () async {
    final (container, projectId, writer) = await makeProject();
    addTearDown(container.dispose);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
    );
    writer.addHarmonyBlock(
      sectionId: section.id,
      laneId: laneId,
      block: const SongBlock(
        id: 'block-c',
        startBar: 0,
        spanBars: 2,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
      ),
    );

    final saveState = container.read(saveSystemProvider);
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    final link = saveState.writerLinks.single;
    final folder = saveState.folders.singleWhere(
      (folder) => folder.id == link.folderId,
    );
    final save = saveState.saves.singleWhere((save) => save.id == block.saveId);
    expect(link.blockId, block.id);
    expect(link.sectionId, section.id);
    expect(folder.writerSectionId, section.id);
    expect(save.folderId, folder.id);
    expect(save.origin, SaveOrigin.writer);
    expect(
      (save.snapshot as HarmonyChordSnapshot).writerBlock.chordSymbol,
      'C',
    );
    expect(save.folderId, isNot(projectId));
  });

  test(
    'New clears the named-save binding in its recoverable journal',
    () async {
      final storage = _InterruptedNewStorage();
      final container = ProviderContainer(
        overrides: [writerSaveSyncStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final saveSystem = container.read(saveSystemProvider.notifier);
      final projectId = saveSystem.createProject(
        'Writer sync',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      await writer.reconcileCurrentProject();
      final saveId = saveSystem.saveSnapshot(
        'Prior Song',
        projectId,
        writer.materializeCurrentContent(),
      )!;
      await writer.bindNamedSave(saveId);
      container
          .read(writerSaveBindingProvider.notifier)
          .setAlwaysOverwrite(projectId, true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await writer.reconcileCurrentProject();

      final persistedBinding =
          (jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
                  as Map<String, dynamic>)[projectId]
              as Map<String, dynamic>;
      expect(persistedBinding['activeSaveId'], saveId);
      expect(persistedBinding['alwaysOverwrite'], isTrue);

      storage.interruptNextSaveSystemWrite = true;
      await expectLater(writer.newProject(), throwsStateError);

      final stagedJournal = WriterSaveSyncJournal.decode(
        storage.values[writerSaveSyncJournalStorageKey]!,
      )!;
      final stagedBindings =
          jsonDecode(stagedJournal.writerBindingsPayload)
              as Map<String, dynamic>;
      expect(stagedBindings.containsKey(projectId), isFalse);
      expect(container.read(writerSaveBindingProvider)[projectId], isNull);

      final relaunched = ProviderContainer(
        overrides: [writerSaveSyncStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(relaunched.dispose);
      await relaunched
          .read(writerSaveSyncProvider.notifier)
          .replayPendingTransaction();

      final recoveredBindings =
          jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
              as Map<String, dynamic>;
      expect(recoveredBindings.containsKey(projectId), isFalse);
      expect(
        storage.values.containsKey(writerSaveSyncJournalStorageKey),
        isFalse,
      );
    },
  );

  test('all Writer lane kinds reconcile to complete snapshots', () async {
    final (container, _, writer) = await makeProject();
    addTearDown(container.dispose);
    writer.addSection(label: 'All lanes', lengthBars: 8);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    String lane(SongLaneKind kind) =>
        writer.addLane(sectionId: sectionId, kind: kind);

    final harmonyLane = lane(SongLaneKind.harmony);
    writer.insertBlock(
      sectionId: sectionId,
      laneId: harmonyLane,
      block: const SongBlock(
        id: 'harmony-block',
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
      ),
    );

    final saveLane = lane(SongLaneKind.save);
    writer.insertBlock(
      sectionId: sectionId,
      laneId: saveLane,
      block: SongBlock(
        id: 'voicing-block',
        startBar: 0,
        spanBars: 1,
        embedded: PianoRollSnapshot(
          tempo: 120,
          numerator: 4,
          denominator: 4,
          totalMeasures: 1,
          notes: const [],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: const [],
        ),
      ),
    );

    final drumPatternId = writer.addDrumPattern(name: 'Drums');
    final drumLane = lane(SongLaneKind.drum);
    writer.addDrumBlock(
      sectionId: sectionId,
      laneId: drumLane,
      patternId: drumPatternId,
      startBar: 0,
      spanBars: 1,
    );

    final melodyPatternId = writer.addMelodyPattern(name: 'Lead');
    final melodyLane = lane(SongLaneKind.melody);
    writer.addMelodyBlock(
      sectionId: sectionId,
      laneId: melodyLane,
      patternId: melodyPatternId,
      startBar: 0,
      spanBars: 1,
    );

    final strumPatternId = writer.addGuitarStrumPattern(name: 'Strum');
    final strumLane = lane(SongLaneKind.guitarStrum);
    writer.addGuitarStrumBlock(
      sectionId: sectionId,
      laneId: strumLane,
      patternId: strumPatternId,
      startBar: 0,
      spanBars: 1,
    );

    writer.addAudioAsset(
      const AudioAsset(
        id: 'all-lanes-audio',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 2,
        format: 'wav',
        peaks: [],
        sourceLabel: 'clip.wav',
      ),
    );
    final clipId = writer.addAudioClip(
      assetId: 'all-lanes-audio',
      durationMs: 1000,
    );
    final audioLane = lane(SongLaneKind.audio);
    writer.addAudioBlock(
      sectionId: sectionId,
      laneId: audioLane,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 1,
    );

    final project = container.read(songwriterProvider);
    final blocks = project.sections.single.lanes
        .expand((lane) => lane.blocks)
        .toList();
    final saves = container.read(saveSystemProvider).saves;
    final links = container.read(saveSystemProvider).writerLinks;
    expect(blocks, hasLength(SongLaneKind.values.length));
    expect(links, hasLength(blocks.length));
    for (final block in blocks) {
      expect(block.saveId, isNotNull);
      final link = links.singleWhere((link) => link.blockId == block.id);
      final snapshot = saves
          .singleWhere((save) => save.id == link.saveId)
          .snapshot;
      if (link.laneKind == SongLaneKind.save) {
        expect(snapshot, isA<PianoRollSnapshot>());
      } else if (link.laneKind == SongLaneKind.harmony &&
          (snapshot is HarmonyChordSnapshot)) {
        expect(snapshot.writerBlock.laneKind, SongLaneKind.harmony);
      } else {
        expect(snapshot, isA<WriterBlockSnapshot>());
        expect((snapshot as WriterBlockSnapshot).laneKind, link.laneKind);
      }
    }
  });

  test('explicit Use in Writer reuses a root manual Writer save ID', () async {
    final (container, projectId, writer) = await makeProject();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final saveId = saveSystem.saveSnapshot('C idea', projectId, chord('C', 0))!;
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;

    expect(
      writer.insertWriterBlockFromSave(
        saveId: saveId,
        sectionId: sectionId,
        laneKind: SongLaneKind.harmony,
        startBar: 0,
      ),
      isTrue,
    );
    final saveState = container.read(saveSystemProvider);
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .blocks
        .single;
    expect(block.saveId, saveId);
    expect(saveState.writerLinks.single.saveId, saveId);
    expect(
      saveState.saves.singleWhere((save) => save.id == saveId).folderId,
      projectId,
    );
    expect(
      saveState.saves.singleWhere((save) => save.id == saveId).origin,
      SaveOrigin.manual,
    );
  });

  test(
    'Use in Writer copies saved default lyrics into local placements',
    () async {
      final (container, projectId, writer) = await makeProject();
      addTearDown(container.dispose);
      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'C idea',
            projectId,
            chord('C', 0, defaultLyrics: const ['Saved default']),
          )!;
      writer.addSection(label: 'Verse', lengthBars: 4);
      writer.addSection(label: 'Chorus', lengthBars: 4);
      final sections = container.read(songwriterProvider).sections;

      for (final (section, bar) in [(sections[0], 0), (sections[1], 0)]) {
        expect(
          writer.insertWriterBlockFromSave(
            saveId: saveId,
            sectionId: section.id,
            laneKind: SongLaneKind.harmony,
            startBar: bar,
          ),
          isTrue,
        );
      }

      var project = container.read(songwriterProvider);
      final verse = project.sections[0];
      final chorus = project.sections[1];
      final verseLane = verse.lanes.singleWhere(
        (lane) => lane.kind == SongLaneKind.harmony,
      );
      final chorusLane = chorus.lanes.singleWhere(
        (lane) => lane.kind == SongLaneKind.harmony,
      );
      final verseBlock = verseLane.blocks.single;
      final chorusBlock = chorusLane.blocks.single;
      expect(verseBlock.lyrics, ['Saved default']);
      expect(chorusBlock.lyrics, ['Saved default']);

      writer.setBlockLyric(
        sectionId: verse.id,
        laneId: verseLane.id,
        blockId: verseBlock.id,
        verseIndex: 0,
        text: 'Local verse lyric',
      );
      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: verse.id,
          startBar: 0,
          chordSymbol: 'D',
          chordQuality: '',
          chordRootPc: 2,
          chordNotes: const ['D', 'F#', 'A'],
          replaceBlockId: verseBlock.id,
        ),
        isTrue,
      );

      project = container.read(songwriterProvider);
      final updatedVerseBlock = project.sections[0].lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
          .blocks
          .single;
      final unchangedChorusBlock = project.sections[1].lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
          .blocks
          .single;
      expect(updatedVerseBlock.chordSymbol, 'D');
      expect(updatedVerseBlock.lyrics, ['Local verse lyric']);
      expect(updatedVerseBlock.saveId, isNot(saveId));
      expect(unchangedChorusBlock.chordSymbol, 'C');
      expect(unchangedChorusBlock.lyrics, ['Saved default']);
      final updatedSave = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      expect(
        (updatedSave.snapshot as HarmonyChordSnapshot)
            .writerBlock
            .defaultLyrics,
        ['Saved default'],
      );
      expect(
        (container
                    .read(saveSystemProvider)
                    .saves
                    .singleWhere((save) => save.id == updatedVerseBlock.saveId)
                    .snapshot
                as HarmonyChordSnapshot)
            .writerBlock
            .chordSymbol,
        'D',
      );
    },
  );

  test(
    'Make Unique preserves stretched audio state and asset references',
    () async {
      final (container, projectId, writer) = await makeProject();
      addTearDown(container.dispose);
      const sourceAsset = AudioAsset(
        id: 'source-audio',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Take 1',
      );
      const stretchedAsset = AudioAsset(
        id: 'stretched-audio',
        durationMs: 2000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Take 1 (stretched)',
      );
      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'Stretched take',
            projectId,
            WriterBlockSnapshot(
              laneKind: SongLaneKind.audio,
              audioClip: const AudioClip(
                id: 'shared-clip',
                assetId: 'source-audio',
                trimEndMs: 1000,
                fitMode: AudioFitMode.stretch,
                stretchedAssetId: 'stretched-audio',
              ),
              audioAsset: sourceAsset,
              stretchedAudioAsset: stretchedAsset,
            ),
          )!;
      writer.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      expect(
        writer.insertWriterBlockFromSave(
          saveId: saveId,
          sectionId: sectionId,
          laneKind: SongLaneKind.audio,
          startBar: 0,
        ),
        isTrue,
      );
      final before = container.read(songwriterProvider);
      final lane = before.sections.single.lanes.singleWhere(
        (lane) => lane.kind == SongLaneKind.audio,
      );
      final block = lane.blocks.single;
      final oldClipId = block.audioClipId;

      expect(
        writer.makeBlockUnique(
          sectionId: sectionId,
          laneId: lane.id,
          blockId: block.id,
        ),
        isTrue,
      );

      final after = container.read(songwriterProvider);
      final uniqueBlock = after.sections.single.lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.audio)
          .blocks
          .single;
      final uniqueSave = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == uniqueBlock.saveId);
      final uniqueSnapshot = uniqueSave.snapshot as WriterBlockSnapshot;
      expect(uniqueBlock.saveId, isNot(saveId));
      expect(uniqueBlock.audioClipId, isNot(oldClipId));
      expect(uniqueSnapshot.audioClip?.id, uniqueBlock.audioClipId);
      expect(uniqueSnapshot.audioClip?.stretchedAssetId, stretchedAsset.id);
      expect(uniqueSnapshot.stretchedAudioAsset?.id, stretchedAsset.id);
      expect(
        after.audioAssets.map((asset) => asset.id),
        containsAll([sourceAsset.id, stretchedAsset.id]),
      );
      expect(
        songwriterSchedulableAudioClips(after).single.asset.id,
        stretchedAsset.id,
      );
    },
  );

  test(
    'unique audio clips rerender independently and retain saved stretch assets',
    () async {
      final (container, projectId, writer) = await makeProject();
      addTearDown(container.dispose);
      const sourceAsset = AudioAsset(
        id: 'source-audio-two-clips',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Take 2',
      );
      const stretchedAsset = AudioAsset(
        id: 'stretched-audio-two-clips',
        durationMs: 2000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Take 2 (stretched)',
      );
      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'Shared take',
            projectId,
            WriterBlockSnapshot(
              laneKind: SongLaneKind.audio,
              audioClip: const AudioClip(
                id: 'shared-clip-two',
                assetId: 'source-audio-two-clips',
                trimEndMs: 1000,
                fitMode: AudioFitMode.stretch,
                stretchedAssetId: 'stretched-audio-two-clips',
              ),
              audioAsset: sourceAsset,
              stretchedAudioAsset: stretchedAsset,
            ),
          )!;
      writer.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      expect(
        writer.insertWriterBlockFromSave(
          saveId: saveId,
          sectionId: sectionId,
          laneKind: SongLaneKind.audio,
          startBar: 0,
        ),
        isTrue,
      );
      expect(
        writer.insertWriterBlockFromSave(
          saveId: saveId,
          sectionId: sectionId,
          laneKind: SongLaneKind.audio,
          startBar: 2,
        ),
        isTrue,
      );
      final beforeUnique = container.read(songwriterProvider);
      final lane = beforeUnique.sections.single.lanes.singleWhere(
        (lane) => lane.kind == SongLaneKind.audio,
      );
      final blockToMakeUnique = lane.blocks.last;
      expect(
        beforeUnique.audioClips,
        hasLength(1),
        reason: 'the two placements initially share one source clip',
      );
      expect(
        beforeUnique.audioClips.map((clip) => clip.stretchedAssetId),
        everyElement(stretchedAsset.id),
      );
      expect(
        writer.makeBlockUnique(
          sectionId: sectionId,
          laneId: lane.id,
          blockId: blockToMakeUnique.id,
        ),
        isTrue,
      );

      final uniqueState = container.read(songwriterProvider);
      final uniqueBlock = uniqueState.sections.single.lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.audio)
          .blocks
          .last;
      final liveClipIds = uniqueState.audioClips.map((clip) => clip.id).toSet();
      expect(liveClipIds, hasLength(2));
      expect(uniqueState.audioClips, hasLength(2));
      expect(
        uniqueState.audioClips.map((clip) => clip.stretchedAssetId),
        everyElement(stretchedAsset.id),
      );
      expect(uniqueBlock.audioClipId, isNot(blockToMakeUnique.audioClipId));

      // Saving a named version keeps the original stretch metadata reachable
      // after both live clips are rerendered to independent assets.
      container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('Before rerender', projectId, uniqueState);
      final liveClips = [...uniqueState.audioClips];
      const rerenderedUnique = AudioAsset(
        id: 'unique-rerender',
        durationMs: 3000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Unique rerender',
      );
      const rerenderedShared = AudioAsset(
        id: 'shared-rerender',
        durationMs: 3000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Shared rerender',
      );
      writer.setClipStretchedAsset(
        clipId: uniqueBlock.audioClipId!,
        stretchedAsset: rerenderedUnique,
        removeAssetId: stretchedAsset.id,
      );
      expect(
        container.read(songwriterProvider).audioAssets.map((asset) => asset.id),
        contains(stretchedAsset.id),
        reason: 'the shared live clip still points at the previous render',
      );
      writer.setClipStretchedAsset(
        clipId: liveClips
            .firstWhere((clip) => clip.id != uniqueBlock.audioClipId)
            .id,
        stretchedAsset: rerenderedShared,
        removeAssetId: stretchedAsset.id,
      );
      final afterRerender = container.read(songwriterProvider);
      expect(
        afterRerender.audioClips.map((clip) => clip.stretchedAssetId),
        containsAll([rerenderedUnique.id, rerenderedShared.id]),
      );
      expect(
        afterRerender.audioAssets.map((asset) => asset.id),
        contains(stretchedAsset.id),
        reason: 'the saved Song version still references the prior render',
      );
    },
  );

  test(
    'legacy Made Unique fallback migrates to a new canonical save',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      final projectId = saveSystem.createProject(
        'Writer sync',
        const ProjectConfig(),
      )!;
      final oldSaveId = saveSystem.saveSnapshot(
        'Original',
        projectId,
        chord('C', 0),
      )!;
      final legacy = SongwriterProjectSnapshot(
        config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        sections: const [
          SongSection(
            id: 'legacy-section',
            lengthBars: 4,
            order: 0,
            lanes: [
              SongLane(
                id: 'legacy-lane',
                kind: SongLaneKind.harmony,
                order: 0,
                blocks: [
                  SongBlock(
                    id: 'legacy-block',
                    startBar: 0,
                    spanBars: 1,
                    saveId: 'legacy-save',
                    embedded: WriterBlockSnapshot(
                      laneKind: SongLaneKind.harmony,
                      chordSymbol: 'D',
                      chordQuality: 'm',
                      chordRootPc: 2,
                      chordNotes: ['D', 'F', 'A'],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final actualLegacy = SongwriterProjectSnapshot.fromJson({
        ...legacy.toJson(),
        'sections': [
          {
            ...legacy.sections.single.toJson(),
            'lanes': [
              {
                ...legacy.sections.single.lanes.single.toJson(),
                'blocks': [
                  {
                    ...legacy.sections.single.lanes.single.blocks.single
                        .toJson(),
                    'saveId': oldSaveId,
                  },
                ],
              },
            ],
          },
        ],
      });
      container.read(songwriterSessionsProvider.notifier).commitState({
        projectId: actualLegacy,
      });
      saveSystem.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      await writer.reconcileCurrentProject();

      final migrated = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(migrated.saveId, isNot(oldSaveId));
      final saveState = container.read(saveSystemProvider);
      expect(saveState.saves.map((save) => save.id), contains(oldSaveId));
      expect(saveState.writerLinks.single.saveId, migrated.saveId);
      expect(
        (saveState.saves
                    .singleWhere((save) => save.id == migrated.saveId)
                    .snapshot
                as WriterBlockSnapshot)
            .chordSymbol,
        'D',
      );
    },
  );

  test('shared pattern edits refresh each linked Writer save', () async {
    final (container, _, writer) = await makeProject();
    addTearDown(container.dispose);
    final patternId = writer.addMelodyPattern(name: 'Lead', lengthTicks: 16);
    for (var index = 0; index < 2; index++) {
      writer.addSection(label: 'Part $index', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.last;
      final laneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.melody,
      );
      writer.addMelodyBlock(
        sectionId: section.id,
        laneId: laneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 1,
      );
    }
    final before = container.read(saveSystemProvider).writerLinks;
    expect(before, hasLength(2));
    final pattern = container.read(songwriterProvider).melodyPatterns.single;
    writer.updateMelodyPattern(
      pattern.copyWith(
        notes: const [
          NotePatternNote(
            id: 'note-one',
            midiNote: 67,
            startTick: 0,
            durationTicks: 2,
          ),
        ],
      ),
    );
    final saves = container.read(saveSystemProvider).saves;
    for (final link in before) {
      final snapshot =
          saves.singleWhere((save) => save.id == link.saveId).snapshot
              as WriterBlockSnapshot;
      expect(snapshot.melodyPattern?.notes.single.midiNote, 67);
    }
  });

  test(
    'replacing one shared Harmony placement leaves its Save unchanged',
    () async {
      final (container, projectId, writer) = await makeProject();
      addTearDown(container.dispose);
      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('Shared chord', projectId, chord('C', 0))!;
      writer.addSection(label: 'Shared', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final laneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
      );
      for (final bar in [0, 1]) {
        expect(
          writer.insertWriterBlockFromSave(
            saveId: saveId,
            sectionId: sectionId,
            laneKind: SongLaneKind.harmony,
            startBar: bar,
            laneId: laneId,
          ),
          isTrue,
        );
      }
      final initialBlocks = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks;
      final firstPlacement = initialBlocks.singleWhere(
        (block) => block.startBar == 0,
      );
      final secondPlacement = initialBlocks.singleWhere(
        (block) => block.startBar == 1,
      );

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: sectionId,
          startBar: secondPlacement.startBar,
          chordSymbol: 'D',
          chordQuality: '',
          chordRootPc: 2,
          chordNotes: const ['D', 'F#', 'A'],
          replaceBlockId: secondPlacement.id,
        ),
        isTrue,
      );
      final blocks = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks;
      final unchanged = blocks.singleWhere(
        (block) => block.id == firstPlacement.id,
      );
      expect(unchanged.saveId, saveId);
      final updated = blocks.singleWhere(
        (block) => block.id == secondPlacement.id,
      );
      expect(updated.saveId, isNot(saveId));
      expect(
        (updated.embedded as HarmonyChordSnapshot).writerBlock.chordSymbol,
        'D',
      );
      expect(
        (unchanged.embedded as HarmonyChordSnapshot).writerBlock.chordSymbol,
        'C',
      );
      expect(
        (container
                    .read(saveSystemProvider)
                    .saves
                    .singleWhere((save) => save.id == saveId)
                    .snapshot
                as HarmonyChordSnapshot)
            .writerBlock
            .chordSymbol,
        'C',
      );
    },
  );

  test(
    'loading an older named version keeps its unchanged canonical Save',
    () async {
      final (container, _, writer) = await makeProject();
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
          id: 'versioned-chord',
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
      final originalId = originalBlock.saveId!;
      // Use the source block ID to update its canonical content in place.
      writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 0,
        chordSymbol: 'D',
        chordQuality: '',
        chordRootPc: 2,
        chordNotes: const ['D', 'F#', 'A'],
        replaceBlockId: originalBlock.id,
      );
      writer.loadProject(namedVersion);
      expect(container.read(writerReconciliationConflictsProvider), isEmpty);

      final restoredBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single;
      expect(restoredBlock.saveId, originalId);
      final saves = container.read(saveSystemProvider).saves;
      final restored = saves.singleWhere(
        (save) => save.id == restoredBlock.saveId,
      );
      final original = saves.singleWhere((save) => save.id == originalId);
      expect(
        (restored.snapshot as HarmonyChordSnapshot).writerBlock.chordSymbol,
        'C',
      );
      expect(
        (original.snapshot as HarmonyChordSnapshot).writerBlock.chordSymbol,
        'C',
      );
    },
  );

  test(
    'named version load binds a clean baseline, then becomes dirty',
    () async {
      final (container, projectId, writer) = await makeProject();
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
          id: 'versioned-block',
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
        ),
      );
      final savedVersion = writer.materializeCurrentContent();
      final saveSystem = container.read(saveSystemProvider.notifier);
      final versionId = saveSystem.saveSnapshot(
        'First version',
        projectId,
        savedVersion,
      )!;
      await writer.bindNamedSave(versionId);
      expect(container.read(writerDirtyProvider), isFalse);

      final originalBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single;
      writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 0,
        chordSymbol: 'D',
        chordQuality: '',
        chordRootPc: 2,
        chordNotes: const ['D', 'F#', 'A'],
        replaceBlockId: originalBlock.id,
      );
      container
          .read(writerSaveBindingProvider.notifier)
          .setAlwaysOverwrite(projectId, true);
      expect(
        container.read(writerSaveBindingProvider)[projectId]?.alwaysOverwrite,
        isTrue,
      );

      await writer.loadProject(savedVersion, saveId: versionId);

      final binding = container.read(writerSaveBindingProvider)[projectId]!;
      expect(binding.activeSaveId, versionId);
      expect(binding.alwaysOverwrite, isFalse);
      expect(binding.materializedBaselineJson, isNotNull);
      expect(container.read(writerDirtyProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      final persistedBindings =
          (jsonDecode(prefs.getString(writerSaveBindingsStorageKey)!)
                  as Map<String, dynamic>)[projectId]
              as Map<String, dynamic>;
      expect(persistedBindings['activeSaveId'], versionId);
      expect(persistedBindings['alwaysOverwrite'], isFalse);
      expect(persistedBindings['materializedBaselineJson'], isNotNull);
      expect(prefs.containsKey(writerSaveSyncJournalStorageKey), isFalse);
      final persistedSaveState = deserialiseState(
        prefs.getString(saveSystemStorageKey)!,
      )!;
      final restoredBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single;
      expect(
        persistedSaveState.writerLinks.single.saveId,
        restoredBlock.saveId,
      );
      final persistedDrafts =
          jsonDecode(prefs.getString(songwriterSessionsStorageKey)!)
              as Map<String, dynamic>;
      final persistedDraft = SongwriterProjectSnapshot.fromJson(
        persistedDrafts[projectId] as Map<String, dynamic>,
      );
      expect(
        persistedDraft.sections.single.lanes
            .singleWhere((lane) => lane.id == laneId)
            .blocks
            .single
            .saveId,
        restoredBlock.saveId,
      );

      writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 0,
        chordSymbol: 'E',
        chordQuality: '',
        chordRootPc: 4,
        chordNotes: const ['E', 'G#', 'B'],
        replaceBlockId: originalBlock.id,
      );
      expect(container.read(writerDirtyProvider), isTrue);
    },
  );

  test(
    'changing one shared harmony block updates its save and keeps local lyrics',
    () async {
      final (container, _, writer) = await makeProject();
      addTearDown(container.dispose);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final verseId = container.read(songwriterProvider).sections.last.id;
      final verseLaneId = writer.addLane(
        sectionId: verseId,
        kind: SongLaneKind.harmony,
      );
      writer.addHarmonyBlock(
        sectionId: verseId,
        laneId: verseLaneId,
        block: const SongBlock(
          id: 'shared-verse-chord',
          startBar: 1,
          spanBars: 2,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
          lyrics: ['Verse lyric'],
        ),
      );
      final original = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == verseLaneId)
          .blocks
          .single;
      final saveId = original.saveId!;

      writer.addSection(label: 'Chorus', lengthBars: 8);
      final chorusId = container.read(songwriterProvider).sections.last.id;
      final chorusLaneId = writer.addLane(
        sectionId: chorusId,
        kind: SongLaneKind.harmony,
      );
      expect(
        writer.insertWriterBlockFromSave(
          saveId: saveId,
          sectionId: chorusId,
          laneKind: SongLaneKind.harmony,
          startBar: 3,
          spanBars: 2,
          laneId: chorusLaneId,
        ),
        isTrue,
      );
      final chorusBlock = container
          .read(songwriterProvider)
          .sections
          .last
          .lanes
          .singleWhere((lane) => lane.id == chorusLaneId)
          .blocks
          .single;
      writer.setBlockLyric(
        sectionId: chorusId,
        laneId: chorusLaneId,
        blockId: chorusBlock.id,
        verseIndex: 0,
        text: 'Chorus lyric',
      );

      final undoCount = writer.undoCount;
      expect(
        writer.updateHarmonyBlock(
          sectionId: verseId,
          laneId: verseLaneId,
          blockId: original.id,
          content: const SongBlock(
            id: 'editor-result',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'Dm7',
            chordQuality: 'm7',
            chordRootPc: 2,
            chordNotes: ['D', 'F', 'A', 'C'],
            lyrics: ['Updated verse lyric'],
          ),
          lyricVerseIndex: 0,
        ),
        isTrue,
      );

      final updatedSections = container.read(songwriterProvider).sections;
      final updatedVerse = updatedSections
          .singleWhere((section) => section.id == verseId)
          .lanes
          .singleWhere((lane) => lane.id == verseLaneId)
          .blocks
          .single;
      final updatedChorus = updatedSections
          .singleWhere((section) => section.id == chorusId)
          .lanes
          .singleWhere((lane) => lane.id == chorusLaneId)
          .blocks
          .single;
      expect(writer.undoCount, undoCount + 1);
      expect(updatedVerse.id, original.id);
      expect(updatedVerse.saveId, saveId);
      expect(updatedVerse.startBar, 1);
      expect(updatedVerse.spanBars, 2);
      expect(updatedVerse.chordSymbol, 'Dm7');
      expect(updatedVerse.lyrics, ['Updated verse lyric']);
      expect(updatedChorus.saveId, saveId);
      expect(updatedChorus.startBar, 3);
      expect(updatedChorus.spanBars, 2);
      expect(updatedChorus.chordSymbol, 'Dm7');
      expect(updatedChorus.lyrics, ['Chorus lyric']);
      expect(
        (container
                    .read(saveSystemProvider)
                    .saves
                    .singleWhere((save) => save.id == saveId)
                    .snapshot
                as HarmonyChordSnapshot)
            .writerBlock
            .chordSymbol,
        'Dm7',
      );

      expect(writer.undo(), isTrue);
      final undoneSections = container.read(songwriterProvider).sections;
      expect(
        undoneSections
            .singleWhere((section) => section.id == verseId)
            .lanes
            .singleWhere((lane) => lane.id == verseLaneId)
            .blocks
            .single
            .chordSymbol,
        'C',
      );
      expect(
        undoneSections
            .singleWhere((section) => section.id == chorusId)
            .lanes
            .singleWhere((lane) => lane.id == chorusLaneId)
            .blocks
            .single
            .chordSymbol,
        'C',
      );
      expect(
        undoneSections
            .singleWhere((section) => section.id == verseId)
            .lanes
            .singleWhere((lane) => lane.id == verseLaneId)
            .blocks
            .single
            .lyrics,
        ['Verse lyric'],
      );
      expect(
        undoneSections
            .singleWhere((section) => section.id == chorusId)
            .lanes
            .singleWhere((lane) => lane.id == chorusLaneId)
            .blocks
            .single
            .lyrics,
        ['Chorus lyric'],
      );
    },
  );

  test('linked instrument edits refresh every shared block fallback', () async {
    final (container, projectId, writer) = await makeProject();
    addTearDown(container.dispose);
    final canonical = PianoRollSnapshot(
      tempo: 120,
      numerator: 4,
      denominator: 4,
      totalMeasures: 1,
      notes: const [],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 1,
      highlightedNotes: const [],
    );
    final saveId = container
        .read(saveSystemProvider.notifier)
        .saveSnapshot('Voicing', projectId, canonical)!;
    for (var index = 0; index < 2; index++) {
      writer.addSection(label: 'Section $index', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.last.id;
      final laneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.save,
      );
      writer.addSaveBlock(
        sectionId: sectionId,
        laneId: laneId,
        saveId: saveId,
        startBar: 0,
        spanBars: 1,
      );
    }

    final updated = PianoRollSnapshot(
      tempo: canonical.tempo,
      numerator: canonical.numerator,
      denominator: canonical.denominator,
      totalMeasures: canonical.totalMeasures,
      notes: const [
        {'id': 'edited-note', 'midiNote': 67, 'startTick': 0},
      ],
      pitchRangeStart: canonical.pitchRangeStart,
      pitchRangeEnd: canonical.pitchRangeEnd,
      snapTicks: canonical.snapTicks,
      highlightedNotes: canonical.highlightedNotes,
    );
    expect(
      writer.updateLinkedInstrumentSave(saveId: saveId, snapshot: updated),
      isTrue,
    );

    final linkedBlocks = container
        .read(songwriterProvider)
        .sections
        .expand((section) => section.lanes)
        .expand((lane) => lane.blocks)
        .toList();
    expect(linkedBlocks, hasLength(2));
    for (final block in linkedBlocks) {
      expect(block.saveId, saveId);
      expect(
        (block.embedded as PianoRollSnapshot).notes.single['id'],
        'edited-note',
      );
    }
    expect(
      (container
                  .read(saveSystemProvider)
                  .saves
                  .singleWhere((save) => save.id == saveId)
                  .snapshot
              as PianoRollSnapshot)
          .notes
          .single['id'],
      'edited-note',
    );
  });

  test('project config retrofit preserves named Writer versions', () async {
    final (container, projectId, _) = await makeProject();
    addTearDown(container.dispose);
    final namedVersion = const SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 90, beatsPerBar: 3, beatUnit: 4),
    );
    final versionId = container
        .read(saveSystemProvider.notifier)
        .saveSnapshot('Slow version', projectId, namedVersion)!;

    await container
        .read(saveSystemProvider.notifier)
        .applyProjectConfig(
          projectId,
          const ProjectConfig(tempo: 140, beatsPerBar: 4, beatUnit: 4),
          retrofit: true,
        );

    final saved = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((entry) => entry.id == versionId);
    expect(saved.snapshot.toJson(), namedVersion.toJson());
  });

  test('removing one shared audio placement keeps its clip live', () async {
    final (container, _, writer) = await makeProject();
    addTearDown(container.dispose);
    writer.addSection(label: 'Audio', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.audio,
    );
    writer.addAudioAsset(
      const AudioAsset(
        id: 'asset-shared',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 2,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Shared',
      ),
    );
    final clipId = writer.addAudioClip(
      assetId: 'asset-shared',
      durationMs: 1000,
    );
    writer.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 1,
    );
    writer.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 1,
      spanBars: 1,
    );
    final blocks = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks;

    writer.removeAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blocks.first.id,
    );
    expect(
      container.read(songwriterProvider).audioClips.map((clip) => clip.id),
      contains(clipId),
    );
    writer.removeAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blocks.last.id,
    );
    expect(
      container.read(songwriterProvider).audioClips.map((clip) => clip.id),
      isNot(contains(clipId)),
    );
  });
}
