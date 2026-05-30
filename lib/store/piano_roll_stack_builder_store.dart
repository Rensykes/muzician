library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano_roll_stack_builder.dart';
import '../schema/rules/piano_roll_stack_builder_rules.dart';
import '../models/piano_roll.dart';
import '../utils/note_utils.dart';
import 'piano_roll_store.dart';

class PianoRollStackBuilderNotifier
    extends Notifier<PianoRollStackBuilderState> {
  @override
  PianoRollStackBuilderState build() {
    final state = defaultStackBuilderState;
    final recognition = recognizeStack(state.midiNotes);
    return state.copyWith(recognition: recognition);
  }

  // ── Internal helpers ───────────────────────────────────────────────────

  void _clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: () => null);
    }
  }

  void _updateWith(List<int> midiNotes) {
    final clamped = enforceMaxNotes(midiNotes);
    final recognition = recognizeStack(clamped);
    state = state.copyWith(
      midiNotes: clamped,
      recognition: recognition,
      errorMessage: () => null,
    );
  }

  bool _isDuplicate(int midiNote) => state.midiNotes.contains(midiNote);

  // ── View ───────────────────────────────────────────────────────────────

  void switchView(PianoRollStackBuilderView view) {
    _clearError();
    state = state.copyWith(activeView: view);
  }

  // ── Canonical controls ─────────────────────────────────────────────────

  void setCanonicalRoot(String root) {
    final invIndex = state.recognition.recognizedInversionIndex ?? 0;
    final result = retargetCanonicalStack(
      currentMidiNotes: state.midiNotes,
      root: root,
      quality: state.recognition.recognizedQuality ?? '',
      inversionIndex: invIndex,
    );
    _updateWith(result);
  }

  void setCanonicalQuality(String quality) {
    final root = state.recognition.recognizedRoot ?? 'C';
    final invIndex = state.recognition.recognizedInversionIndex ?? 0;
    final result = retargetCanonicalStack(
      currentMidiNotes: state.midiNotes,
      root: root,
      quality: quality,
      inversionIndex: invIndex,
    );
    _updateWith(result);
  }

  void setCanonicalInversion(int inversionIndex) {
    final root = state.recognition.recognizedRoot ?? 'C';
    final quality = state.recognition.recognizedQuality ?? '';
    final result = retargetCanonicalStack(
      currentMidiNotes: state.midiNotes,
      root: root,
      quality: quality,
      inversionIndex: inversionIndex,
    );
    _updateWith(result);
  }

  void setDurationTicks(int ticks) {
    _clearError();
    state = state.copyWith(durationTicks: ticks);
  }

  // ── Advanced edits ─────────────────────────────────────────────────────

  bool addAbsoluteNote(int midiNote) {
    if (state.midiNotes.length >= 10) {
      state = state.copyWith(errorMessage: () => 'Maximum 10 notes');
      return false;
    }
    if (_isDuplicate(midiNote)) {
      final name = _midiToName(midiNote);
      state = state.copyWith(
        errorMessage: () => '$name already exists in the stack',
      );
      return false;
    }
    final updated = [...state.midiNotes, midiNote];
    _updateWith(updated);
    return true;
  }

  bool replaceNoteAt(int index, int midiNote) {
    if (index < 0 || index >= state.midiNotes.length) {
      return false;
    }
    if (_isDuplicate(midiNote) && state.midiNotes[index] != midiNote) {
      final name = _midiToName(midiNote);
      state = state.copyWith(
        errorMessage: () => '$name already exists in the stack',
      );
      return false;
    }
    final notes = [...state.midiNotes];
    notes[index] = midiNote;
    _updateWith(notes);
    return true;
  }

  void removeNoteAt(int index) {
    if (index < 0 || index >= state.midiNotes.length) return;
    final notes = [...state.midiNotes]..removeAt(index);
    _updateWith(notes);
  }

  void reorderNotes(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= state.midiNotes.length ||
        newIndex < 0 ||
        newIndex >= state.midiNotes.length ||
        oldIndex == newIndex) {
      return;
    }
    final notes = [...state.midiNotes];
    final item = notes.removeAt(oldIndex);
    notes.insert(newIndex, item);
    _updateWith(notes);
  }

  void replaceAllNotes(List<int> midiNotes) {
    _updateWith(midiNotes);
  }

  void insertDegreeShortcut(String degree) {
    final root = state.recognition.recognizedRoot ?? 'C';
    final degreeNum = int.tryParse(degree);
    if (degreeNum == null) return;

    const intervals = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23];
    if (degreeNum < 1 || degreeNum > intervals.length) return;

    final semitones = intervals[degreeNum - 1];
    final rootPc = noteToPC[root] ?? 0;
    final targetPc = (rootPc + semitones) % 12;

    final highest = state.midiNotes.isEmpty
        ? 60
        : state.midiNotes.reduce((a, b) => a > b ? a : b);
    var candidate = ((highest ~/ 12) * 12) + targetPc;
    if (candidate <= highest) candidate += 12;

    addAbsoluteNote(candidate);
  }

  void clearError() {
    state = state.copyWith(errorMessage: () => null);
  }

  // ── Add Stack → Piano Roll ─────────────────────────────────────────────

  bool addStack() {
    final prState = ref.read(pianoRollProvider);
    final prNotifier = ref.read(pianoRollProvider.notifier);
    final startTick =
        prState.selectedColumnTick ?? prNotifier.firstEmptyColumnTick();
    final createdCount = prNotifier.addNoteStack(
      state.midiNotes,
      startTick,
      state.durationTicks,
    );
    if (createdCount == 0) {
      final activeScale = ref.read(pianoRollActiveScaleProvider);
      final scaleLabel = activeScale == null
          ? null
          : scaleGroups.values
                .expand((group) => group)
                .firstWhere(
                  (entry) => entry.$1 == activeScale.scaleName,
                  orElse: () => (activeScale.scaleName, activeScale.scaleName),
                )
                .$2;
      final error = activeScale == null
          ? 'Unable to add this stack at the current position'
          : 'Stack contains notes outside ${formatRootChoiceLabel(activeScale.root)} $scaleLabel. Clear the scale pill to add chromatic notes.';
      state = state.copyWith(errorMessage: () => error);
      return false;
    }
    prNotifier.selectColumn(startTick);
    state = state.copyWith(
      lastAddedNotes: List.of(state.midiNotes),
      lastAddedDurationTicks: state.durationTicks,
      errorMessage: () => null,
    );
    return true;
  }

  void quickAddStack() {
    final prState = ref.read(pianoRollProvider);
    final prNotifier = ref.read(pianoRollProvider.notifier);
    final hasSelection = prState.selectedNoteIds.isNotEmpty;

    if (hasSelection) {
      _quickCopySelected(prNotifier, prState);
    } else if (state.lastAddedNotes.isNotEmpty) {
      _quickRepeatLast(prNotifier, prState);
    }
  }

  void _quickCopySelected(
    PianoRollNotifier prNotifier,
    PianoRollState prState,
  ) {
    if (prState.selectedNoteIds.isEmpty) return;
    final selectedNotes = prState.notes
        .where((n) => prState.selectedNoteIds.contains(n.id))
        .toList();
    if (selectedNotes.isEmpty) return;

    final earliestTick = selectedNotes
        .map((n) => n.startTick)
        .reduce((a, b) => a < b ? a : b);
    final destTick = prState.selectedColumnTick ?? 0;

    for (final note in selectedNotes) {
      final offset = note.startTick - earliestTick;
      prNotifier.addNote(note.midiNote, destTick + offset, note.durationTicks);
    }
    prNotifier.selectColumn(destTick);

    state = state.copyWith(
      lastAddedNotes: selectedNotes.map((n) => n.midiNote).toList(),
      lastAddedDurationTicks: selectedNotes
          .map((n) => n.durationTicks)
          .reduce((a, b) => a > b ? a : b),
      errorMessage: () => null,
    );
  }

  void _quickRepeatLast(PianoRollNotifier prNotifier, PianoRollState prState) {
    final startTick = prState.selectedColumnTick ?? 0;
    prNotifier.addNoteStack(
      state.lastAddedNotes,
      startTick,
      state.lastAddedDurationTicks,
    );
    prNotifier.selectColumn(startTick);
  }

  String _midiToName(int midi) => formatMidiNoteLabel(midi);
}

final pianoRollStackBuilderProvider =
    NotifierProvider<PianoRollStackBuilderNotifier, PianoRollStackBuilderState>(
      PianoRollStackBuilderNotifier.new,
    );
