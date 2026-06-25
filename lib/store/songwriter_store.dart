/// Songwriter project Riverpod store with per-project session auto-save.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../models/song_project.dart';
import '../models/songwriter.dart';
import '../schema/rules/save_system_rules.dart';
import '../schema/rules/songwriter_rules.dart';
import '../schema/rules/songwriter_third_above_rules.dart';
import '../schema/rules/songwriter_voicing_rules.dart';
import '../utils/note_utils.dart';
import 'save_system_store.dart';
import 'songwriter_sessions_store.dart';
import 'writer_save_binding_store.dart';

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
  bool _hydrating = false;

  @override
  SongwriterProjectSnapshot build() {
    // React to project selection changes.
    ref.listen<String?>(saveSystemProvider.select((s) => s.selectedProjectId), (
      prev,
      next,
    ) {
      // Persist outgoing immediately.
      if (prev != null && prev != next) {
        ref.read(songwriterSessionsProvider.notifier).put(prev, state);
      }
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
    });

    // Cold start: the listener above only fires on project *changes*. When a
    // project is already selected (restored during hydrate) before this provider
    // is first read, seed directly from its saved working draft — otherwise the
    // Writer would open blank until the user switched projects.
    final id = ref.read(saveSystemProvider).selectedProjectId;
    if (id == null) return _emptyProject();
    final session = ref.read(songwriterSessionsProvider.notifier).get(id);
    return session ?? _defaultFor(id);
  }

  @override
  set state(SongwriterProjectSnapshot value) {
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

  void _set(SongwriterProjectSnapshot next) {
    state = next;
  }

  Future<void> newProject() async {
    state = _emptyProject();
    final id = ref.read(saveSystemProvider).selectedProjectId;
    if (id != null) {
      ref.read(songwriterSessionsProvider.notifier).remove(id);
      ref.read(writerSaveBindingProvider.notifier).clear(id);
    }
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

  void _replaceSection(String sectionId, SongSection Function(SongSection) f) {
    final sections = state.sections
        .map((s) => s.id == sectionId ? f(s) : s)
        .toList();
    if (_sameElements(state.sections, sections)) return; // nothing changed
    _set(state.copyWith(sections: sections));
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
    SongLane Function(SongLane) f,
  ) {
    _replaceSection(sectionId, (s) {
      final lanes = s.lanes.map((l) => l.id == laneId ? f(l) : l).toList();
      if (_sameElements(s.lanes, lanes)) return s; // lane unchanged
      return s.copyWith(lanes: lanes);
    });
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
                  ? b.copyWith(clearPatternId: true)
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
  String addAudioClip({required String assetId, required int durationMs}) {
    final clip = makeAudioClip(assetId: assetId, durationMs: durationMs);
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

  /// Removes an audio block and its 1:1 clip. The underlying asset file is
  /// reclaimed by the load-time orphan reconcile (see SongAudioRepository).
  void removeAudioBlock({
    required String sectionId,
    required String laneId,
    required String blockId,
  }) {
    final lane = state.sections
        .where((s) => s.id == sectionId)
        .expand((s) => s.lanes)
        .where((l) => l.id == laneId)
        .firstOrNull;
    final clipId = lane?.blocks
        .where((b) => b.id == blockId)
        .firstOrNull
        ?.audioClipId;
    _replaceLane(
      sectionId,
      laneId,
      (l) =>
          l.copyWith(blocks: l.blocks.where((b) => b.id != blockId).toList()),
    );
    if (clipId != null) {
      _set(
        state.copyWith(
          audioClips: state.audioClips.where((c) => c.id != clipId).toList(),
        ),
      );
    }
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

  /// Returns true when a save-lane block at [startBar]/[spanBars] would land
  /// inside the section's first existing save lane without overlapping any of
  /// its blocks. When the section has no save lane yet, returns true (the
  /// auto-created lane will be empty).
  ///
  /// Mirrors [_findOrCreateSaveLane]'s lane-selection rule (first save lane by
  /// `order`) so callers can preflight overlaps before persisting a SaveEntry.
  bool _canPlaceSaveBlockInSection(
    SongSection section,
    int startBar,
    int spanBars,
  ) {
    final saveLanes =
        section.lanes.where((l) => l.kind == SongLaneKind.save).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (saveLanes.isEmpty) return true;
    final lane = saveLanes.first;
    final endBar = startBar + spanBars;
    for (final b in lane.blocks) {
      if (startBar < b.endBar && b.startBar < endBar) return false;
    }
    return true;
  }

  /// Persists a voicing suggestion as a SaveEntry in the project's top-level
  /// folder (auto-created from the project name) and inserts a save-lane block
  /// in the section aligned to the triggering harmony block's bars.
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

    // Preflight: if the candidate block would overlap the destination save
    // lane, abort BEFORE creating the SaveEntry. addSaveBlock silently
    // rejects overlaps, which would otherwise leave behind an orphan save.
    if (!_canPlaceSaveBlockInSection(
      section,
      harmonyBlock.startBar,
      harmonyBlock.spanBars,
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

    final saves = ref.read(saveSystemProvider.notifier);
    final rootName = chromaticNotes[suggestion.rootPc];
    final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
    final saveId = saves.saveSnapshot(
      saveName,
      selId,
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

  /// Persists a 3rd-above harmony suggestion as a SaveEntry in the project's
  /// top-level folder (auto-created from the project name) and inserts a
  /// save-lane block aligned to the triggering harmony block's bars.
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

    if (!_canPlaceSaveBlockInSection(
      section,
      harmonyBlock.startBar,
      harmonyBlock.spanBars,
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

    final saves = ref.read(saveSystemProvider.notifier);

    final rootName = chromaticNotes[suggestion.rootPc];
    final saveName = '$rootName${suggestion.quality} — ${suggestion.label}';
    final saveId = saves.saveSnapshot(
      saveName,
      selId,
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

  /// Inserts a save-lane block at [startBar] referencing an existing [saveId],
  /// without going through a harmony chord. Used by the add-bar sheet's "From
  /// library" picker. No-ops when the section is missing or the placement
  /// overlaps the destination save lane.
  void addLibraryBlockAt({
    required String sectionId,
    required String saveId,
    required int startBar,
    int spanBars = 1,
  }) {
    final section = state.sections.where((s) => s.id == sectionId).firstOrNull;
    if (section == null) return;
    if (!_canPlaceSaveBlockInSection(section, startBar, spanBars)) return;
    final laneId = _findOrCreateSaveLane(sectionId);
    if (laneId == null) return;
    addSaveBlock(
      sectionId: sectionId,
      laneId: laneId,
      saveId: saveId,
      startBar: startBar,
      spanBars: spanBars,
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
