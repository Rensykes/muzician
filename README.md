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
| **Piano Roll** | Quantized timeline note editor with pinch-zoom, beat snapping, chord detection | [docs/piano_roll.md](docs/piano_roll.md) |
| **Save System** | Hierarchical folder-based progression persistence shared across all instruments | [docs/save_system.md](docs/save_system.md) |

## Project Structure

```
lib/
  main.dart                   ← App shell, tab navigation, screen layouts
  theme/
    muzician_theme.dart       ← Colours, gradients, glassmorphism helpers
  models/                     ← Immutable data types (fretboard, piano, piano_roll, save_system)
  schema/rules/               ← Validation, music math, default state factories
  store/                      ← Riverpod providers (one per feature)
  features/
    fretboard/                ← Fretboard widgets
    piano/                    ← Piano widgets
    piano_roll/               ← Piano roll widgets
    save_system/              ← Save/load widgets
docs/
  fretboard.md
  piano.md
  piano_roll.md
  save_system.md
```

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

