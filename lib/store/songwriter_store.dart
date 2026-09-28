/// Songwriter project Riverpod store with per-project session auto-save.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails, ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/harmony_lane_instrument.dart';
import '../models/piano.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../models/song_project.dart';
import '../models/songwriter.dart';
import '../schema/rules/save_system_rules.dart';
import '../schema/rules/fretboard_rules.dart' show tunings;
import '../schema/rules/piano_rules.dart' as piano_rules;
import '../schema/rules/songwriter_rules.dart';
import '../schema/rules/songwriter_segment_rules.dart';
import '../schema/rules/songwriter_slice_rules.dart';
import '../schema/rules/songwriter_third_above_rules.dart';
import '../schema/rules/songwriter_voicing_rules.dart';
import '../utils/note_utils.dart';
import 'save_system_store.dart';
import 'fretboard_store.dart' show fretboardProvider;
import 'piano_store.dart' show pianoProvider;
import 'settings_store.dart';
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

class HarmonyChordMutationResult {
  const HarmonyChordMutationResult({
    required this.success,
    this.blockId,
    this.harmonyInstrument,
    this.errorMessage,
  });

  final bool success;
  final String? blockId;
  final HarmonyLaneInstrument? harmonyInstrument;
  final String? errorMessage;
}

class HarmonyInstrumentEditResult {
  const HarmonyInstrumentEditResult({
    required this.success,
    this.snapshot,
    this.errorMessage,
  });

  final bool success;
  final HarmonyChordSnapshot? snapshot;
  final String? errorMessage;
}

class _RemovedWriterFolderSubtree {
  const _RemovedWriterFolderSubtree({
    required this.folders,
    required this.saveLocations,
  });

  final List<SaveFolder> folders;
  final Map<String, (String, int)> saveLocations;
}

class SongwriterNotifier extends Notifier<SongwriterProjectSnapshot> {
  bool _hydrating = false;
  bool _suppressHistory = false;
  SongwriterProjectSnapshot? _trackedState;
  final Map<String, _RemovedWriterFolderSubtree> _removedWriterFolderSubtrees =
      {};
  final ProjectSnapshotHistory<SongwriterProjectSnapshot> _history =
      ProjectSnapshotHistory();

  String? lastHarmonyMutationError;

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

  HarmonyLaneInstrument get projectDefaultHarmonyInstrumentForSelectedProject {
    final saveState = ref.read(saveSystemProvider);
    final projectId = saveState.selectedProjectId;
    final project = projectId == null
        ? null
        : saveState.folders
              .where((folder) => folder.id == projectId)
              .firstOrNull;
    return project?.projectConfig?.defaultHarmonyInstrument ??
        ref.read(settingsProvider).defaultNewProjectHarmonyInstrument ??
        HarmonyLaneInstrument.fretboard;
  }

