/// Piano Roll Riverpod Store
library;

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hum_to_midi.dart';
import '../models/piano_roll.dart';
import '../models/save_system.dart' show PianoRollSnapshot;
import '../schema/rules/piano_roll_rules.dart' as rules;

class PianoRollNotifier extends Notifier<PianoRollState> {
  @override
  PianoRollState build() => rules.getDefaultPianoRollState();

  String _makeId() =>
      'pr_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999).toString().padLeft(6, '0')}';

  int _clamp(int value, int minV, int maxV) => value.clamp(minV, maxV);

  bool _isAllowedByActiveScale(int midiNote) {
    final highlightedNotes = state.highlightedNotes;
    if (highlightedNotes.isEmpty) return true;
    return highlightedNotes.contains(rules.midiToPitchClass(midiNote));
  }

  void rememberLatestImportedRange(int startTick, int endTickExclusive) {
    state = state.copyWith(
      latestImportedRange: () => PianoRollImportedRange(
        startTick: startTick,
        endTickExclusive: endTickExclusive,
      ),
    );
  }

  void clearLatestImportedRange() =>
      state = state.copyWith(latestImportedRange: () => null);

  PianoRollImportedRange? Function()? _latestImportedRangeClearForNewNote() =>
      state.latestImportedRange == null ? null : () => null;

  void setTempo(int tempo) => state = state.copyWith(
    config: state.config.copyWith(
      tempo: tempo.clamp(rules.minTempo, rules.maxTempo),
    ),
  );

  void setKey(String? key) =>
      state = state.copyWith(config: state.config.copyWith(key: () => key));

  void setTimeSignature(TimeSignature ts) {
    final maxTick = rules.totalTicks(ts, state.config.totalMeasures);
    final notes = state.notes
        .where((n) => n.startTick < maxTick)
        .map(
          (n) => n.copyWith(
            durationTicks: min(n.durationTicks, max(1, maxTick - n.startTick)),
          ),
        )
        .toList();
    state = state.copyWith(
      config: state.config.copyWith(timeSignature: ts),
      notes: notes,
      selectedColumnTick: () => state.selectedColumnTick != null
          ? min(state.selectedColumnTick!, maxTick - 1)
          : null,
    );
  }

  void setTotalMeasures(int measures) {
    final nextMeasures = measures.clamp(1, 32);
    final maxTick = rules.totalTicks(state.config.timeSignature, nextMeasures);
    final notes = state.notes
        .where((n) => n.startTick < maxTick)
        .map(
          (n) => n.copyWith(
            durationTicks: min(n.durationTicks, max(1, maxTick - n.startTick)),
          ),
        )
        .toList();
    state = state.copyWith(
      config: state.config.copyWith(totalMeasures: nextMeasures),
      notes: notes,
      selectedColumnTick: () {
        final selectedTick = state.selectedColumnTick;
        if (selectedTick == null) return null;
        return min(selectedTick, maxTick - 1);
      },
    );
  }

  void setPitchRange(int startMidi, int endMidi) {
    final s = _clamp(startMidi, 21, 107);
    final e = _clamp(endMidi, s + 1, 108);
    state = state.copyWith(pitchRangeStart: s, pitchRangeEnd: e);
  }

  void shiftPitchRange(int semitones) {
    final span = state.pitchRangeEnd - state.pitchRangeStart;
    var nextStart = state.pitchRangeStart + semitones;
    var nextEnd = state.pitchRangeEnd + semitones;
    if (nextStart < 21) {
      nextStart = 21;
      nextEnd = 21 + span;
    }
    if (nextEnd > 108) {
      nextEnd = 108;
      nextStart = 108 - span;
    }
    state = state.copyWith(pitchRangeStart: nextStart, pitchRangeEnd: nextEnd);
  }

