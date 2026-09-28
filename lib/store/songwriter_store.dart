/// Songwriter project Riverpod store with per-project session auto-save.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails, ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../models/song_project.dart';
import '../models/songwriter.dart';
import '../schema/rules/save_system_rules.dart';
import '../schema/rules/songwriter_rules.dart';
import '../schema/rules/songwriter_segment_rules.dart';
import '../schema/rules/songwriter_slice_rules.dart';
import '../schema/rules/songwriter_third_above_rules.dart';
import '../schema/rules/songwriter_voicing_rules.dart';
import '../utils/note_utils.dart';
import 'save_system_store.dart';
import 'songwriter_sessions_store.dart';
import 'writer_save_binding_store.dart';
import 'writer_save_sync_store.dart';
import 'project_snapshot_history.dart';

SongwriterProjectSnapshot _emptyProject() => const SongwriterProjectSnapshot(
  config: SongwriterConfig(
    tempo: 120,
    beatsPerBar: 4,
    beatUnit: 4,
    keyRoot: 0,
    keyScaleName: 'major',
  ),
  sections: [],
);

class WriterReconciliationConflict {
  const WriterReconciliationConflict({
    required this.projectId,
    required this.blockId,
    required this.canonicalSaveId,
    required this.recoveredSaveId,
  });

  final String projectId;
  final String blockId;
  final String canonicalSaveId;
  final String recoveredSaveId;
}

final writerReconciliationConflictsProvider =
    StateProvider<List<WriterReconciliationConflict>>((ref) => const []);

String _writerReconciliationConflictKey(
  WriterReconciliationConflict conflict,
) => '${conflict.projectId}/${conflict.blockId}/${conflict.canonicalSaveId}';

class SongwriterNotifier extends Notifier<SongwriterProjectSnapshot> {
  bool _hydrating = false;
  bool _suppressHistory = false;
  SongwriterProjectSnapshot? _trackedState;
  final Map<String, SaveFolder> _removedWriterFolders = {};
  final ProjectSnapshotHistory<SongwriterProjectSnapshot> _history =
      ProjectSnapshotHistory();

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  int get undoCount => _history.undoCount;
  int get redoCount => _history.redoCount;
  int get historyRevision => _history.revision;
  ValueListenable<int> get historyRevisionListenable =>
      _history.revisionListenable;

  @override
  SongwriterProjectSnapshot build() {
    ref.onDispose(_history.dispose);
    // React to project selection changes.
    ref.listen<String?>(saveSystemProvider.select((s) => s.selectedProjectId), (
      prev,
      next,
    ) {
      // Persist outgoing immediately.
      if (prev != null && prev != next) {
        final projectStillExists = ref
            .read(saveSystemProvider)
            .folders
            .any((folder) => folder.id == prev);
        if (projectStillExists) {
          ref.read(songwriterSessionsProvider.notifier).put(prev, state);
        }
      }
      if (prev != next) _history.clear();
      if (next == null) {
        _hydrating = true;
        state = _emptyProject();
        _hydrating = false;
        return;
      }
      _hydrating = true;
      final session = ref.read(songwriterSessionsProvider.notifier).get(next);
      if (session != null) {
        state = session;
      } else {
        state = _defaultFor(next);
      }
      _hydrating = false;
      unawaited(reconcileCurrentProject().catchError(_reportWriterSyncFailure));
    });

    // Cold start: the listener above only fires on project *changes*. When a
    // project is already selected (restored during hydrate) before this provider
    // is first read, seed directly from its saved working draft — otherwise the
    // Writer would open blank until the user switched projects.
    final id = ref.read(saveSystemProvider).selectedProjectId;
    if (id == null) {
      final empty = _emptyProject();
      _trackedState = empty;
      return empty;
    }
    final session = ref.read(songwriterSessionsProvider.notifier).get(id);
    final initial = session ?? _defaultFor(id);
    _trackedState = initial;
    return initial;
  }

  @override
  set state(SongwriterProjectSnapshot value) {
    final previous = _trackedState;
    if (!_hydrating && !_suppressHistory && previous != null) {
      _history.recordChange(previous, value);
    }
    _trackedState = value;
    super.state = value;
    _schedulePersist(value);
  }

  SongwriterProjectSnapshot _defaultFor(String projectId) {
    final folder = ref
        .read(saveSystemProvider)
        .folders
        .firstWhere((f) => f.id == projectId);
    final cfg = folder.projectConfig ?? const ProjectConfig();
    return SongwriterProjectSnapshot(
      name: folder.name,
      config: SongwriterConfig(
        tempo: cfg.tempo,
        beatsPerBar: cfg.beatsPerBar,
        beatUnit: cfg.beatUnit,
        keyRoot: cfg.keyRootPc,
        keyScaleName: cfg.keyScaleName,
      ),
    );
  }

  void _schedulePersist(SongwriterProjectSnapshot project) {
    if (_hydrating) return;
    final id = ref.read(saveSystemProvider).selectedProjectId;
    if (id != null) {
      ref.read(songwriterSessionsProvider.notifier).put(id, project);
    }
  }

  void _set(
    SongwriterProjectSnapshot next, {
    Map<String, String> saveNames = const {},
  }) {
    _commitWriterStateInBackground(next, saveNames: saveNames);
  }

  void _commitWriterStateInBackground(
    SongwriterProjectSnapshot next, {
    Map<String, String> saveNames = const {},
    Map<String, SaveEntry> adoptSaves = const {},
    String? bindSaveId,
    bool resetBinding = false,
  }) {
    unawaited(
      _commitWriterState(
        next,
        saveNames: saveNames,
        adoptSaves: adoptSaves,
        bindSaveId: bindSaveId,
        resetBinding: resetBinding,
      ).catchError(_reportWriterSyncFailure),
    );
  }

