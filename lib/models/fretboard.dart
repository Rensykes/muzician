/// Fretboard Type Definitions
/// Data structures for the interactive guitar fretboard component.

/// Supported guitar tuning presets.
enum TuningName {
  standard,
  dropD,
  ebStandard,
  dStandard,
  dropC,
  dropB,
  openD,
  openG,
  dadgad,
  facgce,
}

/// Grouping label for the tuning selector UI.
enum TuningCategory { standard, metal, midwestEmo }

/// View modes for selected notes on the fretboard.
enum FretboardViewMode { pitchClass, exact, focus, exactFocus }

/// A single string's open note with MIDI reference.
class StringTuning {
  final int stringNumber;
  final String note;
  final int midiNote;

  const StringTuning({
    required this.stringNumber,
    required this.note,
    required this.midiNote,
  });
}

/// A full guitar tuning definition.
class Tuning {
  final TuningName name;
  final String displayName;
  final TuningCategory category;
  final List<StringTuning> strings;

  const Tuning({
    required this.name,
    required this.displayName,
    required this.category,
    required this.strings,
  });
}

/// A single cell on the fretboard (one string × one fret).
class FretCell {
  final int stringIndex;
  final int fret;
  final String noteName;
  final String noteWithOctave;
  final bool isNatural;
  final int midiNote;

  const FretCell({
    required this.stringIndex,
    required this.fret,
    required this.noteName,
    required this.noteWithOctave,
    required this.isNatural,
    required this.midiNote,
  });
}

/// An exact fret + string position tapped by the user.
class FretCoordinate {
  final int stringIndex;
  final int fret;
  final String noteName;

  const FretCoordinate({
    required this.stringIndex,
    required this.fret,
    required this.noteName,
  });

  Map<String, dynamic> toJson() => {
        'stringIndex': stringIndex,
        'fret': fret,
        'noteName': noteName,
      };

  factory FretCoordinate.fromJson(Map<String, dynamic> json) => FretCoordinate(
        stringIndex: json['stringIndex'] as int,
        fret: json['fret'] as int,
        noteName: json['noteName'] as String,
      );
}

/// A single chord voicing: one fret position per string.
class ChordVoicing {
  /// Index 0 = high e string, 5 = low E string.
  /// null → muted, 0 → open, n > 0 → fret n pressed.
  final List<int?> positions;

  /// Lowest non-open fret. 0 if all open/muted.
  final int baseFret;

  const ChordVoicing({required this.positions, required this.baseFret});
}

/// Fretboard display configuration / state shape.
class FretboardState {
  final TuningName currentTuning;
  final int numFrets;
  final int capo;
  final List<String> highlightedNotes;
  final List<String> selectedNotes;
  final List<FretCoordinate> selectedCells;
  final FretboardViewMode viewMode;

  const FretboardState({
    required this.currentTuning,
    required this.numFrets,
    required this.capo,
    required this.highlightedNotes,
    required this.selectedNotes,
    required this.selectedCells,
    required this.viewMode,
  });

  FretboardState copyWith({
    TuningName? currentTuning,
    int? numFrets,
    int? capo,
    List<String>? highlightedNotes,
    List<String>? selectedNotes,
    List<FretCoordinate>? selectedCells,
    FretboardViewMode? viewMode,
  }) =>
      FretboardState(
        currentTuning: currentTuning ?? this.currentTuning,
        numFrets: numFrets ?? this.numFrets,
        capo: capo ?? this.capo,
        highlightedNotes: highlightedNotes ?? this.highlightedNotes,
        selectedNotes: selectedNotes ?? this.selectedNotes,
        selectedCells: selectedCells ?? this.selectedCells,
        viewMode: viewMode ?? this.viewMode,
      );
}