  void toggleCellNote(int midiNote, int startTick, [int durationTicks = 1]) {
    final existing = state.notes
        .where((n) => n.midiNote == midiNote && n.startTick == startTick)
        .toList();
    if (existing.isNotEmpty) {
      state = state.copyWith(
        notes: state.notes.where((n) => n.id != existing.first.id).toList(),
        selectedNoteIds: state.selectedNoteIds.difference({existing.first.id}),
      );
      return;
    }
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (startTick < 0 || startTick >= maxTick) return;
    if (!_isAllowedByActiveScale(midiNote)) return;
    final note = PianoRollNote(
      id: _makeId(),
      midiNote: midiNote,
      pitchClass: rules.midiToPitchClass(midiNote),
      noteWithOctave: rules.midiToNoteWithOctave(midiNote),
      startTick: startTick,
      durationTicks: durationTicks,
    );
    state = state.copyWith(
      notes: [...state.notes, note],
      selectedNoteIds: {note.id},
      latestImportedRange: _latestImportedRangeClearForNewNote(),
    );
  }

  void addNote(int midiNote, int startTick, int durationTicks) {
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (startTick < 0 || startTick >= maxTick) return;
    if (!_isAllowedByActiveScale(midiNote)) return;
    final safeDuration = durationTicks.clamp(1, maxTick - startTick);
    final note = PianoRollNote(
      id: _makeId(),
      midiNote: midiNote,
      pitchClass: rules.midiToPitchClass(midiNote),
      noteWithOctave: rules.midiToNoteWithOctave(midiNote),
      startTick: startTick,
      durationTicks: safeDuration,
    );
    state = state.copyWith(
      notes: [...state.notes, note],
      selectedNoteIds: {note.id},
      latestImportedRange: _latestImportedRangeClearForNewNote(),
    );
  }

  void removeNote(String noteId) => state = state.copyWith(
    notes: state.notes.where((n) => n.id != noteId).toList(),
    selectedNoteIds: state.selectedNoteIds.difference({noteId}),
  );

  void setActiveTool(PianoRollTool tool) =>
      state = state.copyWith(activeTool: tool);

  void setSnapTicks(int ticks) =>
      state = state.copyWith(snapTicks: ticks.clamp(1, 16));

  void toggleNoteInSelection(String noteId) {
    final updated = state.selectedNoteIds.contains(noteId)
        ? state.selectedNoteIds.difference({noteId})
        : {...state.selectedNoteIds, noteId};
    state = state.copyWith(selectedNoteIds: updated);
  }

  void setSelection(Set<String> ids) =>
      state = state.copyWith(selectedNoteIds: ids);

  void clearSelection() =>
      state = state.copyWith(selectedNoteIds: const <String>{});

  void deleteSelectedNotes() {
    final selectedIds = state.selectedNoteIds;
    if (selectedIds.isEmpty) return;
    state = state.copyWith(
      notes: state.notes
          .where((note) => !selectedIds.contains(note.id))
          .toList(),
      selectedNoteIds: const <String>{},
    );
  }

  void selectNotesAtTick(int tick) {
    final idsAtTick = rules
        .getNotesAtTick(state.notes, tick)
        .map((note) => note.id)
        .toSet();
    state = state.copyWith(
      selectedNoteIds: idsAtTick,
      selectedColumnTick: () => tick,
    );
  }

  void splitNote(String noteId, int splitTick) {
    final target = state.notes.where((n) => n.id == noteId).firstOrNull;
    if (target == null) return;
    if (splitTick <= target.startTick ||
        splitTick >= target.startTick + target.durationTicks) {
      return;
    }
    final dur1 = splitTick - target.startTick;
    final dur2 = (target.startTick + target.durationTicks) - splitTick;
    final left = target.copyWith(durationTicks: dur1);
    final right = PianoRollNote(
      id: _makeId(),
      midiNote: target.midiNote,
      pitchClass: target.pitchClass,
      noteWithOctave: target.noteWithOctave,
      startTick: splitTick,
      durationTicks: dur2,
    );
    state = state.copyWith(
      notes: [...state.notes.where((n) => n.id != noteId), left, right],
      selectedNoteIds: {right.id},
      latestImportedRange: _latestImportedRangeClearForNewNote(),
    );
  }

  void resizeNote(String noteId, int durationTicks) {
    final target = state.notes.where((n) => n.id == noteId).firstOrNull;
    if (target == null) return;
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    final safe = durationTicks
        .clamp(1, max(1, maxTick - target.startTick))
        .toInt();
    state = state.copyWith(
      notes: state.notes
          .map((n) => n.id == noteId ? n.copyWith(durationTicks: safe) : n)
          .toList(),
    );
  }

