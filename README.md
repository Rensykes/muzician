# Muzician

A Flutter songwriting workspace for exploring harmony on guitar and piano, capturing ideas, and developing them into song arrangements and demos.

Product direction and design guidance live in [PRODUCT.md](PRODUCT.md) and [DESIGN.md](DESIGN.md).

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x+ (Impeller) |
| Language | Dart (sound null safety) |
| State | Riverpod 2.x (`NotifierProvider`) |
| Persistence | `shared_preferences` |
| Rendering | `CustomPainter` + `RepaintBoundary` |
| Music theory | `music_notes` (Dart) |
| Audio | `audioplayers` for playback; `record` for capture |
| Generated files | `share_plus`, `file_picker`, and `archive` for platform delivery and Song Bundles |
| IDs | `uuid` |

## Features

| Feature | Description | Docs |
|---|---|---|
| **Fretboard** | Interactive guitar fretboard with tunings, capo, chord voicing, scale highlighting | [docs/fretboard.md](docs/fretboard.md) |
| **Piano** | Piano keyboard (49 / 61 / 88 keys) with chord and scale highlighting | [docs/piano.md](docs/piano.md) |
| **Piano Roll** | Quantized timeline note editor with four tool modes, pinch-zoom, beat snapping, hum-to-MIDI, metronome | [docs/piano_roll.md](docs/piano_roll.md) |
| **Writer** | Section sketch with instrument-bound Harmony lanes, one composite Save per authored chord, lane-category folders, shared-save choices, explicit chord replacement, playback, and project-scoped undo/redo | [docs/songwriter.md](docs/songwriter.md), [Song & Writer guide](docs/song_writer_guide.md) |
| **Song** | Clip arrangement workspace with recording review, contextual Writer import when tracks are available, project-scoped undo/redo, PCM16 WAV mixdown, and portable Song Bundle import/export | [docs/song_workspace.md](docs/song_workspace.md), [Song & Writer guide](docs/song_writer_guide.md) |
| **Save System** | Project-scoped saves with Writer-managed section/category folders, composite Harmony chord snapshots, shared canonical content, protected linked work, and startup recovery for malformed or interrupted saved data | [docs/save_system.md](docs/save_system.md) |

## Project Structure

```
lib/
  main.dart                   ← App shell, tab navigation, screen layouts
  theme/
    muzician_theme.dart       ← Colours, gradients, glassmorphism helpers
  models/                     ← Immutable data types
  schema/rules/               ← Validation, music math, default state factories
  store/                      ← Riverpod providers and project-scoped undo history
  utils/                      ← Cross-platform helpers (note playback, pitch detection)
    note_utils.dart           ← Chord/scale detection, formatting
    note_player.dart          ← Synthesised audio note playback engine
    note_player_io.dart       ← IO (mobile/desktop) audio backend
    note_player_web.dart      ← Web audio backend
    mic_pitch_session.dart    ← PCM capture + windowing for hum-to-MIDI
  ui/
    save_browser_panel.dart   ← Reusable folder-browser save/load panel
    core/                     ← Shared dialogs and info panels
  features/
    fretboard/                ← Guitar fretboard, tuning, capo, and voicings
    piano/                    ← Piano keyboard and harmony tools
    piano_roll/               ← Note editor and hum-to-MIDI
    songwriter/               ← Section, chord, lyric, melody, drum, strum, and audio writing
    song/                     ← Track and clip arranger
    save_system/              ← Save system barrel export
docs/
  fretboard.md
  piano.md
  piano_roll.md
  songwriter.md
  song_workspace.md
  song_writer_guide.md
  save_system.md
  superpowers/
    HANDOFF-songwriter.md
    plans/                    ← Implementation plans, including the approved songwriting workflow plan
    specs/                    ← Design specifications
```

## Notes (Fretboard & Piano)

- **Out-of-key confirmation:** When a scale highlight is active and the user tries to add a note that falls outside the highlighted scale, the app shows an "out-of-key" confirmation dialog (with a "Don't show again" option). See [lib/ui/core/out_of_key_dialog.dart](lib/ui/core/out_of_key_dialog.dart).

- **View modes:** Both fretboard and piano support `exact` (note name only) and `exactFocus` (note name with focus highlighting) display modes. See [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart) and [lib/features/piano/piano_keyboard.dart](lib/features/piano/piano_keyboard.dart).


## Running the App

```bash
# Install dependencies
flutter pub get

# iOS Simulator
open -a Simulator
flutter run

# Android
flutter run -d <device-id>

# Specific device
flutter devices
flutter run -d <id>
```

## Architecture Notes

- All heavy rendering (fretboard, keyboard, piano roll grid) uses `CustomPainter` with `RepaintBoundary` to isolate repaints.
- The piano roll uses a raw `Listener` (not `GestureDetector`) for pointer events to bypass Flutter's gesture arena — necessary for reliable resize and pitch-drag on iOS touch.
- Pinch-to-zoom on the piano roll is tracked via a `Map<int, Offset>` keyed by pointer ID, updating `_cellW` / `_rowH` in `setState` on every move.
- State is never mutated — all store methods return a new `copyWith` state.
