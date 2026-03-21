/// Piano Riverpod Store

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano.dart';
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
    List<PianoCoordinate> nextKeys;
    if (state.viewMode == PianoViewMode.exact ||
        state.viewMode == PianoViewMode.exactFocus) {
      final idx = keys.indexWhere((k) => k.midiNote == midiNote);
      if (idx >= 0) {
        nextKeys = List.of(keys)..removeAt(idx);
      } else {
        nextKeys = [
          ...keys,
          PianoCoordinate(
              keyIndex: keyIndex, midiNote: midiNote, noteName: noteName)
        ];
      }
    } else {
      final hasPitchClass = keys.any((k) => k.noteName == noteName);
      nextKeys = hasPitchClass
          ? keys.where((k) => k.noteName != noteName).toList()
          : [
              ...keys,
              PianoCoordinate(
                  keyIndex: keyIndex, midiNote: midiNote, noteName: noteName)
            ];
    }
    final selectedNotes = nextKeys.map((k) => k.noteName).toSet().toList();
    state = state.copyWith(selectedKeys: nextKeys, selectedNotes: selectedNotes);
  }

  void clearSelectedNotes() => state = state.copyWith(
        selectedNotes: [],
        selectedKeys: [],
        viewMode: PianoViewMode.pitchClass,
      );

  void setViewMode(PianoViewMode mode) =>
      state = state.copyWith(viewMode: mode);

  void loadExactMidis(List<int> midis) {
    final allKeys = getKeys();
    final keyMap = {for (final k in allKeys) k.midiNote: k};
    final selectedKeys = <PianoCoordinate>[];
    for (final midi in midis) {
      final key = keyMap[midi];
      if (key == null) continue;
      selectedKeys.add(PianoCoordinate(
        keyIndex: key.keyIndex,
        midiNote: key.midiNote,
        noteName: key.noteName,
      ));
    }
    final selectedNotes =
        selectedKeys.map((k) => k.noteName).toSet().toList();
    state = state.copyWith(
        selectedKeys: selectedKeys,
        selectedNotes: selectedNotes,
        viewMode: PianoViewMode.exact);
  }

  void reset() => state = getDefaultPianoState();
}

final pianoProvider =
    NotifierProvider<PianoNotifier, PianoState>(PianoNotifier.new);

final pianoPendingChordProvider =
    StateProvider<({String root, String quality})?>((_) => null);

final pianoPendingScaleProvider =
    StateProvider<({String root, String scaleName})?>((_) => null);
