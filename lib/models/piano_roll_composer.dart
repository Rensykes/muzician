/// Piano Roll Composer State
/// Shared chord-stack composer state used by V1 stack selector and V2 dock.
library;

import '../schema/rules/piano_roll_rules.dart' as rules;

/// Canonical quality symbol → display label.
const qualityLabelBySymbol = <String, String>{
  '5': '5th',
  '': 'maj',
  'm': 'min',
  '7': 'dom7',
  'maj7': 'maj7',
  'm7': 'm7',
  'sus2': 'sus2',
  'sus4': 'sus4',
  'dim': 'dim',
  'aug': 'aug',
  'm7b5': 'm7♭5',
  'add9': 'add9',
  'maj9': 'maj9',
  '6': '6',
  'm6': 'm6',
  'dim7': 'dim7',
  '7sus4': '7sus4',
};

/// Display label → canonical quality symbol.
const qualitySymbolByLabel = <String, String>{
  '5th': '5',
  'maj': '',
  'min': 'm',
  'dom7': '7',
  'maj7': 'maj7',
  'm7': 'm7',
  'sus2': 'sus2',
  'sus4': 'sus4',
  'dim': 'dim',
  'aug': 'aug',
  'm7♭5': 'm7b5',
  'add9': 'add9',
  'maj9': 'maj9',
  '6': '6',
  'm6': 'm6',
  'dim7': 'dim7',
  '7sus4': '7sus4',
};

/// Display label → duration in ticks.
const labelToDurationTicks = <String, int>{
  '1/16': 1,
  '1/8': 2,
  '1/4': 4,
  '1/2': 8,
  '1/1': 16,
};

/// Duration in ticks → display label.
const durationTicksToLabel = <int, String>{
  1: '1/16',
  2: '1/8',
  4: '1/4',
  8: '1/2',
  16: '1/1',
};

class PianoRollComposerState {
  final String root;
  final String quality;
  final int durationTicks;

  const PianoRollComposerState({
    required this.root,
    required this.quality,
    required this.durationTicks,
  });

  static const defaultState = PianoRollComposerState(
    root: 'C',
    quality: '',
    durationTicks: rules.ticksPerQuarter, // 4 = quarter note
  );

  PianoRollComposerState copyWith({
    String? root,
    String? quality,
    int? durationTicks,
  }) => PianoRollComposerState(
    root: root ?? this.root,
    quality: quality ?? this.quality,
    durationTicks: durationTicks ?? this.durationTicks,
  );
}
