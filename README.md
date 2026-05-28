# Muzician

A high-performance Flutter music theory app migrated from the React Native "Mugician" project.

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x+ (Impeller) |
| Language | Dart (sound null safety) |
| State | Riverpod 2.x (`NotifierProvider`) |
| Persistence | `shared_preferences` |
| Rendering | `CustomPainter` + `RepaintBoundary` |
| Music theory | `music_notes` (Dart) |
| Audio | `audioplayers` |
| IDs | `uuid` |

## Features

| Feature | Description | Docs |
|---|---|---|
| **Fretboard** | Interactive guitar fretboard with tunings, capo, chord voicing, scale highlighting | [docs/fretboard.md](docs/fretboard.md) |
| **Piano** | Piano keyboard (49 / 61 / 88 keys) with chord and scale highlighting | [docs/piano.md](docs/piano.md) |
| **Piano Roll** | Quantized timeline note editor with four tool modes, pinch-zoom, beat snapping, hum-to-MIDI, metronome | [docs/piano_roll.md](docs/piano_roll.md) |
| **Save System** | Hierarchical folder-based progression persistence across all three instruments | [docs/save_system.md](docs/save_system.md) |

## Project Structure

```
lib/
  main.dart                   ← App shell, tab navigation, screen layouts
  theme/
    muzician_theme.dart       ← Colours, gradients, glassmorphism helpers
  models/                     ← Immutable data types (7 files)
  schema/rules/               ← Validation, music math, default state factories (7 files)
  store/                      ← Riverpod providers (8 files)
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
    fretboard/                ← Fretboard widgets (10 files)
    piano/                    ← Piano widgets (9 files)
    piano_roll/               ← Piano roll widgets (8 files)
    save_system/              ← Save system barrel export
docs/
  fretboard.md
  piano.md
  piano_roll.md
  save_system.md
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