  /// Returns the persisted instrument for a destination Harmony Lane. A null
  /// [laneId] resolves to the primary existing lane, or the project default
  /// when the section has no Harmony Lane yet.
  HarmonyLaneInstrument? harmonyInstrumentForLane({
    required String sectionId,
    String? laneId,
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    if (section == null) return null;
    final lane = laneId == null
        ? section.lanes
              .where((candidate) => candidate.kind == SongLaneKind.harmony)
              .firstOrNull
        : section.lanes
              .where(
                (candidate) =>
                    candidate.id == laneId &&
                    candidate.kind == SongLaneKind.harmony,
              )
              .firstOrNull;
    return lane?.harmonyInstrument ??
        projectDefaultHarmonyInstrumentForSelectedProject;
  }

  /// Authors a chord and its native realization before publishing any Writer
  /// state. When [laneId] is null, the existing primary Harmony Lane is used;
  /// if the section has none, a default-instrument lane is staged and only
  /// committed after the chord can be realized.
  HarmonyChordMutationResult addHarmonyChord({
    required String sectionId,
    String? laneId,
    required SongBlock block,
    String? saveName,
  }) {
    lastHarmonyMutationError = null;
    final sectionIndex = state.sections.indexWhere(
      (section) => section.id == sectionId,
    );
    if (sectionIndex < 0 || block.isSilent) {
      return _harmonyMutationFailure('Choose a valid Harmony bar.');
    }
    final section = state.sections[sectionIndex];
    final existingLane = laneId == null
        ? section.lanes
              .where((lane) => lane.kind == SongLaneKind.harmony)
              .firstOrNull
        : section.lanes
              .where(
                (lane) =>
                    lane.id == laneId && lane.kind == SongLaneKind.harmony,
              )
              .firstOrNull;
    if (laneId != null && existingLane == null) {
      return _harmonyMutationFailure(
        'That Harmony Lane is no longer available.',
      );
    }
    if (block.startBar < 0 ||
        block.spanBars < 1 ||
        block.startBar >= section.lengthBars ||
        _blocksById(state).containsKey(block.id)) {
      return _harmonyMutationFailure('Choose a valid Harmony bar.');
    }
    final instrument =
        existingLane?.harmonyInstrument ??
        projectDefaultHarmonyInstrumentForSelectedProject;
    final lane =
        existingLane ??
        makeLane(
          kind: SongLaneKind.harmony,
          order: section.lanes.length,
          harmonyInstrument: instrument,
        );
    if (blocksOverlap(lane.blocks, block)) {
      return _harmonyMutationFailure('That bar already contains a chord.');
    }
    // Add chord always authors a new canonical Save. A caller may pass a
    // block copied from another placement, but that binding must not turn this
    // creation into an edit of the source Save.
    final newBlock = block.copyWith(clearSaveId: true);
    final writerBlock = _writerSnapshotFromBlock(state, lane, newBlock);
    if (writerBlock == null || !_hasChordContent(writerBlock)) {
      return _harmonyMutationFailure('Choose a chord before adding it.');
    }
    final composite = _buildHarmonyChordSnapshot(
      writerBlock,
      existing: newBlock.embedded,
      instrument: instrument,
    );
    if (composite == null) {
      return _harmonyMutationFailure(
        lastHarmonyMutationError ??
            'Could not create a playable realization for this chord.',
        instrument: instrument,
      );
    }

    final placed = newBlock.copyWith(embedded: composite);
    final updatedLane = lane.copyWith(
      harmonyInstrument: instrument,
      blocks: [...lane.blocks, placed],
    );
    final lanes = [...section.lanes];
    final laneIndex = lanes.indexWhere((candidate) => candidate.id == lane.id);
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
        if (saveName != null && saveName.trim().isNotEmpty) placed.id: saveName,
      },
    );
    return HarmonyChordMutationResult(
      success: true,
      blockId: placed.id,
      harmonyInstrument: instrument,
    );
  }

  HarmonyChordMutationResult _harmonyMutationFailure(
    String message, {
    HarmonyLaneInstrument? instrument,
  }) {
    lastHarmonyMutationError = message;
    return HarmonyChordMutationResult(
      success: false,
      harmonyInstrument: instrument,
      errorMessage: message,
    );
  }

  /// Adds a secondary Harmony Lane with its instrument chosen explicitly.
  /// Sections normally start with a project-default primary Harmony Lane, so
  /// this method refuses to create an explicit-instrument primary lane for a
  /// malformed or legacy section that has none.
  String? addHarmonyLane({
    required String sectionId,
    required HarmonyLaneInstrument harmonyInstrument,
    String? label,
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    if (section == null ||
        !section.lanes.any((lane) => lane.kind == SongLaneKind.harmony)) {
      return null;
    }
    return addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: label,
      harmonyInstrument: harmonyInstrument,
    );
  }

  /// Validates an edited native half and returns a standalone-ready composite
  /// that retains the canonical Writer chord. This method has no side effects;
  /// callers can save its result as a project-root Save without changing any
  /// Writer placement or link.
  HarmonyInstrumentEditResult buildStandaloneHarmonySaveSnapshot({
    required String saveId,
    required InstrumentSnapshot snapshot,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) {
      return const HarmonyInstrumentEditResult(
        success: false,
        errorMessage: 'Select a project before saving this chord.',
      );
    }
    final existing = resolveSaveInProject(
      ref.read(saveSystemProvider),
      projectId,
      saveId,
    )?.snapshot;
    if (existing is! HarmonyChordSnapshot) {
      return const HarmonyInstrumentEditResult(
        success: false,
        errorMessage: 'This is not a compatible Harmony chord save.',
      );
    }
    if (snapshot is HarmonyChordSnapshot &&
        snapshot.harmonyInstrument != existing.harmonyInstrument) {
      return const HarmonyInstrumentEditResult(
        success: false,
        errorMessage: 'The edited instrument does not match this Harmony save.',
      );
    }
    final native = snapshot is HarmonyChordSnapshot
        ? snapshot.instrumentState
        : snapshot;
    final normalized = _validatedHarmonyInstrumentEdit(existing, native);
    if (normalized == null) {
      return HarmonyInstrumentEditResult(
        success: false,
        errorMessage: lastHarmonyMutationError,
      );
    }
    return HarmonyInstrumentEditResult(success: true, snapshot: normalized);
  }

  /// Saves an edited linked Harmony chord as a new manual project-root Save.
  /// The source Save and all Writer placements remain unchanged.
  String? saveStandaloneHarmonyEdit({
    required String sourceSaveId,
    required String name,
    required InstrumentSnapshot snapshot,
  }) {
    lastHarmonyMutationError = null;
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) {
      lastHarmonyMutationError = 'Select a project before saving this chord.';
      return null;
    }
    final validation = buildStandaloneHarmonySaveSnapshot(
      saveId: sourceSaveId,
      snapshot: snapshot,
    );
    if (!validation.success || validation.snapshot == null) {
      lastHarmonyMutationError = validation.errorMessage;
      return null;
    }
    final saveState = ref.read(saveSystemProvider);
    final project = saveState.folders
        .where((folder) => folder.id == projectId)
        .firstOrNull;
    if (project?.kind != SaveFolderKind.project) {
      lastHarmonyMutationError = 'Select a project before saving this chord.';
      return null;
    }
    final saveId = ref
        .read(saveSystemProvider.notifier)
        .saveSnapshot(name, projectId, validation.snapshot!);
    if (saveId == null) {
      lastHarmonyMutationError = ref
          .read(saveSystemProvider.notifier)
          .lastMutationError;
    }
    return saveId;
  }

  /// Copies a canonical Harmony chord Save to the project root without
  /// changing its source Save or any Writer placement/link.
  String? createStandaloneHarmonySave({
    required String sourceSaveId,
    required String name,
  }) {
    lastHarmonyMutationError = null;
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) {
      lastHarmonyMutationError = 'Select a project before saving this chord.';
      return null;
    }
    final saveState = ref.read(saveSystemProvider);
    final project = saveState.folders
        .where((folder) => folder.id == projectId)
        .firstOrNull;
    final source = resolveSaveInProject(saveState, projectId, sourceSaveId);
    if (project?.kind != SaveFolderKind.project ||
        source?.snapshot is! HarmonyChordSnapshot) {
      lastHarmonyMutationError = 'This is not a compatible Harmony chord save.';
      return null;
    }
    final saveId = ref
        .read(saveSystemProvider.notifier)
        .saveSnapshot(name, projectId, source!.snapshot);
    if (saveId == null) {
      lastHarmonyMutationError = ref
          .read(saveSystemProvider.notifier)
          .lastMutationError;
    }
    return saveId;
  }

  /// Replaces one Harmony placement with a compatible composite Save. The
  /// selected Save remains canonical, and all timing, lane, lyrics, repeats,
  /// and other placement-local data stay on the existing block.
  bool replaceHarmonyBlockWithSave({
    required String sectionId,
    required String laneId,
    required String blockId,
    required String saveId,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return false;
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where((candidate) => candidate.id == laneId)
        .firstOrNull;
    final block = lane?.blocks
        .where((candidate) => candidate.id == blockId)
        .firstOrNull;
    if (section == null ||
        lane?.kind != SongLaneKind.harmony ||
        block == null) {
      return false;
    }
    final save = resolveSaveInProject(
      ref.read(saveSystemProvider),
      projectId,
      saveId,
    );
    final snapshot = save?.snapshot;
    if (snapshot is! HarmonyChordSnapshot ||
        snapshot.harmonyInstrument !=
            (lane!.harmonyInstrument ??
                projectDefaultHarmonyInstrumentForSelectedProject)) {
      lastHarmonyMutationError =
          'Choose a Harmony save made for this lane’s instrument.';
      return false;
    }
    final normalized = _validatedHarmonyInstrumentEdit(
      snapshot,
      snapshot.instrumentState,
    );
    if (normalized == null) return false;
    final writerBlock = normalized.writerBlock;
    _replaceLane(sectionId, laneId, (currentLane) {
      if (currentLane.kind != SongLaneKind.harmony) return currentLane;
      return currentLane.copyWith(
        blocks: [
          for (final currentBlock in currentLane.blocks)
            if (currentBlock.id == blockId)
              currentBlock.copyWith(
                saveId: saveId,
                embedded: normalized,
                chordSymbol: writerBlock.chordSymbol,
                chordQuality: writerBlock.chordQuality,
                chordRootPc: writerBlock.chordRootPc,
                chordNotes: writerBlock.chordNotes,
                romanNumeral: writerBlock.romanNumeral,
                clearRomanNumeral: writerBlock.romanNumeral == null,
                isSilent: writerBlock.isSilent,
              )
            else
              currentBlock,
        ],
      );
    });
    return true;
  }

  HarmonyChordSnapshot? _validatedHarmonyInstrumentEdit(
    HarmonyChordSnapshot canonical,
    InstrumentSnapshot native,
  ) {
    lastHarmonyMutationError = null;
    final matchesInstrument = switch (canonical.harmonyInstrument) {
      HarmonyLaneInstrument.fretboard => native is FretboardSnapshot,
      HarmonyLaneInstrument.piano => native is PianoSnapshot,
    };
    if (!matchesInstrument) {
      lastHarmonyMutationError =
          'Choose ${canonical.harmonyInstrument.name} for this Harmony Lane.';
      return null;
    }
    final expected = _harmonyPitchClasses(canonical.writerBlock);
    final actual = _selectedPitchClasses(native);
    if (expected == null ||
        actual == null ||
        !_samePitchClassSet(actual, expected)) {
      lastHarmonyMutationError =
          'The instrument notes must match ${canonical.writerBlock.chordSymbol ?? 'the saved chord'}.';
      return null;
    }
    return HarmonyChordSnapshot(
      harmonyInstrument: canonical.harmonyInstrument,
      writerBlock: canonical.writerBlock,
      instrumentState: _withPendingChord(native, canonical.writerBlock),
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
    lastHarmonyMutationError = null;
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
      if (lastHarmonyMutationError != null) return Future<void>.value();
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
          restoredWriterSaveLocations: prepared.restoredWriterSaveLocations,
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
    Map<String, (String, int)> restoredWriterSaveLocations,
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
    final removedFolderIds = <String>{};
    for (final removed in previous.sections.where(
      (section) => !sectionIds.contains(section.id),
    )) {
      final folder = getWriterSectionFolder(saveState, projectId, removed.id);
      if (folder != null) {
        final subtreeIds = getSubtreeFolderIds(saveState.folders, folder.id);
        removedFolderIds.addAll(subtreeIds);
        _removedWriterFolderSubtrees['$projectId/${removed.id}'] =
            _RemovedWriterFolderSubtree(
              folders: saveState.folders
                  .where((candidate) => subtreeIds.contains(candidate.id))
                  .toList(),
              saveLocations: {
                for (final save in saveState.saves)
                  if (save.origin == SaveOrigin.writer &&
                      subtreeIds.contains(save.folderId))
                    save.id: (save.folderId, save.order),
              },
            );
      }
    }
    var folders = saveState.folders.where((folder) {
      if (!isFolderInProject(saveState.folders, folder.id, projectId)) {
        return true;
      }
      return !removedFolderIds.contains(folder.id) &&
          (folder.writerSectionId == null ||
              sectionIds.contains(folder.writerSectionId));
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
      final removedStructure =
          _removedWriterFolderSubtrees['$projectId/${section.id}'];
      final cachedRoot = removedStructure?.folders
          .where(
            (folder) =>
                folder.parentId == projectId &&
                folder.writerSectionId == section.id &&
                folder.writerLaneKind == null,
          )
          .firstOrNull;
      final folder =
          existingFolder?.copyWith(name: displayName, order: section.order) ??
          cachedRoot?.copyWith(name: displayName, order: section.order) ??
          createWriterSectionFolder(
            candidate,
            projectId: projectId,
            sectionId: section.id,
            name: displayName,
            order: section.order,
          );
      if (existingFolder == null &&
          removedStructure != null &&
          cachedRoot != null) {
        final removedIds = removedStructure.folders
            .map((removedFolder) => removedFolder.id)
            .toSet();
        folders = [
          ...folders.where((existing) => !removedIds.contains(existing.id)),
          for (final removedFolder in removedStructure.folders)
            if (removedFolder.id == folder.id) folder else removedFolder,
        ];
      } else {
        folders = [
          ...folders.where((existing) => existing.id != folder.id),
          folder,
        ];
      }
      candidate = candidate.copyWith(folders: folders);
    }

    // Writer links live in a stable child folder for each lane kind. Stage all
    // category folders before building links so the transaction validates the
    // complete tree and never points at a section root.
    for (final section in proposed.sections) {
      final sectionFolder = getWriterSectionFolder(
        candidate,
        projectId,
        section.id,
      );
      if (sectionFolder == null) continue;
      final laneKinds = section.lanes.map((lane) => lane.kind).toSet();
      for (final laneKind in laneKinds) {
        if (getWriterLaneCategoryFolder(
              candidate,
              projectId: projectId,
              sectionId: section.id,
              laneKind: laneKind,
            ) !=
            null) {
          continue;
        }
        final category = getOrCreateWriterLaneFolder(
          candidate,
          projectId: projectId,
          sectionId: section.id,
          laneKind: laneKind,
          sectionFolder: sectionFolder,
        );
        folders = [...candidate.folders, category];
        candidate = candidate.copyWith(folders: folders);
      }
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
    final localOnlyHarmonyBlockIds = <String>{};
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
        final categoryFolder = getWriterLaneCategoryFolder(
          candidate,
          projectId: projectId,
          sectionId: section.id,
          laneKind: lane.kind,
        );
        if (categoryFolder == null) continue;
        for (final block in lane.blocks) {
          final blockId = block.id;
          final oldLocation = previousBlocks[blockId];
          final oldBlock = oldLocation?.$3;
          final oldLane = oldLocation?.$2;
          final oldContent = oldBlock == null || oldLane == null
              ? null
              : _contentSnapshot(previous, oldLane, oldBlock);
          var liveContent = _contentSnapshot(proposed, lane, block);
          if (lane.kind == SongLaneKind.harmony &&
              liveContent is WriterBlockSnapshot &&
              !_hasChordContent(liveContent)) {
            // Empty/silent Harmony placeholders carry Writer placement and
            // lyrics only. They have no instrument-bound chord Save to link.
            localOnlyHarmonyBlockIds.add(blockId);
            continue;
          }
          if (lane.kind == SongLaneKind.harmony &&
              !block.isSilent &&
              block.chordRootPc != null &&
              block.chordQuality != null &&
              block.chordNotes.isNotEmpty &&
              liveContent is! HarmonyChordSnapshot) {
            lastHarmonyMutationError ??=
                'Could not create a playable realization for this chord.';
            return null;
          }

          final legacyDetached =
              oldBlock != null &&
              isLegacyDetachedWriterBlock(block, saveState.writerLinks) &&
              !adoptSaves.containsKey(block.saveId);
          final linkedSaveId = block.saveId;
          final originalSave = linkedSaveId == null
              ? null
              : resolveSaveInProject(saveState, projectId, linkedSaveId);
          var existing = originalSave == null
              ? adoptSaves[linkedSaveId]
              : (nextSaves[originalSave.id] ?? originalSave);
          final isSaveRebind =
              oldBlock != null && oldBlock.saveId != block.saveId;
          if (lane.kind == SongLaneKind.harmony &&
              (existing?.snapshot is! HarmonyChordSnapshot ||
                  (existing!.snapshot as HarmonyChordSnapshot)
                          .harmonyInstrument !=
                      (lane.harmonyInstrument ??
                          projectDefaultHarmonyInstrumentForSelectedProject))) {
            // A symbolic legacy save has no instrument identity. Never mutate
            // or silently reuse it as an instrument-bound Harmony save.
            existing = null;
          }
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
              !isSaveRebind &&
              !legacyDetached &&
              !_jsonEqual(
                existing.snapshot.toJson(),
                reconciliationFallback.toJson(),
              );
          final liveWriterBlock = _writerBlockOf(liveContent);
          final existingWriterBlock = _writerBlockOf(existing?.snapshot);
          if (liveWriterBlock != null && existingWriterBlock != null) {
            liveContent = _replaceWriterBlock(
              liveContent!,
              _copyWriterBlockSnapshot(
                liveWriterBlock,
                defaultLyrics: existingWriterBlock.defaultLyrics,
              ),
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
            if (isContentChanged && !isSaveRebind) {
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
              categoryFolder.id,
            );
            save = createWriterSaveEntry(
              name,
              categoryFolder.id,
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
              folderId: categoryFolder.id,
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

    // Undoing a section removal restores its category tree and the previous
    // physical folder for linked saves. Keep the live Save content and name;
    // only restore its folder ownership and order.
    final linkedSaveIds = links.map((link) => link.saveId).toSet();
    final restoredWriterSaveLocations = <String, (String, int)>{};
    for (final section in proposed.sections) {
      final removedStructure =
          _removedWriterFolderSubtrees['$projectId/${section.id}'];
      if (removedStructure == null) continue;
      for (final entry in removedStructure.saveLocations.entries) {
        final save = nextSaves[entry.key];
        final (folderId, order) = entry.value;
        if (save == null ||
            save.origin != SaveOrigin.writer ||
            !linkedSaveIds.contains(save.id) ||
            !candidate.folders.any((folder) => folder.id == folderId)) {
          continue;
        }
        restoredWriterSaveLocations[save.id] = (folderId, order);
      }
    }

    final reconciledInput = localOnlyHarmonyBlockIds.isEmpty
        ? proposed
        : proposed.copyWith(
            sections: [
              for (final section in proposed.sections)
                section.copyWith(
                  lanes: [
                    for (final lane in section.lanes)
                      lane.copyWith(
                        blocks: [
                          for (final block in lane.blocks)
                            if (localOnlyHarmonyBlockIds.contains(block.id))
                              block.copyWith(
                                clearSaveId: true,
                                clearEmbedded: true,
                              )
                            else
                              block,
                        ],
                      ),
                  ],
                ),
            ],
          );
    final reconciled = _applyCanonicalSnapshots(
      reconciledInput,
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
        .buildWriterStructure(
          projectId,
          candidate,
          restoredWriterSaveLocations: restoredWriterSaveLocations,
        );
    if (preparedSaveState == null) return null;
    return (
      project: reconciled,
      saveSystem: preparedSaveState,
      conflicts: conflicts,
      restoredWriterSaveLocations: restoredWriterSaveLocations,
    );
  }

  InstrumentSnapshot? _normalizeReconciliationFallback(
    SongLane lane,
    SongBlock block,
    InstrumentSnapshot? fallback,
    InstrumentSnapshot? canonical,
  ) {
    final fallbackWriter = _writerBlockOf(fallback);
    final canonicalWriter = _writerBlockOf(canonical);
    if (fallbackWriter == null ||
        canonicalWriter == null ||
        (_writerBlockOf(block.embedded)?.laneKind == lane.kind)) {
      return fallback;
    }

    // Without an embedded cache, block.lyrics are placement-local. Preserve
    // the canonical default seed in the comparison while comparing all
    // musical content retained by the Writer fields and pattern references.
    return _replaceWriterBlock(
      fallback!,
      _copyWriterBlockSnapshot(
        fallbackWriter,
        defaultLyrics: canonicalWriter.defaultLyrics,
      ),
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
  ) {
    if (lane.kind == SongLaneKind.save) return block.embedded;
    if (lane.kind != SongLaneKind.harmony) {
      return writerBlockSnapshotFor(project, lane, block);
    }
    final writerBlock = _writerSnapshotFromBlock(project, lane, block);
    if (writerBlock == null || !_hasChordContent(writerBlock)) {
      return writerBlock;
    }
    final instrument =
        lane.harmonyInstrument ??
        projectDefaultHarmonyInstrumentForSelectedProject;
    InstrumentSnapshot? saved = block.embedded;
    if (saved is! HarmonyChordSnapshot && block.saveId != null) {
      final projectId = ref.read(saveSystemProvider).selectedProjectId;
      if (projectId != null) {
        saved = resolveSaveInProject(
          ref.read(saveSystemProvider),
          projectId,
          block.saveId!,
        )?.snapshot;
      }
    }
    return _buildHarmonyChordSnapshot(
      writerBlock,
      existing: saved,
      instrument: instrument,
    );
  }

  WriterBlockSnapshot? _writerSnapshotFromBlock(
    SongwriterProjectSnapshot project,
    SongLane lane,
    SongBlock block,
  ) {
    final fallback = _writerBlockOf(block.embedded);
    if (lane.kind != SongLaneKind.harmony) {
      return writerBlockSnapshotFor(project, lane, block);
    }
    if (fallback != null &&
        fallback.laneKind == SongLaneKind.harmony &&
        block.chordSymbol == null &&
        block.chordQuality == null &&
        block.chordRootPc == null &&
        block.chordNotes.isEmpty &&
        !block.isSilent &&
        (fallback.isSilent || fallback.chordSymbol != null)) {
      return fallback;
    }
    return WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      isSilent: block.isSilent,
      chordSymbol: block.chordSymbol,
      chordQuality: block.chordQuality,
      chordRootPc: block.chordRootPc,
      chordNotes: block.chordNotes,
      romanNumeral: block.romanNumeral,
      defaultLyrics: fallback?.laneKind == SongLaneKind.harmony
          ? fallback!.defaultLyrics
          : block.lyrics,
    );
  }

  WriterBlockSnapshot? _writerBlockOf(InstrumentSnapshot? snapshot) =>
      switch (snapshot) {
        HarmonyChordSnapshot(:final writerBlock) => writerBlock,
        final WriterBlockSnapshot writerBlock => writerBlock,
        _ => null,
      };

  InstrumentSnapshot _replaceWriterBlock(
    InstrumentSnapshot snapshot,
    WriterBlockSnapshot writerBlock,
  ) => switch (snapshot) {
    HarmonyChordSnapshot(:final harmonyInstrument, :final instrumentState) =>
      HarmonyChordSnapshot(
        harmonyInstrument: harmonyInstrument,
        writerBlock: writerBlock,
        instrumentState: instrumentState,
      ),
    _ => writerBlock,
  };

  bool _hasChordContent(WriterBlockSnapshot snapshot) =>
      !snapshot.isSilent &&
      snapshot.chordRootPc != null &&
      snapshot.chordQuality != null &&
      snapshot.chordNotes.isNotEmpty;

  Set<int>? _harmonyPitchClasses(WriterBlockSnapshot writerBlock) {
    final pitchClasses = <int>{};
    for (final note in writerBlock.chordNotes) {
      final pitchClass = noteToPC[toSharp(note)];
      if (pitchClass == null) return null;
      pitchClasses.add(pitchClass);
    }
    final rootPc = writerBlock.chordRootPc;
    final quality = writerBlock.chordQuality;
    if (rootPc == null || quality == null || pitchClasses.isEmpty) return null;
    final intervals = chordIntervals[quality];
    if (intervals == null) return null;
    final expected = {
      for (final interval in intervals) (rootPc + interval) % 12,
    };
    return _samePitchClassSet(pitchClasses, expected) ? pitchClasses : null;
  }

  bool _samePitchClassSet(Set<int> left, Set<int> right) =>
      left.length == right.length && left.containsAll(right);

  Set<int>? _selectedPitchClasses(InstrumentSnapshot snapshot) {
    final pitchClasses = <int>{};
    switch (snapshot) {
      case PianoSnapshot():
        final range = piano_rules.pianoRanges[snapshot.currentRange];
        if (range == null || snapshot.selectedKeys.isEmpty) return null;
        for (final key in snapshot.selectedKeys) {
          if (key.midiNote < range.startMidi || key.midiNote > range.endMidi) {
            return null;
          }
          pitchClasses.add(((key.midiNote % 12) + 12) % 12);
        }
      case FretboardSnapshot():
        final tuning = tunings[snapshot.tuning];
        if (tuning == null || snapshot.selectedCells.isEmpty) return null;
        for (final cell in snapshot.selectedCells) {
          if (cell.stringIndex < 0 ||
              cell.stringIndex >= tuning.strings.length ||
              cell.fret < snapshot.capo ||
              cell.fret > snapshot.numFrets) {
            return null;
          }
          final midi = tuning.strings[cell.stringIndex].midiNote + cell.fret;
          pitchClasses.add(((midi % 12) + 12) % 12);
        }
      default:
        return null;
    }
    return pitchClasses;
  }

  PendingChord? _pendingChordFor(WriterBlockSnapshot writerBlock) {
    final rootPc = writerBlock.chordRootPc;
    final quality = writerBlock.chordQuality;
    if (rootPc == null || quality == null) return null;
    final root = chromaticNotes[((rootPc % 12) + 12) % 12];
    return PendingChord(
      root: root,
      quality: quality,
      symbol: writerBlock.chordSymbol ?? '$root$quality',
    );
  }

  HarmonyChordSnapshot? _buildHarmonyChordSnapshot(
    WriterBlockSnapshot writerBlock, {
    required HarmonyLaneInstrument instrument,
    InstrumentSnapshot? existing,
  }) {
    final chordPcs = _harmonyPitchClasses(writerBlock);
    if (chordPcs == null) {
      lastHarmonyMutationError =
          'This chord has incomplete or unsupported pitch data.';
      return null;
    }
    final composite =
        existing is HarmonyChordSnapshot &&
            existing.harmonyInstrument == instrument
        ? existing
        : null;
    final oldNative = composite?.instrumentState;
    if (oldNative != null) {
      final oldPcs = _selectedPitchClasses(oldNative);
      if (oldPcs != null && _samePitchClassSet(oldPcs, chordPcs)) {
        return HarmonyChordSnapshot(
          harmonyInstrument: instrument,
          writerBlock: writerBlock,
          instrumentState: _withPendingChord(oldNative, writerBlock),
        );
      }
    }

    final native = _realizeHarmonyChord(
      writerBlock,
      instrument: instrument,
      existing: oldNative,
    );
    if (native == null) return null;
    return HarmonyChordSnapshot(
      harmonyInstrument: instrument,
      writerBlock: writerBlock,
      instrumentState: _withPendingChord(native, writerBlock),
    );
  }

  InstrumentSnapshot? _realizeHarmonyChord(
    WriterBlockSnapshot writerBlock, {
    required HarmonyLaneInstrument instrument,
    InstrumentSnapshot? existing,
  }) {
    final rootPc = writerBlock.chordRootPc!;
    final quality = writerBlock.chordQuality!;
    final pendingChord = _pendingChordFor(writerBlock);
    switch (instrument) {
      case HarmonyLaneInstrument.piano:
        final current = ref.read(pianoProvider);
        final rangeName = existing is PianoSnapshot
            ? existing.currentRange
            : current.currentRange;
        final range = piano_rules.pianoRanges[rangeName]!;
        final keys = piano_rules.getKeysForRange(rangeName);
        final keyByMidi = {for (final key in keys) key.midiNote: key};
        final intervals = chordIntervals[quality];
        if (intervals == null) {
          lastHarmonyMutationError =
              'This chord quality cannot be realized on Piano.';
          return null;
        }
        final uniqueIntervals = <int>[];
        final seenPcs = <int>{};
        for (final interval in intervals) {
          if (seenPcs.add((rootPc + interval) % 12)) {
            uniqueIntervals.add(interval);
          }
        }
        final rootCandidates =
            [
              for (var midi = range.startMidi; midi <= range.endMidi; midi++)
                if (midi % 12 == rootPc) midi,
            ]..sort((left, right) {
              final leftPreferred = left >= 60 ? 0 : 1;
              final rightPreferred = right >= 60 ? 0 : 1;
              final preference = leftPreferred.compareTo(rightPreferred);
              if (preference != 0) return preference;
              return (left - 60).abs().compareTo((right - 60).abs());
            });
        final rootMidi = rootCandidates.firstWhere(
          (candidate) => uniqueIntervals.every(
            (interval) => keyByMidi.containsKey(candidate + interval),
          ),
          orElse: () => -1,
        );
        if (rootMidi < 0) {
          lastHarmonyMutationError =
              'The selected Piano range does not contain this chord.';
          return null;
        }
        final selected = <PianoCoordinate>[];
        for (final interval in uniqueIntervals) {
          final midi = (rootMidi + interval);
          final key = keyByMidi[midi];
          if (key == null) {
            lastHarmonyMutationError =
                'The selected Piano range does not contain this chord.';
            return null;
          }
          selected.add(
            PianoCoordinate(
              keyIndex: key.keyIndex,
              midiNote: key.midiNote,
              noteName: key.noteName,
            ),
          );
        }
        return PianoSnapshot(
          currentRange: rangeName,
          selectedKeys: selected,
          selectedNotes: [for (final pc in seenPcs) chromaticNotes[pc]],
          viewMode: existing is PianoSnapshot
              ? existing.viewMode
              : current.viewMode,
          pendingChord: pendingChord,
        );
      case HarmonyLaneInstrument.fretboard:
        final current = ref.read(fretboardProvider);
        final tuning = existing is FretboardSnapshot
            ? existing.tuning
            : current.currentTuning;
        final capo = existing is FretboardSnapshot
            ? existing.capo
            : current.capo;
        final numFrets = existing is FretboardSnapshot
            ? existing.numFrets
            : current.numFrets;
        final suggestions = suggestPlayableVoicings(
          chordRootPc: rootPc,
          quality: quality,
          tuning: tuning,
          capo: capo,
          numFrets: numFrets,
          maxResults: 1,
        );
        if (suggestions.isEmpty) {
          final tuningName = tunings[tuning]?.displayName ?? tuning.name;
          lastHarmonyMutationError =
              'No playable $tuningName Fretboard shape fits '
              '${writerBlock.chordSymbol ?? 'this chord'} with capo $capo '
              'and frets $capo–$numFrets. Adjust the tuning, capo, or fret range.';
          return null;
        }
        return voicingToSnapshot(suggestions.first);
    }
  }

  InstrumentSnapshot _withPendingChord(
    InstrumentSnapshot snapshot,
    WriterBlockSnapshot writerBlock,
  ) {
    final pending = _pendingChordFor(writerBlock);
    return switch (snapshot) {
      FretboardSnapshot() => FretboardSnapshot(
        tuning: snapshot.tuning,
        numFrets: snapshot.numFrets,
        capo: snapshot.capo,
        selectedCells: snapshot.selectedCells,
        selectedNotes: snapshot.selectedNotes,
        viewMode: snapshot.viewMode,
        pendingChord: pending,
        pendingScale: snapshot.pendingScale,
      ),
      PianoSnapshot() => PianoSnapshot(
        currentRange: snapshot.currentRange,
        selectedKeys: snapshot.selectedKeys,
        selectedNotes: snapshot.selectedNotes,
        viewMode: snapshot.viewMode,
        pendingChord: pending,
        pendingScale: snapshot.pendingScale,
      ),
      _ => snapshot,
    };
  }

  bool _jsonEqual(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  String _defaultWriterSaveName(
    SongLane lane,
    SongBlock block,
    InstrumentSnapshot snapshot,
  ) {
    final writerBlock = _writerBlockOf(snapshot);
    if (writerBlock != null) {
      if (writerBlock.chordSymbol?.trim().isNotEmpty == true) {
        return writerBlock.chordSymbol!.trim();
      }
      final patternName =
          writerBlock.drumPattern?.name ??
          writerBlock.melodyPattern?.name ??
          writerBlock.guitarStrumPattern?.name;
      if (patternName != null && patternName.trim().isNotEmpty) {
        return patternName.trim();
      }
      final sourceLabel = writerBlock.audioAsset?.sourceLabel;
      if (sourceLabel != null && sourceLabel.trim().isNotEmpty) {
        return sourceLabel.trim();
      }
      if (writerBlock.isSilent) return 'Lyrics';
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
      final writerBlock = _writerBlockOf(snapshot);
      if (writerBlock == null) return updated;
      if (writerBlock.laneKind == SongLaneKind.harmony) {
        final hasChord =
            writerBlock.chordSymbol != null ||
            writerBlock.chordQuality != null ||
            writerBlock.chordRootPc != null ||
            writerBlock.chordNotes.isNotEmpty;
        updated = hasChord
            ? updated.copyWith(
                chordSymbol: writerBlock.chordSymbol,
                chordQuality: writerBlock.chordQuality,
                chordRootPc: writerBlock.chordRootPc,
                chordNotes: writerBlock.chordNotes,
                romanNumeral: writerBlock.romanNumeral,
                clearRomanNumeral: writerBlock.romanNumeral == null,
                isSilent: writerBlock.isSilent,
              )
            : updated.copyWith(
                clearChordData: true,
                isSilent: writerBlock.isSilent,
              );
      } else if (writerBlock.drumPattern case final pattern?) {
        upsert(drumPatterns, pattern.id, pattern, (item) => item.id);
        updated = updated.copyWith(
          patternId: pattern.id,
          clearAudioClipId: true,
        );
      } else if (writerBlock.melodyPattern case final pattern?) {
        upsert(melodyPatterns, pattern.id, pattern, (item) => item.id);
        updated = updated.copyWith(
          patternId: pattern.id,
          clearAudioClipId: true,
        );
      } else if (writerBlock.guitarStrumPattern case final pattern?) {
        upsert(guitarPatterns, pattern.id, pattern, (item) => item.id);
        updated = updated.copyWith(
          patternId: pattern.id,
          clearAudioClipId: true,
        );
      } else if (writerBlock.audioClip case final clip?) {
        upsert(audioClips, clip.id, clip, (item) => item.id);
        if (writerBlock.audioAsset case final asset?) {
          upsert(audioAssets, asset.id, asset, (item) => item.id);
        }
        if (writerBlock.stretchedAudioAsset case final asset?) {
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
  void addSection({String? label, required int lengthBars, String? id}) {
    final section = makeSection(
      label: label,
      lengthBars: lengthBars,
      order: state.sections.length,
      harmonyInstrument: projectDefaultHarmonyInstrumentForSelectedProject,
      id: id,
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
    HarmonyLaneInstrument? harmonyInstrument,
  }) {
    if (kind != SongLaneKind.harmony && harmonyInstrument != null) {
      throw ArgumentError.value(
        harmonyInstrument,
        'harmonyInstrument',
        'Only Harmony lanes can select a Harmony instrument.',
      );
    }
    final lane = makeLane(
      kind: kind,
      label: label,
      order: 0,
      harmonyInstrument: kind == SongLaneKind.harmony
          ? harmonyInstrument ??
                projectDefaultHarmonyInstrumentForSelectedProject
          : null,
    );
    _replaceSection(sectionId, (s) {
      final positioned = lane.copyWith(order: s.lanes.length);
      return s.copyWith(lanes: [...s.lanes, positioned]);
    });
    return lane.id;
  }

  /// Duplicates a Harmony lane and its chord placements. The copied blocks get
  /// fresh placement IDs while retaining their canonical Save IDs.
  Future<String?> duplicateHarmonyLane({
    required String sectionId,
    required String laneId,
  }) async {
    final initialSection = state.sections
        .where((section) => section.id == sectionId)
        .firstOrNull;
    final initialLane = initialSection?.lanes
        .where((lane) => lane.id == laneId && lane.kind == SongLaneKind.harmony)
        .firstOrNull;
    if (initialLane == null || initialLane.harmonyInstrument == null) {
      return null;
    }
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId != null) {
      await _commitWriterStateWithoutHistory(state);
    }
    if (projectId != ref.read(saveSystemProvider).selectedProjectId) {
      return null;
    }
    final sectionIndex = state.sections.indexWhere(
      (section) => section.id == sectionId,
    );
    if (sectionIndex < 0) return null;
    final section = state.sections[sectionIndex];
    final source = section.lanes
        .where((lane) => lane.id == laneId && lane.kind == SongLaneKind.harmony)
        .firstOrNull;
    if (source == null || source.harmonyInstrument == null) return null;

    final copiedBlocks = [
      for (final block in source.blocks) _copyHarmonyBlockForDuplicate(block),
    ];
    final harmonyCount = section.lanes
        .where((lane) => lane.kind == SongLaneKind.harmony)
        .length;
    final copy = SongLane(
      id: generateId(),
      kind: SongLaneKind.harmony,
      label: harmonyLaneFallbackLabel(harmonyCount),
      order: section.lanes.length,
      repeat: source.repeat,
      blocks: copiedBlocks,
      volume: source.volume,
      pan: source.pan,
      muted: source.muted,
      harmonyInstrument: source.harmonyInstrument,
    );
    final sections = [...state.sections];
    sections[sectionIndex] = section.copyWith(lanes: [...section.lanes, copy]);
    await _commitWriterState(state.copyWith(sections: sections));
    return copy.id;
  }

  SongBlock _copyHarmonyBlockForDuplicate(SongBlock source) => SongBlock(
    id: generateId(),
    startBar: source.startBar,
    spanBars: source.spanBars,
    saveId: source.saveId,
    embedded: source.embedded,
    chordSymbol: source.chordSymbol,
    chordQuality: source.chordQuality,
    chordRootPc: source.chordRootPc,
    chordNotes: source.chordNotes,
    romanNumeral: source.romanNumeral,
    patternId: source.patternId,
    audioClipId: source.audioClipId,
    lyrics: source.lyrics,
    isSilent: source.isSilent,
  );

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
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where((candidate) => candidate.id == laneId)
        .firstOrNull;
    if (section == null || lane == null) return;
    if (lane.kind == SongLaneKind.save &&
        !_saveLaneBlocksMatchAnchor(
          section,
          lane,
          harmonyLaneId: harmonyLaneId,
        )) {
      return;
    }
    _replaceLane(
      sectionId,
      laneId,
      (current) => harmonyLaneId == null
          ? current.copyWith(clearAnchorLaneId: true)
          : current.copyWith(anchorLaneId: harmonyLaneId),
    );
  }

  /// Whether every placed native Save in a lane can follow the selected
  /// Harmony Lane. Null selects the section's primary lane.
  bool canSetSaveLaneAnchorLane({
    required String sectionId,
    required String laneId,
    required String? harmonyLaneId,
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where(
          (candidate) =>
              candidate.id == laneId && candidate.kind == SongLaneKind.save,
        )
        .firstOrNull;
    if (section == null || lane == null) return false;
    if (harmonyLaneId != null &&
        !section.lanes.any(
          (candidate) =>
              candidate.id == harmonyLaneId &&
              candidate.kind == SongLaneKind.harmony,
        )) {
      return false;
    }
    return _saveLaneBlocksMatchAnchor(
      section,
      lane,
      harmonyLaneId: harmonyLaneId,
    );
  }

  bool canChangeHarmonyLaneInstrument({
    required String sectionId,
    required String laneId,
  }) {
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where(
          (candidate) =>
              candidate.id == laneId && candidate.kind == SongLaneKind.harmony,
        )
        .firstOrNull;
    if (section == null || lane == null || lane.blocks.isNotEmpty) return false;
    return !section.lanes.any(
      (candidate) =>
          candidate.kind == SongLaneKind.save &&
          saveAnchorLane(section, candidate)?.id == laneId,
    );
  }

  /// Changes an empty Harmony lane's native instrument while preserving its ID.
  /// Save lanes anchored to it keep that instrument contract, so they block the
  /// change even when they do not currently contain blocks.
  bool setHarmonyLaneInstrument({
    required String sectionId,
    required String laneId,
    required HarmonyLaneInstrument instrument,
  }) {
    if (!canChangeHarmonyLaneInstrument(sectionId: sectionId, laneId: laneId)) {
      return false;
    }
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .first;
    final lane = section.lanes.firstWhere(
      (candidate) => candidate.id == laneId,
    );
    if (lane.harmonyInstrument == instrument) return true;
    _replaceLane(
      sectionId,
      laneId,
      (current) => current.copyWith(harmonyInstrument: instrument),
    );
    return true;
  }

  void removeLane({required String sectionId, required String laneId}) {
    _replaceSection(sectionId, (section) {
      final removed = section.lanes
          .where((lane) => lane.id == laneId)
          .firstOrNull;
      if (removed == null) return section;
      return section.copyWith(
        lanes: [
          for (final lane in section.lanes)
            if (lane.id != laneId &&
                !(removed.kind == SongLaneKind.harmony &&
                    lane.kind == SongLaneKind.save &&
                    saveAnchorLane(section, lane)?.id == laneId))
              lane,
        ],
      );
    });
  }

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
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where(
          (candidate) =>
              candidate.id == laneId && candidate.kind == SongLaneKind.save,
        )
        .firstOrNull;
    if (section == null || lane == null) return;
    final resolvedSnapshot =
        snapshot ??
        (projectId == null
            ? null
            : resolveSaveInProject(
                ref.read(saveSystemProvider),
                projectId,
                saveId ?? '',
              )?.snapshot);
    if (resolvedSnapshot is HarmonyChordSnapshot ||
        (resolvedSnapshot != null &&
            !_saveSnapshotMatchesAnchor(
              section,
              resolvedSnapshot,
              harmonyLaneId: lane.anchorLaneId,
            ))) {
      return;
    }
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
    addHarmonyChord(
      sectionId: sectionId,
      laneId: laneId,
      block: block,
      saveName: saveName,
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
    lastHarmonyMutationError = null;
    final section = state.sections
        .where((candidate) => candidate.id == sectionId)
        .firstOrNull;
    final lane = section?.lanes
        .where(
          (candidate) =>
              candidate.id == laneId && candidate.kind == SongLaneKind.harmony,
        )
        .firstOrNull;
    final block = lane?.blocks
        .where((candidate) => candidate.id == blockId)
        .firstOrNull;
    if (lane == null || block == null) return false;

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
    var candidate = block.copyWith(
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
    if (!candidate.isSilent) {
      final writerBlock = _writerSnapshotFromBlock(state, lane, candidate);
      if (writerBlock == null || !_hasChordContent(writerBlock)) {
        lastHarmonyMutationError =
            'This chord has incomplete or unsupported pitch data.';
        return false;
      }
      final composite = _buildHarmonyChordSnapshot(
        writerBlock,
        existing: block.embedded,
        instrument:
            lane.harmonyInstrument ??
            projectDefaultHarmonyInstrumentForSelectedProject,
      );
      if (composite == null) return false;
      candidate = candidate.copyWith(embedded: composite);
    }

    _replaceLane(sectionId, laneId, (currentLane) {
      return currentLane.copyWith(
        blocks: currentLane.blocks
            .map(
              (currentBlock) =>
                  currentBlock.id == blockId ? candidate : currentBlock,
            )
            .toList(),
      );
    });
    return true;
  }

  /// Inserts an instrument selection without creating a library save.
  /// Passing [snapshot] creates an embedded save-lane block; otherwise the
  /// chord fields create a harmony-lane block. When [replaceBlockId] is set,
  /// the stored source block is replaced in place so repeated placements keep
  /// their source ID, start, span, and lane repeat pattern.
  bool insertInstrumentSelectionAtBar({
    required String? sectionId,
    required int startBar,
    InstrumentSnapshot? snapshot,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String> chordNotes = const [],
    String? replaceBlockId,
    String? saveName,
    String? reuseSaveId,
    String? laneId,
    String? anchorLaneId,
    HarmonyLaneInstrument? harmonyInstrument,
    bool createSectionIfMissing = false,
    String? stagedSectionId,
    String? stagedSectionLabel,
    int stagedSectionLengthBars = 8,
    String? expectedProjectId,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (expectedProjectId != null && expectedProjectId != projectId) {
      return false;
    }
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
      if (canonical == null ||
          canonical is WriterBlockSnapshot ||
          canonical is HarmonyChordSnapshot) {
        return false;
      }
      // The selected save is authoritative. A snapshot captured before the
      // naming dialog may have gone stale while the dialog was open.
      snapshot = canonical;
    }
    final isHarmony = snapshot == null;
    if (startBar < 0 ||
        (harmonyInstrument != null && !isHarmony) ||
        (isHarmony &&
            saveName != null &&
            saveName.trim().isNotEmpty &&
            !isValidSaveName(saveName.trim()))) {
      return false;
    }
    if (isHarmony &&
        (chordSymbol == null || chordQuality == null || chordRootPc == null)) {
      return false;
    }
    final requestedSectionId = sectionId ?? stagedSectionId;
    final sectionIndex = requestedSectionId == null
        ? -1
        : state.sections.indexWhere(
            (section) => section.id == requestedSectionId,
          );
    final sectionExists = sectionIndex >= 0;
    if ((!sectionExists && !createSectionIfMissing) ||
        (sectionExists && stagedSectionId != null)) {
      return false;
    }
    final actualSectionId = requestedSectionId ?? generateId();
    if (!sectionExists &&
        (sectionId != null ||
            state.sections.any((section) => section.id == actualSectionId))) {
      return false;
    }
    final projectDefault = projectDefaultHarmonyInstrumentForSelectedProject;
    final selectedInstrument = isHarmony
        ? harmonyInstrument ?? projectDefault
        : _harmonyInstrumentForNativeSnapshot(snapshot);
    if (!sectionExists &&
        (stagedSectionLengthBars < 1 || startBar >= stagedSectionLengthBars)) {
      return false;
    }
    var section = sectionExists
        ? state.sections[sectionIndex]
        : _stagedSection(
            id: actualSectionId,
            label: stagedSectionLabel,
            lengthBars: stagedSectionLengthBars,
            primaryLaneId: isHarmony && selectedInstrument == projectDefault
                ? laneId
                : null,
            additionalHarmonyInstrument: selectedInstrument == projectDefault
                ? null
                : selectedInstrument,
            additionalHarmonyLaneId:
                isHarmony && selectedInstrument != projectDefault
                ? laneId
                : null,
          );
    if (startBar >= section.lengthBars) return false;

    if (isHarmony) {
      final requestedLane = laneId == null
          ? null
          : section.lanes
                .where(
                  (lane) =>
                      lane.id == laneId && lane.kind == SongLaneKind.harmony,
                )
                .firstOrNull;
      if (laneId != null && requestedLane == null) return false;
      SongLane? destination = requestedLane;
      if (destination != null &&
          _instrumentForHarmonyLane(destination) != selectedInstrument) {
        return false;
      }
      if (destination == null && replaceBlockId != null) {
        destination = section.lanes
            .where(
              (lane) =>
                  lane.kind == SongLaneKind.harmony &&
                  lane.blocks.any((block) => block.id == replaceBlockId) &&
                  _instrumentForHarmonyLane(lane) == selectedInstrument,
            )
            .firstOrNull;
      }
      destination ??= section.lanes
          .where(
            (lane) =>
                lane.kind == SongLaneKind.harmony &&
                _instrumentForHarmonyLane(lane) == selectedInstrument,
          )
          .toList()
          .firstOrNull;
      destination ??= SongLane(
        id: laneId ?? generateId(),
        kind: SongLaneKind.harmony,
        order: section.lanes.length,
        harmonyInstrument: selectedInstrument,
      );
      final laneHasSource = destination.blocks.any(
        (block) => block.id == replaceBlockId,
      );
      if (replaceBlockId != null && !laneHasSource) return false;
      final source = replaceBlockId == null
          ? null
          : destination.blocks
                .where((block) => block.id == replaceBlockId)
                .firstOrNull;
      if (source != null &&
          !tileLaneBlocks(
            destination,
            sectionLengthBars: section.lengthBars,
          ).any(
            (placement) =>
                placement.id == source.id && placement.startBar == startBar,
          )) {
        return false;
      }
      var candidate = source == null
          ? makeHarmonyBlock(
              startBar: startBar,
              spanBars: 1,
              chordSymbol: chordSymbol!,
              chordQuality: chordQuality!,
              chordRootPc: chordRootPc!,
              chordNotes: chordNotes,
            )
          : source.copyWith(
              clearSaveId: true,
              chordSymbol: chordSymbol,
              chordQuality: chordQuality,
              chordRootPc: chordRootPc,
              chordNotes: chordNotes,
              clearRomanNumeral: true,
              isSilent: false,
            );
      if (source != null &&
          blocksOverlap(
            destination.blocks.where((block) => block.id != source.id).toList(),
            candidate,
          )) {
        return false;
      }
      final writerBlock = _writerSnapshotFromBlock(
        state,
        destination,
        candidate,
      );
      if (writerBlock == null || !_hasChordContent(writerBlock)) return false;
      final composite = _buildHarmonyChordSnapshot(
        writerBlock,
        existing: source?.embedded ?? candidate.embedded,
        instrument: selectedInstrument!,
      );
      if (composite == null) return false;
      candidate = candidate.copyWith(embedded: composite);
      final updatedLane = destination.copyWith(
        harmonyInstrument: selectedInstrument,
        blocks: source == null
            ? [...destination.blocks, candidate]
            : [
                for (final block in destination.blocks)
                  if (block.id == source.id) candidate else block,
              ],
      );
      final updatedLanes = [
        for (final lane in section.lanes)
          if (lane.id != updatedLane.id) lane,
        updatedLane,
      ];
      final nextSection = section.copyWith(lanes: updatedLanes);
      final sections = [...state.sections];
      if (sectionExists) {
        sections[sectionIndex] = nextSection;
      } else {
        sections.add(nextSection);
      }
      _set(
        state.copyWith(sections: sections),
        saveNames: {
          if (saveName != null && saveName.trim().isNotEmpty)
            candidate.id: saveName,
        },
      );
      return true;
    }

    final selectedNativeInstrument = selectedInstrument;
    SongLane? harmonyLane;
    if (anchorLaneId != null) {
      harmonyLane = section.lanes
          .where(
            (lane) =>
                lane.id == anchorLaneId && lane.kind == SongLaneKind.harmony,
          )
          .firstOrNull;
      if (harmonyLane == null ||
          (selectedNativeInstrument != null &&
              _instrumentForHarmonyLane(harmonyLane) !=
                  selectedNativeInstrument)) {
        return false;
      }
    } else if (selectedNativeInstrument != null) {
      harmonyLane = section.lanes
          .where(
            (lane) =>
                lane.kind == SongLaneKind.harmony &&
                _instrumentForHarmonyLane(lane) == selectedNativeInstrument,
          )
          .firstOrNull;
      if (harmonyLane == null) {
        harmonyLane = SongLane(
          id: generateId(),
          kind: SongLaneKind.harmony,
          order: section.lanes.length,
          harmonyInstrument: selectedNativeInstrument,
        );
        section = section.copyWith(lanes: [...section.lanes, harmonyLane]);
      }
    } else {
      harmonyLane = section.lanes
          .where((lane) => lane.kind == SongLaneKind.harmony)
          .firstOrNull;
    }
    final explicitAnchorLaneId = _explicitSaveAnchorLaneId(
      section,
      harmonyLane?.id,
    );
    SongLane? destination;
    if (laneId != null) {
      destination = section.lanes
          .where((lane) => lane.id == laneId && lane.kind == SongLaneKind.save)
          .firstOrNull;
      if (destination == null && sectionExists) {
        return false;
      }
      if (destination != null &&
          saveAnchorLane(section, destination)?.id != harmonyLane?.id) {
        return false;
      }
    } else if (replaceBlockId != null) {
      destination = section.lanes
          .where(
            (lane) =>
                lane.kind == SongLaneKind.save &&
                lane.blocks.any((block) => block.id == replaceBlockId) &&
                saveAnchorLane(section, lane)?.id == harmonyLane?.id,
          )
          .firstOrNull;
    } else {
      destination = _saveLaneForAnchor(section, explicitAnchorLaneId);
    }
    final targetLane =
        destination ??
        SongLane(
          id: laneId ?? generateId(),
          kind: SongLaneKind.save,
          order: section.lanes.length,
          anchorLaneId: explicitAnchorLaneId,
        );
    final source = replaceBlockId == null
        ? null
        : targetLane.blocks
              .where((block) => block.id == replaceBlockId)
              .firstOrNull;
    if (replaceBlockId != null && source == null) {
      return false;
    }
    if (source != null &&
        !tileLaneBlocks(targetLane, sectionLengthBars: section.lengthBars).any(
          (placement) =>
              placement.id == source.id && placement.startBar == startBar,
        )) {
      return false;
    }
    final candidate = source == null
        ? reuseSaveId == null
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
            clearChordData: true,
            clearRomanNumeral: true,
            isSilent: false,
          );
    final retainedBlocks = targetLane.blocks
        .where((block) => block.id != source?.id)
        .toList();
    if (blocksOverlap(retainedBlocks, candidate)) {
      return false;
    }
    final updatedLane = targetLane.copyWith(
      blocks: source == null
          ? [...targetLane.blocks, candidate]
          : [
              for (final block in targetLane.blocks)
                if (block.id == source.id) candidate else block,
            ],
    );
    final updatedLanes = [
      for (final lane in section.lanes)
        if (lane.id != updatedLane.id) lane,
      updatedLane,
    ];
    final nextSection = section.copyWith(lanes: updatedLanes);
    final sections = [...state.sections];
    if (sectionExists) {
      sections[sectionIndex] = nextSection;
    } else {
      sections.add(nextSection);
    }
    _set(
      state.copyWith(sections: sections),
      saveNames: {
        if (saveName != null && saveName.trim().isNotEmpty)
          candidate.id: saveName,
      },
    );
    return true;
  }

  HarmonyLaneInstrument? _harmonyInstrumentForNativeSnapshot(
    InstrumentSnapshot snapshot,
  ) => switch (snapshot) {
    FretboardSnapshot() => HarmonyLaneInstrument.fretboard,
    PianoSnapshot() => HarmonyLaneInstrument.piano,
    _ => null,
  };

  HarmonyLaneInstrument? _instrumentForSaveSnapshot(
    InstrumentSnapshot snapshot,
  ) => switch (snapshot) {
    HarmonyChordSnapshot(:final harmonyInstrument) => harmonyInstrument,
    FretboardSnapshot() => HarmonyLaneInstrument.fretboard,
    PianoSnapshot() => HarmonyLaneInstrument.piano,
    _ => null,
  };

  bool _saveSnapshotMatchesAnchor(
    SongSection section,
    InstrumentSnapshot snapshot, {
    required String? harmonyLaneId,
  }) {
    final sourceInstrument = _instrumentForSaveSnapshot(snapshot);
    if (sourceInstrument == null) return true;
    final anchor = harmonyLaneId == null
        ? primaryHarmonyLane(section)
        : section.lanes
              .where(
                (candidate) =>
                    candidate.id == harmonyLaneId &&
                    candidate.kind == SongLaneKind.harmony,
              )
              .firstOrNull;
    if (harmonyLaneId != null && anchor == null) return false;
    final targetInstrument =
        anchor?.harmonyInstrument ??
        (harmonyLaneId == null
            ? projectDefaultHarmonyInstrumentForSelectedProject
            : null);
    return sourceInstrument == targetInstrument;
  }

  bool _saveLaneBlocksMatchAnchor(
    SongSection section,
    SongLane lane, {
    required String? harmonyLaneId,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    for (final block in lane.blocks) {
      final snapshot =
          block.embedded ??
          (projectId == null || block.saveId == null
              ? null
              : resolveSaveInProject(
                  ref.read(saveSystemProvider),
                  projectId,
                  block.saveId!,
                )?.snapshot);
      if (snapshot != null &&
          !_saveSnapshotMatchesAnchor(
            section,
            snapshot,
            harmonyLaneId: harmonyLaneId,
          )) {
        return false;
      }
    }
    return true;
  }

  HarmonyLaneInstrument _instrumentForHarmonyLane(SongLane lane) =>
      lane.harmonyInstrument ??
      projectDefaultHarmonyInstrumentForSelectedProject;

  SongSection _stagedSection({
    required String id,
    String? label,
    required int lengthBars,
    String? primaryLaneId,
    HarmonyLaneInstrument? additionalHarmonyInstrument,
    String? additionalHarmonyLaneId,
  }) {
    final primaryInstrument = projectDefaultHarmonyInstrumentForSelectedProject;
    final lanes = <SongLane>[
      SongLane(
        id: primaryLaneId ?? generateId(),
        kind: SongLaneKind.harmony,
        order: 0,
        harmonyInstrument: primaryInstrument,
      ),
    ];
    if (additionalHarmonyInstrument != null &&
        additionalHarmonyInstrument != primaryInstrument) {
      lanes.add(
        SongLane(
          id: additionalHarmonyLaneId ?? generateId(),
          kind: SongLaneKind.harmony,
          order: lanes.length,
          harmonyInstrument: additionalHarmonyInstrument,
        ),
      );
    }
    return SongSection(
      id: id,
      label: label,
      lengthBars: lengthBars,
      order: state.sections.length,
      lanes: lanes,
    );
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
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return false;
    final saveState = ref.read(saveSystemProvider);
    final canonical = resolveSaveInProject(saveState, projectId, saveId);
    if (canonical == null) return false;
    final links = getWriterLinksForSave(saveState, projectId, saveId);
    if (links.isEmpty) return false;
    final InstrumentSnapshot updatedSnapshot;
    if (canonical.snapshot is HarmonyChordSnapshot) {
      final result = buildStandaloneHarmonySaveSnapshot(
        saveId: saveId,
        snapshot: snapshot,
      );
      if (!result.success || result.snapshot == null) return false;
      final locations = _blocksById(state);
      for (final link in links) {
        final location = locations[link.blockId];
        final section = location?.$1;
        final lane = location?.$2;
        final linkedHarmonyInstrument = switch (link.laneKind) {
          SongLaneKind.harmony =>
            lane?.kind == SongLaneKind.harmony ? lane?.harmonyInstrument : null,
          SongLaneKind.save =>
            section != null && lane?.kind == SongLaneKind.save
                ? saveAnchorLane(section, lane!)?.harmonyInstrument
                : null,
          _ => null,
        };
        if (section == null ||
            lane == null ||
            linkedHarmonyInstrument != result.snapshot!.harmonyInstrument) {
          lastHarmonyMutationError =
              'Every linked Harmony Lane and Save / Voicing anchor must use the save’s instrument.';
          return false;
        }
      }
      updatedSnapshot = result.snapshot!;
    } else {
      if (snapshot is WriterBlockSnapshot || snapshot is HarmonyChordSnapshot) {
        return false;
      }
      if (snapshot.instrument != canonical.snapshot.instrument) return false;
      final nativeInstrument = _harmonyInstrumentForNativeSnapshot(
        canonical.snapshot,
      );
      if (nativeInstrument != null) {
        final locations = _blocksById(state);
        for (final link in links) {
          final location = locations[link.blockId];
          final section = location?.$1;
          final lane = location?.$2;
          final anchor = section != null && lane?.kind == SongLaneKind.save
              ? saveAnchorLane(section, lane!)
              : null;
          if (link.laneKind != SongLaneKind.save ||
              section == null ||
              lane == null ||
              anchor == null ||
              anchor.harmonyInstrument != nativeInstrument) {
            return false;
          }
        }
      }
      updatedSnapshot = snapshot;
    }
    final linkedBlockIds = links.map((link) => link.blockId).toSet();
    final sections = state.sections.map((section) {
      return section.copyWith(
        lanes: section.lanes.map((lane) {
          return lane.copyWith(
            blocks: lane.blocks.map((block) {
              if (!linkedBlockIds.contains(block.id)) return block;
              return block.copyWith(embedded: updatedSnapshot);
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
    required String? sectionId,
    required SongLaneKind laneKind,
    required int startBar,
    int spanBars = 1,
    String? laneId,
    String? anchorLaneId,
    HarmonyLaneInstrument? harmonyInstrument,
    bool createSectionIfMissing = false,
    String? stagedSectionId,
    String? stagedSectionLabel,
    int stagedSectionLengthBars = 8,
    String? expectedProjectId,
    String? replaceBlockId,
  }) {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null ||
        (expectedProjectId != null && expectedProjectId != projectId) ||
        startBar < 0 ||
        spanBars < 1) {
      return false;
    }
    final saveState = ref.read(saveSystemProvider);
    final save = resolveSaveInProject(saveState, projectId, saveId);
    final snapshot = save?.snapshot;
    final writerSnapshot = _writerBlockOf(snapshot);
    if (writerSnapshot == null ||
        writerSnapshot.laneKind != laneKind ||
        laneKind == SongLaneKind.save ||
        (laneKind == SongLaneKind.harmony &&
            (snapshot is! HarmonyChordSnapshot ||
                !_hasChordContent(writerSnapshot))) ||
        (laneKind != SongLaneKind.harmony &&
            (snapshot is! WriterBlockSnapshot || harmonyInstrument != null)) ||
        !_hasRestorableWriterSnapshot(writerSnapshot)) {
      return false;
    }
    final harmonySave = snapshot is HarmonyChordSnapshot ? snapshot : null;
    final targetHarmonyInstrument = harmonySave?.harmonyInstrument;
    if (harmonySave != null &&
        (harmonyInstrument != null &&
                harmonyInstrument != targetHarmonyInstrument ||
            !_isPlayableHarmonyComposite(harmonySave))) {
      return false;
    }

    final requestedSectionId = sectionId ?? stagedSectionId;
    final sectionIndex = requestedSectionId == null
        ? -1
        : state.sections.indexWhere(
            (section) => section.id == requestedSectionId,
          );
    final sectionExists = sectionIndex >= 0;
    if (!sectionExists && !createSectionIfMissing) return false;
    if (sectionExists && stagedSectionId != null) return false;
    final actualSectionId = requestedSectionId ?? generateId();
    if (!sectionExists &&
        (sectionId != null ||
            state.sections.any((section) => section.id == actualSectionId))) {
      return false;
    }
    final defaultInstrument = projectDefaultHarmonyInstrumentForSelectedProject;
    SongSection section;
    if (sectionExists) {
      section = state.sections[sectionIndex];
    } else {
      if (stagedSectionLengthBars < 1 || startBar >= stagedSectionLengthBars) {
        return false;
      }
      final primaryId =
          targetHarmonyInstrument == defaultInstrument && laneId != null
          ? laneId
          : generateId();
      final lanes = <SongLane>[
        SongLane(
          id: primaryId,
          kind: SongLaneKind.harmony,
          order: 0,
          harmonyInstrument: defaultInstrument,
        ),
      ];
      if (targetHarmonyInstrument != null &&
          targetHarmonyInstrument != defaultInstrument) {
        lanes.add(
          SongLane(
            id: laneId ?? generateId(),
            kind: SongLaneKind.harmony,
            order: lanes.length,
            harmonyInstrument: targetHarmonyInstrument,
          ),
        );
      }
      section = SongSection(
        id: actualSectionId,
        label: stagedSectionLabel,
        lengthBars: stagedSectionLengthBars,
        order: state.sections.length,
        lanes: lanes,
      );
    }
    if (startBar >= section.lengthBars) return false;

    SongLane? destination;
    if (laneId != null) {
      destination = section.lanes
          .where((lane) => lane.id == laneId && lane.kind == laneKind)
          .firstOrNull;
      if (destination == null ||
          (harmonySave != null &&
              destination.harmonyInstrument != harmonySave.harmonyInstrument)) {
        return false;
      }
    } else {
      final matching =
          section.lanes
              .where(
                (lane) =>
                    lane.kind == laneKind &&
                    (harmonySave == null ||
                        lane.harmonyInstrument ==
                            harmonySave.harmonyInstrument) &&
                    (replaceBlockId == null ||
                        lane.blocks.any((block) => block.id == replaceBlockId)),
              )
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      destination = matching.firstOrNull;
    }
    if (destination == null && laneId != null && sectionExists) return false;
    final targetLane =
        destination ??
        SongLane(
          id: laneId ?? generateId(),
          kind: laneKind,
          order: section.lanes.length,
          harmonyInstrument: laneKind == SongLaneKind.harmony
              ? targetHarmonyInstrument ?? defaultInstrument
              : null,
        );
    final source = replaceBlockId == null
        ? null
        : targetLane.blocks
              .where((block) => block.id == replaceBlockId)
              .firstOrNull;
    if (replaceBlockId != null && source == null) return false;
    if (source != null &&
        !tileLaneBlocks(targetLane, sectionLengthBars: section.lengthBars).any(
          (placement) =>
              placement.id == source.id && placement.startBar == startBar,
        )) {
      return false;
    }
    final block = source == null
        ? _blockFromWriterSnapshot(
            writerSnapshot,
            id: generateId(),
            saveId: saveId,
            startBar: startBar,
            spanBars: spanBars,
            embeddedSnapshot: snapshot,
          )
        : SongBlock(
            id: source.id,
            startBar: source.startBar,
            spanBars: source.spanBars,
            saveId: saveId,
            embedded: snapshot,
            chordSymbol: writerSnapshot.chordSymbol,
            chordQuality: writerSnapshot.chordQuality,
            chordRootPc: writerSnapshot.chordRootPc,
            chordNotes: writerSnapshot.chordNotes,
            romanNumeral: writerSnapshot.romanNumeral,
            patternId:
                writerSnapshot.drumPattern?.id ??
                writerSnapshot.melodyPattern?.id ??
                writerSnapshot.guitarStrumPattern?.id,
            audioClipId: writerSnapshot.audioClip?.id,
            lyrics: source.lyrics,
            isSilent: writerSnapshot.isSilent,
          );
    final retainedBlocks = targetLane.blocks
        .where((currentBlock) => currentBlock.id != source?.id)
        .toList();
    if (blocksOverlap(retainedBlocks, block)) return false;
    final laneWithBlock = targetLane.copyWith(
      blocks: source == null
          ? [...targetLane.blocks, block]
          : [
              for (final currentBlock in targetLane.blocks)
                if (currentBlock.id == source.id) block else currentBlock,
            ],
      anchorLaneId: laneKind == SongLaneKind.guitarStrum
          ? anchorLaneId
          : targetLane.anchorLaneId,
    );
    final lanes = [
      for (final lane in section.lanes)
        if (lane.id != laneWithBlock.id) lane,
      laneWithBlock,
    ];
    final sections = [...state.sections];
    if (sectionExists) {
      sections[sectionIndex] = section.copyWith(lanes: lanes);
    } else {
      sections.add(section.copyWith(lanes: lanes));
    }
    final restored = _restoreWriterBlockSnapshot(state, writerSnapshot);
    _set(restored.copyWith(sections: sections));
    return true;
  }

  bool _isPlayableHarmonyComposite(HarmonyChordSnapshot snapshot) {
    final expected = _harmonyPitchClasses(snapshot.writerBlock);
    final actual = _selectedPitchClasses(snapshot.instrumentState);
    return _hasChordContent(snapshot.writerBlock) &&
        expected != null &&
        actual != null &&
        _samePitchClassSet(expected, actual);
  }

  SongBlock _blockFromWriterSnapshot(
    WriterBlockSnapshot snapshot, {
    required String id,
    required String saveId,
    required int startBar,
    required int spanBars,
    InstrumentSnapshot? embeddedSnapshot,
  }) {
    switch (snapshot.laneKind) {
      case SongLaneKind.harmony:
        return SongBlock(
          id: id,
          startBar: startBar,
          spanBars: spanBars,
          saveId: saveId,
          embedded: embeddedSnapshot ?? snapshot,
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
    final sourceLane = section.lanes
        .where(
          (lane) =>
              lane.id == harmonyLaneId && lane.kind == SongLaneKind.harmony,
        )
        .firstOrNull;
    if (sourceLane == null ||
        _instrumentForHarmonyLane(sourceLane) !=
            HarmonyLaneInstrument.fretboard) {
      return;
    }
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
    final sourceLane = section.lanes
        .where(
          (lane) =>
              lane.id == harmonyLaneId && lane.kind == SongLaneKind.harmony,
        )
        .firstOrNull;
    if (sourceLane == null ||
        _instrumentForHarmonyLane(sourceLane) != HarmonyLaneInstrument.piano) {
      return;
    }
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
    addLibraryBlockAt(
      sectionId: sectionId,
      saveId: saveId,
      startBar: selectedBlock.startBar,
      spanBars: selectedBlock.spanBars,
      anchorLaneId: harmonyLaneId,
    );
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
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    final snapshot = projectId == null
        ? null
        : resolveSaveInProject(
            ref.read(saveSystemProvider),
            projectId,
            saveId,
          )?.snapshot;
    if ((projectId != null && snapshot == null) ||
        snapshot is HarmonyChordSnapshot ||
        (snapshot != null &&
            !_saveSnapshotMatchesAnchor(
              section,
              snapshot,
              harmonyLaneId: explicitAnchorLaneId,
            ))) {
      return;
    }
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
