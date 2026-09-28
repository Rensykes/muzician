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
        folder.writerLaneKind == null &&
        folder.parentId == projectId &&
        folder.kind == SaveFolderKind.normal &&
        isFolderInProject(state.folders, folder.id, projectId)) {
      return folder;
    }
  }
  return null;
}

/// True when [folder] is the direct, lane-kind category child of a Writer
/// section root. A Writer section root itself never carries a lane kind.
bool isWriterLaneCategoryFolder(
  List<SaveFolder> folders,
  SaveFolder folder, {
  String? projectId,
  String? sectionId,
  SongLaneKind? laneKind,
}) {
  final folderSectionId = folder.writerSectionId;
  final folderLaneKind = folder.writerLaneKind;
  if (folderSectionId == null ||
      folderLaneKind == null ||
      folder.kind != SaveFolderKind.normal ||
      (sectionId != null && folderSectionId != sectionId) ||
      (laneKind != null && folderLaneKind != laneKind)) {
    return false;
  }

  final sectionFolder = folders
      .where((candidate) => candidate.id == folder.parentId)
      .firstOrNull;
  if (sectionFolder == null ||
      sectionFolder.parentId == null ||
      sectionFolder.writerSectionId != folderSectionId ||
      sectionFolder.writerLaneKind != null ||
      sectionFolder.kind != SaveFolderKind.normal ||
      (projectId != null && sectionFolder.parentId != projectId)) {
    return false;
  }
  final enclosingProjectId = getProjectIdForFolder(folders, sectionFolder.id);
  return enclosingProjectId != null &&
      sectionFolder.parentId == enclosingProjectId &&
      (projectId == null || enclosingProjectId == projectId) &&
      isFolderInProject(folders, folder.id, enclosingProjectId);
}

bool isWriterSaveLinkCategoryValid(
  List<SaveFolder> folders,
  WriterSaveLink link, {
  required String projectId,
}) {
  final folder = folders
      .where((candidate) => candidate.id == link.folderId)
      .firstOrNull;
  return folder != null &&
      isWriterLaneCategoryFolder(
        folders,
        folder,
        projectId: projectId,
        sectionId: link.sectionId,
        laneKind: link.laneKind,
      );
}

SaveFolder? getWriterLaneCategoryFolder(
  SaveSystemState state, {
  required String projectId,
  required String sectionId,
  required SongLaneKind laneKind,
}) {
  final sectionFolder = getWriterSectionFolder(state, projectId, sectionId);
  if (sectionFolder == null) return null;
  return state.folders
      .where(
        (folder) =>
            folder.parentId == sectionFolder.id &&
            isWriterLaneCategoryFolder(
              state.folders,
              folder,
              projectId: projectId,
              sectionId: sectionId,
              laneKind: laneKind,
            ),
      )
      .firstOrNull;
}

/// Reuses a lane category's stable ID when it already exists in [state], or
/// stages a new direct child of [sectionFolder] with deterministic ordering.
SaveFolder getOrCreateWriterLaneFolder(
  SaveSystemState state, {
  required String projectId,
  required String sectionId,
  required SongLaneKind laneKind,
  required SaveFolder sectionFolder,
}) {
  final sectionRoot = getWriterSectionFolder(state, projectId, sectionId);
  final root = sectionRoot?.id == sectionFolder.id ? sectionRoot : null;
  if (root == null || sectionFolder.writerSectionId != sectionId) {
    throw ArgumentError('sectionFolder must be the Writer section root.');
  }
  final existing = getWriterLaneCategoryFolder(
    state,
    projectId: projectId,
    sectionId: sectionId,
    laneKind: laneKind,
  );
  if (existing != null) return existing;

  return SaveFolder(
    id: generateId(),
    name: _writerLaneFolderName(laneKind),
    parentId: sectionFolder.id,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    order: laneKind.index,
    writerSectionId: sectionId,
    writerLaneKind: laneKind,
  );
}

String _writerLaneFolderName(SongLaneKind laneKind) => switch (laneKind) {
  SongLaneKind.harmony => 'Harmony',
  SongLaneKind.save => 'Voicing',
  SongLaneKind.drum => 'Drum',
  SongLaneKind.audio => 'Audio',
  SongLaneKind.melody => 'Melody',
  SongLaneKind.guitarStrum => 'Guitar strum',
};

List<WriterSaveLink> getWriterLinksForSection(
  SaveSystemState state,
  String projectId,
  String sectionId,
) {
  if (getWriterSectionFolder(state, projectId, sectionId) == null) {
    return const [];
  }
  return state.writerLinks
      .where(
        (link) =>
            link.sectionId == sectionId &&
            resolveSaveInProject(state, projectId, link.saveId) != null &&
            getWriterLaneCategoryFolder(
                  state,
                  projectId: projectId,
                  sectionId: sectionId,
                  laneKind: link.laneKind,
                )?.id ==
                link.folderId,
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
            isWriterSaveLinkCategoryValid(
              state.folders,
              link,
              projectId: projectId,
            ),
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
  String? originalFolderId,
}) {
  if (save.origin != SaveOrigin.writer) return save.folderId;
  final physicalFolderId = originalFolderId ?? save.folderId;
  if (isFolderInProject(state.folders, physicalFolderId, projectId)) {
    return physicalFolderId;
  }
  final sectionRootsById = {
    for (final folder in state.folders)
      if (folder.writerSectionId != null &&
          folder.writerLaneKind == null &&
          folder.parentId == projectId &&
          isFolderInProject(state.folders, folder.id, projectId))
        folder.writerSectionId!: folder,
  };
  final laneFoldersById = {
    for (final folder in state.folders)
      if (isWriterLaneCategoryFolder(
        state.folders,
        folder,
        projectId: projectId,
      ))
        folder.id: folder,
  };
  final linkedFolders =
      links
          .where((link) => link.saveId == save.id)
          .where(
            (link) =>
                laneFoldersById[link.folderId]?.writerSectionId ==
                    link.sectionId &&
                laneFoldersById[link.folderId]?.writerLaneKind == link.laneKind,
          )
          .map((link) => laneFoldersById[link.folderId])
          .whereType<SaveFolder>()
          .toList()
        ..sort((a, b) {
          final aSectionOrder =
              sectionRootsById[a.writerSectionId]?.order ?? a.order;
          final bSectionOrder =
              sectionRootsById[b.writerSectionId]?.order ?? b.order;
          final bySectionOrder = aSectionOrder.compareTo(bSectionOrder);
          if (bySectionOrder != 0) return bySectionOrder;
          final bySectionId = a.writerSectionId!.compareTo(b.writerSectionId!);
          if (bySectionId != 0) return bySectionId;
          final byLaneOrder = a.writerLaneKind!.index.compareTo(
            b.writerLaneKind!.index,
          );
          return byLaneOrder != 0 ? byLaneOrder : a.id.compareTo(b.id);
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
