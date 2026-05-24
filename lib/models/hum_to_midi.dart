enum HumToMidiStatus { idle, requestingPermission, recording, processing, completed, error }

class PitchFrame {
  final int timestampMs;
  final double frequencyHz;
  final int? midiNote;
  final double centsOffset;
  final double amplitude;
  final double confidence;
  final bool isSilence;

  const PitchFrame({
    required this.timestampMs,
    required this.frequencyHz,
    required this.midiNote,
    required this.centsOffset,
    required this.amplitude,
    required this.confidence,
    required this.isSilence,
  });
}

class DetectedMonoNote {
  final int startMs;
  final int endMs;
  final int midiNote;
  final double confidence;

  const DetectedMonoNote({
    required this.startMs,
    required this.endMs,
    required this.midiNote,
    required this.confidence,
  });
}

class QuantizedHumNote {
  final int midiNote;
  final int startTick;
  final int durationTicks;

  const QuantizedHumNote({
    required this.midiNote,
    required this.startTick,
    required this.durationTicks,
  });
}
