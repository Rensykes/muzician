library;

enum PianoRollStackBuilderView { canonical, advanced }

class PianoRollStackRecognition {
  final String? recognizedRoot;
  final String? recognizedQuality;
  final int? recognizedInversionIndex;
  final bool isRecognized;
  final bool isCustomVoicing;

  const PianoRollStackRecognition({
    this.recognizedRoot,
    this.recognizedQuality,
    this.recognizedInversionIndex,
    this.isRecognized = false,
    this.isCustomVoicing = false,
  });
}

class PianoRollStackBuilderState {
  final List<int> midiNotes;
  final int durationTicks;
  final PianoRollStackBuilderView activeView;
  final PianoRollStackRecognition recognition;
  final String? errorMessage;
  final List<int> lastAddedNotes;
  final int lastAddedDurationTicks;

  const PianoRollStackBuilderState({
    required this.midiNotes,
    this.durationTicks = 4,
    this.activeView = PianoRollStackBuilderView.canonical,
    this.recognition = const PianoRollStackRecognition(),
    this.errorMessage,
    this.lastAddedNotes = const [],
    this.lastAddedDurationTicks = 4,
  });

  PianoRollStackBuilderState copyWith({
    List<int>? midiNotes,
    int? durationTicks,
    PianoRollStackBuilderView? activeView,
    PianoRollStackRecognition? recognition,
    String? Function()? errorMessage,
    List<int>? lastAddedNotes,
    int? lastAddedDurationTicks,
  }) => PianoRollStackBuilderState(
    midiNotes: midiNotes ?? this.midiNotes,
    durationTicks: durationTicks ?? this.durationTicks,
    activeView: activeView ?? this.activeView,
    recognition: recognition ?? this.recognition,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    lastAddedNotes: lastAddedNotes ?? this.lastAddedNotes,
    lastAddedDurationTicks:
        lastAddedDurationTicks ?? this.lastAddedDurationTicks,
  );
}

const defaultStackBuilderState = PianoRollStackBuilderState(
  midiNotes: [60, 64, 67],
);
