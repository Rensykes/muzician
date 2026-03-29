/// Piano Riverpod Store
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano.dart';
import '../models/save_system.dart' show PianoSnapshot;
import '../schema/rules/piano_rules.dart';

class PianoNotifier extends Notifier<PianoState> {
  @override
  PianoState build() => getDefaultPianoState();

  PianoRange getCurrentRange() => pianoRanges[state.currentRange]!;

  List<PianoKeyCell> getKeys() => getKeysForRange(state.currentRange);

  void setRange(PianoRangeName range) =>
      state = state.copyWith(currentRange: range);

  void setHighlightedNotes(List<String> notes) =>
      state = state.copyWith(highlightedNotes: notes);

  void toggleKey(int keyIndex, int midiNote, String noteName) {
    final keys = state.selectedKeys;
    final idx = keys.indexWhere((k) => k.midiNote == midiNote);
    final List<PianoCoordinate> nextKeys;
    if (idx >= 0) {
      nextKeys = List.of(keys)..removeAt(idx);
    } else {
      nextKeys = [
        ...keys,
        PianoCoordinate(
          keyIndex: keyIndex,
          midiNote: midiNote,
          noteName: noteName,
        ),
      ];
    }
    final selectedNotes = nextKeys.map((k) => k.noteName).toSet().toList();
    // Remove focused pitch classes that no longer have any tapped key.
    final remainingPc = nextKeys.map((k) => k.noteName).toSet();
    final newFocused = state.focusedNotes.intersection(remainingPc);
    state = state.copyWith(
      selectedKeys: nextKeys,
      selectedNotes: selectedNotes,
      focusedNotes: newFocused,
    );
    ref.read(pianoManualEditProvider.notifier).state++;
  }

  void clearSelectedNotes() =>
      state = state.copyWith(
        selectedNotes: [],
        selectedKeys: [],
        focusedNotes: {},
      );

  void removeNotesByPitchClass(List<String> noteNames) {
    final bad = Set<String>.from(noteNames);
    final newKeys = state.selectedKeys
        .where((k) => !bad.contains(k.noteName))
        .toList();
    final newNotes = newKeys.map((k) => k.noteName).toSet().toList();
    state = state.copyWith(selectedKeys: newKeys, selectedNotes: newNotes);
  }

  void setViewMode(PianoViewMode mode) =>
      state = state.copyWith(viewMode: mode);

  void setFocusedNote(String? note) =>
      state = state.copyWith(focusedNotes: {});

  void toggleFocusedNote(String note) {
    final next = Set<String>.from(state.focusedNotes);
    if (next.contains(note)) {
      next.remove(note);
    } else {
      next.add(note);
    }
    state = state.copyWith(focusedNotes: next);
  }

  void loadExactMidis(List<int> midis) {
    final allKeys = getKeys();
    final keyMap = {for (final k in allKeys) k.midiNote: k};
    final selectedKeys = <PianoCoordinate>[];
    for (final midi in midis) {
      final key = keyMap[midi];
      if (key == null) continue;
      selectedKeys.add(
        PianoCoordinate(
          keyIndex: key.keyIndex,
          midiNote: key.midiNote,
          noteName: key.noteName,
        ),
      );
    }
    final selectedNotes = selectedKeys.map((k) => k.noteName).toSet().toList();
    state = state.copyWith(
      selectedKeys: selectedKeys,
      selectedNotes: selectedNotes,
    );
  }

  void loadSnapshot(PianoSnapshot snap) {
    state = PianoState(
      currentRange: snap.currentRange,
      highlightedNotes: const [],
      selectedNotes: List<String>.from(snap.selectedNotes),
      selectedKeys: List<PianoCoordinate>.from(snap.selectedKeys),
      viewMode: snap.viewMode,
    );
  }

  void reset() => state = getDefaultPianoState();
}

final pianoProvider = NotifierProvider<PianoNotifier, PianoState>(
  PianoNotifier.new,
);

final pianoPendingChordProvider =
    StateProvider<({String root, String quality})?>((_) => null);

final pianoPendingScaleProvider =
    StateProvider<({String root, String scaleName})?>((_) => null);

/// MIDI note the keyboard should animate to (one-shot, cleared after use).
final pianoScrollToMidiProvider = StateProvider<int?>((_) => null);

/// Incremented each time the user manually taps a key on the piano.
/// Consumers (e.g. PianoChordPicker) listen to this to clear committed state.
final pianoManualEditProvider = StateProvider<int>((_) => 0);

/// True while the user has committed a piano chord voicing (tapped a voicing card).
/// Cleared when the user manually edits the keyboard.
final pianoChordCommittedProvider = StateProvider<bool>((_) => false);
