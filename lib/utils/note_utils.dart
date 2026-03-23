// Utilities for note name normalization
const Map<String, String> _flatToSharp = {
  'Db': 'C#',
  'Eb': 'D#',
  'Fb': 'E',
  'Gb': 'F#',
  'Ab': 'G#',
  'Bb': 'A#',
  'Cb': 'B',
};

String toSharp(String note) => _flatToSharp[note] ?? note;
