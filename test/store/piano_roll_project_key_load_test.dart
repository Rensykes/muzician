import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/piano_roll_store.dart';

PianoRollSnapshot _snapshot({
  String? key = 'C',
  List<String> highlightedNotes = const ['C', 'E', 'G'],
  PendingScale? pendingScale = const PendingScale(
    root: 'C',
    scaleName: 'major',
  ),
}) => PianoRollSnapshot(
  tempo: 111,
  key: key,
  numerator: 4,
  denominator: 4,
  totalMeasures: 8,
  notes: const [
    {'midiNote': 64, 'startTick': 0, 'durationTicks': 4},
  ],
  pitchRangeStart: 40,
  pitchRangeEnd: 84,
  selectedColumnTick: 0,
  snapTicks: 2,
  highlightedNotes: highlightedNotes,
  pendingScale: pendingScale,
);

void main() {
  test(
    'same-project load keeps master key and highlight while loading notes',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pianoRollProvider.notifier);

      notifier.loadSnapshot(
        _snapshot(),
        projectConfig: const ProjectConfig(
          keyRootPc: 7,
          keyScaleName: 'major',
          tempo: 96,
          beatsPerBar: 3,
          beatUnit: 4,
        ),
      );

      final state = container.read(pianoRollProvider);
      expect(state.config.key, 'G');
      expect(state.config.tempo, 96);
      expect(state.config.timeSignature.beatsPerMeasure, 3);
      expect(
        state.highlightedNotes,
        containsAll(['G', 'A', 'B', 'C', 'D', 'E', 'F#']),
      );
      expect(state.notes.single.midiNote, 64);
      expect(container.read(pianoRollActiveScaleProvider), (
        root: 'G',
        scaleName: 'major',
      ));
      expect(container.read(pianoRollPendingScaleProvider), isNull);
    },
  );

  test('Dump/local load restores the snapshot key and scale', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pianoRollProvider.notifier);

    notifier.loadSnapshot(_snapshot());

    final state = container.read(pianoRollProvider);
    expect(state.config.key, 'C');
    expect(state.config.tempo, 111);
    expect(state.config.timeSignature.beatsPerMeasure, 4);
    expect(state.highlightedNotes, ['C', 'E', 'G']);
    expect(container.read(pianoRollActiveScaleProvider), (
      root: 'C',
      scaleName: 'major',
    ));
    expect(container.read(pianoRollPendingScaleProvider), isNull);
  });

  test('a project without a key clears stale snapshot scale metadata', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pianoRollProvider.notifier);

    notifier.loadSnapshot(_snapshot(), projectConfig: const ProjectConfig());

    final state = container.read(pianoRollProvider);
    expect(state.config.key, isNull);
    expect(state.highlightedNotes, isEmpty);
    expect(state.notes.single.midiNote, 64);
    expect(container.read(pianoRollActiveScaleProvider), isNull);
    expect(container.read(pianoRollPendingScaleProvider), isNull);
  });
}
