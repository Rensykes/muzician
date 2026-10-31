# Piano Roll: Hum accuracy, web/desktop Hum, and selectable sound

## Goals
1. Improve Hum-to-MIDI accuracy: fewer spurious/split notes, fewer missed or merged notes, lower onset latency, fewer false notes in noisy rooms.
2. Enable Hum-to-MIDI on web and desktop (macOS, Linux; no Windows runner exists today).
3. Let the user swap the sound used by Piano Roll playback; the choice is saved with each roll.

## 1. Hum accuracy (pure Dart, `lib/schema/rules/mono_pitch_rules.dart` + `lib/utils/mic_pitch_session.dart`)
- **Adaptive noise gate:** estimate the noise floor from the first ~300 ms of a recording; gate = max(`minHumAmplitude`, floor × margin). Replaces the fixed amplitude gate.
- **Octave guard:** choose the lowest-lag CMNDF candidate below threshold; reject jumps of ±12 semitones between adjacent frames unless sustained.
- **Pitch smoothing:** median-of-3 filter over frame pitch before segmentation.
- **Segmentation:** bridge short unvoiced gaps, merge flicker, split only on a sustained pitch change (existing `switchFrames`/`deadbandCents` presets) or an energy re-attack; back-date note start to the first voiced frame.
- **Latency:** hop 512 → 256 samples (~16 ms frames). Window stays ≥ 2× the max period of the lowest pitch.
- Sensitivity presets (Strict/Balanced/Forgiving) are kept and retuned.
- `RecordMicPitchSession` uses the stream's real sample rate (browsers may ignore the requested 16 kHz) and passes it to the estimator.

## 2. Platform enablement
- Remove the `isWeb` gate in `piano_roll_hum_recorder.dart`; keep the permission-denied and unsupported-platform messages (the latter only for platforms where `record` reports no support).
- Add the macOS microphone entitlement (`com.apple.security.device.audio-input`) and `NSMicrophoneUsageDescription` if missing.
- Playback remains blocked while humming.

## 3. Selectable sound
- New `PianoRollSound` enum: `piano`, `cleanGuitar`, `distortedGuitar`, `organ`, `synthLead`, `bell`.
- `PianoRollState` and `PianoRollSnapshot` gain `sound`; absent in old saves → `piano`.
- `pianoRollPlaybackSinkProvider` receives the sound; `NotePlayer` gets previews for the new synthesised timbres (organ, synth lead, bell) and reuses the existing guitar previews.
- UI: a sound picker in the Piano Roll utility/settings area with labelled 44 px targets; auditions the sound on selection.
- Writer's `MelodyLaneSound` is unchanged.

## Testing
- `test/schema/rules/mono_pitch_rules_test.dart`: synthetic hums (steady tone, vibrato, octave jump, noise, gaps, re-attack).
- Store tests for sound persistence and snapshot back-compat.
- Widget test: Hum panel renders controls on web.
- Run `dart format`, `flutter analyze`, targeted `flutter test`.

## Docs
Update `docs/piano_roll.md` (Hum, web capability table, sound), and the `README.md` feature overview.
