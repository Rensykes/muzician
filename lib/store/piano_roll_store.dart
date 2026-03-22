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
      config: state.config
          .copyWith(tempo: tempo.clamp(rules.minTempo, rules.maxTempo)));

  void setKey(String? key) =>
      state = state.copyWith(config: state.config.copyWith(key: key));

  void setTimeSignature(TimeSignature ts) {
    final maxTick = rules.totalTicks(ts, state.config.totalMeasures);
    final notes = state.notes
        .where((n) => n.startTick < maxTick)
        .map((n) => n.copyWith(
            durationTicks: min(n.durationTicks, max(1, maxTick - n.startTick))))
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
    final maxTick =
        rules.totalTicks(state.config.timeSignature, nextMeasures);
    final notes = state.notes
        .where((n) => n.startTick < maxTick)
        .map((n) => n.copyWith(
            durationTicks: min(n.durationTicks, max(1, maxTick - n.startTick))))
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
        .where(
            (n) => n.midiNote == midiNote && n.startTick == startTick)
        .toList();
    if (existing.isNotEmpty) {
      state = state.copyWith(
        notes: state.notes
            .where((n) => n.id != existing.first.id)
            .toList(),
        selectedNoteId: () =>
            state.selectedNoteId == existing.first.id
                ? null
                : state.selectedNoteId,
      );
      return;
    }
    final maxTick = rules.totalTicks(
        state.config.timeSignature, state.config.totalMeasures);
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
      selectedNoteId: () => note.id,
    );
  }

  void addNote(int midiNote, int startTick, int durationTicks) {
    final maxTick = rules.totalTicks(
        state.config.timeSignature, state.config.totalMeasures);
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
      selectedNoteId: () => note.id,
    );
  }

  void removeNote(String noteId) => state = state.copyWith(
        notes: state.notes.where((n) => n.id != noteId).toList(),
        selectedNoteId: () =>
            state.selectedNoteId == noteId ? null : state.selectedNoteId,
      );

  void resizeNote(String noteId, int durationTicks) {
    final target = state.notes.where((n) => n.id == noteId).firstOrNull;
    if (target == null) return;
    final maxTick = rules.totalTicks(
        state.config.timeSignature, state.config.totalMeasures);
    final safe = durationTicks.clamp(1, max(1, maxTick - target.startTick)).toInt();
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
        state.config.timeSignature, state.config.totalMeasures);
    final boundedStart = newStartTick.clamp(0, max(0, maxTick - 1)).toInt();
    final midi =
        (newMidiNote ?? target.midiNote).clamp(state.pitchRangeStart, state.pitchRangeEnd);
    final maxDuration = max<int>(1, maxTick - boundedStart);
    state = state.copyWith(
      notes: state.notes
          .map((n) => n.id == noteId
              ? n.copyWith(
                  midiNote: midi,
                  pitchClass: rules.midiToPitchClass(midi),
                  noteWithOctave: rules.midiToNoteWithOctave(midi),
                  startTick: boundedStart,
                  durationTicks: min(n.durationTicks, maxDuration),
                )
              : n)
          .toList(),
    );
  }

  void addNoteStack(List<int> midiNotes, int startTick, int durationTicks) {
    final maxTick = rules.totalTicks(
        state.config.timeSignature, state.config.totalMeasures);
    if (startTick < 0 || startTick >= maxTick) return;
    final safe = durationTicks.clamp(1, maxTick - startTick);
    final unique = midiNotes.toSet().where(
        (m) => m >= state.pitchRangeStart && m <= state.pitchRangeEnd);
    if (unique.isEmpty) return;
    final created = unique.map((midi) => PianoRollNote(
          id: _makeId(),
          midiNote: midi,
          pitchClass: rules.midiToPitchClass(midi),
          noteWithOctave: rules.midiToNoteWithOctave(midi),
          startTick: startTick,
          durationTicks: safe,
        ));
    state = state.copyWith(notes: [...state.notes, ...created]);
  }

  void selectColumn(int? tick) =>
      state = state.copyWith(selectedColumnTick: () => tick);

  void selectNote(String? noteId) =>
      state = state.copyWith(selectedNoteId: () => noteId);

  List<PianoRollNote> getNotesAtSelectedColumn() {
    if (state.selectedColumnTick == null) return [];
    return rules.getNotesAtTick(state.notes, state.selectedColumnTick!);
  }

  void clearNotes() => state = state.copyWith(
        notes: [],
        selectedColumnTick: () => null,
        selectedNoteId: () => null,
      );

  void reset() => state = rules.getDefaultPianoRollState();
}

final pianoRollProvider =
    NotifierProvider<PianoRollNotifier, PianoRollState>(PianoRollNotifier.new);
