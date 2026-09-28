/// Save System Riverpod Store
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/piano_roll.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../models/songwriter.dart';
import '../schema/rules/save_system_rules.dart';
import '../utils/note_utils.dart';
import 'persisted_data_recovery_store.dart';
import 'songwriter_sessions_store.dart';
import 'writer_save_binding_store.dart';
import 'writer_save_sync_store.dart';

class SaveSystemNotifier extends Notifier<SaveSystemState> {
  String? lastMutationError;

  @override
  SaveSystemState build() => getDefaultSaveSystemState();

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(saveSystemStorageKey);
    if (existing != null) {
      final parsed = deserialiseState(existing);
      if (parsed == null) {
        throw MalformedPersistedPayload(
          storageKey: saveSystemStorageKey,
          raw: existing,
        );
      }
      state = state.copyWith(
        folders: parsed.folders,
        saves: parsed.saves,
        writerLinks: parsed.writerLinks,
        selectedProjectId: () => parsed.selectedProjectId,
        hydrated: true,
      );
      return;
    }
    // First v3 launch — wipe legacy blobs, but only when legacy data was
    // actually present (a truly fresh install has nothing to clean, and the
    // audio-dir wipe touches path_provider, which test environments lack).
    var hadLegacy = false;
    for (final key in legacySaveSystemStorageKeys) {
      if (prefs.containsKey(key)) {
        hadLegacy = true;
        await prefs.remove(key);
      }
    }
    for (final key in legacySessionKeys) {
      if (prefs.containsKey(key)) {
        hadLegacy = true;
        await prefs.remove(key);
      }
    }
    if (hadLegacy) {
      await _wipeAudioDir();
    }
    state = state.copyWith(hydrated: true);
    await _persist();
  }

  Future<void> _wipeAudioDir() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${docsDir.path}/song_audio');
      if (await audioDir.exists()) {
        await audioDir.delete(recursive: true);
      }
    } catch (_) {
      /* best-effort; ignore */
    }
  }

  Future<void> _persist() => ref
      .read(writerSaveSyncProvider.notifier)
      .persistSaveSystem(serialiseSaveSystemState(state));

  // ── Folder Management ────────────────────────────────────────────────────

  String? createSaveFolder(String name, String? parentId) {
    lastMutationError = null;
    if (!isValidFolderName(name)) {
      lastMutationError = 'Folder name is invalid.';
      return null;
    }
    if (parentId != null &&
        isWriterManagedFolderOrDescendant(state.folders, parentId)) {
      lastMutationError = 'Writer section folders are managed by Writer.';
      return null;
    }
    final siblings = getChildFolders(state.folders, parentId);
    final folder = createFolder(name, parentId, siblings.length);
    state = state.copyWith(folders: [...state.folders, folder]);
    _persist();
    return folder.id;
  }

  bool renameFolder(String id, String name) {
    lastMutationError = null;
    if (!isValidFolderName(name)) {
      lastMutationError = 'Folder name is invalid.';
      return false;
    }
    if (isWriterManagedFolderOrDescendant(state.folders, id)) {
      lastMutationError = 'Writer section folders are managed by Writer.';
      return false;
    }
    if (!state.folders.any((folder) => folder.id == id)) return false;
    state = state.copyWith(
      folders: state.folders
          .map((f) => f.id == id ? f.copyWith(name: name.trim()) : f)
          .toList(),
    );
    _persist();
    return true;
  }

  bool deleteFolder(String id) {
    lastMutationError = null;
    final f = state.folders.where((x) => x.id == id).firstOrNull;
    if (f == null) return false;
    if (f.kind == SaveFolderKind.dump) {
      lastMutationError = 'The Dump folder cannot be deleted.';
      return false;
    }
    if (f.kind == SaveFolderKind.project) {
      unawaited(deleteProject(id));
      return true;
    }
    if (isWriterManagedFolderOrDescendant(state.folders, id)) {
      lastMutationError =
          'Remove Writer work before deleting this section folder.';
      return false;
    }
    final descendantIds = getDescendantFolderIds(state.folders, id);
    final allDeletedIds = [id, ...descendantIds];
    final removedSaveIds = state.saves
        .where((save) => allDeletedIds.contains(save.folderId))
        .map((save) => save.id)
        .toSet();
    final linkedSaveIds = state.writerLinks
        .where((link) => removedSaveIds.contains(link.saveId))
        .map((link) => link.saveId)
        .toSet();
    if (linkedSaveIds.isNotEmpty) {
      final names = state.saves
          .where((save) => linkedSaveIds.contains(save.id))
          .map((save) => save.name)
          .toSet()
          .join(', ');
      lastMutationError =
          'Remove or reposition linked Writer saves before deleting this folder: $names.';
      return false;
    }
    final nextFolders = state.folders
        .where((f) => !allDeletedIds.contains(f.id))
        .toList();
    final nextSaves = state.saves
        .where((s) => !allDeletedIds.contains(s.folderId))
        .toList();
    final nextSession =
        state.activeSession != null &&
            allDeletedIds.contains(state.activeSession!.folderId)
        ? null
        : state.activeSession;
    state = state.copyWith(
      folders: nextFolders,
      saves: nextSaves,
      activeSession: () => nextSession,
    );
    _persist();
    return true;
  }

  // ── Project CRUD ──────────────────────────────────────────────────────────

  String? createProject(String name, ProjectConfig cfg) {
    if (!isValidFolderName(name)) return null;
    final siblings = state.folders.where((f) => f.parentId == null).toList();
    final folder = createProjectFolder(name, cfg, siblings.length);
    state = state.copyWith(folders: [...state.folders, folder]);
    _persist();
    return folder.id;
  }

  void renameProject(String id, String name) {
    if (!isValidFolderName(name)) return;
    state = state.copyWith(
      folders: state.folders.map((f) {
        if (f.id != id || f.kind != SaveFolderKind.project) return f;
        return f.copyWith(name: name.trim());
      }).toList(),
    );
    _persist();
  }

  Future<void> deleteProject(String id) async {
    final folder = state.folders.firstWhere(
      (f) => f.id == id && f.kind == SaveFolderKind.project,
      orElse: () => const SaveFolder(id: '', name: '', createdAt: 0, order: 0),
    );
    if (folder.id.isEmpty) return;
    final ids = getSubtreeFolderIds(state.folders, id);
    final nextFolders = state.folders
        .where((f) => !ids.contains(f.id))
        .toList();
    final nextSaves = state.saves
        .where((s) => !ids.contains(s.folderId))
        .toList();
    final clearSel = state.selectedProjectId == id;
    final nextState = state.copyWith(
      folders: nextFolders,
      saves: nextSaves,
      writerLinks: state.writerLinks
          .where(
            (link) =>
                !ids.contains(link.folderId) &&
                !state.saves.any(
                  (save) =>
                      save.id == link.saveId && ids.contains(save.folderId),
                ),
          )
          .toList(),
      selectedProjectId: clearSel ? () => null : null,
    );
    final sessions = ref.read(songwriterSessionsProvider.notifier);
    final nextDrafts = {...sessions.state}..remove(id);
    final bindings = ref.read(writerSaveBindingProvider.notifier);
    final nextBindings = {...bindings.state}..remove(id);
    await ref
        .read(writerSaveSyncProvider.notifier)
        .commitWriterTransaction(
          projectId: id,
          saveSystemState: nextState,
          writerDrafts: nextDrafts,
          writerBindings: {
            for (final entry in nextBindings.entries)
              entry.key: entry.value.toJson(),
          },
          commitMemory: () {
            state = nextState;
            sessions.commitState(nextDrafts);
            bindings.commitState(nextBindings);
          },
        );
  }

  void updateProjectConfig(String id, ProjectConfig cfg) {
    state = state.copyWith(
      folders: state.folders.map((f) {
        if (f.id != id || f.kind != SaveFolderKind.project) return f;
        return f.copyWith(projectConfig: cfg);
      }).toList(),
    );
    _persist();
  }

  String ensureDumpFolder() {
    final existing = getDumpFolder(state.folders);
    if (existing != null) return existing.id;
    final siblings = state.folders.where((f) => f.parentId == null).toList();
    final folder = createDumpFolder(siblings.length);
    state = state.copyWith(folders: [...state.folders, folder]);
    _persist();
    return folder.id;
  }

  void selectProject(String? id) {
    if (id == null) {
      state = state.copyWith(selectedProjectId: () => null);
      _persist();
      return;
    }
    final folder = state.folders.where((f) => f.id == id).firstOrNull;
    if (folder == null) return;
    if (folder.kind != SaveFolderKind.project &&
        folder.kind != SaveFolderKind.dump) {
      return;
    }
    state = state.copyWith(selectedProjectId: () => id);
    _persist();
  }

  /// Commits a Writer reconciliation. Pass `persist: false` when a shared
  /// Writer/Save System journal owns the durable write; serialize the prepared
  /// state with [serialiseSaveSystemState] and persist it through that queue.
  bool commitWriterStructure(
    String projectId,
    SaveSystemState next, {
    Map<String, (String, int)> restoredWriterSaveLocations = const {},
    bool persist = true,
  }) {
    final prepared = buildWriterStructure(
      projectId,
      next,
      restoredWriterSaveLocations: restoredWriterSaveLocations,
    );
    if (prepared == null) return false;
    state = prepared;
    if (persist) _persist();
    return true;
  }

  /// Prepares a complete Writer reconciliation without changing Save System
  /// state or writing storage. This lets the transaction coordinator capture
  /// the exact payload before it writes its pending journal.
  SaveSystemState? buildWriterStructure(
    String projectId,
    SaveSystemState next, {
    Map<String, (String, int)> restoredWriterSaveLocations = const {},
  }) {
    lastMutationError = null;
    final project = state.folders
        .where(
          (folder) =>
              folder.id == projectId &&
              folder.kind == SaveFolderKind.project &&
              folder.parentId == null,
        )
        .firstOrNull;
    if (project == null || state.selectedProjectId != projectId) {
      lastMutationError = 'Select the project before syncing Writer saves.';
      return null;
    }
    final nextProject = next.folders
        .where(
          (folder) =>
              folder.id == projectId &&
              folder.kind == SaveFolderKind.project &&
              folder.parentId == null,
        )
        .firstOrNull;
    if (nextProject == null) {
      lastMutationError = 'Writer sync cannot remove the selected project.';
      return null;
    }

    final desiredLinks = next.writerLinks.where((link) {
      return isFolderInProject(next.folders, link.folderId, projectId) ||
          resolveSaveInProject(next, projectId, link.saveId) != null;
    }).toList();
    final seenBlockIds = <String>{};
    for (final link in desiredLinks) {
      if (!isWriterSaveLinkCategoryValid(
            next.folders,
            link,
            projectId: projectId,
          ) ||
          (resolveSaveInProject(next, projectId, link.saveId) == null &&
              resolveSaveInProject(state, projectId, link.saveId) == null) ||
          !seenBlockIds.add(link.blockId)) {
        lastMutationError =
            'Writer sync contains an invalid or duplicate link.';
        return null;
      }
    }
    final nextProjectFolderIds = getSubtreeFolderIds(next.folders, projectId);
    final sectionIds = <String>{};
    final laneCategories = <String>{};
    for (final folder in next.folders.where(
      (folder) =>
          nextProjectFolderIds.contains(folder.id) &&
          folder.writerSectionId != null &&
          folder.writerLaneKind == null,
    )) {
      if (folder.parentId != projectId ||
          folder.kind != SaveFolderKind.normal ||
          !sectionIds.add(folder.writerSectionId!)) {
        lastMutationError =
            'Writer sync contains invalid or duplicate section folders.';
        return null;
      }
    }
    for (final folder in next.folders.where(
      (folder) =>
          nextProjectFolderIds.contains(folder.id) &&
          folder.writerLaneKind != null,
    )) {
      final laneKey =
          '${folder.writerSectionId}/${folder.writerLaneKind!.name}';
      if (!isWriterLaneCategoryFolder(
            next.folders,
            folder,
            projectId: projectId,
          ) ||
          !sectionIds.contains(folder.writerSectionId) ||
          !laneCategories.add(laneKey)) {
        lastMutationError =
            'Writer sync contains invalid or duplicate lane category folders.';
        return null;
      }
    }

    final deletedManagedFolderIds = <String>{};
    for (final folder in state.folders) {
      if (isFolderInProject(state.folders, folder.id, projectId) &&
          isWriterManagedFolderOrDescendant(state.folders, folder.id) &&
          !nextProjectFolderIds.contains(folder.id)) {
        deletedManagedFolderIds.addAll(
          getSubtreeFolderIds(state.folders, folder.id),
        );
      }
    }

    final currentProjectFolderIds = getSubtreeFolderIds(
      state.folders,
      projectId,
    );
    final projectFolders = [
      ...state.folders.where(
        (folder) => !currentProjectFolderIds.contains(folder.id),
      ),
      project,
      ...next.folders.where(
        (folder) =>
            nextProjectFolderIds.contains(folder.id) && folder.id != projectId,
      ),
    ];
    final existingSavesById = {for (final save in state.saves) save.id: save};
    final currentProjectSaves = state.saves
        .where(
          (save) => isFolderInProject(state.folders, save.folderId, projectId),
        )
        .toList();
    final currentProjectSaveIds = currentProjectSaves
        .map((save) => save.id)
        .toSet();
    final nextProjectSaves = next.saves
        .where(
          (save) =>
              isFolderInProject(next.folders, save.folderId, projectId) ||
              currentProjectSaveIds.contains(save.id),
        )
        .toList();
    final nextProjectSavesById = {
      for (final save in nextProjectSaves) save.id: save,
    };
    final projectSaves = <SaveEntry>[
      for (final save in currentProjectSaves)
        nextProjectSavesById[save.id] ?? save,
      ...nextProjectSaves.where(
        (save) => !currentProjectSaveIds.contains(save.id),
      ),
    ];
    for (var saveIndex = 0; saveIndex < projectSaves.length; saveIndex++) {
      var save = projectSaves[saveIndex];
      final existing = existingSavesById[save.id];
      final manualRehomeAllowed =
          existing?.origin == SaveOrigin.manual &&
          isFolderInProject(state.folders, existing!.folderId, projectId) &&
          deletedManagedFolderIds.contains(existing.folderId) &&
          save.folderId == projectId;
      if (existing?.origin == SaveOrigin.manual &&
          isFolderInProject(state.folders, existing!.folderId, projectId) &&
          existing.folderId != save.folderId &&
          !manualRehomeAllowed) {
        lastMutationError = 'Writer sync cannot move a manual save.';
        return null;
      }
      if (existing?.origin == SaveOrigin.manual &&
          isFolderInProject(state.folders, existing!.folderId, projectId) &&
          !isFolderInProject(projectFolders, existing.folderId, projectId)) {
        if (!deletedManagedFolderIds.contains(existing.folderId)) {
          lastMutationError =
              'Writer sync cannot remove a folder containing a manual save.';
          return null;
        }
        final rootOrder = projectSaves
            .where(
              (candidate) =>
                  candidate.id != existing.id &&
                  candidate.folderId == projectId,
            )
            .length;
        save = existing.copyWith(folderId: projectId, order: rootOrder);
        projectSaves[saveIndex] = save;
      }
      if (existing?.origin == SaveOrigin.writer &&
          next.folders.any(
            (folder) =>
                folder.id == save.folderId &&
                !isFolderInProject(next.folders, folder.id, projectId),
          )) {
        lastMutationError = 'Writer saves cannot move to another project.';
        return null;
      }
      if (save.origin != SaveOrigin.writer &&
          isWriterManagedFolderOrDescendant(projectFolders, save.folderId) &&
          !state.writerLinks.any((link) => link.saveId == save.id)) {
        lastMutationError = 'Manual saves cannot be created in Writer folders.';
        return null;
      }
    }

    bool belongsToProject(WriterSaveLink link, SaveSystemState source) {
      return isFolderInProject(source.folders, link.folderId, projectId) ||
          resolveSaveInProject(source, projectId, link.saveId) != null;
    }

    final otherProjectLinks = state.writerLinks
        .where((link) => !belongsToProject(link, state))
        .toList();
    final links = [...otherProjectLinks, ...desiredLinks];
    final linkedState = state.copyWith(
      folders: projectFolders,
      saves: projectSaves,
      writerLinks: links,
    );
    final saves = <SaveEntry>[];
    for (final save in projectSaves) {
      final existing = existingSavesById[save.id];
      final wasInProject =
          existingSavesById[save.id] != null &&
          isFolderInProject(
            state.folders,
            existingSavesById[save.id]!.folderId,
            projectId,
          );
      final isInProject = isFolderInProject(
        projectFolders,
        save.folderId,
        projectId,
      );
      if (save.origin != SaveOrigin.writer || (!wasInProject && !isInProject)) {
        saves.add(save);
        continue;
      }
      final destination = writerSaveFolderForLinks(
        linkedState,
        projectId: projectId,
        save: save,
        links: desiredLinks,
        originalFolderId:
            restoredWriterSaveLocations[save.id]?.$1 ??
            (existing?.origin == SaveOrigin.writer ? existing!.folderId : null),
      );
      if (destination == null || destination == save.folderId) {
        saves.add(save);
        continue;
      }
      final order =
          restoredWriterSaveLocations[save.id]?.$2 ??
          getSavesInFolder(
            saves.where((candidate) => candidate.id != save.id).toList(),
            destination,
          ).length;
      saves.add(save.copyWith(folderId: destination, order: order));
    }

    final savesOutsideProject = state.saves
        .where((save) => !currentProjectSaveIds.contains(save.id))
        .toList();
    final committedSaves = [...savesOutsideProject, ...saves];
    final activeSave = state.activeSession == null
        ? null
        : committedSaves
              .where((save) => save.id == state.activeSession!.saveId)
              .firstOrNull;
    final activeSession = activeSave == null
        ? state.activeSession
        : ActiveSession(saveId: activeSave.id, folderId: activeSave.folderId);

    return state.copyWith(
      folders: projectFolders,
      saves: committedSaves,
      writerLinks: links,
      activeSession: () => activeSession,
    );
  }

  SaveEntry? resolveSaveForProject(String projectId, String saveId) =>
      resolveSaveInProject(state, projectId, saveId);

  WriterSaveLink? resolveWriterBlockLink(String projectId, String blockId) =>
      state.writerLinks
          .where(
            (link) =>
                link.blockId == blockId &&
                resolveSaveInProject(state, projectId, link.saveId) != null &&
                isWriterSaveLinkCategoryValid(
                  state.folders,
                  link,
                  projectId: projectId,
                ),
          )
          .firstOrNull;

  Future<void> applyProjectConfig(
    String projectId,
    ProjectConfig cfg, {
    required bool retrofit,
  }) async {
    updateProjectConfig(projectId, cfg);
    if (!retrofit) return;

    final ids = getSubtreeFolderIds(state.folders, projectId);
    final linkedSaveIds = state.writerLinks.map((link) => link.saveId).toSet();
    final nextSaves = state.saves.map((s) {
      if (!ids.contains(s.folderId)) return s;
      if (s.snapshot is SongwriterProjectSnapshot) return s;
      if (linkedSaveIds.contains(s.id) ||
          isWriterManagedFolderOrDescendant(state.folders, s.folderId)) {
        return s;
      }
      final snapped = _retrofitSnapshot(s.snapshot, cfg);
      if (snapped == s.snapshot) return s;
      return s.copyWith(
        snapshot: snapped,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    state = state.copyWith(saves: nextSaves);
    await _persist();
  }

  InstrumentSnapshot _retrofitSnapshot(
    InstrumentSnapshot snap,
    ProjectConfig cfg,
  ) {
    final scaleNotes = _scaleNotesFor(cfg.keyRootPc, cfg.keyScaleName);
    if (snap is FretboardSnapshot) {
      return FretboardSnapshot(
        tuning: snap.tuning,
        numFrets: snap.numFrets,
        capo: snap.capo,
        selectedCells: snap.selectedCells,
        selectedNotes: snap.selectedNotes,
        viewMode: snap.viewMode,
        pendingChord: snap.pendingChord,
        pendingScale: snap.pendingScale,
      );
    }
    if (snap is PianoSnapshot) {
      return PianoSnapshot(
        currentRange: snap.currentRange,
        selectedKeys: snap.selectedKeys,
        selectedNotes: snap.selectedNotes,
        viewMode: snap.viewMode,
        pendingChord: snap.pendingChord,
        pendingScale: snap.pendingScale,
      );
    }
    if (snap is PianoRollSnapshot) {
      return PianoRollSnapshot(
        tempo: cfg.tempo,
        key: cfg.keyRootPc == null ? null : chromaticNotes[cfg.keyRootPc!],
        numerator: cfg.beatsPerBar,
        denominator: cfg.beatUnit,
        totalMeasures: snap.totalMeasures,
        notes: snap.notes,
        pitchRangeStart: snap.pitchRangeStart,
        pitchRangeEnd: snap.pitchRangeEnd,
        selectedColumnTick: snap.selectedColumnTick,
        snapTicks: snap.snapTicks,
        highlightedNotes: scaleNotes,
        pendingScale: snap.pendingScale,
      );
    }
    if (snap is SongProjectSnapshot) {
      final project = snap.project.copyWith(
        config: snap.project.config.copyWith(
          tempo: cfg.tempo,
          timeSignature: TimeSignature(
            beatsPerMeasure: cfg.beatsPerBar,
            beatUnit: cfg.beatUnit,
          ),
          scaleRoot: () =>
              cfg.keyRootPc == null ? null : chromaticNotes[cfg.keyRootPc!],
          scaleName: () => cfg.keyScaleName,
        ),
      );
      return SongProjectSnapshot(project: project);
    }
    if (snap is SongwriterProjectSnapshot) {
      return snap.copyWith(
        config: snap.config.copyWith(
          tempo: cfg.tempo,
          beatsPerBar: cfg.beatsPerBar,
          beatUnit: cfg.beatUnit,
          keyRoot: cfg.keyRootPc,
          keyScaleName: cfg.keyScaleName,
        ),
      );
    }
    return snap;
  }

  List<String> _scaleNotesFor(int? rootPc, String? scaleName) {
    if (rootPc == null || scaleName == null) return const [];
    final intervals = scaleIntervals[scaleName] ?? const [0, 2, 4, 5, 7, 9, 11];
    return intervals.map((i) => chromaticNotes[(rootPc + i) % 12]).toList();
  }

  // ── Save Management ───────────────────────────────────────────────────────

  String? saveSnapshot(
    String name,
    String folderId,
    InstrumentSnapshot snapshot,
  ) {
    lastMutationError = null;
    if (!isValidSaveName(name)) {
      lastMutationError = 'Save name is invalid.';
      return null;
    }
    if (!state.folders.any((folder) => folder.id == folderId)) {
      lastMutationError = 'Choose an existing folder before saving.';
      return null;
    }
    if (isWriterManagedFolderOrDescendant(state.folders, folderId)) {
      lastMutationError = 'Writer section folders are managed by Writer.';
      return null;
    }
    final siblings = getSavesInFolder(state.saves, folderId);
    final entry = createSaveEntry(name, folderId, snapshot, siblings.length);
    state = state.copyWith(saves: [...state.saves, entry]);
    _persist();
    return entry.id;
  }

  bool updateSnapshot(String id, InstrumentSnapshot snapshot) {
    lastMutationError = null;
    final entry = state.saves.where((save) => save.id == id).firstOrNull;
    if (entry == null) return false;
    if (state.writerLinks.any((link) => link.saveId == id) ||
        isWriterManagedFolderOrDescendant(state.folders, entry.folderId)) {
      lastMutationError = 'Update linked Writer saves through Writer.';
      return false;
    }
    state = state.copyWith(
      saves: state.saves
          .map(
            (s) => s.id == id
                ? s.copyWith(
                    snapshot: snapshot,
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                  )
                : s,
          )
          .toList(),
    );
    _persist();
    return true;
  }

  bool renameSave(String id, String name) {
    lastMutationError = null;
    if (!isValidSaveName(name)) {
      lastMutationError = 'Save name is invalid.';
      return false;
    }
    final entry = state.saves.where((save) => save.id == id).firstOrNull;
    if (entry == null) return false;
    if (isWriterManagedFolderOrDescendant(state.folders, entry.folderId)) {
      lastMutationError = 'Rename this linked save from Writer.';
      return false;
    }
    state = state.copyWith(
      saves: state.saves
          .map(
            (s) => s.id == id
                ? s.copyWith(
                    name: name.trim(),
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                  )
                : s,
          )
          .toList(),
    );
    _persist();
    return true;
  }

  bool deleteSave(String id) {
    lastMutationError = null;
    final entry = state.saves.where((save) => save.id == id).firstOrNull;
    if (entry == null) return false;
    if (state.writerLinks.any((link) => link.saveId == id) ||
        isWriterManagedFolderOrDescendant(state.folders, entry.folderId)) {
      lastMutationError =
          'Remove linked Writer blocks before deleting this save.';
      return false;
    }
    final nextSaves = state.saves.where((s) => s.id != id).toList();
    final nextSession = state.activeSession?.saveId == id
        ? null
        : state.activeSession;
    state = state.copyWith(saves: nextSaves, activeSession: () => nextSession);
    _persist();
    return true;
  }

  void moveSaveUp(String id) {
    final save = state.saves.where((s) => s.id == id).firstOrNull;
    if (save == null) return;
    if (isWriterManagedFolderOrDescendant(state.folders, save.folderId)) return;
    final siblings = getSavesInFolder(state.saves, save.folderId);
    final idx = siblings.indexWhere((s) => s.id == id);
    if (idx <= 0) return;
    final updated = List<SaveEntry>.of(siblings);
    final prev = updated[idx - 1];
    updated[idx - 1] = updated[idx].copyWith(order: idx - 1);
    updated[idx] = prev.copyWith(order: idx);
    state = state.copyWith(
      saves: [
        ...state.saves.where((s) => s.folderId != save.folderId),
        ...updated,
      ],
    );
    _persist();
  }

  void moveSaveDown(String id) {
    final save = state.saves.where((s) => s.id == id).firstOrNull;
    if (save == null) return;
    if (isWriterManagedFolderOrDescendant(state.folders, save.folderId)) return;
    final siblings = getSavesInFolder(state.saves, save.folderId);
    final idx = siblings.indexWhere((s) => s.id == id);
    if (idx >= siblings.length - 1) return;
    final updated = List<SaveEntry>.of(siblings);
    final next = updated[idx + 1];
    updated[idx + 1] = updated[idx].copyWith(order: idx + 1);
    updated[idx] = next.copyWith(order: idx);
    state = state.copyWith(
      saves: [
        ...state.saves.where((s) => s.folderId != save.folderId),
        ...updated,
      ],
    );
    _persist();
  }

  void moveFolderUp(String id) {
    final folder = state.folders.where((f) => f.id == id).firstOrNull;
    if (folder == null) return;
    if (isWriterManagedFolderOrDescendant(state.folders, id) ||
        (folder.parentId != null &&
            isWriterManagedFolderOrDescendant(
              state.folders,
              folder.parentId!,
            ))) {
      return;
    }
    final siblings = getChildFolders(state.folders, folder.parentId);
    final idx = siblings.indexWhere((f) => f.id == id);
    if (idx <= 0) return;
    if (siblings[idx - 1].writerSectionId != null) return;
    final swapped = List<SaveFolder>.of(siblings);
    final prev = swapped[idx - 1];
    swapped[idx - 1] = swapped[idx].copyWith(order: idx - 1);
    swapped[idx] = prev.copyWith(order: idx);
    state = state.copyWith(
      folders: [
        ...state.folders.where((f) => f.parentId != folder.parentId),
        ...swapped,
      ],
    );
    _persist();
  }

  void moveFolderDown(String id) {
    final folder = state.folders.where((f) => f.id == id).firstOrNull;
    if (folder == null) return;
    if (isWriterManagedFolderOrDescendant(state.folders, id) ||
        (folder.parentId != null &&
            isWriterManagedFolderOrDescendant(
              state.folders,
              folder.parentId!,
            ))) {
      return;
    }
    final siblings = getChildFolders(state.folders, folder.parentId);
    final idx = siblings.indexWhere((f) => f.id == id);
    if (idx >= siblings.length - 1) return;
    if (siblings[idx + 1].writerSectionId != null) return;
    final swapped = List<SaveFolder>.of(siblings);
    final next = swapped[idx + 1];
    swapped[idx + 1] = swapped[idx].copyWith(order: idx + 1);
    swapped[idx] = next.copyWith(order: idx);
    state = state.copyWith(
      folders: [
        ...state.folders.where((f) => f.parentId != folder.parentId),
        ...swapped,
      ],
    );
    _persist();
  }

  // ── Session / Navigation ─────────────────────────────────────────────────

  void setActiveSession(ActiveSession? session) {
    state = state.copyWith(activeSession: () => session);
  }

  void loadSave(String saveId, void Function(InstrumentSnapshot) apply) {
    final entry = state.saves.where((s) => s.id == saveId).firstOrNull;
    if (entry == null) return;
    apply(entry.snapshot);
    state = state.copyWith(
      activeSession: () =>
          ActiveSession(saveId: saveId, folderId: entry.folderId),
    );
  }

  void navigatePrev(void Function(InstrumentSnapshot) apply) {
    final adj = getAdjacentSaves(state.saves, state.activeSession);
    if (adj.prev != null) loadSave(adj.prev!, apply);
  }

  void navigateNext(void Function(InstrumentSnapshot) apply) {
    final adj = getAdjacentSaves(state.saves, state.activeSession);
    if (adj.next != null) loadSave(adj.next!, apply);
  }
}

final saveSystemProvider =
    NotifierProvider<SaveSystemNotifier, SaveSystemState>(
      SaveSystemNotifier.new,
    );

final selectedProjectProvider = Provider<SaveFolder?>((ref) {
  final state = ref.watch(saveSystemProvider);
  final id = state.selectedProjectId;
  if (id == null) return null;
  return state.folders.where((f) => f.id == id).firstOrNull;
});

final projectsListProvider = Provider<List<SaveFolder>>((ref) {
  final folders = ref.watch(saveSystemProvider.select((s) => s.folders));
  return getProjectFolders(folders);
});

final dumpFolderProvider = Provider<SaveFolder?>((ref) {
  final folders = ref.watch(saveSystemProvider.select((s) => s.folders));
  return getDumpFolder(folders);
});

final isProjectLockedProvider = Provider<bool>((ref) {
  final sel = ref.watch(selectedProjectProvider);
  return sel != null && sel.kind == SaveFolderKind.project;
});
