import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hum_to_midi.dart';
import '../schema/rules/mono_pitch_rules.dart' as rules;
import '../store/piano_roll_store.dart';
import '../utils/mic_pitch_session.dart';

final micPitchSessionProvider = Provider<MicPitchSession>(
  (_) => RecordMicPitchSession(),
);

class HumToMidiNotifier extends Notifier<HumToMidiState> {
  StreamSubscription<PitchFrame>? _framesSub;

  @override
  HumToMidiState build() => const HumToMidiState();

  Future<void> startRecording() async {
    final session = ref.read(micPitchSessionProvider);
    state = state.copyWith(
      status: HumToMidiStatus.requestingPermission,
      errorMessage: () => null,
      feedbackMessage: () => null,
      frames: const <PitchFrame>[],
      liveMidiNote: () => null,
      startedAtMs: () => null,
    );
    if (!await session.hasPermission()) {
      state = state.copyWith(
        status: HumToMidiStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }
    final stream = await session.start();
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    _framesSub = stream.listen((frame) {
      state = state.copyWith(
        status: HumToMidiStatus.recording,
        frames: [...state.frames, frame],
        liveMidiNote: () => frame.midiNote,
      );
    });
    state = state.copyWith(
      status: HumToMidiStatus.recording,
      startedAtMs: () => startedAtMs,
    );
  }

  Future<void> stopRecording() async {
    final session = ref.read(micPitchSessionProvider);
    state = state.copyWith(status: HumToMidiStatus.processing);
    await _framesSub?.cancel();
    await session.stop();
    final segmented = rules.segmentStableNotes(state.frames);
    final pianoRoll = ref.read(pianoRollProvider);
    final anchorTick =
        ref.read(pianoRollProvider.notifier).suggestedImportAnchorTick();
    final imported = rules.quantizeNotesToTicks(
      notes: segmented,
      anchorTick: anchorTick,
      tempo: pianoRoll.config.tempo,
      timeSignature: pianoRoll.config.timeSignature,
      snapTicks: pianoRoll.snapTicks,
    );
    final importResult =
        ref.read(pianoRollProvider.notifier).appendImportedNotes(imported);
    final feedbackMessage = imported.isEmpty
        ? 'No stable note detected'
        : importResult.truncated
        ? 'Take clipped to fit the piano roll'
        : null;
    state = state.copyWith(
      status: HumToMidiStatus.completed,
      frames: const <PitchFrame>[],
      liveMidiNote: () => null,
      startedAtMs: () => null,
      feedbackMessage: () => feedbackMessage,
    );
  }
}

final humToMidiProvider =
    NotifierProvider<HumToMidiNotifier, HumToMidiState>(HumToMidiNotifier.new);
