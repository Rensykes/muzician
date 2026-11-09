# Changelog

All notable changes to Muzician are recorded here. User-visible changes are listed; internal refactors and test work appear only when they change behaviour.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Feedback capture: a composer in Settings, or a shake on a phone or tablet, sending the message with app version, platform, OS version, screen, locale and the tab you were on. Delivery goes through Firestore with create-only rules; nothing is readable back.
- Feedback is available on web, Android, iOS, macOS and Windows.
- Piano Roll: each roll keeps its own playback sound, with organ, synth lead and bell timbres, chosen in Roll Settings.
- Hum to notes now works on web and desktop as well as mobile, with 16 ms PCM framing and an adaptive noise gate.

### Changed

- The Song workspace is gone. The Writer keeps the playback harness, the audio clip sink and the saves, and persisted Song data is discarded during hydration.

### Fixed

- Writer: strum, drum and metronome playback no longer lag behind the timeline.
- Piano Roll: the select tool selects a note on tap, gesture state resets when a pointer is cancelled, and a roll's sound picker and sink stay scoped to that roll.
- Fretboard, Piano Roll and the Writer melody timeline ignore non-primary mouse buttons.
- Android deploys retry the Play upload when Google returns a transient 503.

## [2.0.0] - 2026-10-28

### Added

- Studio workspace redesign: a graphite and mint visual system, one workspace per instrument, and a shared theme across Fretboard, Piano, Roll and Writer.
- Instrument UX V2: the instrument stays visible while a bounded Notes / Voicings / Setup inspector scrolls; compact Input and View menus replace the mode bars; a single Actions sheet holds note details, Save idea and Add to Writer; voicings browse From notes or By chord.
- Fretboard audition tones (clean and distorted) and Full/Solo note-label modes on both instruments.
- Writer: named multi-bar melodies with a Bars stepper and bar-aligned length, a wrapped melody timeline with single-pass note previews, a repeat picker with linked reuse, independent lane sounds, silent tails and placement limits.

### Changed

- Piano Roll pitch range moved into the unframed top toolbar.

### Fixed

- Writer: first melody save, resizing across autoscroll, repeat linkage and occupancy, and melody labels under larger accessibility text sizes.

## [1.0.0] - 2026-10-08

First public release, after the March 2026 rewrite from React Native to Flutter.

### Added

- Fretboard: 24-fret workspace with tunings and capo, chord and scale detection, voicings, and Save idea.
- Piano: 49 / 61 / 88-key ranges with chord and scale detection and the same save and voicing tools.
- Piano Roll: draw, split, paint and delete tools, a Stack Builder, a hum-to-notes recorder with adjustable sensitivity, and playback with a metronome.
- Writer: sections holding chords, lyrics and melodies, with versions and an auto-saved draft.
- Save system: project-scoped saves with folders and startup recovery for interrupted or malformed data.
- Web, Android, iOS, macOS and Windows builds, with Firebase hosting for web and previews.

[Unreleased]: https://github.com/Rensykes/muzician/compare/2.0.0...HEAD
[2.0.0]: https://github.com/Rensykes/muzician/compare/1.0.0...2.0.0
[1.0.0]: https://github.com/Rensykes/muzician/releases/tag/1.0.0
