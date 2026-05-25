/// Piano Roll Composer Riverpod Store
/// Manages shared chord-stack composer state: root, quality, duration.
///
/// Used by both the V1 stack selector panel and the V2 docked toolbar.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano_roll_composer.dart';
import '../schema/rules/piano_roll_import_rules.dart' as import_rules;
import 'piano_roll_store.dart';

class PianoRollComposerNotifier extends Notifier<PianoRollComposerState> {
  @override
  PianoRollComposerState build() => PianoRollComposerState.defaultState;

  void setRoot(String root) {
    state = state.copyWith(root: root);
  }

  void setQuality(String quality) {
    state = state.copyWith(quality: quality);
  }

  void setDuration(int ticks) {
    state = state.copyWith(durationTicks: ticks);
  }

  /// Builds a chord stack from the current composer state and places it on
  /// the piano roll.
  ///
  /// Reads the pitch range from [pianoRollProvider] to compute the anchor
  /// MIDI and calls [buildChordStackMidis] to map chord tones to MIDI notes
  /// nearest that anchor within the range. Notes are placed at the current
  /// [selectedColumnTick] or at tick 0 if no column is selected.
  void addStack() {
    final prState = ref.read(pianoRollProvider);
    final prNotifier = ref.read(pianoRollProvider.notifier);

    // Anchor at the centre of the pitch range so chord tones spread evenly.
    final anchor = ((prState.pitchRangeStart + prState.pitchRangeEnd) / 2)
        .round();

    final midiStack = import_rules.buildChordStackMidis(
      state.root,
      state.quality,
      anchor,
      prState.pitchRangeStart,
      prState.pitchRangeEnd,
    );

    if (midiStack.isEmpty) return;

    final startTick = prState.selectedColumnTick ?? 0;

    prNotifier.addNoteStack(midiStack, startTick, state.durationTicks);
    prNotifier.selectColumn(startTick);
  }
}

final pianoRollComposerProvider =
    NotifierProvider<PianoRollComposerNotifier, PianoRollComposerState>(
      PianoRollComposerNotifier.new,
    );
