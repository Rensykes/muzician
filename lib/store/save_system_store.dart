/// Save System Riverpod Store
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/save_system.dart';
import '../schema/rules/save_system_rules.dart';

class SaveSystemNotifier extends Notifier<SaveSystemState> {
  @override
  SaveSystemState build() => getDefaultSaveSystemState();

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(saveSystemStorageKey);
    if (raw != null) {
      final parsed = deserialiseState(raw);
      if (parsed != null) {
        state = state.copyWith(
          folders: parsed.folders,
          saves: parsed.saves,
          hydrated: true,
        );
        return;
      }
    }
    state = state.copyWith(hydrated: true);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      saveSystemStorageKey,
      serialiseState(folders: state.folders, saves: state.saves),
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