  void _reportWriterSyncFailure(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'songwriter store',
        context: ErrorDescription('while syncing Writer changes'),
      ),
    );
  }

  void _applyState(SongwriterProjectSnapshot next, {bool persistDraft = true}) {
    final previous = _trackedState;
    if (!_hydrating && !_suppressHistory && previous != null) {
      _history.recordChange(previous, next);
    }
    _trackedState = next;
    super.state = next;
    if (persistDraft) _schedulePersist(next);
  }

  Future<void> _commitWriterState(
    SongwriterProjectSnapshot next, {
    Map<String, String> saveNames = const {},
    Map<String, SaveEntry> adoptSaves = const {},
    String? bindSaveId,
    String? rebaselineSaveId,
    bool resetBinding = false,
    bool detectReconciliationConflicts = false,
    bool clearReconciliationMarkers = false,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    final saveNotifier = ref.read(saveSystemProvider.notifier);
    final previous = _trackedState ?? state;
    if (projectId == null) {
      _applyState(next);
      return Future<void>.value();
    }

    final prepared = _prepareWriterStructure(
      projectId,
      previous,
      next,
      saveNames: saveNames,
      adoptSaves: adoptSaves,
      detectReconciliationConflicts: detectReconciliationConflicts,
      clearReconciliationMarkers: clearReconciliationMarkers,
    );
    if (prepared == null) {
      // A missing or unselected project leaves Writer usable in memory. Once a
      // valid project is selected, the next reconciliation will create links.
      _applyState(next);
      return Future<void>.value();
    }
    final writerProject = _jsonEqual(prepared.project.toJson(), next.toJson())
        ? next
        : prepared.project;

    final sessions = ref.read(songwriterSessionsProvider.notifier);
    final bindings = ref.read(writerSaveBindingProvider.notifier);
    final nextDrafts = {...sessions.state, projectId: writerProject};
    final nextBindings = {...bindings.state};
    if (resetBinding) {
      nextBindings.remove(projectId);
      if (bindSaveId != null) {
        nextBindings[projectId] = WriterSaveBinding(
          activeSaveId: bindSaveId,
          materializedBaselineJson: jsonEncode(writerProject.toJson()),
        );
      }
    } else if (rebaselineSaveId != null) {
      final binding = nextBindings[projectId];
      if (binding != null) {
        nextBindings[projectId] = binding.copyWith(
          activeSaveId: rebaselineSaveId,
          materializedBaselineJson: jsonEncode(writerProject.toJson()),
        );
      }
    }
    final sync = ref.read(writerSaveSyncProvider.notifier);
    return sync.commitWriterTransaction(
      projectId: projectId,
      saveSystemState: prepared.saveSystem,
      writerDrafts: nextDrafts,
      writerBindings: {
        for (final entry in nextBindings.entries)
          entry.key: entry.value.toJson(),
      },
      commitMemory: () {
        saveNotifier.commitWriterStructure(
          projectId,
          prepared.saveSystem,
          persist: false,
        );
        sessions.commitState(nextDrafts);
        bindings.commitState(nextBindings);
        _applyState(writerProject, persistDraft: false);
        if (detectReconciliationConflicts && prepared.conflicts.isNotEmpty) {
          final conflictState = ref.read(writerReconciliationConflictsProvider);
          final existingConflictKeys = conflictState
              .map(_writerReconciliationConflictKey)
              .toSet();
          ref.read(writerReconciliationConflictsProvider.notifier).state = [
            ...conflictState,
            for (final conflict in prepared.conflicts)
              if (existingConflictKeys.add(
                _writerReconciliationConflictKey(conflict),
              ))
                conflict,
          ];
        }
      },
    );
  }

  ({
    SongwriterProjectSnapshot project,
    SaveSystemState saveSystem,
    List<WriterReconciliationConflict> conflicts,
  })?
  _prepareWriterStructure(
    String projectId,
    SongwriterProjectSnapshot previous,
    SongwriterProjectSnapshot proposed, {
    Map<String, String> saveNames = const {},
    Map<String, SaveEntry> adoptSaves = const {},
    bool detectReconciliationConflicts = false,
    bool clearReconciliationMarkers = false,
  }) {
    final saveState = ref.read(saveSystemProvider);
    final projectFolder = saveState.folders
        .where((folder) => folder.id == projectId)
        .firstOrNull;
    if (projectFolder == null ||
        projectFolder.kind != SaveFolderKind.project ||
        saveState.selectedProjectId != projectId) {
      return null;
    }

    final sectionIds = proposed.sections.map((section) => section.id).toSet();
    for (final removed in previous.sections.where(
      (section) => !sectionIds.contains(section.id),
    )) {
      final folder = getWriterSectionFolder(saveState, projectId, removed.id);
      if (folder != null) {
        _removedWriterFolders['$projectId/${removed.id}'] = folder;
      }
    }
    var folders = saveState.folders.where((folder) {
      if (!isFolderInProject(saveState.folders, folder.id, projectId)) {
        return true;
      }
      return folder.writerSectionId == null ||
          sectionIds.contains(folder.writerSectionId);
    }).toList();
    var candidate = saveState.copyWith(folders: folders);
    for (final section in proposed.sections) {
      final displayName = section.label?.trim().isNotEmpty == true
          ? section.label!.trim()
          : 'Section ${section.order + 1}';
      final existingFolder = getWriterSectionFolder(
        candidate,
        projectId,
        section.id,
      );
      final folder =
          existingFolder?.copyWith(name: displayName, order: section.order) ??
          _removedWriterFolders['$projectId/${section.id}']?.copyWith(
            name: displayName,
            order: section.order,
          ) ??
          createWriterSectionFolder(
            candidate,
            projectId: projectId,
            sectionId: section.id,
            name: displayName,
            order: section.order,
          );
      folders = [
        ...folders.where((existing) => existing.id != folder.id),
        folder,
      ];
      candidate = candidate.copyWith(folders: folders);
    }

    final existingSaves = {for (final save in saveState.saves) save.id: save};
    final nextSaves = {...existingSaves, ...adoptSaves};
    if (clearReconciliationMarkers) {
      for (final save in nextSaves.values.toList()) {
        if (save.recoveredFromSaveId != null &&
            isFolderInProject(saveState.folders, save.folderId, projectId)) {
          nextSaves[save.id] = save.copyWith(clearRecoveredFromSaveId: true);
        }
      }
    }
    final links = <WriterSaveLink>[];
    final canonicalByBlockId = <String, InstrumentSnapshot>{};
    final blockSaveIds = <String, String>{};
    final conflicts = <WriterReconciliationConflict>[];
    final recoveredConflictSaves = <String, SaveEntry>{};
    final previousBlocks = _blocksById(previous);

    for (final section in proposed.sections) {
      final sectionFolder = getWriterSectionFolder(
        candidate,
        projectId,
        section.id,
      );
      if (sectionFolder == null) continue;
      for (final lane in section.lanes) {
        for (final block in lane.blocks) {
          final blockId = block.id;
          final oldLocation = previousBlocks[blockId];
          final oldBlock = oldLocation?.$3;
          final oldLane = oldLocation?.$2;
          final oldContent = oldBlock == null || oldLane == null
              ? null
              : _contentSnapshot(previous, oldLane, oldBlock);
          var liveContent = _contentSnapshot(proposed, lane, block);

          final legacyDetached =
              oldBlock != null &&
              isLegacyDetachedWriterBlock(block, saveState.writerLinks) &&
              !adoptSaves.containsKey(block.saveId);
          final linkedSaveId = block.saveId;
          final originalSave = linkedSaveId == null
              ? null
              : resolveSaveInProject(saveState, projectId, linkedSaveId);
          final existing = originalSave == null
              ? adoptSaves[linkedSaveId]
              : (nextSaves[originalSave.id] ?? originalSave);
          final reconciliationFallback = detectReconciliationConflicts
              ? _normalizeReconciliationFallback(
                  lane,
                  block,
                  liveContent,
                  existing?.snapshot,
                )
              : null;
          final hasReconciliationConflict =
              detectReconciliationConflicts &&
              oldBlock != null &&
              existing != null &&
              reconciliationFallback != null &&
              !legacyDetached &&
              !_jsonEqual(
                existing.snapshot.toJson(),
                reconciliationFallback.toJson(),
              );
          if (liveContent is WriterBlockSnapshot &&
              existing?.snapshot is WriterBlockSnapshot) {
            liveContent = _copyWriterBlockSnapshot(
              liveContent,
              defaultLyrics:
                  (existing!.snapshot as WriterBlockSnapshot).defaultLyrics,
            );
          }
          final contentUnchanged =
              oldBlock != null &&
              _jsonEqual(oldContent?.toJson(), liveContent?.toJson());
          final isContentChanged = oldBlock != null && !contentUnchanged;
          InstrumentSnapshot? snapshot;
          SaveEntry? save = existing;
          final conflictKey = hasReconciliationConflict
              ? '$linkedSaveId/${jsonEncode(reconciliationFallback.toJson())}'
              : null;

          if (legacyDetached) {
            save = null;
            snapshot = block.embedded;
          } else if (hasReconciliationConflict) {
            final recovered = conflictKey == null
                ? null
                : recoveredConflictSaves[conflictKey];
            save = recovered;
            snapshot = recovered?.snapshot ?? reconciliationFallback;
          } else if (existing != null) {
            if (isContentChanged) {
              snapshot = liveContent ?? block.embedded;
              if (snapshot != null) {
                save = existing.copyWith(
                  snapshot: snapshot,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );
              } else {
                snapshot = existing.snapshot;
              }
            } else {
              snapshot = existing.snapshot;
            }
          } else {
            // A legacy or cross-project reference is never adopted. Recover it
            // as a new Writer save only when its retained fallback is usable.
            snapshot = liveContent ?? block.embedded;
            if (block.saveId != null && snapshot == null) continue;
          }

          if (save == null && snapshot == null) continue;
          if (save == null) {
            snapshot ??= liveContent ?? block.embedded;
            if (snapshot == null) continue;
            final name =
                saveNames[blockId] ??
                (hasReconciliationConflict ? existing.name : null) ??
                _defaultWriterSaveName(lane, block, snapshot);
            final siblings = getSavesInFolder(
              nextSaves.values.toList(),
              sectionFolder.id,
            );
            save = createWriterSaveEntry(
              name,
              sectionFolder.id,
              snapshot,
              siblings.length,
            );
            if (hasReconciliationConflict) {
              save = save.copyWith(recoveredFromSaveId: existing.id);
            }
            if (conflictKey != null) {
              recoveredConflictSaves[conflictKey] = save;
            }
          } else {
            final explicitName = saveNames[blockId]?.trim();
            if (explicitName != null &&
                explicitName.isNotEmpty &&
                isValidSaveName(explicitName)) {
              save = save.copyWith(
                name: explicitName,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              );
            }
          }
          nextSaves[save.id] = save;
          blockSaveIds[blockId] = save.id;
          canonicalByBlockId[blockId] = save.snapshot;
          final preservedSaveId = hasReconciliationConflict
              ? existing.id
              : existing?.recoveredFromSaveId;
          if (preservedSaveId != null) {
            conflicts.add(
              WriterReconciliationConflict(
                projectId: projectId,
                blockId: blockId,
                canonicalSaveId: preservedSaveId,
                recoveredSaveId: save.id,
              ),
            );
          }
          links.add(
            WriterSaveLink(
              blockId: blockId,
              sectionId: section.id,
              folderId: sectionFolder.id,
              saveId: save.id,
              laneKind: lane.kind,
            ),
          );
        }
      }
    }

    final reportedRecoverySaveIds = conflicts
        .map((conflict) => conflict.recoveredSaveId)
        .toSet();
    for (final save in nextSaves.values) {
      final originalSaveId = save.recoveredFromSaveId;
      if (originalSaveId == null ||
          reportedRecoverySaveIds.contains(save.id) ||
          !isFolderInProject(candidate.folders, save.folderId, projectId)) {
        continue;
      }
      conflicts.add(
        WriterReconciliationConflict(
          projectId: projectId,
          blockId: save.id,
          canonicalSaveId: originalSaveId,
          recoveredSaveId: save.id,
        ),
      );
    }

    // Multiple placements can intentionally share one canonical save. Resolve
    // every fallback after all placements have had a chance to update that
    // save, so an earlier unchanged placement cannot retain stale content.
    for (final entry in blockSaveIds.entries) {
      final finalSave = nextSaves[entry.value];
      if (finalSave != null) canonicalByBlockId[entry.key] = finalSave.snapshot;
    }

    final reconciled = _applyCanonicalSnapshots(
      proposed,
      blockSaveIds,
      canonicalByBlockId,
    );
    candidate = candidate.copyWith(
      saves: nextSaves.values.toList(),
      writerLinks: [
        ...saveState.writerLinks.where(
          (link) =>
              !isFolderInProject(saveState.folders, link.folderId, projectId),
        ),
        ...links,
      ],
    );
    final preparedSaveState = ref
        .read(saveSystemProvider.notifier)
        .buildWriterStructure(projectId, candidate);
    if (preparedSaveState == null) return null;
    return (
      project: reconciled,
      saveSystem: preparedSaveState,
      conflicts: conflicts,
    );
  }

  InstrumentSnapshot? _normalizeReconciliationFallback(
    SongLane lane,
    SongBlock block,
    InstrumentSnapshot? fallback,
    InstrumentSnapshot? canonical,
  ) {
    if (fallback is! WriterBlockSnapshot ||
        canonical is! WriterBlockSnapshot ||
        (block.embedded is WriterBlockSnapshot &&
            (block.embedded as WriterBlockSnapshot).laneKind == lane.kind)) {
      return fallback;
    }

    // Without an embedded cache, block.lyrics are placement-local. Preserve
    // the canonical default seed in the comparison while comparing all
    // musical content retained by the Writer fields and pattern references.
    return _copyWriterBlockSnapshot(
      fallback,
      defaultLyrics: canonical.defaultLyrics,
    );
  }

  Map<String, (SongSection, SongLane, SongBlock)> _blocksById(
    SongwriterProjectSnapshot project,
  ) => {
    for (final section in project.sections)
      for (final lane in section.lanes)
        for (final block in lane.blocks) block.id: (section, lane, block),
  };

  InstrumentSnapshot? _contentSnapshot(
    SongwriterProjectSnapshot project,
    SongLane lane,
    SongBlock block,
  ) => lane.kind == SongLaneKind.save
      ? block.embedded
      : writerBlockSnapshotFor(project, lane, block);

  bool _jsonEqual(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  String _defaultWriterSaveName(
    SongLane lane,
    SongBlock block,
    InstrumentSnapshot snapshot,
  ) {
    if (snapshot is WriterBlockSnapshot) {
      if (snapshot.chordSymbol?.trim().isNotEmpty == true) {
        return snapshot.chordSymbol!.trim();
      }
      final patternName =
          snapshot.drumPattern?.name ??
          snapshot.melodyPattern?.name ??
          snapshot.guitarStrumPattern?.name;
      if (patternName != null && patternName.trim().isNotEmpty) {
        return patternName.trim();
      }
      final sourceLabel = snapshot.audioAsset?.sourceLabel;
      if (sourceLabel != null && sourceLabel.trim().isNotEmpty) {
        return sourceLabel.trim();
      }
      if (snapshot.isSilent) return 'Lyrics';
      return laneKindFallbackLabel(lane.kind);
    }
    return block.chordSymbol?.trim().isNotEmpty == true
        ? block.chordSymbol!.trim()
        : 'Voicing';
  }

  SongwriterProjectSnapshot _applyCanonicalSnapshots(
    SongwriterProjectSnapshot project,
    Map<String, String> saveIds,
    Map<String, InstrumentSnapshot> snapshots,
  ) {
    var drumPatterns = [...project.drumPatterns];
    var melodyPatterns = [...project.melodyPatterns];
    var guitarPatterns = [...project.guitarStrumPatterns];
    var audioClips = [...project.audioClips];
    var audioAssets = [...project.audioAssets];

    void upsert<T>(
      List<T> values,
      String id,
      T value,
      String Function(T) idOf,
    ) {
      final index = values.indexWhere((item) => idOf(item) == id);
      if (index < 0) {
        values.add(value);
      } else {
        values[index] = value;
      }
    }

    SongBlock apply(SongLane lane, SongBlock block) {
      final saveId = saveIds[block.id];
      final snapshot = snapshots[block.id];
      if (snapshot == null) return block;
      var updated = block.copyWith(
        saveId: saveId,
        embedded: snapshot,
        clearSaveId: saveId == null,
      );
      if (snapshot is! WriterBlockSnapshot) return updated;
      if (snapshot.laneKind == SongLaneKind.harmony) {
        final hasChord =
            snapshot.chordSymbol != null ||
            snapshot.chordQuality != null ||
            snapshot.chordRootPc != null ||
            snapshot.chordNotes.isNotEmpty;
        updated = hasChord
            ? updated.copyWith(
                chordSymbol: snapshot.chordSymbol,
                chordQuality: snapshot.chordQuality,
                chordRootPc: snapshot.chordRootPc,
                chordNotes: snapshot.chordNotes,
                romanNumeral: snapshot.romanNumeral,
                clearRomanNumeral: snapshot.romanNumeral == null,
                isSilent: snapshot.isSilent,
              )
            : updated.copyWith(
                clearChordData: true,
                isSilent: snapshot.isSilent,
              );
      } else if (snapshot.drumPattern case final pattern?) {
        upsert(drumPatterns, pattern.id, pattern, (item) => item.id);
        updated = updated.copyWith(
          patternId: pattern.id,
          clearAudioClipId: true,
        );
      } else if (snapshot.melodyPattern case final pattern?) {
        upsert(melodyPatterns, pattern.id, pattern, (item) => item.id);
        updated = updated.copyWith(
          patternId: pattern.id,
          clearAudioClipId: true,
        );
      } else if (snapshot.guitarStrumPattern case final pattern?) {
        upsert(guitarPatterns, pattern.id, pattern, (item) => item.id);
        updated = updated.copyWith(
          patternId: pattern.id,
          clearAudioClipId: true,
        );
      } else if (snapshot.audioClip case final clip?) {
        upsert(audioClips, clip.id, clip, (item) => item.id);
        if (snapshot.audioAsset case final asset?) {
          upsert(audioAssets, asset.id, asset, (item) => item.id);
        }
        if (snapshot.stretchedAudioAsset case final asset?) {
          upsert(audioAssets, asset.id, asset, (item) => item.id);
        }
        updated = updated.copyWith(audioClipId: clip.id, clearPatternId: true);
      }
      return updated;
    }

    return project.copyWith(
      sections: [
        for (final section in project.sections)
          section.copyWith(
            lanes: [
              for (final lane in section.lanes)
                lane.copyWith(
                  blocks: [for (final block in lane.blocks) apply(lane, block)],
                ),
            ],
          ),
      ],
      drumPatterns: drumPatterns,
      melodyPatterns: melodyPatterns,
      guitarStrumPatterns: guitarPatterns,
      audioClips: audioClips,
      audioAssets: audioAssets,
    );
  }

  /// Groups several project mutations into one undo step. Pair this with
  /// [endHistoryGroup] at the end of a drag, slider gesture, or compound edit.
  void beginHistoryGroup() => _history.beginGroup();

  void endHistoryGroup() => _history.endGroup(state);

  T runHistoryGroup<T>(T Function() edit) {
    beginHistoryGroup();
    try {
      return edit();
    } finally {
      endHistoryGroup();
    }
  }

  bool undo({int? ifRevision}) {
    if (ifRevision != null && !_history.isCurrentRevision(ifRevision)) {
      return false;
    }
    final previous = _history.takeUndo(state);
    if (previous == null) return false;
    _history.restore(() => _commitWriterStateInBackground(previous));
    return true;
  }

  bool redo() {
    final next = _history.takeRedo(state);
    if (next == null) return false;
    _history.restore(() => _commitWriterStateInBackground(next));
    return true;
  }

  Future<void> newProject() async {
    _history.clear();
    final id = ref.read(saveSystemProvider).selectedProjectId;
    await _commitWriterStateWithoutHistory(
      _emptyProject(),
      resetBinding: id != null,
    );
    if (id != null) {
      ref.read(songwriterSessionsProvider.notifier).remove(id);
    }
  }

  // ── config ──
  void setKey(int? root, String? scaleName) {
    final cfg = (root == null)
        ? state.config.copyWith(clearKey: true)
        : state.config.copyWith(keyRoot: root, keyScaleName: scaleName);
    runHistoryGroup(() {
      _set(state.copyWith(config: cfg));
      _recomputeNumerals();
    });
  }

  void setTempo(int tempo) =>
      _set(state.copyWith(config: state.config.copyWith(tempo: tempo)));

  void setMeter({required int beatsPerBar, required int beatUnit}) => _set(
    state.copyWith(
      config: state.config.copyWith(
        beatsPerBar: beatsPerBar,
        beatUnit: beatUnit,
      ),
    ),
  );

  /// Synchronizes the project-owned config fields without recording a user
  /// edit. A changed master config invalidates snapshots from the old config;
  /// an equal sync leaves the current history intact.
  void syncProjectConfig({
    required int tempo,
    required int beatsPerBar,
    required int beatUnit,
    required int? keyRoot,
    required String? keyScaleName,
  }) {
    final current = state.config;
    final nextConfig = SongwriterConfig(
      tempo: tempo,
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
      keyRoot: keyRoot,
      keyScaleName: keyRoot == null ? null : keyScaleName,
    );
    if (current.tempo == nextConfig.tempo &&
        current.beatsPerBar == nextConfig.beatsPerBar &&
        current.beatUnit == nextConfig.beatUnit &&
        current.keyRoot == nextConfig.keyRoot &&
        current.keyScaleName == nextConfig.keyScaleName) {
      return;
    }

    _history.clear();
    _suppressHistory = true;
    try {
      _commitWriterStateInBackground(state.copyWith(config: nextConfig));
    } finally {
      _suppressHistory = false;
    }
  }

  // ── sections ──
  void addSection({String? label, required int lengthBars}) {
    final section = makeSection(
      label: label,
      lengthBars: lengthBars,
      order: state.sections.length,
    );
    _set(state.copyWith(sections: [...state.sections, section]));
  }

  /// True when [next] is element-wise `identical` to [prev] (same order, same
  /// instances). Used to skip a `_set` when a map callback returned unchanged
  /// instances — avoids a wasted Riverpod rebuild + persist write.
  static bool _sameElements<T>(List<T> prev, List<T> next) {
    if (prev.length != next.length) return false;
    for (var i = 0; i < prev.length; i++) {
      if (!identical(prev[i], next[i])) return false;
    }
    return true;
  }

  void _replaceSection(
    String sectionId,
    SongSection Function(SongSection) f, {
    Map<String, String> saveNames = const {},
  }) {
    final sections = state.sections
        .map((s) => s.id == sectionId ? f(s) : s)
        .toList();
    if (_sameElements(state.sections, sections)) return; // nothing changed
    _set(state.copyWith(sections: sections), saveNames: saveNames);
  }

  void renameSection(String sectionId, String? label) => _replaceSection(
    sectionId,
    (s) =>
        label == null ? s.copyWith(clearLabel: true) : s.copyWith(label: label),
  );

  void setSectionLength(String sectionId, int lengthBars) => _replaceSection(
    sectionId,
    (s) => s.copyWith(lengthBars: lengthBars < 1 ? 1 : lengthBars),
  );

  void setSectionRepeat(String sectionId, int repeat) {
    final clamped = repeat < 1 ? 1 : repeat;
    _replaceSection(sectionId, (s) {
      final lanes = s.lanes.map((l) {
        if (l.kind != SongLaneKind.harmony) return l;
        final blocks = l.blocks.map((b) {
          if (b.lyrics.length >= clamped) return b;
          final padded = [
            ...b.lyrics,
            for (var i = b.lyrics.length; i < clamped; i++) '',
          ];
          return b.copyWith(lyrics: padded);
        }).toList();
        return l.copyWith(blocks: blocks);
      }).toList();
      return s.copyWith(repeat: clamped, lanes: lanes);
    });
  }

  /// Sets the free-text lyrics for one verse (repeat instance) of a section.
  /// Grows the list to reach [verseIndex] and trims trailing empties, mirroring
  /// [setBlockLyric].
  void setSectionLyric({
    required String sectionId,
    required int verseIndex,
    required String? text,
  }) {
    if (verseIndex < 0) return;
    _replaceSection(sectionId, (s) {
      final list = [...s.lyrics];
      while (list.length <= verseIndex) {
        list.add('');
      }
      list[verseIndex] = text ?? '';
      while (list.isNotEmpty && list.last.isEmpty) {
        list.removeLast();
      }
      return s.copyWith(lyrics: list);
    });
  }

  void removeSection(String sectionId) => _set(
    state.copyWith(
      sections: state.sections.where((s) => s.id != sectionId).toList(),
    ),
  );

  void reorderSections(int oldIndex, int newIndex) {
    final list = [...state.sections];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(target.clamp(0, list.length), moved);
    _set(
      state.copyWith(
        sections: [
          for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
        ],
      ),
    );
  }

  void reorderLanes(String sectionId, int oldIndex, int newIndex) {
    _replaceSection(sectionId, (s) {
      final list = [...s.lanes];
      if (oldIndex < 0 || oldIndex >= list.length) return s;
      var target = newIndex;
      if (target > oldIndex) target -= 1;
      final moved = list.removeAt(oldIndex);
      list.insert(target.clamp(0, list.length), moved);
      return s.copyWith(
        lanes: [
          for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
        ],
      );
    });
  }

  // ── lanes ──
  String addLane({
    required String sectionId,
    required SongLaneKind kind,
    String? label,
  }) {
    final lane = makeLane(kind: kind, label: label, order: 0);
    _replaceSection(sectionId, (s) {
      final positioned = lane.copyWith(order: s.lanes.length);
      return s.copyWith(lanes: [...s.lanes, positioned]);
    });
    return lane.id;
  }

  void _replaceLane(
    String sectionId,
    String laneId,
    SongLane Function(SongLane) f, {
    Map<String, String> saveNames = const {},
  }) {
    _replaceSection(sectionId, (s) {
      final lanes = s.lanes.map((l) => l.id == laneId ? f(l) : l).toList();
      if (_sameElements(s.lanes, lanes)) return s; // lane unchanged
      return s.copyWith(lanes: lanes);
    }, saveNames: saveNames);
  }

  void setLaneRepeat({
    required String sectionId,
    required String laneId,
    required int repeat,
  }) => _replaceLane(
    sectionId,
    laneId,
    (l) => l.copyWith(repeat: repeat < 1 ? 1 : repeat),
  );

  /// Sets or clears a lane's display label. Empty / whitespace-only labels
  /// clear to null so kind fallbacks ("Harmony", "Beat", …) apply again.
  void renameLane({
    required String sectionId,
    required String laneId,
    required String? label,
  }) {
    final trimmed = label?.trim();
    _replaceLane(
      sectionId,
      laneId,
      (l) => trimmed == null || trimmed.isEmpty
          ? l.copyWith(clearLabel: true)
          : l.copyWith(label: trimmed),
    );
  }

  void setLaneVolume({
    required String sectionId,
    required String laneId,
    required double volume,
  }) => _replaceLane(
    sectionId,
    laneId,
    (l) => l.copyWith(volume: volume.clamp(0.0, 1.0)),
  );

  void setLanePan({
    required String sectionId,
    required String laneId,
    required double pan,
  }) => _replaceLane(
    sectionId,
    laneId,
    (l) => l.copyWith(pan: pan.clamp(-1.0, 1.0)),
  );

  void setLaneMuted({
    required String sectionId,
    required String laneId,
    required bool muted,
  }) => _replaceLane(sectionId, laneId, (l) => l.copyWith(muted: muted));

  /// Selects the harmony lane used by save voicings or guitar strums.
  /// A null selection follows the section's primary harmony lane.
  void setLaneAnchorLane({
    required String sectionId,
    required String laneId,
    required String? harmonyLaneId,
  }) => _replaceLane(
    sectionId,
    laneId,
    (lane) => harmonyLaneId == null
        ? lane.copyWith(clearAnchorLaneId: true)
        : lane.copyWith(anchorLaneId: harmonyLaneId),
  );

  void removeLane({required String sectionId, required String laneId}) =>
      _replaceSection(
        sectionId,
        (s) => s.copyWith(lanes: s.lanes.where((l) => l.id != laneId).toList()),
      );

  // ── blocks ──
  void addSaveBlock({
    required String sectionId,
    required String laneId,
    String? saveId,
    required int startBar,
    required int spanBars,
    InstrumentSnapshot? snapshot,
    String? saveName,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (snapshot == null &&
        projectId != null &&
        resolveSaveInProject(
              ref.read(saveSystemProvider),
              projectId,
              saveId ?? '',
            ) ==
            null) {
      return;
    }
    final candidate = snapshot == null
        ? makeSaveBlock(
            saveId: saveId ?? '',
            startBar: startBar,
            spanBars: spanBars,
          )
        : makeEmbeddedSaveBlock(
            snapshot: snapshot,
            startBar: startBar,
            spanBars: spanBars,
          );
    _replaceLane(
      sectionId,
      laneId,
      (l) {
        if (blocksOverlap(l.blocks, candidate)) return l; // ignore overlaps
        return l.copyWith(blocks: [...l.blocks, candidate]);
      },
      saveNames: {
        if (saveName != null && saveName.trim().isNotEmpty)
          candidate.id: saveName,
      },
    );
  }

  void addHarmonyBlock({
    required String sectionId,
    required String laneId,
    required SongBlock block, // build via makeHarmonyBlock at the call site
    String? saveName,
  }) {
    _replaceLane(
      sectionId,
      laneId,
      (l) {
        if (blocksOverlap(l.blocks, block)) return l;
        return l.copyWith(blocks: [...l.blocks, block]);
      },
      saveNames: {
        if (saveName != null && saveName.trim().isNotEmpty) block.id: saveName,
      },
    );
  }

  /// Updates a harmony block's musical content in place. Keeping the source
  /// block ID and save link lets Writer reconciliation update the canonical
  /// save and every placement that shares it.
  bool updateHarmonyBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
    required SongBlock content,
    int? lyricVerseIndex,
  }) {
    var updated = false;
    _replaceLane(sectionId, laneId, (lane) {
      if (lane.kind != SongLaneKind.harmony ||
          !lane.blocks.any((block) => block.id == blockId)) {
        return lane;
      }
      return lane.copyWith(
        blocks: lane.blocks.map((block) {
          if (block.id != blockId) return block;
          updated = true;
          final lyrics = [...block.lyrics];
          if (lyricVerseIndex != null) {
            while (lyrics.length <= lyricVerseIndex) {
              lyrics.add('');
            }
            lyrics[lyricVerseIndex] = content.lyrics.firstOrNull ?? '';
            while (lyrics.isNotEmpty && lyrics.last.isEmpty) {
              lyrics.removeLast();
            }
          }
          return block.copyWith(
            chordSymbol: content.chordSymbol,
            chordQuality: content.chordQuality,
            chordRootPc: content.chordRootPc,
            chordNotes: content.chordNotes,
            romanNumeral: content.romanNumeral,
            clearRomanNumeral: content.romanNumeral == null,
            clearChordData: content.isSilent,
            lyrics: lyrics,
            isSilent: content.isSilent,
          );
        }).toList(),
      );
    });
    return updated;
  }

  /// Inserts an instrument selection without creating a library save.
  /// Passing [snapshot] creates an embedded save-lane block; otherwise the
  /// chord fields create a harmony-lane block. When [replaceBlockId] is set,
  /// the stored source block is replaced in place so repeated placements keep
  /// their source ID, start, span, and lane repeat pattern.
  bool insertInstrumentSelectionAtBar({
    required String sectionId,
    required int startBar,
    InstrumentSnapshot? snapshot,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String> chordNotes = const [],
    String? replaceBlockId,
    String? saveName,
    String? reuseSaveId,
  }) {
    final sectionIndex = state.sections.indexWhere((s) => s.id == sectionId);
    if (sectionIndex < 0 || startBar < 0) return false;
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (reuseSaveId != null) {
      if (projectId == null ||
          (saveName != null && !isValidSaveName(saveName.trim()))) {
        return false;
      }
      final canonical = resolveSaveInProject(
        ref.read(saveSystemProvider),
        projectId,
        reuseSaveId,
      )?.snapshot;
      if (canonical == null || canonical is WriterBlockSnapshot) {
        return false;
      }
      // The selected save is authoritative. A snapshot captured before the
      // naming dialog may have gone stale while the dialog was open.
      snapshot = canonical;
    }
    final isHarmony = snapshot == null;
    if (isHarmony &&
        (chordSymbol == null || chordQuality == null || chordRootPc == null)) {
      return false;
    }
    final section = state.sections[sectionIndex];
    final laneKind = isHarmony ? SongLaneKind.harmony : SongLaneKind.save;
    final laneIndex = section.lanes.indexWhere((lane) => lane.kind == laneKind);
    final existingLane = laneIndex < 0 ? null : section.lanes[laneIndex];
    final existingBlocks = existingLane?.blocks ?? const <SongBlock>[];
    final sourceIndex = replaceBlockId == null
        ? -1
        : existingBlocks.indexWhere((block) => block.id == replaceBlockId);
    if (replaceBlockId != null && sourceIndex < 0) return false;

    final source = sourceIndex < 0 ? null : existingBlocks[sourceIndex];
    final candidate = source == null
        ? isHarmony
              ? makeHarmonyBlock(
                  startBar: startBar,
                  spanBars: 1,
                  chordSymbol: chordSymbol!,
                  chordQuality: chordQuality!,
                  chordRootPc: chordRootPc!,
                  chordNotes: chordNotes,
                )
              : reuseSaveId == null
              ? makeEmbeddedSaveBlock(
                  snapshot: snapshot,
                  startBar: startBar,
                  spanBars: 1,
                )
              : SongBlock(
                  id: generateId(),
                  startBar: startBar,
                  spanBars: 1,
                  saveId: reuseSaveId,
                  embedded: snapshot,
                )
        : source.copyWith(
            saveId: reuseSaveId,
            embedded: snapshot,
            chordSymbol: chordSymbol,
            chordQuality: chordQuality,
            chordRootPc: chordRootPc,
            chordNotes: chordNotes,
            clearEmbedded: isHarmony,
            clearRomanNumeral: true,
            clearChordData: !isHarmony,
            isSilent: false,
          );
    final retainedBlocks = [
      for (var index = 0; index < existingBlocks.length; index++)
        if (index != sourceIndex) existingBlocks[index],
    ];
    if (blocksOverlap(retainedBlocks, candidate)) return false;

    final lane =
        existingLane ?? makeLane(kind: laneKind, order: section.lanes.length);
    final updatedBlocks = source == null
        ? [...existingBlocks, candidate]
        : [
            for (var index = 0; index < existingBlocks.length; index++)
              index == sourceIndex ? candidate : existingBlocks[index],
          ];
    final updatedLane = lane.copyWith(blocks: updatedBlocks);
    final lanes = [...section.lanes];
    if (laneIndex < 0) {
      lanes.add(updatedLane);
    } else {
      lanes[laneIndex] = updatedLane;
    }
    final sections = [...state.sections];
    sections[sectionIndex] = section.copyWith(lanes: lanes);
    _set(
      state.copyWith(sections: sections),
      saveNames: {
        if (saveName != null && saveName.trim().isNotEmpty)
          candidate.id: saveName,
      },
    );
    return true;
  }

  /// Returns the selected project's canonical save for a linked Writer block.
  SaveEntry? canonicalSaveForBlock(String blockId) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return null;
    final saveState = ref.read(saveSystemProvider);
    final block = _blocksById(state)[blockId]?.$3;
    final saveId = block?.saveId;
    if (saveId != null) {
      final direct = resolveSaveInProject(saveState, projectId, saveId);
      if (direct != null) return direct;
    }
    for (final link in saveState.writerLinks) {
      if (link.blockId != blockId ||
          !isFolderInProject(saveState.folders, link.folderId, projectId)) {
        continue;
      }
      final linked = resolveSaveInProject(saveState, projectId, link.saveId);
      if (linked != null) return linked;
    }
    return null;
  }

  void setBlockLyric({
    required String sectionId,
    required String laneId,
    required String blockId,
    required int verseIndex,
    required String? text,
  }) {
    if (verseIndex < 0) return;
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(
        blocks: l.blocks.map((b) {
          if (b.id != blockId) return b;
          final list = [...b.lyrics];
          while (list.length <= verseIndex) {
            list.add('');
          }
          list[verseIndex] = text ?? '';
          while (list.isNotEmpty && list.last.isEmpty) {
            list.removeLast();
          }
          return b.copyWith(lyrics: list);
        }).toList(),
      ),
    );
  }

  void addSilentBlock({
    required String sectionId,
    required String laneId,
    required int startBar,
    required int spanBars,
    int verseCount = 1,
  }) {
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(
        blocks: [
          ...l.blocks,
          makeSilentBlock(
            startBar: startBar,
            spanBars: spanBars,
            verseCount: verseCount,
          ),
        ],
      ),
    );
  }

  void removeBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
  }) {
    _replaceLane(
      sectionId,
      laneId,
      (l) =>
          l.copyWith(blocks: l.blocks.where((b) => b.id != blockId).toList()),
    );
  }

  // ── inserters (for undo of deletes) ──
  void insertSection(SongSection section, int index) {
    final list = [...state.sections];
    final i = index.clamp(0, list.length);
    list.insert(i, section);
    _set(
      state.copyWith(
        sections: [
          for (var k = 0; k < list.length; k++) list[k].copyWith(order: k),
        ],
      ),
    );
  }

  void insertLane({
    required String sectionId,
    required SongLane lane,
    required int index,
  }) {
    _replaceSection(sectionId, (s) {
      final list = [...s.lanes];
      final i = index.clamp(0, list.length);
      list.insert(i, lane);
      return s.copyWith(
        lanes: [
          for (var k = 0; k < list.length; k++) list[k].copyWith(order: k),
        ],
      );
    });
  }

  void insertBlock({
    required String sectionId,
    required String laneId,
    required SongBlock block,
  }) {
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(blocks: [...l.blocks, block]),
    );
  }

  String addDrumPattern({String name = 'Pattern'}) {
    final pattern = makeDrumPattern(name: name);
    _set(state.copyWith(drumPatterns: [...state.drumPatterns, pattern]));
    return pattern.id;
  }

  SongBlock _clearPatternContent(SongBlock block, SongLaneKind laneKind) {
    final fallback = block.embedded;
    return block.copyWith(
      clearPatternId: true,
      embedded: WriterBlockSnapshot(
        laneKind: laneKind,
        defaultLyrics:
            fallback is WriterBlockSnapshot && fallback.laneKind == laneKind
            ? fallback.defaultLyrics
            : block.lyrics,
      ),
    );
  }

  void updateDrumPattern(DrumPattern updated) {
    _set(
      state.copyWith(
        drumPatterns: state.drumPatterns
            .map((p) => p.id == updated.id ? updated : p)
            .toList(),
      ),
    );
  }

  void removeDrumPattern(String patternId) {
    final patterns = state.drumPatterns
        .where((p) => p.id != patternId)
        .toList();
    final sections = state.sections.map((s) {
      final lanes = s.lanes.map((l) {
        if (l.kind != SongLaneKind.drum) return l;
        final blocks = l.blocks
            .map(
              (b) => b.patternId == patternId
                  ? _clearPatternContent(b, SongLaneKind.drum)
                  : b,
            )
            .toList();
        return l.copyWith(blocks: blocks);
      }).toList();
      return s.copyWith(lanes: lanes);
    }).toList();
    _set(state.copyWith(drumPatterns: patterns, sections: sections));
  }

  void addDrumBlock({
    required String sectionId,
    required String laneId,
    required String patternId,
    required int startBar,
    required int spanBars,
  }) {
    _set(
      state.copyWith(
        sections: state.sections.map((s) {
          if (s.id != sectionId) return s;
          return s.copyWith(
            lanes: s.lanes.map((l) {
              if (l.id != laneId || l.kind != SongLaneKind.drum) return l;
              return l.copyWith(
                blocks: [
                  ...l.blocks,
                  makeDrumBlock(
                    patternId: patternId,
                    startBar: startBar,
                    spanBars: spanBars,
                  ),
                ],
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  String addMelodyPattern({String name = 'Melody', int? lengthTicks}) {
    final pattern = makeMelodyPattern(
      name: name,
      lengthTicks: lengthTicks ?? state.config.measureTicks,
    );
    _set(state.copyWith(melodyPatterns: [...state.melodyPatterns, pattern]));
    return pattern.id;
  }

  void updateMelodyPattern(NotePattern updated) {
    _set(
      state.copyWith(
        melodyPatterns: state.melodyPatterns
            .map((pattern) => pattern.id == updated.id ? updated : pattern)
            .toList(),
      ),
    );
  }

  void removeMelodyPattern(String patternId) {
    final sections = state.sections.map((section) {
      final lanes = section.lanes.map((lane) {
        if (lane.kind != SongLaneKind.melody) return lane;
        return lane.copyWith(
          blocks: lane.blocks
              .map(
                (block) => block.patternId == patternId
                    ? _clearPatternContent(block, SongLaneKind.melody)
                    : block,
              )
              .toList(),
        );
      }).toList();
      return section.copyWith(lanes: lanes);
    }).toList();
    _set(
      state.copyWith(
        melodyPatterns: state.melodyPatterns
            .where((pattern) => pattern.id != patternId)
            .toList(),
        sections: sections,
      ),
    );
  }

  void addMelodyBlock({
    required String sectionId,
    required String laneId,
    required String patternId,
    required int startBar,
    required int spanBars,
  }) => _addPatternBlock(
    kind: SongLaneKind.melody,
    sectionId: sectionId,
    laneId: laneId,
    patternId: patternId,
    startBar: startBar,
    spanBars: spanBars,
  );

  String addGuitarStrumPattern({String name = 'Strum', int? lengthTicks}) {
    final pattern = makeGuitarStrumPattern(
      name: name,
      lengthTicks: lengthTicks ?? state.config.measureTicks,
      beatTicks: state.config.ticksPerBeat,
    );
    _set(
      state.copyWith(
        guitarStrumPatterns: [...state.guitarStrumPatterns, pattern],
      ),
    );
    return pattern.id;
  }

  void updateGuitarStrumPattern(GuitarStrumPattern updated) {
    _set(
      state.copyWith(
        guitarStrumPatterns: state.guitarStrumPatterns
            .map((pattern) => pattern.id == updated.id ? updated : pattern)
            .toList(),
      ),
    );
  }

  void removeGuitarStrumPattern(String patternId) {
    final sections = state.sections.map((section) {
      final lanes = section.lanes.map((lane) {
        if (lane.kind != SongLaneKind.guitarStrum) return lane;
        return lane.copyWith(
          blocks: lane.blocks
              .map(
                (block) => block.patternId == patternId
                    ? _clearPatternContent(block, SongLaneKind.guitarStrum)
                    : block,
              )
              .toList(),
        );
      }).toList();
      return section.copyWith(lanes: lanes);
    }).toList();
    _set(
      state.copyWith(
        guitarStrumPatterns: state.guitarStrumPatterns
            .where((pattern) => pattern.id != patternId)
            .toList(),
        sections: sections,
      ),
    );
  }

  void addGuitarStrumBlock({
    required String sectionId,
    required String laneId,
    required String patternId,
    required int startBar,
    required int spanBars,
  }) => _addPatternBlock(
    kind: SongLaneKind.guitarStrum,
    sectionId: sectionId,
    laneId: laneId,
    patternId: patternId,
    startBar: startBar,
    spanBars: spanBars,
  );

  void _addPatternBlock({
    required SongLaneKind kind,
    required String sectionId,
    required String laneId,
    required String patternId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (lane) {
      if (lane.kind != kind) return lane;
      final block = makePatternBlock(
        patternId: patternId,
        startBar: startBar,
        spanBars: spanBars,
      );
      if (blocksOverlap(lane.blocks, block)) return lane;
      return lane.copyWith(blocks: [...lane.blocks, block]);
    });
  }

  // ── audio assets ──
  /// Adds (or replaces by id) an [AudioAsset] in the project. Recording/import
  /// calls this before [addAudioClip] so the clip's asset resolves.
  void addAudioAsset(AudioAsset asset) {
    final assets = [
      for (final a in state.audioAssets)
        if (a.id != asset.id) a,
      asset,
    ];
    _set(state.copyWith(audioAssets: assets));
  }

  // ── audio clips ──
  String addAudioClip({
    required String assetId,
    required int durationMs,
    AudioFitMode fitMode = AudioFitMode.loop,
  }) {
    final clip = makeAudioClip(
      assetId: assetId,
      durationMs: durationMs,
      fitMode: fitMode,
    );
    _set(state.copyWith(audioClips: [...state.audioClips, clip]));
    return clip.id;
  }

  void updateAudioClip(AudioClip updated) {
    _set(
      state.copyWith(
        audioClips: state.audioClips
            .map((c) => c.id == updated.id ? updated : c)
            .toList(),
      ),
    );
  }

  void setClipFitMode({required String clipId, required AudioFitMode fitMode}) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(clip.copyWith(fitMode: fitMode));
  }

  void setClipTrim({
    required String clipId,
    required int trimStartMs,
    required int trimEndMs,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(
      clip.copyWith(
        trimStartMs: trimStartMs < 0 ? 0 : trimStartMs,
        trimEndMs: trimEndMs < trimStartMs ? trimStartMs : trimEndMs,
      ),
    );
  }

  /// Attaches [stretchedAsset] to [clipId] as its derived stretch and removes
  /// [removeAssetId] only when no live clip or retained snapshot references it.
  /// Returns false without changing state when the clip no longer exists
  /// (removed while the render was in flight) — the caller then owns cleaning
  /// up the now-orphaned [stretchedAsset] file.
  bool setClipStretchedAsset({
    required String clipId,
    required AudioAsset stretchedAsset,
    String? removeAssetId,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return false;
    final stillUsedByLiveClip =
        removeAssetId != null &&
        state.audioClips.any(
          (candidate) =>
              candidate.id != clipId &&
              candidate.stretchedAssetId == removeAssetId,
        );
    final retainedAssetIds = _assetIdsInRetainedSnapshots();
    final assets = [
      for (final a in state.audioAssets)
        if (a.id != removeAssetId ||
            stillUsedByLiveClip ||
            retainedAssetIds.contains(a.id))
          a,
      if (!state.audioAssets.any((asset) => asset.id == stretchedAsset.id))
        stretchedAsset,
    ];
    final clips = state.audioClips
        .map(
          (c) => c.id == clipId
              ? c.copyWith(stretchedAssetId: stretchedAsset.id)
              : c,
        )
        .toList();
    // Stretch output is derived from the user's trim/placement/tempo edit.
    // Publishing the completed render must not create a second undo step or
    // clear a redo branch after the user edit has already been recorded.
    _history.restore(() {
      _set(state.copyWith(audioAssets: assets, audioClips: clips));
    });
    return true;
  }

  // ── chord segments ──
  String addChordSegment({
    required String clipId,
    required int startTick,
    required int spanTicks,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String> chordNotes = const [],
    String? romanNumeral,
    String? saveId,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return '';
    final seg = ChordSegment(
      id: generateId(),
      startTick: startTick,
      spanTicks: spanTicks,
      chordSymbol: chordSymbol,
      chordQuality: chordQuality,
      chordRootPc: chordRootPc,
      chordNotes: chordNotes,
      romanNumeral: romanNumeral,
      saveId: saveId,
    );
    updateAudioClip(clip.copyWith(segments: [...clip.segments, seg]));
    return seg.id;
  }

  void removeChordSegment({required String clipId, required String segmentId}) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(
      clip.copyWith(
        segments: clip.segments.where((s) => s.id != segmentId).toList(),
      ),
    );
  }

  void clampClipSegments({
    required String clipId,
    required int spanTotalTicks,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    updateAudioClip(
      clip.copyWith(segments: clampedSegments(clip.segments, spanTotalTicks)),
    );
  }

  void addAudioBlock({
    required String sectionId,
    required String laneId,
    required String audioClipId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      if (l.kind != SongLaneKind.audio) return l;
      final candidate = makeAudioBlock(
        audioClipId: audioClipId,
        startBar: startBar,
        spanBars: spanBars,
      );
      if (blocksOverlap(l.blocks, candidate)) return l;
      return l.copyWith(blocks: [...l.blocks, candidate]);
    });
  }

  /// Removes an audio block. Clips and asset metadata stay alive while another
  /// live block, clip, or retained Save System snapshot references them.
  void removeAudioBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
  }) {
    runHistoryGroup(
      () => _removeAudioBlock(
        sectionId: sectionId,
        laneId: laneId,
        blockId: blockId,
      ),
    );
  }

  void _removeAudioBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where((candidate) => candidate.id == laneId)
        .firstOrNull;
    final removedBlock = lane?.blocks
        .where((block) => block.id == blockId)
        .firstOrNull;
    final clipId = removedBlock?.audioClipId;
    final removedClip = clipId == null
        ? null
        : state.audioClips.where((c) => c.id == clipId).firstOrNull;
    final sections = state.sections.map((candidateSection) {
      if (candidateSection.id != sectionId) return candidateSection;
      return candidateSection.copyWith(
        lanes: candidateSection.lanes.map((candidateLane) {
          if (candidateLane.id != laneId) return candidateLane;
          return candidateLane.copyWith(
            blocks: candidateLane.blocks
                .where((block) => block.id != blockId)
                .toList(),
          );
        }).toList(),
      );
    }).toList();
    final liveClipIds = {
      for (final section in sections)
        for (final lane in section.lanes)
          for (final block in lane.blocks)
            if (block.audioClipId != null) block.audioClipId!,
    };
    final clips = state.audioClips
        .where((clip) => clip.id != clipId || liveClipIds.contains(clip.id))
        .toList();
    final liveAssetIds = <String>{
      for (final clip in clips) clip.assetId,
      for (final clip in clips)
        if (clip.stretchedAssetId != null) clip.stretchedAssetId!,
    };
    final removedAssetIds = <String>{
      if (removedClip != null) removedClip.assetId,
      if (removedClip?.stretchedAssetId != null) removedClip!.stretchedAssetId!,
    }..removeAll(liveAssetIds);
    final retainedAssetIds = _assetIdsInRetainedSnapshots()
      ..addAll(_assetIdsInProjectSnapshot(state));
    final assets = state.audioAssets
        .where(
          (asset) =>
              !removedAssetIds.contains(asset.id) ||
              retainedAssetIds.contains(asset.id),
        )
        .toList();
    _set(
      state.copyWith(
        sections: sections,
        audioClips: clips,
        audioAssets: assets,
      ),
    );
  }

  Set<String> _assetIdsInRetainedSnapshots() {
    final ids = <String>{};
    void include(InstrumentSnapshot snapshot) {
      if (snapshot is WriterBlockSnapshot) {
        if (snapshot.audioAsset != null) ids.add(snapshot.audioAsset!.id);
        if (snapshot.stretchedAudioAsset != null) {
          ids.add(snapshot.stretchedAudioAsset!.id);
        }
      } else if (snapshot is SongwriterProjectSnapshot) {
        ids.addAll(snapshot.audioAssets.map((asset) => asset.id));
        for (final clip in snapshot.audioClips) {
          ids.add(clip.assetId);
          if (clip.stretchedAssetId != null) ids.add(clip.stretchedAssetId!);
        }
      }
    }

    for (final save in ref.read(saveSystemProvider).saves) {
      include(save.snapshot);
    }
    for (final snapshot in _history.retainedSnapshots) {
      include(snapshot);
    }
    return ids;
  }

  Set<String> _assetIdsInProjectSnapshot(SongwriterProjectSnapshot snapshot) =>
      {
        ...snapshot.audioAssets.map((asset) => asset.id),
        for (final clip in snapshot.audioClips) ...[
          clip.assetId,
          if (clip.stretchedAssetId != null) clip.stretchedAssetId!,
        ],
      };

  /// Replace the source audio block+clip with one clip+block per slice on
  /// consecutive bars. Each new clip shares the source assetId with the slice's
  /// trim region; fit defaults to stretch (timing correction). Skips a bar
  /// already occupied by another block. Returns the new clip ids in placement
  /// order so callers can kick the stretch render for each placed clip.
  List<String> scatterSlices({
    required String sectionId,
    required String laneId,
    required String sourceBlockId,
    required List<PlacedSlice> slices,
    AudioFitMode fitMode = AudioFitMode.stretch,
  }) => runHistoryGroup(
    () => _scatterSlices(
      sectionId: sectionId,
      laneId: laneId,
      sourceBlockId: sourceBlockId,
      slices: slices,
      fitMode: fitMode,
    ),
  );

  List<String> _scatterSlices({
    required String sectionId,
    required String laneId,
    required String sourceBlockId,
    required List<PlacedSlice> slices,
    required AudioFitMode fitMode,
  }) {
    final lane = state.sections
        .where((s) => s.id == sectionId)
        .expand((s) => s.lanes)
        .where((l) => l.id == laneId)
        .firstOrNull;
    final source = lane?.blocks.where((b) => b.id == sourceBlockId).firstOrNull;
    final clipId = source?.audioClipId;
    final assetId = clipId == null
        ? null
        : state.audioClips.where((c) => c.id == clipId).firstOrNull?.assetId;
    if (lane == null || source == null || assetId == null) return const [];

    // Bars occupied by OTHER blocks (the source's own bars are free to reuse).
    final occupied = <int>{
      for (final b in lane.blocks)
        if (b.id != sourceBlockId)
          for (var i = b.startBar; i < b.endBar; i++) i,
    };

    // Slices that fit (stop at the first bar blocked by another block).
    final accepted = <PlacedSlice>[];
    for (final s in slices) {
      if (occupied.contains(s.bar)) break; // stop at the first blocked bar
      accepted.add(s);
    }
    if (accepted.isEmpty) return const [];

    // Phase 1 — add every slice clip FIRST. They reference the shared assetId,
    // so the source removal below cannot reclaim (delete) the asset file.
    final newClipIds = <String>[];
    for (final s in accepted) {
      final newClipId = addAudioClip(
        assetId: assetId,
        durationMs: s.trimEndMs - s.trimStartMs,
      );
      setClipTrim(
        clipId: newClipId,
        trimStartMs: s.trimStartMs,
        trimEndMs: s.trimEndMs,
      );
      setClipFitMode(clipId: newClipId, fitMode: fitMode);
      newClipIds.add(newClipId);
    }

    // Phase 2 — remove the source block now that its asset is safe. This frees
    // the source's bars so a slice can reuse them without an overlap rejection.
    removeAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      blockId: sourceBlockId,
    );

    // Phase 3 — place one 1-bar block per accepted slice.
    for (var i = 0; i < accepted.length; i++) {
      addAudioBlock(
        sectionId: sectionId,
        laneId: laneId,
        audioClipId: newClipIds[i],
        startBar: accepted[i].bar,
        spanBars: 1,
      );
    }
    return newClipIds;
  }

  /// Move/resize a block. Clamps to valid bounds; rejects (no-op) if the new
  /// placement would overlap another block in the same lane.
  void setBlockPlacement({
    required String sectionId,
    required String laneId,
    required String blockId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      final current = l.blocks.where((b) => b.id == blockId).firstOrNull;
      if (current == null) return l;
      final moved = current.copyWith(
        startBar: startBar < 0 ? 0 : startBar,
        spanBars: spanBars < 1 ? 1 : spanBars,
      );
      final others = l.blocks.where((b) => b.id != blockId).toList();
      if (blocksOverlap(others, moved)) return l; // reject overlap
      return l.copyWith(
        blocks: l.blocks.map((b) => b.id == blockId ? moved : b).toList(),
      );
    });
  }

  /// Make Unique: detach a block from its live save by embedding a snapshot.
  bool makeBlockUnique({
    required String sectionId,
    required String laneId,
    required String blockId,
    InstrumentSnapshot? snapshot,
    String? saveName,
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where((candidate) => candidate.id == laneId)
        .firstOrNull;
    final block = lane?.blocks
        .where((candidate) => candidate.id == blockId)
        .firstOrNull;
    if (section == null || lane == null || block == null) return false;

    snapshot ??= canonicalSaveForBlock(blockId)?.snapshot;
    snapshot ??= _contentSnapshot(state, lane, block) ?? block.embedded;
    if (snapshot == null) return false;

    var project = state;
    var uniqueSnapshot = snapshot;
    var patternId = block.patternId;
    var audioClipId = block.audioClipId;
    if (snapshot is WriterBlockSnapshot) {
      if (snapshot.drumPattern case final pattern?) {
        final cloned = pattern.copyWith(id: generateId());
        project = project.copyWith(
          drumPatterns: [...project.drumPatterns, cloned],
        );
        patternId = cloned.id;
        uniqueSnapshot = _copyWriterBlockSnapshot(
          snapshot,
          drumPattern: cloned,
        );
      } else if (snapshot.melodyPattern case final pattern?) {
        final cloned = pattern.copyWith(id: generateId());
        project = project.copyWith(
          melodyPatterns: [...project.melodyPatterns, cloned],
        );
        patternId = cloned.id;
        uniqueSnapshot = _copyWriterBlockSnapshot(
          snapshot,
          melodyPattern: cloned,
        );
      } else if (snapshot.guitarStrumPattern case final pattern?) {
        final cloned = pattern.copyWith(id: generateId());
        project = project.copyWith(
          guitarStrumPatterns: [...project.guitarStrumPatterns, cloned],
        );
        patternId = cloned.id;
        uniqueSnapshot = _copyWriterBlockSnapshot(
          snapshot,
          guitarStrumPattern: cloned,
        );
      } else if (snapshot.audioClip case final clip?) {
        final cloned = AudioClip(
          id: generateId(),
          assetId: clip.assetId,
          trimStartMs: clip.trimStartMs,
          trimEndMs: clip.trimEndMs,
          fitMode: clip.fitMode,
          stretchedAssetId: clip.stretchedAssetId,
          segments: clip.segments,
        );
        project = project.copyWith(audioClips: [...project.audioClips, cloned]);
        audioClipId = cloned.id;
        uniqueSnapshot = _copyWriterBlockSnapshot(snapshot, audioClip: cloned);
      }
    }

    final sections = project.sections.map((candidateSection) {
      if (candidateSection.id != sectionId) return candidateSection;
      return candidateSection.copyWith(
        lanes: candidateSection.lanes.map((candidateLane) {
          if (candidateLane.id != laneId) return candidateLane;
          return candidateLane.copyWith(
            blocks: candidateLane.blocks.map((candidateBlock) {
              if (candidateBlock.id != blockId) return candidateBlock;
              return candidateBlock.copyWith(
                clearSaveId: true,
                embedded: uniqueSnapshot,
                patternId: patternId,
                clearPatternId: patternId == null,
                audioClipId: audioClipId,
                clearAudioClipId: audioClipId == null,
              );
            }).toList(),
          );
        }).toList(),
      );
    }).toList();
    _set(
      project.copyWith(sections: sections),
      saveNames: {
        if (saveName != null && saveName.trim().isNotEmpty) blockId: saveName,
      },
    );
    return true;
  }

  void relinkBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
    required String saveId,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId != null &&
        resolveSaveInProject(ref.read(saveSystemProvider), projectId, saveId) ==
            null) {
      return;
    }
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(
        blocks: l.blocks
            .map(
              (b) => b.id == blockId
                  ? b.copyWith(saveId: saveId, clearEmbedded: true)
                  : b,
            )
            .toList(),
      ),
    );
  }

  WriterBlockSnapshot _copyWriterBlockSnapshot(
    WriterBlockSnapshot snapshot, {
    DrumPattern? drumPattern,
    NotePattern? melodyPattern,
    GuitarStrumPattern? guitarStrumPattern,
    AudioClip? audioClip,
    List<String>? defaultLyrics,
  }) => WriterBlockSnapshot(
    laneKind: snapshot.laneKind,
    isSilent: snapshot.isSilent,
    chordSymbol: snapshot.chordSymbol,
    chordQuality: snapshot.chordQuality,
    chordRootPc: snapshot.chordRootPc,
    chordNotes: snapshot.chordNotes,
    romanNumeral: snapshot.romanNumeral,
    defaultLyrics: defaultLyrics ?? snapshot.defaultLyrics,
    drumPattern: drumPattern ?? snapshot.drumPattern,
    melodyPattern: melodyPattern ?? snapshot.melodyPattern,
    guitarStrumPattern: guitarStrumPattern ?? snapshot.guitarStrumPattern,
    audioClip: audioClip ?? snapshot.audioClip,
    audioAsset: snapshot.audioAsset,
    stretchedAudioAsset: snapshot.stretchedAudioAsset,
  );

  bool renameLinkedSave({required String saveId, required String name}) {
    final trimmed = name.trim();
    if (!isValidSaveName(trimmed)) return false;
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return false;
    final saveState = ref.read(saveSystemProvider);
    final save = resolveSaveInProject(saveState, projectId, saveId);
    if (save == null) return false;
    final linkedBlockIds = getWriterLinksForSave(
      saveState,
      projectId,
      saveId,
    ).map((link) => link.blockId).toList();
    if (linkedBlockIds.isEmpty) return false;
    _commitWriterStateInBackground(
      state,
      saveNames: {for (final blockId in linkedBlockIds) blockId: trimmed},
    );
    return true;
  }

  /// Applies an instrument edit to the canonical linked save and refreshes the
  /// fallback cache on every placement in the selected project.
  bool updateLinkedSaveSnapshot({
    required String saveId,
    required InstrumentSnapshot snapshot,
  }) {
    if (snapshot is WriterBlockSnapshot) return false;
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return false;
    final saveState = ref.read(saveSystemProvider);
    if (resolveSaveInProject(saveState, projectId, saveId) == null) {
      return false;
    }
    final links = getWriterLinksForSave(saveState, projectId, saveId);
    if (links.isEmpty) return false;
    final linkedBlockIds = links.map((link) => link.blockId).toSet();
    final sections = state.sections.map((section) {
      return section.copyWith(
        lanes: section.lanes.map((lane) {
          return lane.copyWith(
            blocks: lane.blocks.map((block) {
              if (!linkedBlockIds.contains(block.id)) return block;
              return block.copyWith(embedded: snapshot);
            }).toList(),
          );
        }).toList(),
      );
    }).toList();
    _set(state.copyWith(sections: sections));
    return true;
  }

  /// Compatibility alias for instrument panels that expose a linked-save
  /// update action.
  bool updateLinkedInstrumentSave({
    required String saveId,
    required InstrumentSnapshot snapshot,
  }) => updateLinkedSaveSnapshot(saveId: saveId, snapshot: snapshot);

  /// Inserts a new source block linked to an existing same-project Writer
  /// native save. If [laneId] is omitted, the first matching lane is used or a
  /// matching lane is created as part of the same Writer transaction.
  bool insertWriterBlockFromSave({
    required String saveId,
    required String sectionId,
    required SongLaneKind laneKind,
    required int startBar,
    int spanBars = 1,
    String? laneId,
    String? anchorLaneId,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null || startBar < 0 || spanBars < 1) return false;
    final save = resolveSaveInProject(
      ref.read(saveSystemProvider),
      projectId,
      saveId,
    );
    final snapshot = save?.snapshot;
    if (snapshot is! WriterBlockSnapshot ||
        snapshot.laneKind != laneKind ||
        laneKind == SongLaneKind.save ||
        !_hasRestorableWriterSnapshot(snapshot)) {
      return false;
    }
    final sectionIndex = state.sections.indexWhere(
      (section) => section.id == sectionId,
    );
    if (sectionIndex < 0) return false;
    final section = state.sections[sectionIndex];
    SongLane? destination;
    if (laneId != null) {
      destination = section.lanes
          .where((lane) => lane.id == laneId && lane.kind == laneKind)
          .firstOrNull;
      if (destination == null) return false;
    } else {
      final matching =
          section.lanes.where((lane) => lane.kind == laneKind).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      destination = matching.firstOrNull;
    }
    final targetLane =
        destination ?? makeLane(kind: laneKind, order: section.lanes.length);
    final block = _blockFromWriterSnapshot(
      snapshot,
      id: generateId(),
      saveId: saveId,
      startBar: startBar,
      spanBars: spanBars,
    );
    if (blocksOverlap(targetLane.blocks, block)) return false;
    final laneWithBlock = targetLane.copyWith(
      blocks: [...targetLane.blocks, block],
      anchorLaneId: anchorLaneId,
    );
    final lanes = [
      for (final lane in section.lanes)
        if (lane.id != laneWithBlock.id) lane,
      laneWithBlock,
    ];
    final sections = [...state.sections];
    sections[sectionIndex] = section.copyWith(lanes: lanes);
    final restored = _restoreWriterBlockSnapshot(state, snapshot);
    _set(restored.copyWith(sections: sections));
    return true;
  }

  SongBlock _blockFromWriterSnapshot(
    WriterBlockSnapshot snapshot, {
    required String id,
    required String saveId,
    required int startBar,
    required int spanBars,
  }) {
    switch (snapshot.laneKind) {
      case SongLaneKind.harmony:
        return SongBlock(
          id: id,
          startBar: startBar,
          spanBars: spanBars,
          saveId: saveId,
          embedded: snapshot,
          chordSymbol: snapshot.chordSymbol,
          chordQuality: snapshot.chordQuality,
          chordRootPc: snapshot.chordRootPc,
          chordNotes: snapshot.chordNotes,
          romanNumeral: snapshot.romanNumeral,
          lyrics: snapshot.defaultLyrics,
          isSilent: snapshot.isSilent,
        );
      case SongLaneKind.save:
        return SongBlock(id: id, startBar: startBar, spanBars: spanBars);
      case SongLaneKind.drum:
        return SongBlock(
          id: id,
          startBar: startBar,
          spanBars: spanBars,
          saveId: saveId,
          embedded: snapshot,
          patternId: snapshot.drumPattern?.id,
          lyrics: snapshot.defaultLyrics,
        );
      case SongLaneKind.melody:
        return SongBlock(
          id: id,
          startBar: startBar,
          spanBars: spanBars,
          saveId: saveId,
          embedded: snapshot,
          patternId: snapshot.melodyPattern?.id,
          lyrics: snapshot.defaultLyrics,
        );
      case SongLaneKind.guitarStrum:
        return SongBlock(
          id: id,
          startBar: startBar,
          spanBars: spanBars,
          saveId: saveId,
          embedded: snapshot,
          patternId: snapshot.guitarStrumPattern?.id,
          lyrics: snapshot.defaultLyrics,
        );
      case SongLaneKind.audio:
        return SongBlock(
          id: id,
          startBar: startBar,
          spanBars: spanBars,
          saveId: saveId,
          embedded: snapshot,
          audioClipId: snapshot.audioClip?.id,
          lyrics: snapshot.defaultLyrics,
        );
    }
  }

  bool _hasRestorableWriterSnapshot(WriterBlockSnapshot snapshot) =>
      switch (snapshot.laneKind) {
        SongLaneKind.harmony => true,
        SongLaneKind.save => false,
        SongLaneKind.drum => snapshot.drumPattern != null,
        SongLaneKind.melody => snapshot.melodyPattern != null,
        SongLaneKind.guitarStrum => snapshot.guitarStrumPattern != null,
        SongLaneKind.audio =>
          snapshot.audioClip != null && snapshot.audioAsset != null,
      };

  SongwriterProjectSnapshot _restoreWriterBlockSnapshot(
    SongwriterProjectSnapshot project,
    WriterBlockSnapshot snapshot,
  ) {
    List<T> upsert<T>(List<T> current, T value, String Function(T) idOf) => [
      for (final item in current)
        if (idOf(item) != idOf(value)) item,
      value,
    ];
    return project.copyWith(
      drumPatterns: snapshot.drumPattern == null
          ? project.drumPatterns
          : upsert(
              project.drumPatterns,
              snapshot.drumPattern!,
              (pattern) => pattern.id,
            ),
      melodyPatterns: snapshot.melodyPattern == null
          ? project.melodyPatterns
          : upsert(
              project.melodyPatterns,
              snapshot.melodyPattern!,
              (pattern) => pattern.id,
            ),
      guitarStrumPatterns: snapshot.guitarStrumPattern == null
          ? project.guitarStrumPatterns
          : upsert(
              project.guitarStrumPatterns,
              snapshot.guitarStrumPattern!,
              (pattern) => pattern.id,
            ),
      audioClips: snapshot.audioClip == null
          ? project.audioClips
          : upsert(project.audioClips, snapshot.audioClip!, (clip) => clip.id),
      audioAssets: [
        for (final asset in project.audioAssets)
          if (asset.id != snapshot.audioAsset?.id &&
              asset.id != snapshot.stretchedAudioAsset?.id)
            asset,
        if (snapshot.audioAsset != null) snapshot.audioAsset!,
        if (snapshot.stretchedAudioAsset != null) snapshot.stretchedAudioAsset!,
      ],
    );
  }

  /// Returns true when a save-lane block at [startBar]/[spanBars] would land
  /// inside the section's first existing save lane without overlapping any of
  /// its blocks. When the section has no save lane yet, returns true (the
  /// auto-created lane will be empty).
  ///
  /// The section's save lane anchored to [anchorLaneId] (null = the primary
  /// harmony lane), or null if none exists yet. Anchors resolve through
  /// [saveAnchorLane], so a legacy anchor-less save lane matches the primary.
  SongLane? _saveLaneForAnchor(SongSection section, String? anchorLaneId) {
    final resolved = anchorLaneId ?? primaryHarmonyLane(section)?.id;
    final saveLanes =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    for (final lane in saveLanes) {
      if (saveAnchorLane(section, lane)?.id == resolved) return lane;
    }
    return null;
  }

  String? _explicitSaveAnchorLaneId(SongSection section, String? anchorLaneId) {
    if (anchorLaneId == null) return null;
    return primaryHarmonyLane(section)?.id == anchorLaneId
        ? null
        : anchorLaneId;
  }

  /// Mirrors [_findOrCreateSaveLane]'s lane-selection rule so callers can
  /// preflight overlaps before persisting a SaveEntry. Only the save lane
  /// anchored to [anchorLaneId] is checked — voicings for different harmony
  /// lanes may share bars.
  bool _canPlaceSaveBlockInSection(
    SongSection section,
    int startBar,
    int spanBars, {
    String? anchorLaneId,
  }) {
    final lane = _saveLaneForAnchor(
      section,
      _explicitSaveAnchorLaneId(section, anchorLaneId),
    );
    if (lane == null) return true;
    final endBar = startBar + spanBars;
    for (final b in lane.blocks) {
      if (startBar < b.endBar && b.startBar < endBar) return false;
    }
    return true;
  }

  /// Persists a voicing suggestion as a SaveEntry in its Writer section folder
  /// and inserts a save-lane block aligned to the triggering harmony block.
  ///
  /// Preflights the overlap check against the destination save lane and bails
  /// out before persisting a SaveEntry when the candidate block cannot land —
  /// avoiding an orphan save with no block in the arrangement.
  Future<void> acceptVoicingSuggestion({
    required String sectionId,
    required String harmonyBlockId,
    required VoicingSuggestion suggestion,
  }) async {
    final section = state.sections.firstWhere(
      (s) => s.id == sectionId,
      orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
    );
    if (section.id.isEmpty) return;
    SongBlock? harmonyBlock;
    String? harmonyLaneId;
    for (final lane in section.lanes) {
      for (final b in lane.blocks) {
        if (b.id == harmonyBlockId) {
          harmonyBlock = b;
          harmonyLaneId = lane.id;
          break;
        }
      }
      if (harmonyBlock != null) break;
    }
    final selectedBlock = harmonyBlock;
    if (selectedBlock == null) return;
    final anchorLaneId = _explicitSaveAnchorLaneId(section, harmonyLaneId);

    // Preflight: if the candidate block would overlap the destination save
    // lane, abort BEFORE creating the SaveEntry. addSaveBlock silently
    // rejects overlaps, which would otherwise leave behind an orphan save.
    if (!_canPlaceSaveBlockInSection(
      section,
      selectedBlock.startBar,
      selectedBlock.spanBars,
      anchorLaneId: anchorLaneId,
    )) {
      return;
    }

    final selId = ref.read(saveSystemProvider).selectedProjectId;
    if (selId == null) return;
    final selFolder = ref
        .read(saveSystemProvider)
        .folders
        .where((f) => f.id == selId)
        .firstOrNull;
    if (selFolder == null || selFolder.kind != SaveFolderKind.project) return;

    final rootName = chromaticNotes[suggestion.rootPc];
    final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
    final snapshot = voicingToSnapshot(suggestion);

    runHistoryGroup(() {
      final laneId = _findOrCreateSaveLane(
        sectionId,
        anchorLaneId: anchorLaneId,
      );
      if (laneId == null) return;
      addSaveBlock(
        sectionId: sectionId,
        laneId: laneId,
        snapshot: snapshot,
        saveName: saveName,
        startBar: selectedBlock.startBar,
        spanBars: selectedBlock.spanBars,
      );
    });
  }

  /// Persists a 3rd-above harmony suggestion as a SaveEntry in its Writer
  /// section folder and inserts a save-lane block aligned to the triggering
  /// harmony block.
  ///
  /// Preflights the overlap check against the destination save lane and bails
  /// out before persisting a SaveEntry when the candidate block cannot land —
  /// avoiding an orphan save with no block in the arrangement.
  Future<void> acceptThirdAboveSuggestion({
    required String sectionId,
    required String harmonyBlockId,
    required ThirdAboveSuggestion suggestion,
  }) async {
    final section = state.sections.firstWhere(
      (s) => s.id == sectionId,
      orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
    );
    if (section.id.isEmpty) return;
    SongBlock? harmonyBlock;
    String? harmonyLaneId;
    for (final lane in section.lanes) {
      for (final b in lane.blocks) {
        if (b.id == harmonyBlockId) {
          harmonyBlock = b;
          harmonyLaneId = lane.id;
          break;
        }
      }
      if (harmonyBlock != null) break;
    }
    final selectedBlock = harmonyBlock;
    if (selectedBlock == null) return;
    final anchorLaneId = _explicitSaveAnchorLaneId(section, harmonyLaneId);

    if (!_canPlaceSaveBlockInSection(
      section,
      selectedBlock.startBar,
      selectedBlock.spanBars,
      anchorLaneId: anchorLaneId,
    )) {
      return;
    }

    final selId = ref.read(saveSystemProvider).selectedProjectId;
    if (selId == null) return;
    final selFolder = ref
        .read(saveSystemProvider)
        .folders
        .where((f) => f.id == selId)
        .firstOrNull;
    if (selFolder == null || selFolder.kind != SaveFolderKind.project) return;

    final rootName = chromaticNotes[suggestion.rootPc];
    final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
    final snapshot = thirdAboveToSnapshot(suggestion);

    runHistoryGroup(() {
      final laneId = _findOrCreateSaveLane(
        sectionId,
        anchorLaneId: anchorLaneId,
      );
      if (laneId == null) return;
      addSaveBlock(
        sectionId: sectionId,
        laneId: laneId,
        snapshot: snapshot,
        saveName: saveName,
        startBar: selectedBlock.startBar,
        spanBars: selectedBlock.spanBars,
      );
    });
  }

  /// Inserts a save-lane block in [sectionId] aligned to the harmony block's
  /// bars, referencing the existing [saveId]. Does NOT create a new SaveEntry.
  /// Silently no-ops when the section or harmony block is missing.
  void acceptLibraryMatch({
    required String sectionId,
    required String harmonyBlockId,
    required String saveId,
  }) {
    final section = state.sections.firstWhere(
      (s) => s.id == sectionId,
      orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
    );
    if (section.id.isEmpty) return;
    SongBlock? harmonyBlock;
    String? harmonyLaneId;
    for (final lane in section.lanes) {
      for (final b in lane.blocks) {
        if (b.id == harmonyBlockId) {
          harmonyBlock = b;
          harmonyLaneId = lane.id;
          break;
        }
      }
      if (harmonyBlock != null) break;
    }
    final selectedBlock = harmonyBlock;
    if (selectedBlock == null) return;
    final anchorLaneId = _explicitSaveAnchorLaneId(section, harmonyLaneId);

    runHistoryGroup(() {
      final laneId = _findOrCreateSaveLane(
        sectionId,
        anchorLaneId: anchorLaneId,
      );
      if (laneId == null) return;
      addSaveBlock(
        sectionId: sectionId,
        laneId: laneId,
        saveId: saveId,
        startBar: selectedBlock.startBar,
        spanBars: selectedBlock.spanBars,
      );
    });
  }

  /// Inserts a save-lane block at [startBar] referencing an existing [saveId],
  /// without going through a harmony chord. Used by the add-bar sheet's "From
  /// library" picker. No-ops when the section is missing or the placement
  /// overlaps the destination save lane.
  void addLibraryBlockAt({
    required String sectionId,
    required String saveId,
    required int startBar,
    int spanBars = 1,
    String? anchorLaneId,
  }) {
    final section = state.sections.where((s) => s.id == sectionId).firstOrNull;
    if (section == null) return;
    final explicitAnchorLaneId = _explicitSaveAnchorLaneId(
      section,
      anchorLaneId,
    );
    if (!_canPlaceSaveBlockInSection(
      section,
      startBar,
      spanBars,
      anchorLaneId: explicitAnchorLaneId,
    )) {
      return;
    }
    runHistoryGroup(() {
      final laneId = _findOrCreateSaveLane(
        sectionId,
        anchorLaneId: explicitAnchorLaneId,
      );
      if (laneId == null) return;
      addSaveBlock(
        sectionId: sectionId,
        laneId: laneId,
        saveId: saveId,
        startBar: startBar,
        spanBars: spanBars,
      );
    });
  }

  /// Updates the project's display name and renames its linked top-level
  /// folder if one with the old name exists. Whitespace-only names are ignored.
  void setProjectName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final old = state.name;
    if (trimmed == old) return;
    _set(state.copyWith(name: trimmed));
    final sel = ref.read(saveSystemProvider).selectedProjectId;
    if (sel != null) {
      ref.read(saveSystemProvider.notifier).renameProject(sel, trimmed);
    } else {
      _renameProjectFolderIfExists(old, trimmed);
    }
  }

  void _renameProjectFolderIfExists(String oldName, String newName) {
    final trimmedOld = oldName.trim();
    if (trimmedOld.isEmpty || trimmedOld == newName) return;
    for (final f in ref.read(saveSystemProvider).folders) {
      if (f.parentId == null && f.name == trimmedOld) {
        ref.read(saveSystemProvider.notifier).renameFolder(f.id, newName);
        return;
      }
    }
  }

  /// Returns the saves visible to library-match: selected project's subtree.
  /// Returns empty when no project is selected.
  List<SaveEntry> searchableSavesForLibraryMatch() {
    final sv = ref.read(saveSystemProvider);
    final selId = sv.selectedProjectId;
    if (selId == null) return const [];
    final f = sv.folders.where((f) => f.id == selId).firstOrNull;
    if (f == null || f.kind != SaveFolderKind.project) return const [];
    return getSavesInSubtree(sv.folders, sv.saves, selId);
  }

  /// Save lane for voicings anchored to [anchorLaneId] (null = the primary
  /// harmony lane) — found, or created and stamped with the anchor.
  String? _findOrCreateSaveLane(String sectionId, {String? anchorLaneId}) {
    final section = state.sections.firstWhere(
      (s) => s.id == sectionId,
      orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
    );
    if (section.id.isEmpty) return null;
    final explicitAnchorLaneId = _explicitSaveAnchorLaneId(
      section,
      anchorLaneId,
    );
    final existing = _saveLaneForAnchor(section, explicitAnchorLaneId);
    if (existing != null) {
      final primaryLaneId = primaryHarmonyLane(section)?.id;
      if (explicitAnchorLaneId == null &&
          existing.anchorLaneId != null &&
          existing.anchorLaneId == primaryLaneId) {
        _replaceLane(
          sectionId,
          existing.id,
          (l) => l.copyWith(clearAnchorLaneId: true),
        );
      }
      return existing.id;
    }
    final laneId = addLane(sectionId: sectionId, kind: SongLaneKind.save);
    if (explicitAnchorLaneId != null) {
      _replaceLane(
        sectionId,
        laneId,
        (l) => l.copyWith(anchorLaneId: explicitAnchorLaneId),
      );
    }
    return laneId;
  }

  void _recomputeNumerals() {
    final key = state.config;
    _set(
      state.copyWith(
        sections: state.sections
            .map(
              (s) => s.copyWith(
                lanes: s.lanes
                    .map(
                      (l) => l.kind != SongLaneKind.harmony
                          ? l
                          : l.copyWith(
                              blocks: l.blocks.map((b) {
                                if (b.chordRootPc == null ||
                                    b.chordQuality == null) {
                                  return b;
                                }
                                final numeral = romanNumeralFor(
                                  b.chordRootPc!,
                                  b.chordQuality!,
                                  key.keyRoot,
                                  key.keyScaleName,
                                );
                                return b.copyWith(
                                  romanNumeral: numeral,
                                  clearRomanNumeral: numeral == null,
                                );
                              }).toList(),
                            ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  /// Replaces the whole project from a named save and starts a fresh history.
  /// The bound save ID, overwrite setting, and materialized clean baseline are
  /// committed in the same journaled transaction as the restored project.
  Future<void> loadProject(
    SongwriterProjectSnapshot project, {
    String? saveId,
  }) async {
    _history.clear();
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    final currentConfig = projectId == null ? project.config : state.config;
    final loadable = project.copyWith(config: currentConfig);
    final loadedEntry = projectId == null || saveId == null
        ? null
        : resolveSaveInProject(ref.read(saveSystemProvider), projectId, saveId);
    final selectedSaveId = loadedEntry?.snapshot is SongwriterProjectSnapshot
        ? saveId
        : null;
    final materialized = projectId == null
        ? (project: loadable, saves: <String, SaveEntry>{})
        : _forkChangedNamedVersion(projectId, loadable);
    await _commitWriterStateWithoutHistory(
      materialized.project,
      adoptSaves: materialized.saves,
      bindSaveId: selectedSaveId,
      resetBinding: projectId != null,
    );
  }

  /// Overwrites the active named Song version and advances its clean baseline
  /// in the same journaled transaction, preserving the project's overwrite
  /// preference.
  Future<bool> overwriteNamedSave(String saveId) async {
    final saveState = ref.read(saveSystemProvider);
    final projectId = saveState.selectedProjectId;
    if (projectId == null ||
        ref.read(writerSaveBindingProvider)[projectId]?.activeSaveId !=
            saveId) {
      return false;
    }
    final entry = resolveSaveInProject(saveState, projectId, saveId);
    if (entry?.snapshot is! SongwriterProjectSnapshot) return false;

    final materialized = materializeCurrentContent();
    await _commitWriterStateWithoutHistory(
      state,
      adoptSaves: {
        saveId: entry!.copyWith(
          snapshot: materialized,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      },
      rebaselineSaveId: saveId,
    );
    return true;
  }

  /// Binds the live Writer session to a newly saved named Song version.
  ///
  /// Reconcile canonical block content before capturing the baseline so the
  /// binding stays clean even when a linked save's fallback cache was stale.
  Future<void> bindNamedSave(String saveId) async {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return;
    final entry = resolveSaveInProject(
      ref.read(saveSystemProvider),
      projectId,
      saveId,
    );
    if (entry?.snapshot is! SongwriterProjectSnapshot) return;
    await _commitWriterState(state, bindSaveId: saveId, resetBinding: true);
  }

  ({SongwriterProjectSnapshot project, Map<String, SaveEntry> saves})
  _forkChangedNamedVersion(String projectId, SongwriterProjectSnapshot saved) {
    final saveState = ref.read(saveSystemProvider);
    final oldToNew = <String, SaveEntry>{};
    final newById = <String, SaveEntry>{};
    var rootOrder = getSavesInFolder(saveState.saves, projectId).length;
    final sections = saved.sections.map((section) {
      return section.copyWith(
        lanes: section.lanes.map((lane) {
          return lane.copyWith(
            blocks: lane.blocks.map((block) {
              final oldId = block.saveId;
              if (oldId == null) return block;
              final fallback = _contentSnapshot(saved, lane, block);
              final existing = resolveSaveInProject(
                saveState,
                projectId,
                oldId,
              );
              if (fallback == null) return block;
              if (existing != null &&
                  _jsonEqual(existing.snapshot.toJson(), fallback.toJson())) {
                return block.copyWith(embedded: existing.snapshot);
              }

              final fork =
                  oldToNew[oldId] ??
                  () {
                    final name =
                        existing?.name ??
                        _defaultWriterSaveName(lane, block, fallback);
                    final created = createWriterSaveEntry(
                      name,
                      projectId,
                      fallback,
                      rootOrder++,
                    );
                    oldToNew[oldId] = created;
                    newById[created.id] = created;
                    return created;
                  }();
              return block.copyWith(saveId: fork.id, embedded: fallback);
            }).toList(),
          );
        }).toList(),
      );
    }).toList();
    final remapped = saved.copyWith(sections: sections);
    return (project: remapped, saves: newById);
  }

  /// Returns a Writer snapshot with every live canonical save copied into its
  /// block fallback. Named Song versions should use this before they are saved.
  SongwriterProjectSnapshot materializeCurrentContent() {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return state;
    final saveState = ref.read(saveSystemProvider);
    final ids = <String, String>{};
    final snapshots = <String, InstrumentSnapshot>{};
    for (final section in state.sections) {
      for (final lane in section.lanes) {
        for (final block in lane.blocks) {
          final saveId = block.saveId;
          if (saveId == null) continue;
          final save = resolveSaveInProject(saveState, projectId, saveId);
          if (save == null) continue;
          ids[block.id] = saveId;
          snapshots[block.id] = save.snapshot;
        }
      }
    }
    return _applyCanonicalSnapshots(state, ids, snapshots);
  }

  /// Reconciles the active Writer project after startup or project selection.
  /// The operation is idempotent and commits its three persisted payloads as
  /// one Writer save transaction.
  Future<void> reconcileCurrentProject() async {
    if (ref.read(saveSystemProvider).selectedProjectId == null) return;
    await _commitWriterStateWithoutHistory(
      state,
      detectReconciliationConflicts: true,
    );
  }

  Future<void> acknowledgeWriterReconciliationConflicts(
    String projectId,
  ) async {
    if (ref.read(saveSystemProvider).selectedProjectId != projectId) return;
    await _commitWriterStateWithoutHistory(
      state,
      clearReconciliationMarkers: true,
    );
    ref.read(writerReconciliationConflictsProvider.notifier).state = ref
        .read(writerReconciliationConflictsProvider)
        .where((conflict) => conflict.projectId != projectId)
        .toList();
  }

  /// Suppresses history while the prepared snapshot is published in memory.
  /// The persistence transaction completes asynchronously; keeping history
  /// suppressed while it drains would discard edits made in the meantime.
  Future<void> _commitWriterStateWithoutHistory(
    SongwriterProjectSnapshot next, {
    Map<String, String> saveNames = const {},
    Map<String, SaveEntry> adoptSaves = const {},
    String? bindSaveId,
    String? rebaselineSaveId,
    bool resetBinding = false,
    bool detectReconciliationConflicts = false,
    bool clearReconciliationMarkers = false,
  }) {
    final wasSuppressed = _suppressHistory;
    _suppressHistory = true;
    try {
      return _commitWriterState(
        next,
        saveNames: saveNames,
        adoptSaves: adoptSaves,
        bindSaveId: bindSaveId,
        rebaselineSaveId: rebaselineSaveId,
        resetBinding: resetBinding,
        detectReconciliationConflicts: detectReconciliationConflicts,
        clearReconciliationMarkers: clearReconciliationMarkers,
      );
    } finally {
      _suppressHistory = wasSuppressed;
    }
  }
}

final songwriterProvider =
    NotifierProvider<SongwriterNotifier, SongwriterProjectSnapshot>(
      SongwriterNotifier.new,
    );
