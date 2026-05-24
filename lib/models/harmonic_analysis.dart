/// Shared value types for exact-note-aware harmonic analysis.
library;

enum NoteDisplayStyle { canonicalSharp, contextual }

class ExactSelectionNote {
  final int midiNote;
  final String pitchClass;

  const ExactSelectionNote({
    required this.midiNote,
    required this.pitchClass,
  });
}

class ChordDetectionResult {
  final String root;
  final String quality;
  final String? bass;

  const ChordDetectionResult({
    required this.root,
    required this.quality,
    this.bass,
  });
}

class ScaleDetectionResult {
  final String root;
  final String scaleName;

  const ScaleDetectionResult({
    required this.root,
    required this.scaleName,
  });
}
