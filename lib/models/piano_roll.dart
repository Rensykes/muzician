/// Piano Roll Type Definitions
/// Data structures for timeline-based note placement and stack detection.

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
  }) =>
      PianoRollNote(
        id: id,
        midiNote: midiNote ?? this.midiNote,
        pitchClass: pitchClass ?? this.pitchClass,
        noteWithOctave: noteWithOctave ?? this.noteWithOctave,
        startTick: startTick ?? this.startTick,
        durationTicks: durationTicks ?? this.durationTicks,
      );
}

class TimeSignature {
  final int beatsPerMeasure;
  final int beatUnit; // 4 or 8

  const TimeSignature({required this.beatsPerMeasure, required this.beatUnit});

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
    String? key,
    TimeSignature? timeSignature,
    int? totalMeasures,
  }) =>
      PianoRollConfig(
        tempo: tempo ?? this.tempo,
        key: key ?? this.key,
        timeSignature: timeSignature ?? this.timeSignature,
        totalMeasures: totalMeasures ?? this.totalMeasures,
      );
}

class PianoRollState {
  final PianoRollConfig config;
  final List<PianoRollNote> notes;
  final int pitchRangeStart;
  final int pitchRangeEnd;
  final int? selectedColumnTick;
  final String? selectedNoteId;

  const PianoRollState({
    required this.config,
    required this.notes,
    required this.pitchRangeStart,
    required this.pitchRangeEnd,
    this.selectedColumnTick,
    this.selectedNoteId,
  });

  PianoRollState copyWith({
    PianoRollConfig? config,
    List<PianoRollNote>? notes,
    int? pitchRangeStart,
    int? pitchRangeEnd,
    int? Function()? selectedColumnTick,
    String? Function()? selectedNoteId,
  }) =>
      PianoRollState(
        config: config ?? this.config,
        notes: notes ?? this.notes,
        pitchRangeStart: pitchRangeStart ?? this.pitchRangeStart,
        pitchRangeEnd: pitchRangeEnd ?? this.pitchRangeEnd,
        selectedColumnTick: selectedColumnTick != null
            ? selectedColumnTick()
            : this.selectedColumnTick,
        selectedNoteId: selectedNoteId != null
            ? selectedNoteId()
            : this.selectedNoteId,
      );
}
