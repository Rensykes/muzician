import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/features/instrument_shared/instrument_binding.dart';

void main() {
  test('notifiers implement the shared action interfaces', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(fretboardProvider.notifier), isA<SelectionActions>());
    expect(container.read(pianoProvider.notifier), isA<SelectionActions>());
    expect(container.read(pianoRollProvider.notifier), isA<ScaleActions>());
  });

  test('bindings expose live reads', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(fretboardBinding.selectedPitchClasses), isA<List<String>>());
    expect(container.read(pianoBinding.exactNotes), isNotNull);
    expect(container.read(pianoRollScaleBinding.highlightedNotes), isA<List<String>>());
  });
}
