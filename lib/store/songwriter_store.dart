/// Songwriter project Riverpod store with debounced session auto-save.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/save_system.dart';
import '../models/songwriter.dart';
import '../schema/rules/songwriter_rules.dart';

const _sessionKey = '@muzician/songwriter_session/v1';

SongwriterProjectSnapshot _emptyProject() => const SongwriterProjectSnapshot(
  config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
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
        (s) => label == null ? s.copyWith(clearLabel: true) : s.copyWith(label: label),
      );

  void setSectionLength(String sectionId, int lengthBars) => _replaceSection(
      sectionId, (s) => s.copyWith(lengthBars: lengthBars < 1 ? 1 : lengthBars));

  void setSectionRepeat(String sectionId, int repeat) => _replaceSection(
      sectionId, (s) => s.copyWith(repeat: repeat < 1 ? 1 : repeat));

  void removeSection(String sectionId) => _set(state.copyWith(
        sections: state.sections.where((s) => s.id != sectionId).toList(),
      ));

  void reorderSections(int oldIndex, int newIndex) {
    final list = [...state.sections];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(target.clamp(0, list.length), moved);
    _set(state.copyWith(
      sections: [for (var i = 0; i < list.length; i++) list[i].copyWith(order: i)],
    ));
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