  void resizeNotesBatch(List<({String id, int durationTicks})> updates) {
    if (updates.isEmpty) return;
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    final updateMap = <String, int>{
      for (final u in updates) u.id: u.durationTicks,
    };
    state = state.copyWith(
      notes: state.notes.map((note) {
        final nextDuration = updateMap[note.id];
        if (nextDuration == null) return note;
        final safeDuration = nextDuration
            .clamp(1, max(1, maxTick - note.startTick))
            .toInt();
        return note.copyWith(durationTicks: safeDuration);
      }).toList(),
    );
  }

  void splitSelectedNotesAtTick(int splitTick) {
    final selectedIds = state.selectedNoteIds;
    if (selectedIds.isEmpty) return;

    final splittable = state.notes
        .where(
          (note) =>
              selectedIds.contains(note.id) &&
              splitTick > note.startTick &&
              splitTick < note.startTick + note.durationTicks,
        )
        .toList();
    if (splittable.isEmpty) return;

    final splitIds = splittable.map((note) => note.id).toSet();
    final rightSelection = <String>{};
    final splitNotes = <PianoRollNote>[];
    for (final note in splittable) {
      final leftDuration = splitTick - note.startTick;
      final rightDuration = (note.startTick + note.durationTicks) - splitTick;
      final right = PianoRollNote(
        id: _makeId(),
        midiNote: note.midiNote,
        pitchClass: note.pitchClass,
        noteWithOctave: note.noteWithOctave,
        startTick: splitTick,
        durationTicks: rightDuration,
      );
      splitNotes.add(note.copyWith(durationTicks: leftDuration));
      splitNotes.add(right);
      rightSelection.add(right.id);
    }

    final untouchedSelection = selectedIds.difference(splitIds);
    state = state.copyWith(
      notes: [
        ...state.notes.where((note) => !splitIds.contains(note.id)),
        ...splitNotes,
      ],
      selectedNoteIds: {...rightSelection, ...untouchedSelection},
      latestImportedRange: () => null,
    );
  }

  void moveNote(String noteId, int newStartTick, [int? newMidiNote]) {
    final target = state.notes.where((n) => n.id == noteId).firstOrNull;
    if (target == null) return;
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    final boundedStart = newStartTick.clamp(0, max(0, maxTick - 1)).toInt();
    final midi = (newMidiNote ?? target.midiNote).clamp(
      state.pitchRangeStart,
      state.pitchRangeEnd,
    );
    if (!_isAllowedByActiveScale(midi)) return;
    final maxDuration = max<int>(1, maxTick - boundedStart);
    state = state.copyWith(
      notes: state.notes
          .map(
            (n) => n.id == noteId
                ? n.copyWith(
                    midiNote: midi,
                    pitchClass: rules.midiToPitchClass(midi),
                    noteWithOctave: rules.midiToNoteWithOctave(midi),
                    startTick: boundedStart,
                    durationTicks: min(n.durationTicks, maxDuration),
                  )
                : n,
          )
          .toList(),
    );
  }

  void moveNotesBatch(
    List<({String id, int startTick, int midiNote})> updates,
  ) {
    if (updates.isEmpty) return;
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    final updateMap = <String, ({int startTick, int midiNote})>{
      for (final u in updates)
        u.id: (startTick: u.startTick, midiNote: u.midiNote),
    };
    final nextNotesById = <String, PianoRollNote>{};
    for (final note in state.notes) {
      final update = updateMap[note.id];
      if (update == null) continue;
      final boundedStart = update.startTick
          .clamp(0, max(0, maxTick - 1))
          .toInt();
      final midi = update.midiNote.clamp(
        state.pitchRangeStart,
        state.pitchRangeEnd,
      );
      if (!_isAllowedByActiveScale(midi)) {
        return;
      }
      final maxDuration = max<int>(1, maxTick - boundedStart);
      nextNotesById[note.id] = note.copyWith(
        midiNote: midi,
        pitchClass: rules.midiToPitchClass(midi),
        noteWithOctave: rules.midiToNoteWithOctave(midi),
        startTick: boundedStart,
        durationTicks: min(note.durationTicks, maxDuration),
      );
    }
    state = state.copyWith(
      notes: state.notes.map((n) {
        return nextNotesById[n.id] ?? n;
      }).toList(),
    );
  }

