// test/features/instrument_shared/instrument_binding_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/instrument_binding.dart';
import 'package:muzician/models/harmonic_analysis.dart';

class _FakeActions implements SelectionActions {
  final List<String> highlighted = [];
  final List<String> removed = [];
  bool cleared = false;
  String? toggled;
  @override
  void setHighlightedNotes(List<String> notes) => highlighted
    ..clear()
    ..addAll(notes);
  @override
  void removeNotesByPitchClass(List<String> notes) => removed.addAll(notes);
  @override
  void clearSelectedNotes() => cleared = true;
  @override
  void toggleFocusedNote(String note) => toggled = note;
}

void main() {
  test('InstrumentBinding exposes scale + detection surface', () {
    final selected = Provider<List<String>>((_) => const ['C', 'E', 'G']);
    final highlighted = Provider<List<String>>((_) => const <String>[]);
    final focused = Provider<Set<String>>((_) => const <String>{});
    final exact = Provider<List<ExactSelectionNote>>((_) => const []);
    final pendingScale = StateProvider<({String root, String scaleName})?>(
      (_) => null,
    );
    final activeScale = StateProvider<({String root, String scaleName})?>(
      (_) => null,
    );
    final pendingChord = StateProvider<({String root, String quality})?>(
      (_) => null,
    );
    final activeChord = StateProvider<({String root, String quality})?>(
      (_) => null,
    );
    final manualEdit = StateProvider<int>((_) => 0);
    final committed = StateProvider<bool>((_) => false);

    final actions = _FakeActions();
    final binding = InstrumentBinding(
      selectedPitchClasses: selected,
      highlightedNotes: highlighted,
      actions: (_) => actions,
      pendingScale: pendingScale,
      activeScale: activeScale,
      selectedNotes: selected,
      focusedNotes: focused,
      exactNotes: exact,
      pendingChord: pendingChord,
      activeChord: activeChord,
      manualEdit: manualEdit,
      chordCommitted: committed,
    );

    final ScalePickerBinding scaleView = binding;
    expect(scaleView.activeScale, same(activeScale));
  });
}
