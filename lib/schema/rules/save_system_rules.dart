/// Save System Schema Rules
/// Validation, defaults, factory helpers, and tree traversal.
library;

import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../models/project_config.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';

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

SaveFolder createWriterSectionFolder(
  SaveSystemState state, {
  required String projectId,
  required String sectionId,
  required String name,
  required int order,
}) {
  final existing = getWriterSectionFolder(state, projectId, sectionId);
  if (existing != null) {
    return existing.copyWith(name: name.trim(), order: order);
  }
  return SaveFolder(
    id: generateId(),
    name: name.trim(),
    parentId: projectId,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    order: order,
    writerSectionId: sectionId,
  );
}

SaveEntry createSaveEntry(
  String name,
  String folderId,
  InstrumentSnapshot snapshot,
  int siblingCount, [
  ProgressionChordMeta? progressionMeta,
]) => _createSaveEntry(
  name,
  folderId,
  snapshot,
  siblingCount,
  progressionMeta: progressionMeta,
);

SaveEntry createWriterSaveEntry(
  String name,
  String folderId,
  InstrumentSnapshot snapshot,
  int siblingCount, {
  ProgressionChordMeta? progressionMeta,
}) => _createSaveEntry(
  name,
  folderId,
  snapshot,
  siblingCount,
  progressionMeta: progressionMeta,
  origin: SaveOrigin.writer,
);

SaveEntry _createSaveEntry(
  String name,
  String folderId,
  InstrumentSnapshot snapshot,
  int siblingCount, {
  ProgressionChordMeta? progressionMeta,
  SaveOrigin origin = SaveOrigin.manual,
}) {
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
    origin: origin,
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
  List<WriterSaveLink> writerLinks = const [],
  required String? selectedProjectId,
}) {
  return jsonEncode({
    'folders': folders.map((f) => f.toJson()).toList(),
    'saves': saves.map((s) => s.toJson()).toList(),
    'writerLinks': writerLinks.map((link) => link.toJson()).toList(),
    'selectedProjectId': selectedProjectId,
  });
}

/// Serializes an immutable state value for transaction coordinators that must
/// capture a consistent payload before performing asynchronous storage writes.
String serialiseSaveSystemState(SaveSystemState state) => serialiseState(
  folders: state.folders,
  saves: state.saves,
  writerLinks: state.writerLinks,
  selectedProjectId: state.selectedProjectId,
);

({
  List<SaveFolder> folders,
  List<SaveEntry> saves,
  List<WriterSaveLink> writerLinks,
  String? selectedProjectId,
})?
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
    final writerLinks =
        (parsed['writerLinks'] as List?)
            ?.map(
              (link) => WriterSaveLink.fromJson(link as Map<String, dynamic>),
            )
            .toList() ??
        <WriterSaveLink>[];
    final selectedProjectId = parsed['selectedProjectId'] as String?;
    return (
      folders: folders,
      saves: saves,
      writerLinks: writerLinks,
      selectedProjectId: selectedProjectId,
    );
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

/// Returns the enclosing project root for a folder, or null outside projects.
String? getProjectIdForFolder(List<SaveFolder> folders, String folderId) {
  final byId = {for (final folder in folders) folder.id: folder};
  var current = byId[folderId];
  while (current != null) {
    if (current.kind == SaveFolderKind.project && current.parentId == null) {
      return current.id;
    }
    final parentId = current.parentId;
    if (parentId == null) return null;
    current = byId[parentId];
  }
  return null;
}

bool isFolderInProject(
  List<SaveFolder> folders,
  String folderId,
  String projectId,
) => getProjectIdForFolder(folders, folderId) == projectId;

SaveFolder? getWriterSectionFolder(
  SaveSystemState state,
  String projectId,
  String sectionId,
) {
  for (final folder in state.folders) {
    if (folder.writerSectionId == sectionId &&
        folder.parentId == projectId &&
        isFolderInProject(state.folders, folder.id, projectId)) {
      return folder;
    }
  }
  return null;
}

List<WriterSaveLink> getWriterLinksForSection(
  SaveSystemState state,
  String projectId,
  String sectionId,
) {
  final folder = getWriterSectionFolder(state, projectId, sectionId);
  if (folder == null) return const [];
  return state.writerLinks
      .where(
        (link) => link.sectionId == sectionId && link.folderId == folder.id,
      )
      .toList();
}

List<WriterSaveLink> getWriterLinksForSave(
  SaveSystemState state,
  String projectId,
  String saveId,
) {
  if (resolveSaveInProject(state, projectId, saveId) == null) return const [];
  return state.writerLinks
      .where(
        (link) =>
            link.saveId == saveId &&
            isFolderInProject(state.folders, link.folderId, projectId),
      )
      .toList();
}

/// Resolves a save only when its physical folder belongs to [projectId].
SaveEntry? resolveSaveInProject(
  SaveSystemState state,
  String projectId,
  String saveId,
) {
  final entry = state.saves.where((save) => save.id == saveId).firstOrNull;
  if (entry == null ||
      !isFolderInProject(state.folders, entry.folderId, projectId)) {
    return null;
  }
  return entry;
}

/// True for a managed Writer section folder or any nested folder beneath it.
bool isWriterManagedFolderOrDescendant(
  List<SaveFolder> folders,
  String folderId,
) {
  final byId = {for (final folder in folders) folder.id: folder};
  var current = byId[folderId];
  while (current != null) {
    if (current.writerSectionId != null) return true;
    final parentId = current.parentId;
    if (parentId == null) return false;
    current = byId[parentId];
  }
  return false;
}

/// The old Make Unique action retained both saveId and a detached embedded
/// snapshot. This predicate lets reconciliation preserve that detached copy.
bool isLegacyDetachedWriterBlock(
  SongBlock block,
  List<WriterSaveLink> writerLinks,
) =>
    block.saveId != null &&
    block.embedded != null &&
    !writerLinks.any((link) => link.blockId == block.id);

/// Chooses the physical folder for a Writer-origin save after link changes.
/// Manual saves always keep their existing folder.
String? writerSaveFolderForLinks(
  SaveSystemState state, {
  required String projectId,
  required SaveEntry save,
  required List<WriterSaveLink> links,
}) {
  if (save.origin != SaveOrigin.writer) return save.folderId;
  final sectionFoldersById = {
    for (final folder in state.folders)
      if (folder.writerSectionId != null &&
          isFolderInProject(state.folders, folder.id, projectId))
        folder.id: folder,
  };
  final linkedFolders =
      links
          .where((link) => link.saveId == save.id)
          .where(
            (link) =>
                sectionFoldersById[link.folderId]?.writerSectionId ==
                link.sectionId,
          )
          .map((link) => sectionFoldersById[link.folderId])
          .whereType<SaveFolder>()
          .toList()
        ..sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
        });
  return linkedFolders.isEmpty ? projectId : linkedFolders.first.id;
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

bool isProjectRoot(SaveFolder f) =>
    f.parentId == null && f.kind == SaveFolderKind.project;
bool isDumpRoot(SaveFolder f) =>
    f.parentId == null && f.kind == SaveFolderKind.dump;

SaveFolder createProjectFolder(
  String name,
  ProjectConfig cfg,
  int siblingCount,
) {
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
