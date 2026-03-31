/// Piano Roll Riverpod Store
library;

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano_roll.dart';
import '../schema/rules/piano_roll_rules.dart' as rules;

class PianoRollNotifier extends Notifier<PianoRollState> {
  @override
  PianoRollState build() => rules.getDefaultPianoRollState();

  String _makeId() =>
      'pr_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999).toString().padLeft(6, '0')}';

  int _clamp(int value, int minV, int maxV) => value.clamp(minV, maxV);

  void setTempo(int tempo) => state = state.copyWith(
    config: state.config.copyWith(
      tempo: tempo.clamp(rules.minTempo, rules.maxTempo),
    ),
  );

  void setKey(String? key) =>
      state = state.copyWith(config: state.config.copyWith(key: key));

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
    );
  }

  void addNote(int midiNote, int startTick, int durationTicks) {
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (startTick < 0 || startTick >= maxTick) return;
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
    state = state.copyWith(
      notes: state.notes.map((n) {
        final u = updateMap[n.id];
        if (u == null) return n;
        final boundedStart = u.startTick.clamp(0, max(0, maxTick - 1)).toInt();
        final midi = u.midiNote.clamp(
          state.pitchRangeStart,
          state.pitchRangeEnd,
        );
        final maxDuration = max<int>(1, maxTick - boundedStart);
        return n.copyWith(
          midiNote: midi,
          pitchClass: rules.midiToPitchClass(midi),
          noteWithOctave: rules.midiToNoteWithOctave(midi),
          startTick: boundedStart,
          durationTicks: min(n.durationTicks, maxDuration),
        );
      }).toList(),
    );
  }

  void addNoteStack(List<int> midiNotes, int startTick, int durationTicks) {
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (startTick < 0 || startTick >= maxTick) return;
    final safe = durationTicks.clamp(1, maxTick - startTick);
    final unique = midiNotes.toSet().where(
      (m) => m >= state.pitchRangeStart && m <= state.pitchRangeEnd,
    );
    if (unique.isEmpty) return;
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
    state = state.copyWith(notes: [...state.notes, ...created]);
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

  void reset() => state = rules.getDefaultPianoRollState();
}

final pianoRollProvider = NotifierProvider<PianoRollNotifier, PianoRollState>(
  PianoRollNotifier.new,
);

final pianoRollPendingScaleProvider =
    StateProvider<({String root, String scaleName})?>((_) => null);
