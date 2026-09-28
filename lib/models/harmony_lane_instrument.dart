/// Instrument used to realize chords on a Writer Harmony Lane.
enum HarmonyLaneInstrument {
  fretboard,
  piano;

  static HarmonyLaneInstrument? fromJson(String? raw) {
    for (final value in HarmonyLaneInstrument.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}
