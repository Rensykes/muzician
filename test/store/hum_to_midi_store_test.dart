import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/store/hum_to_midi_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/utils/mic_pitch_session.dart';

class _FakeMicPitchSession implements MicPitchSession {
  final _controller = StreamController<PitchFrame>.broadcast();
  bool permissionGranted = true;
  bool startCalled = false;
  bool stopCalled = false;

  void emit(PitchFrame frame) => _controller.add(frame);

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<Stream<PitchFrame>> start() async {
    startCalled = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  test('startRecording enters recording when permission is granted', () async {
    final fake = _FakeMicPitchSession();
    final container = ProviderContainer(
      overrides: [micPitchSessionProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(humToMidiProvider.notifier).startRecording();

    final state = container.read(humToMidiProvider);
    expect(fake.startCalled, isTrue);
    expect(state.status, HumToMidiStatus.recording);
  });

  test('stopRecording imports finalized notes into the piano roll', () async {
    final fake = _FakeMicPitchSession();
    final container = ProviderContainer(
      overrides: [micPitchSessionProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(humToMidiProvider.notifier).startRecording();
    fake.emit(
      const PitchFrame(
        timestampMs: 0,
        frequencyHz: 440,
        midiNote: 69,
        centsOffset: 0,
        amplitude: 0.9,
        confidence: 0.97,
        isSilence: false,
      ),
    );
    fake.emit(
      const PitchFrame(
        timestampMs: 180,
        frequencyHz: 440,
        midiNote: 69,
        centsOffset: 0,
        amplitude: 0.9,
        confidence: 0.97,
        isSilence: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await container.read(humToMidiProvider.notifier).stopRecording();

    final humState = container.read(humToMidiProvider);
    final pianoRollState = container.read(pianoRollProvider);
    expect(fake.stopCalled, isTrue);
    expect(humState.status, HumToMidiStatus.completed);
    expect(pianoRollState.notes.single.midiNote, 69);
  });

  test('stopRecording sets scroll-to-tick signal after import', () async {
    final fake = _FakeMicPitchSession();
    final container = ProviderContainer(
      overrides: [micPitchSessionProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(humToMidiProvider.notifier).startRecording();
    fake.emit(
      const PitchFrame(
        timestampMs: 0,
        frequencyHz: 440,
        midiNote: 69,
        centsOffset: 0,
        amplitude: 0.9,
        confidence: 0.97,
        isSilence: false,
      ),
    );
    fake.emit(
      const PitchFrame(
        timestampMs: 180,
        frequencyHz: 440,
        midiNote: 69,
        centsOffset: 0,
        amplitude: 0.9,
        confidence: 0.97,
        isSilence: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await container.read(humToMidiProvider.notifier).stopRecording();

    expect(container.read(pianoRollScrollToTickProvider), isNotNull);
  });

  test(
    'stopRecording sets selectedColumnTick when no prior column existed',
    () async {
      final fake = _FakeMicPitchSession();
      final container = ProviderContainer(
        overrides: [micPitchSessionProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      // Ensure no column is selected
      container.read(pianoRollProvider.notifier).selectColumn(null);
      expect(container.read(pianoRollProvider).selectedColumnTick, isNull);

      await container.read(humToMidiProvider.notifier).startRecording();
      fake.emit(
        const PitchFrame(
          timestampMs: 0,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      fake.emit(
        const PitchFrame(
          timestampMs: 180,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await container.read(humToMidiProvider.notifier).stopRecording();

      // The first imported note starts at tick 0, so selectedColumnTick should be 0
      expect(container.read(pianoRollProvider).selectedColumnTick, 0);
    },
  );

  test('stopRecording preserves existing selectedColumnTick', () async {
    final fake = _FakeMicPitchSession();
    final container = ProviderContainer(
      overrides: [micPitchSessionProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    // Pre-select column at tick 8
    container.read(pianoRollProvider.notifier).selectColumn(8);
    expect(container.read(pianoRollProvider).selectedColumnTick, 8);

    await container.read(humToMidiProvider.notifier).startRecording();
    fake.emit(
      const PitchFrame(
        timestampMs: 0,
        frequencyHz: 440,
        midiNote: 69,
        centsOffset: 0,
        amplitude: 0.9,
        confidence: 0.97,
        isSilence: false,
      ),
    );
    fake.emit(
      const PitchFrame(
        timestampMs: 180,
        frequencyHz: 440,
        midiNote: 69,
        centsOffset: 0,
        amplitude: 0.9,
        confidence: 0.97,
        isSilence: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await container.read(humToMidiProvider.notifier).stopRecording();

    // Existing selection should be preserved since there was already a prior selection
    expect(container.read(pianoRollProvider).selectedColumnTick, 8);
  });

  test(
    'stopRecording stores latestImportedRange after a successful hum import',
    () async {
      final fake = _FakeMicPitchSession();
      final container = ProviderContainer(
        overrides: [micPitchSessionProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(humToMidiProvider.notifier).startRecording();
      fake.emit(
        const PitchFrame(
          timestampMs: 0,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      fake.emit(
        const PitchFrame(
          timestampMs: 180,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await container.read(humToMidiProvider.notifier).stopRecording();

      final range = container.read(pianoRollProvider).latestImportedRange;
      expect(range, isNotNull);
      expect(range!.startTick, 0);
      expect(range.endTickExclusive, greaterThan(0));
    },
  );

  test(
    'stopRecording replaces the previous latestImportedRange on a later successful import',
    () async {
      final fake = _FakeMicPitchSession();
      final container = ProviderContainer(
        overrides: [micPitchSessionProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      container
          .read(pianoRollProvider.notifier)
          .rememberLatestImportedRange(4, 8);

      await container.read(humToMidiProvider.notifier).startRecording();
      fake.emit(
        const PitchFrame(
          timestampMs: 0,
          frequencyHz: 494,
          midiNote: 71,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      fake.emit(
        const PitchFrame(
          timestampMs: 180,
          frequencyHz: 494,
          midiNote: 71,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await container.read(humToMidiProvider.notifier).stopRecording();

      final range = container.read(pianoRollProvider).latestImportedRange;
      expect(range?.startTick, isNot(4));
    },
  );

  test(
    'stopRecording clears the previous latestImportedRange when no stable note is imported',
    () async {
      final fake = _FakeMicPitchSession();
      final container = ProviderContainer(
        overrides: [micPitchSessionProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      container
          .read(pianoRollProvider.notifier)
          .rememberLatestImportedRange(24, 32);

      await container.read(humToMidiProvider.notifier).startRecording();
      fake.emit(
        const PitchFrame(
          timestampMs: 0,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.9,
          confidence: 0.97,
          isSilence: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await container.read(humToMidiProvider.notifier).stopRecording();

      expect(container.read(pianoRollProvider).latestImportedRange, isNull);
      expect(
        container.read(humToMidiProvider).feedbackMessage,
        'No stable note detected',
      );
    },
  );
}