  /// Returns the first column tick (on the snap grid) that has no notes, or
  /// the next free tick past the last note when every grid column is occupied.
  /// Used when adding a stack with no explicitly-selected column.
  int firstEmptyColumnTick() {
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    final snap = state.snapTicks <= 0 ? 1 : state.snapTicks;
    final occupied = state.notes.map((n) => n.startTick).toSet();
    for (var tick = 0; tick < maxTick; tick += snap) {
      if (!occupied.contains(tick)) return tick;
    }
    if (state.notes.isEmpty) return 0;
    final lastTick = state.notes
        .map((n) => n.startTick)
        .reduce((a, b) => a > b ? a : b);
    return (lastTick + snap).clamp(0, maxTick - 1).toInt();
  }

  int addNoteStack(List<int> midiNotes, int startTick, int durationTicks) {
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (startTick < 0 || startTick >= maxTick) return 0;
    final safe = durationTicks.clamp(1, maxTick - startTick);
    final unique = midiNotes.toSet().where(
      (m) => m >= state.pitchRangeStart && m <= state.pitchRangeEnd,
    );
    if (unique.isEmpty) return 0;
    if (unique.any((midi) => !_isAllowedByActiveScale(midi))) return 0;
    final created = unique.map(
      (midi) => PianoRollNote(
        id: _makeId(),
        midiNote: midi,
        pitchClass: rules.midiToPitchClass(midi),
        noteWithOctave: rules.midiToNoteWithOctave(midi),
        startTick: startTick,
        durationTicks: safe,
      ),
    );
    state = state.copyWith(
      notes: [...state.notes, ...created],
      latestImportedRange: _latestImportedRangeClearForNewNote(),
    );
    return unique.length;
  }

  void selectColumn(int? tick) =>
      state = state.copyWith(selectedColumnTick: () => tick);

  void selectNote(String? noteId) => state = state.copyWith(
    selectedNoteIds: noteId == null ? const <String>{} : {noteId},
  );

  List<PianoRollNote> getNotesAtSelectedColumn() {
    if (state.selectedColumnTick == null) return [];
    return rules.getNotesAtTick(state.notes, state.selectedColumnTick!);
  }

  void clearNotes() => state = state.copyWith(
    notes: [],
    selectedNoteIds: const <String>{},
    selectedColumnTick: () => null,
    latestImportedRange: () => null,
  );

  void setHighlightedNotes(List<String> notes) =>
      state = state.copyWith(highlightedNotes: notes);

  void removeNotesByPitchClass(List<String> pitchClasses) {
    final bad = Set<String>.from(pitchClasses);
    final removed = state.notes.where((n) => bad.contains(n.pitchClass));
    state = state.copyWith(
      notes: state.notes.where((n) => !bad.contains(n.pitchClass)).toList(),
      selectedNoteIds: state.selectedNoteIds.difference(
        removed.map((n) => n.id).toSet(),
      ),
    );
  }

  int suggestedImportAnchorTick() {
    final selectedTick = state.selectedColumnTick;
    if (selectedTick != null) {
      final maxTick = rules.totalTicks(
        state.config.timeSignature,
        state.config.totalMeasures,
      );
      return selectedTick.clamp(0, maxTick - 1).toInt();
    }
    if (state.notes.isEmpty) return 0;
    final measureTicks = rules.ticksPerMeasure(state.config.timeSignature);
    final latestEndTick = state.notes
        .map((note) => note.startTick + note.durationTicks)
        .reduce(max);
    return ((latestEndTick + measureTicks - 1) ~/ measureTicks) * measureTicks;
  }

  void _ensureTimelineCoversEndTick(int endTickExclusive) {
    final measureTicks = rules.ticksPerMeasure(state.config.timeSignature);
    final requiredMeasures = max(
      1,
      (endTickExclusive + measureTicks - 1) ~/ measureTicks,
    );
    if (requiredMeasures > state.config.totalMeasures) {
      setTotalMeasures(requiredMeasures);
    }
  }

