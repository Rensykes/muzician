/// Save-instrument allowlist for Songwriter save lanes.
///
/// Save lanes hold enrichment blocks (voicings, harmonies, riffs) — not
/// arrangement-level saves. Passing this set to `SaveBrowserPanel`'s
/// `allowedInstruments` excludes `songwriter` and `song` saves so the user
/// cannot embed a whole project save inside another arrangement.
library;

const Set<String> songwriterSaveLaneAllowedInstruments = {
  'fretboard',
  'piano',
  'piano_roll',
};
