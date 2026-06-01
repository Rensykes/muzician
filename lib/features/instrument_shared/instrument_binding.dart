// lib/features/instrument_shared/instrument_binding.dart
/// Binding contracts that let generic instrument widgets work against any of
/// the instrument stores without merging them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';

/// Minimal mutation surface the shared scale picker needs. Satisfied by every
/// instrument notifier (Fretboard, Piano, Piano Roll).
abstract interface class ScaleActions {
  void setHighlightedNotes(List<String> notes);
  void removeNotesByPitchClass(List<String> notes);
}

/// Full selection surface for the detection panel + chord pickers.
/// Satisfied by Fretboard and Piano notifiers.
abstract interface class SelectionActions implements ScaleActions {
  void clearSelectedNotes();
  void toggleFocusedNote(String note);
}

/// Everything `SharedScalePicker` needs from an instrument.
class ScalePickerBinding {
  /// Current selected pitch classes, for out-of-key conflict detection.
  final ProviderListenable<List<String>> selectedPitchClasses;

  /// Currently highlighted scale pitch classes.
  final ProviderListenable<List<String>> highlightedNotes;

  /// Resolves the mutation surface against a ref.
  final ScaleActions Function(WidgetRef) actions;

  /// Scale hand-off providers, shared with the detection panel.
  final StateProvider<({String root, String scaleName})?> pendingScale;
  final StateProvider<({String root, String scaleName})?> activeScale;

  const ScalePickerBinding({
    required this.selectedPitchClasses,
    required this.highlightedNotes,
    required this.actions,
    required this.pendingScale,
    required this.activeScale,
  });
}

/// Adds the detection panel + chord picker surface. Fretboard + Piano only.
class InstrumentBinding extends ScalePickerBinding {
  final ProviderListenable<List<ExactSelectionNote>> exactNotes;

  /// Full selected note-name list shown as chips in the detection panel.
  /// (Pitch-class names; see [selectedPitchClasses] for the conflict-check set.)
  final ProviderListenable<List<String>> selectedNotes;
  final ProviderListenable<Set<String>> focusedNotes;

  final StateProvider<({String root, String quality})?> pendingChord;
  final StateProvider<({String root, String quality})?> activeChord;
  final StateProvider<int> manualEdit;
  final StateProvider<bool> chordCommitted;

  /// Chord qualities this instrument's chord picker offers.
  final List<String> chordQualitySymbols;

  const InstrumentBinding({
    required super.selectedPitchClasses,
    required super.highlightedNotes,
    required SelectionActions Function(WidgetRef) actions,
    required super.pendingScale,
    required super.activeScale,
    required this.exactNotes,
    required this.selectedNotes,
    required this.focusedNotes,
    required this.pendingChord,
    required this.activeChord,
    required this.manualEdit,
    required this.chordCommitted,
    required this.chordQualitySymbols,
  })  : selectionActions = actions,
        super(actions: actions);

  /// Same callback as [actions] but typed to the wider [SelectionActions].
  /// Prefer this over [ScalePickerBinding.actions] when holding an
  /// [InstrumentBinding] so the full selection surface stays in scope.
  final SelectionActions Function(WidgetRef) selectionActions;
}
