/// Songwriter project Riverpod store with debounced session auto-save.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/save_system.dart';
import '../models/songwriter.dart';
import '../schema/rules/songwriter_rules.dart';
import '../schema/rules/songwriter_third_above_rules.dart';
import '../schema/rules/songwriter_voicing_rules.dart';
import '../utils/note_utils.dart';
import 'save_system_store.dart';

const _sessionKey = '@muzician/songwriter_session/v1';

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

class SongwriterNotifier extends Notifier<SongwriterProjectSnapshot> {
  Timer? _debounce;

  @override
  SongwriterProjectSnapshot build() {
    ref.onDispose(() => _debounce?.cancel());
    return _emptyProject();
  }

  // ── session persistence ──
  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null) {
      try {
        state = SongwriterProjectSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  void _schedulePersist() {
    _debounce?.cancel();
    final snapshot = state; // capture now, not when the timer fires
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(snapshot.toJson()));
    });
  }

  void _set(SongwriterProjectSnapshot next) {
    state = next;
    _schedulePersist();
  }

  Future<void> newProject() async {
    _debounce?.cancel();
    state = _emptyProject();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  // ── config ──
  void setKey(int? root, String? scaleName) {
    final cfg = (root == null)
        ? state.config.copyWith(clearKey: true)
        : state.config.copyWith(keyRoot: root, keyScaleName: scaleName);
    _set(state.copyWith(config: cfg));
    _recomputeNumerals();
  }

  void setTempo(int tempo) =>
      _set(state.copyWith(config: state.config.copyWith(tempo: tempo)));

  // ── sections ──
  void addSection({String? label, required int lengthBars}) {
    final section = makeSection(
      label: label,
      lengthBars: lengthBars,
      order: state.sections.length,
    );
    _set(state.copyWith(sections: [...state.sections, section]));
  }

  void _replaceSection(String sectionId, SongSection Function(SongSection) f) {
    _set(
      state.copyWith(
        sections: state.sections
            .map((s) => s.id == sectionId ? f(s) : s)
            .toList(),
      ),
    );
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

  void setSectionRepeat(String sectionId, int repeat) => _replaceSection(
    sectionId,
    (s) => s.copyWith(repeat: repeat < 1 ? 1 : repeat),
  );

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
  void addLane({
    required String sectionId,
    required SongLaneKind kind,
    String? label,
  }) {
    _replaceSection(sectionId, (s) {
      final lane = makeLane(kind: kind, label: label, order: s.lanes.length);
      return s.copyWith(lanes: [...s.lanes, lane]);
    });
  }

  void _replaceLane(
    String sectionId,
    String laneId,
    SongLane Function(SongLane) f,
  ) {
    _replaceSection(
      sectionId,
      (s) => s.copyWith(
        lanes: s.lanes.map((l) => l.id == laneId ? f(l) : l).toList(),
      ),
    );
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

  void removeLane({required String sectionId, required String laneId}) =>
      _replaceSection(
        sectionId,
        (s) => s.copyWith(lanes: s.lanes.where((l) => l.id != laneId).toList()),
      );

  // ── blocks ──
  void addSaveBlock({
    required String sectionId,
    required String laneId,
    required String saveId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      final candidate = makeSaveBlock(
        saveId: saveId,
        startBar: startBar,
        spanBars: spanBars,
      );
      if (blocksOverlap(l.blocks, candidate)) return l; // ignore overlaps
      return l.copyWith(blocks: [...l.blocks, candidate]);
    });
  }

  void addHarmonyBlock({
    required String sectionId,
    required String laneId,
    required SongBlock block, // build via makeHarmonyBlock at the call site
  }) {
    _replaceLane(sectionId, laneId, (l) {
      if (blocksOverlap(l.blocks, block)) return l;
      return l.copyWith(blocks: [...l.blocks, block]);
    });
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
      final current = l.blocks.firstWhere((b) => b.id == blockId);
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
  void makeBlockUnique({
    required String sectionId,
    required String laneId,
    required String blockId,
    required InstrumentSnapshot snapshot,
  }) {
    _replaceLane(
      sectionId,
      laneId,
      (l) => l.copyWith(
        blocks: l.blocks
            .map((b) => b.id == blockId ? b.copyWith(embedded: snapshot) : b)
            .toList(),
      ),
    );
  }

  void relinkBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
    required String saveId,
  }) {
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

  /// Persists a voicing suggestion as a SaveEntry in the auto-created
  /// "Songwriter voicings" folder and inserts a save-lane block in the section
  /// aligned to the triggering harmony block's bars.
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
    for (final lane in section.lanes) {
      for (final b in lane.blocks) {
        if (b.id == harmonyBlockId) {
          harmonyBlock = b;
          break;
        }
      }
      if (harmonyBlock != null) break;
    }
    if (harmonyBlock == null) return;

    final saves = ref.read(saveSystemProvider.notifier);
    final folderId = _findOrCreateProjectFolderId(saves);
    if (folderId == null) return;

    final rootName = chromaticNotes[suggestion.rootPc];
    final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
    final saveId = saves.saveSnapshot(
      saveName,
      folderId,
      voicingToSnapshot(suggestion),
    );
    if (saveId == null) return;

    final laneId = _findOrCreateSaveLane(sectionId);
    if (laneId == null) return;

    addSaveBlock(
      sectionId: sectionId,
      laneId: laneId,
      saveId: saveId,
      startBar: harmonyBlock.startBar,
      spanBars: harmonyBlock.spanBars,
    );
  }

  /// Persists a 3rd-above harmony suggestion as a SaveEntry in the auto-created
  /// "Songwriter harmonies" folder and inserts a save-lane block aligned to the
  /// triggering harmony block's bars.
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
    for (final lane in section.lanes) {
      for (final b in lane.blocks) {
        if (b.id == harmonyBlockId) {
          harmonyBlock = b;
          break;
        }
      }
      if (harmonyBlock != null) break;
    }
    if (harmonyBlock == null) return;

    final saves = ref.read(saveSystemProvider.notifier);
    final folderId = _findOrCreateProjectFolderId(saves);
    if (folderId == null) return;

    final rootName = chromaticNotes[suggestion.rootPc];
    final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
    final saveId = saves.saveSnapshot(
      saveName,
      folderId,
      thirdAboveToSnapshot(suggestion),
    );
    if (saveId == null) return;

    final laneId = _findOrCreateSaveLane(sectionId);
    if (laneId == null) return;

    addSaveBlock(
      sectionId: sectionId,
      laneId: laneId,
      saveId: saveId,
      startBar: harmonyBlock.startBar,
      spanBars: harmonyBlock.spanBars,
    );
  }

  /// Updates the project's display name and renames its linked top-level
  /// folder if one with the old name exists. Whitespace-only names are ignored.
  void setProjectName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final old = state.name;
    if (trimmed == old) return;
    _set(state.copyWith(name: trimmed));
    _renameProjectFolderIfExists(old, trimmed);
  }

  /// Returns the id of the project's top-level folder, or null when it does
  /// not exist. Does NOT create the folder. Used by read-only callers.
  String? _findProjectFolderId() {
    final name = state.name.trim();
    if (name.isEmpty) return null;
    for (final f in ref.read(saveSystemProvider).folders) {
      if (f.parentId == null && f.name == name) return f.id;
    }
    return null;
  }

  /// Returns the id of the project's top-level folder, creating it if missing.
  /// Used by accept flows that need to write a SaveEntry.
  String? _findOrCreateProjectFolderId(SaveSystemNotifier saves) {
    final existing = _findProjectFolderId();
    if (existing != null) return existing;
    final name = state.name.trim();
    if (name.isEmpty) return null;
    return saves.createSaveFolder(name, null);
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

  /// Returns the saves visible to library-match: the project's top-level
  /// folder plus every descendant folder. Returns empty when the project
  /// folder does not exist. Does NOT auto-create the folder.
  List<SaveEntry> searchableSavesForLibraryMatch() {
    final rootId = _findProjectFolderId();
    if (rootId == null) return const [];
    final saves = ref.read(saveSystemProvider);
    final include = <String>{rootId};
    final queue = [rootId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      for (final f in saves.folders) {
        if (f.parentId == id) {
          include.add(f.id);
          queue.add(f.id);
        }
      }
    }
    return saves.saves.where((s) => include.contains(s.folderId)).toList();
  }

  String? _findOrCreateSaveLane(String sectionId) {
    final section = state.sections.firstWhere(
      (s) => s.id == sectionId,
      orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
    );
    if (section.id.isEmpty) return null;
    final existing =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (existing.isNotEmpty) return existing.first.id;
    addLane(sectionId: sectionId, kind: SongLaneKind.save);
    final updated = state.sections.firstWhere((s) => s.id == sectionId);
    final saveLanes =
        updated.lanes.where((l) => l.kind == SongLaneKind.save).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return saveLanes.isEmpty ? null : saveLanes.last.id;
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

  /// Replace the whole project (used when loading a named save).
  void loadProject(SongwriterProjectSnapshot project) => _set(project);
}

final songwriterProvider =
    NotifierProvider<SongwriterNotifier, SongwriterProjectSnapshot>(
      SongwriterNotifier.new,
    );
