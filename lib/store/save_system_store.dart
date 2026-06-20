/// Save System Riverpod Store
library;

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

class SaveSystemNotifier extends Notifier<SaveSystemState> {
  @override
  SaveSystemState build() => getDefaultSaveSystemState();

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(saveSystemStorageKey);
    if (existing != null) {
      final parsed = deserialiseState(existing);
      if (parsed != null) {
        state = state.copyWith(
          folders: parsed.folders,
          saves: parsed.saves,
          selectedProjectId: () => parsed.selectedProjectId,
          hydrated: true,
        );
        return;
      }
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

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      saveSystemStorageKey,
      serialiseState(
        folders: state.folders,
        saves: state.saves,
        selectedProjectId: state.selectedProjectId,
      ),
    );
  }

  // ── Folder Management ────────────────────────────────────────────────────

  String? createSaveFolder(String name, String? parentId) {
    if (!isValidFolderName(name)) return null;
    final siblings = getChildFolders(state.folders, parentId);
    final folder = createFolder(name, parentId, siblings.length);
    state = state.copyWith(folders: [...state.folders, folder]);
    _persist();
    return folder.id;
  }

  void renameFolder(String id, String name) {
    if (!isValidFolderName(name)) return;
    state = state.copyWith(
      folders: state.folders
          .map((f) => f.id == id ? f.copyWith(name: name.trim()) : f)
          .toList(),
    );
    _persist();
  }

  void deleteFolder(String id) {
    final f = state.folders.where((x) => x.id == id).firstOrNull;
    if (f == null) return;
    if (f.kind == SaveFolderKind.dump) return; // refuse
    if (f.kind == SaveFolderKind.project) {
      deleteProject(id);
      return;
    }
    final descendantIds = getDescendantFolderIds(state.folders, id);
    final allDeletedIds = [id, ...descendantIds];
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

  void deleteProject(String id) {
    final folder = state.folders.firstWhere(
      (f) => f.id == id && f.kind == SaveFolderKind.project,
      orElse: () => const SaveFolder(id: '', name: '', createdAt: 0, order: 0),
    );
    if (folder.id.isEmpty) return;
    final ids = getSubtreeFolderIds(state.folders, id);
    final nextFolders = state.folders.where((f) => !ids.contains(f.id)).toList();
    final nextSaves = state.saves.where((s) => !ids.contains(s.folderId)).toList();
    final clearSel = state.selectedProjectId == id;
    state = state.copyWith(
      folders: nextFolders,
      saves: nextSaves,
      selectedProjectId: clearSel ? () => null : null,
    );
    _persist();
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
    if (folder.kind != SaveFolderKind.project && folder.kind != SaveFolderKind.dump) return;
    state = state.copyWith(selectedProjectId: () => id);
    _persist();
  }

  Future<void> applyProjectConfig(
    String projectId,
    ProjectConfig cfg, {
    required bool retrofit,
  }) async {
    updateProjectConfig(projectId, cfg);
    if (!retrofit) return;

    final ids = getSubtreeFolderIds(state.folders, projectId);
    final nextSaves = state.saves.map((s) {
      if (!ids.contains(s.folderId)) return s;
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

  InstrumentSnapshot _retrofitSnapshot(InstrumentSnapshot snap, ProjectConfig cfg) {
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
          timeSignature: TimeSignature(beatsPerMeasure: cfg.beatsPerBar, beatUnit: cfg.beatUnit),
          scaleRoot: () => cfg.keyRootPc == null ? null : chromaticNotes[cfg.keyRootPc!],
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
    if (!isValidSaveName(name)) return null;
    final siblings = getSavesInFolder(state.saves, folderId);
    final entry = createSaveEntry(name, folderId, snapshot, siblings.length);
    state = state.copyWith(saves: [...state.saves, entry]);
    _persist();
    return entry.id;
  }

  void updateSnapshot(String id, InstrumentSnapshot snapshot) {
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
  }

  void renameSave(String id, String name) {
    if (!isValidSaveName(name)) return;
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
  }

  void deleteSave(String id) {
    final nextSaves = state.saves.where((s) => s.id != id).toList();
    final nextSession = state.activeSession?.saveId == id
        ? null
        : state.activeSession;
    state = state.copyWith(saves: nextSaves, activeSession: () => nextSession);
    _persist();
  }

  void moveSaveUp(String id) {
    final save = state.saves.where((s) => s.id == id).firstOrNull;
    if (save == null) return;
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
    final siblings = getChildFolders(state.folders, folder.parentId);
    final idx = siblings.indexWhere((f) => f.id == id);
    if (idx <= 0) return;
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
    final siblings = getChildFolders(state.folders, folder.parentId);
    final idx = siblings.indexWhere((f) => f.id == id);
    if (idx >= siblings.length - 1) return;
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
