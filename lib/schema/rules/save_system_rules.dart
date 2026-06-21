/// Save System Schema Rules
/// Validation, defaults, factory helpers, and tree traversal.
library;

import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../models/project_config.dart';
import '../../models/save_system.dart';

const saveSystemStorageKey = '@muzician/save-system/v3';
const legacySaveSystemStorageKeys = <String>[
  '@muzician/save-system/v2',
  '@muzician/save_system',
];
const legacySessionKeys = <String>[
  '@muzician/song_session/v1',
  '@muzician/songwriter_session/v1',
];

final _uuid = Uuid();

String generateId() => _uuid.v4();

// ─── Default State ────────────────────────────────────────────────────────────

SaveSystemState getDefaultSaveSystemState() => const SaveSystemState(
  folders: [],
  saves: [],
  activeSession: null,
  hydrated: false,
);

// ─── Validation ───────────────────────────────────────────────────────────────

bool isValidFolderName(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty && trimmed.length <= 60;
}

bool isValidSaveName(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty && trimmed.length <= 80;
}

// ─── Factory Helpers ─────────────────────────────────────────────────────────

SaveFolder createFolder(
  String name,
  String? parentId,
  int siblingCount, [
  ProgressionFolderMeta? progressionMeta,
]) {
  return SaveFolder(
    id: generateId(),
    name: name.trim(),
    parentId: parentId,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    order: siblingCount,
    progressionMeta: progressionMeta,
  );
}

SaveEntry createSaveEntry(
  String name,
  String folderId,
  InstrumentSnapshot snapshot,
  int siblingCount, [
  ProgressionChordMeta? progressionMeta,
]) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return SaveEntry(
    id: generateId(),
    name: name.trim(),
    folderId: folderId,
    snapshot: snapshot,
    createdAt: now,
    updatedAt: now,
    order: siblingCount,
    progressionMeta: progressionMeta,
  );
}

// ─── Tree Helpers ─────────────────────────────────────────────────────────────

List<SaveEntry> getSavesInFolder(List<SaveEntry> saves, String folderId) {
  return saves.where((s) => s.folderId == folderId).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

List<SaveFolder> getChildFolders(List<SaveFolder> folders, String? parentId) {
  return folders.where((f) => f.parentId == parentId).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

List<String> getDescendantFolderIds(List<SaveFolder> folders, String folderId) {
  final result = <String>[];
  final queue = [folderId];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final child in folders.where((f) => f.parentId == current)) {
      result.add(child.id);
      queue.add(child.id);
    }
  }
  return result;
}

List<({String id, String name})> buildFolderBreadcrumb(
  List<SaveFolder> folders,
  String folderId,
) {
  final crumbs = <({String id, String name})>[];
  SaveFolder? current;
  try {
    current = folders.firstWhere((f) => f.id == folderId);
  } catch (_) {
    return crumbs;
  }
  while (current != null) {
    crumbs.insert(0, (id: current.id, name: current.name));
    final parentId = current.parentId;
    if (parentId == null) break;
    try {
      current = folders.firstWhere((f) => f.id == parentId);
    } catch (_) {
      break;
    }
  }
  return crumbs;
}

({String? prev, String? next}) getAdjacentSaves(
  List<SaveEntry> saves,
  ActiveSession? session,
) {
  if (session == null) return (prev: null, next: null);
  final siblings = getSavesInFolder(saves, session.folderId);
  final idx = siblings.indexWhere((s) => s.id == session.saveId);
  if (idx < 0) return (prev: null, next: null);
  return (
    prev: idx > 0 ? siblings[idx - 1].id : null,
    next: idx < siblings.length - 1 ? siblings[idx + 1].id : null,
  );
}

// ─── Serialisation ───────────────────────────────────────────────────────────

String serialiseState({
  required List<SaveFolder> folders,
  required List<SaveEntry> saves,
  required String? selectedProjectId,
}) {
  return jsonEncode({
    'folders': folders.map((f) => f.toJson()).toList(),
    'saves': saves.map((s) => s.toJson()).toList(),
    'selectedProjectId': selectedProjectId,
  });
}

({List<SaveFolder> folders, List<SaveEntry> saves, String? selectedProjectId})?
    deserialiseState(String raw) {
  try {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['folders'] is! List || parsed['saves'] is! List) return null;
    final folders = (parsed['folders'] as List)
        .map((f) => SaveFolder.fromJson(f as Map<String, dynamic>))
        .toList();
    final saves = (parsed['saves'] as List)
        .map((s) => SaveEntry.fromJson(s as Map<String, dynamic>))
        .toList();
    final selectedProjectId = parsed['selectedProjectId'] as String?;
    return (folders: folders, saves: saves, selectedProjectId: selectedProjectId);
  } catch (_) {
    return null;
  }
}

List<SaveFolder> getProjectFolders(List<SaveFolder> folders) {
  return folders
      .where((f) => f.parentId == null && f.kind == SaveFolderKind.project)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

SaveFolder? getDumpFolder(List<SaveFolder> folders) {
  for (final f in folders) {
    if (f.parentId == null && f.kind == SaveFolderKind.dump) return f;
  }
  return null;
}

Set<String> getSubtreeFolderIds(List<SaveFolder> folders, String rootId) {
  final visited = <String>{rootId};
  final queue = <String>[rootId];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    for (final f in folders) {
      if (f.parentId == current && visited.add(f.id)) queue.add(f.id);
    }
  }
  return visited;
}

List<SaveEntry> getSavesInSubtree(
  List<SaveFolder> folders,
  List<SaveEntry> saves,
  String rootId,
) {
  final ids = getSubtreeFolderIds(folders, rootId);
  return saves.where((s) => ids.contains(s.folderId)).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

bool isProjectRoot(SaveFolder f) => f.parentId == null && f.kind == SaveFolderKind.project;
bool isDumpRoot(SaveFolder f) => f.parentId == null && f.kind == SaveFolderKind.dump;

SaveFolder createProjectFolder(String name, ProjectConfig cfg, int siblingCount) {
  return SaveFolder(
    id: generateId(),
    name: name.trim(),
    parentId: null,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    order: siblingCount,
    kind: SaveFolderKind.project,
    projectConfig: cfg,
  );
}

SaveFolder createDumpFolder(int siblingCount) {
  return SaveFolder(
    id: generateId(),
    name: 'Dump',
    parentId: null,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    order: siblingCount,
    kind: SaveFolderKind.dump,
  );
}
