/// Piano Type Definitions
/// Data structures for the interactive piano keyboard feature.

/// Supported keyboard ranges.
enum PianoRangeName { key88, key61, key49 }

/// Keyboard range metadata.
class PianoRange {
  final PianoRangeName name;
  final String displayName;
  final int startMidi;
  final int endMidi;

  const PianoRange({
    required this.name,
    required this.displayName,
    required this.startMidi,
    required this.endMidi,
  });
}

/// A single rendered piano key.
class PianoKeyCell {
  final int keyIndex;
  final int midiNote;
  final String noteName;
  final String noteWithOctave;
  final int octave;
  final bool isNatural;
  final bool isBlack;

  const PianoKeyCell({
    required this.keyIndex,
    required this.midiNote,
    required this.noteName,
    required this.noteWithOctave,
    required this.octave,
    required this.isNatural,
    required this.isBlack,
  });
}

/// An exact key selection made by the user.
class PianoCoordinate {
  final int keyIndex;
  final int midiNote;
  final String noteName;

  const PianoCoordinate({
    required this.keyIndex,
    required this.midiNote,
    required this.noteName,
  });

  Map<String, dynamic> toJson() => {
        'keyIndex': keyIndex,
        'midiNote': midiNote,
        'noteName': noteName,
      };

  factory PianoCoordinate.fromJson(Map<String, dynamic> json) =>
      PianoCoordinate(
        keyIndex: json['keyIndex'] as int,
        midiNote: json['midiNote'] as int,
        noteName: json['noteName'] as String,
      );
}

/// Mirrors fretboard view modes.
enum PianoViewMode { pitchClass, exact, focus, exactFocus }

/// Piano display and selection state.
class PianoState {
  final PianoRangeName currentRange;
  final List<String> highlightedNotes;
  final List<String> selectedNotes;
  final List<PianoCoordinate> selectedKeys;
  final PianoViewMode viewMode;

  const PianoState({
    required this.currentRange,
    required this.highlightedNotes,
    required this.selectedNotes,
    required this.selectedKeys,
    required this.viewMode,
  });

  PianoState copyWith({
    PianoRangeName? currentRange,
    List<String>? highlightedNotes,
    List<String>? selectedNotes,
    List<PianoCoordinate>? selectedKeys,
    PianoViewMode? viewMode,
  }) =>
      PianoState(
        currentRange: currentRange ?? this.currentRange,
        highlightedNotes: highlightedNotes ?? this.highlightedNotes,
        selectedNotes: selectedNotes ?? this.selectedNotes,
        selectedKeys: selectedKeys ?? this.selectedKeys,
        viewMode: viewMode ?? this.viewMode,
      );
}
