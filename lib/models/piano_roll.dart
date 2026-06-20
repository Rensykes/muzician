/// Piano Roll Type Definitions
/// Data structures for timeline-based note placement and stack detection.
library;

class PianoRollNote {
  final String id;
  final int midiNote;
  final String pitchClass;
  final String noteWithOctave;
  final int startTick;
  final int durationTicks;

  const PianoRollNote({
    required this.id,
    required this.midiNote,
    required this.pitchClass,
    required this.noteWithOctave,
    required this.startTick,
    required this.durationTicks,
  });

  PianoRollNote copyWith({
    int? midiNote,
    String? pitchClass,
    String? noteWithOctave,
    int? startTick,
    int? durationTicks,
  }) => PianoRollNote(
    id: id,
    midiNote: midiNote ?? this.midiNote,
    pitchClass: pitchClass ?? this.pitchClass,
    noteWithOctave: noteWithOctave ?? this.noteWithOctave,
    startTick: startTick ?? this.startTick,
    durationTicks: durationTicks ?? this.durationTicks,
  );
}

/// Ticks per beat for a time-signature denominator: x/8 signatures use 2 ticks
/// per beat, everything else 4. Single source of truth for the tick grid across
/// playback, offline render, and the songwriter.
int ticksPerBeatForUnit(int beatUnit) => beatUnit == 8 ? 2 : 4;

class TimeSignature {
  final int beatsPerMeasure;
  final int beatUnit; // 4 or 8

  const TimeSignature({required this.beatsPerMeasure, required this.beatUnit});

  int get ticksPerBeat => ticksPerBeatForUnit(beatUnit);

  Map<String, dynamic> toJson() => {
    'beatsPerMeasure': beatsPerMeasure,
    'beatUnit': beatUnit,
  };

  factory TimeSignature.fromJson(Map<String, dynamic> json) => TimeSignature(
    beatsPerMeasure: json['beatsPerMeasure'] as int,
    beatUnit: json['beatUnit'] as int,
  );
}

class PianoRollConfig {
  final int tempo;
  final String? key;
  final TimeSignature timeSignature;
  final int totalMeasures;

  const PianoRollConfig({
    required this.tempo,
    this.key,
    required this.timeSignature,
    required this.totalMeasures,
  });

  PianoRollConfig copyWith({
    int? tempo,
    String? Function()? key,
    TimeSignature? timeSignature,
    int? totalMeasures,
  }) => PianoRollConfig(
    tempo: tempo ?? this.tempo,
    key: key != null ? key() : this.key,
    timeSignature: timeSignature ?? this.timeSignature,
    totalMeasures: totalMeasures ?? this.totalMeasures,
  );
}

/// Piano Roll editing tools.
///
///   * [draw]     — add, move, and resize notes.
///   * [select]   — drag a marquee box to select intersected notes.
///   * [scissors] — split notes with a tap.
///   * [paint]    — drag inserts notes along the path at snap-length.
///   * [delete]   — tap or drag over a note removes it.
enum PianoRollTool { draw, select, scissors, paint, delete }

class PianoRollImportedRange {
  final int startTick;
  final int endTickExclusive;

  const PianoRollImportedRange({
    required this.startTick,
    required this.endTickExclusive,
  });
}

class PianoRollState {
  final PianoRollConfig config;
  final List<PianoRollNote> notes;
  final int pitchRangeStart;
  final int pitchRangeEnd;
  final int? selectedColumnTick;
  final Set<String> selectedNoteIds;
  final PianoRollTool activeTool;
  final int snapTicks;
  final List<String> highlightedNotes;
  final PianoRollImportedRange? latestImportedRange;

  const PianoRollState({
    required this.config,
    required this.notes,
    required this.pitchRangeStart,
    required this.pitchRangeEnd,
    this.selectedColumnTick,
    this.selectedNoteIds = const <String>{},
    this.activeTool = PianoRollTool.draw,
    this.snapTicks = 1,
    this.highlightedNotes = const <String>[],
    this.latestImportedRange,
  });

  PianoRollState copyWith({
    PianoRollConfig? config,
    List<PianoRollNote>? notes,
    int? pitchRangeStart,
    int? pitchRangeEnd,
    int? Function()? selectedColumnTick,
    Set<String>? selectedNoteIds,
    PianoRollTool? activeTool,
    int? snapTicks,
    List<String>? highlightedNotes,
    PianoRollImportedRange? Function()? latestImportedRange,
  }) => PianoRollState(
    config: config ?? this.config,
    notes: notes ?? this.notes,
    pitchRangeStart: pitchRangeStart ?? this.pitchRangeStart,
    pitchRangeEnd: pitchRangeEnd ?? this.pitchRangeEnd,
    selectedColumnTick: selectedColumnTick != null
        ? selectedColumnTick()
        : this.selectedColumnTick,
    selectedNoteIds: selectedNoteIds ?? this.selectedNoteIds,
    activeTool: activeTool ?? this.activeTool,
    snapTicks: snapTicks ?? this.snapTicks,
    highlightedNotes: highlightedNotes ?? this.highlightedNotes,
    latestImportedRange: latestImportedRange != null
        ? latestImportedRange()
        : this.latestImportedRange,
  );
}