  ({
    int createdCount,
    bool truncated,
    int? firstStartTick,
    int? furthestEndTick,
  })
  appendImportedNotes(List<QuantizedHumNote> imported) {
    if (imported.isEmpty) {
      return (
        createdCount: 0,
        truncated: false,
        firstStartTick: null,
        furthestEndTick: null,
      );
    }
    final clamped = imported
        .where((note) => note.durationTicks > 0)
        .map(
          (note) => QuantizedHumNote(
            midiNote: note.midiNote.clamp(
              state.pitchRangeStart,
              state.pitchRangeEnd,
            ),
            startTick: note.startTick,
            durationTicks: note.durationTicks,
          ),
        )
        .toList();
    if (clamped.isEmpty) {
      return (
        createdCount: 0,
        truncated: false,
        firstStartTick: null,
        furthestEndTick: null,
      );
    }

    final requestedFurthestEndTick = clamped
        .map((note) => note.startTick + note.durationTicks)
        .reduce(max);
    _ensureTimelineCoversEndTick(requestedFurthestEndTick);
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    var truncated = false;

    final created = clamped.map((note) {
      final boundedStart = note.startTick.clamp(0, maxTick - 1);
      final boundedDuration = min(note.durationTicks, maxTick - boundedStart);
      if (boundedStart != note.startTick ||
          boundedDuration != note.durationTicks) {
        truncated = true;
      }
      return PianoRollNote(
        id: _makeId(),
        midiNote: note.midiNote,
        pitchClass: rules.midiToPitchClass(note.midiNote),
        noteWithOctave: rules.midiToNoteWithOctave(note.midiNote),
        startTick: boundedStart,
        durationTicks: max(1, boundedDuration),
      );
    }).toList();

    state = state.copyWith(
      notes: [...state.notes, ...created],
      selectedNoteIds: created.map((note) => note.id).toSet(),
    );
    final firstCreatedStartTick = created
        .map((note) => note.startTick)
        .reduce(min);
    final furthestCreatedEndTick = created
        .map((note) => note.startTick + note.durationTicks)
        .reduce(max);
    return (
      createdCount: created.length,
      truncated: truncated,
      firstStartTick: firstCreatedStartTick,
      furthestEndTick: furthestCreatedEndTick,
    );
  }

  void loadSnapshot(PianoRollSnapshot snap) {
    final config = PianoRollConfig(
      tempo: snap.tempo,
      key: snap.key,
      timeSignature: TimeSignature(
        beatsPerMeasure: snap.numerator,
        beatUnit: snap.denominator,
      ),
      totalMeasures: snap.totalMeasures,
    );
    final notes = snap.notes.map((n) {
      final midiNote = n['midiNote'] as int? ?? 60;
      return PianoRollNote(
        id: _makeId(),
        midiNote: midiNote,
        pitchClass: rules.midiToPitchClass(midiNote),
        noteWithOctave: rules.midiToNoteWithOctave(midiNote),
        startTick: n['startTick'] as int? ?? 0,
        durationTicks: n['durationTicks'] as int? ?? 480,
      );
    }).toList();
    state = PianoRollState(
      config: config,
      notes: notes,
      pitchRangeStart: snap.pitchRangeStart,
      pitchRangeEnd: snap.pitchRangeEnd,
      selectedColumnTick: snap.selectedColumnTick,
      selectedNoteIds: const <String>{},
      snapTicks: snap.snapTicks,
      highlightedNotes: List<String>.from(snap.highlightedNotes),
      latestImportedRange: null,
    );
  }

  void reset() => state = rules.getDefaultPianoRollState().copyWith(
    latestImportedRange: () => null,
  );
}

final pianoRollProvider = NotifierProvider<PianoRollNotifier, PianoRollState>(
  PianoRollNotifier.new,
);

final pianoRollPendingScaleProvider =
    StateProvider<({String root, String scaleName})?>((_) => null);

final pianoRollActiveScaleProvider =
    StateProvider<({String root, String scaleName})?>((_) => null);

final pianoRollScrollToTickProvider = StateProvider<int?>((_) => null);
