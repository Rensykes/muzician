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

The bottom navigation is labeled **Fretboard**, **Piano**, **Roll**, **Song**, **Writer**, and **Settings**. **Song is temporarily unavailable in V2**: its entry stays visible and disabled, while saved arrangements remain intact. Save System is a shared project feature rather than a bottom-navigation destination.

Fretboard and Piano keep the instrument visible while a bounded Notes / Voicings / Setup inspector scrolls independently. Compact Input/View menus replace full-width mode bars. A single selection **Actions** sheet holds note details, Save idea and Add to Writer across all inspector tabs. Voicings use a horizontal carousel with **From notes** suggestions filtered by selected pitch classes and the active scale, when set, plus independent **By chord** browsing. See the [V2 implementation plan](docs/instrument-ux-v2/PLAN.md) and [verification evidence](docs/instrument-ux-v2/PROGRESS.md).

| Feature | Description | Docs |
|---|---|---|
| **Fretboard** | Studio 24-fret guitar workspace with Full/Solo note labels, clean/distorted electric sound, down/up strum audition, a compact Notes / Voicings / Setup inspector, tuning and capo, Save idea, and Chord-only Writer Harmony handoff | [docs/fretboard.md](docs/fretboard.md) |
| **Piano** | Studio piano workspace with Full/Solo note labels, a compact Notes / Voicings / Setup inspector, 49 / 61 / 88-key ranges, Scale and Library shortcuts, Save idea, and recognized or exact-note Writer Harmony | [docs/piano.md](docs/piano.md) |
| **Piano Roll** | Studio timeline editor (navigation label **Roll**) with all five tools, a Stack Builder / Selection / Tools inspector, Quick, snap and range controls, and the mobile **Hum recorder** | [docs/piano_roll.md](docs/piano_roll.md) |
| **Writer** | Studio section sketch with **Save version**, **Writer versions**, and an auto-persisted **Draft**; compact unframed controls, Harmony guitar tone selection, source-bound Guitar Strum, reusable melodies, instrument-aware guitar playback, and project-scoped undo/redo | [docs/songwriter.md](docs/songwriter.md), [Song & Writer guide](docs/song_writer_guide.md) |
| **Song** | Temporarily disabled in V2; retained clip arrangement workspace with recording review, contextual Writer import when tracks are available, project-scoped undo/redo, PCM16 WAV mixdown, and portable Song Bundle import/export | [docs/song_workspace.md](docs/song_workspace.md), [Song & Writer guide](docs/song_writer_guide.md) |
| **Save System** | Project-scoped saves with Writer-managed section/category folders, composite Harmony chord snapshots, shared canonical content, protected linked work, and startup recovery for malformed or interrupted saved data | [docs/save_system.md](docs/save_system.md) |
| **Settings** | Device-local Studio / Studio Muzician appearance and persistent Sharps/Flats spelling for musical labels, retaining pitches and custom names | [docs/save_system.md](docs/save_system.md) |

## Project Structure

```
lib/
  main.dart                   ← App shell, tab navigation, screen layouts
  theme/
    studio_theme.dart         ← Immutable Studio palettes and semantic UI colors
    muzician_theme.dart       ← Legacy palette retained for Song and compatibility views
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

- **Note spelling:** Settings → **Prefer flat note names** switches musical labels between Sharps (default) and Flats throughout the app. A D# minor pentatonic project displays as Eb minor pentatonic when enabled. Custom Save names and named exact Harmony stay literal; changing spelling does not change the project key or notes.

- **Out-of-key confirmation:** When a scale highlight is active and the user tries to add a note that falls outside the highlighted scale, the app shows an "out-of-key" confirmation dialog (with a "Don't show again" option). See [lib/ui/core/out_of_key_dialog.dart](lib/ui/core/out_of_key_dialog.dart).

- **View modes:** Both fretboard and piano offer **Full** (all note labels) and **Solo** (selected positions only), independently of Chord/Free input. Serialized values remain `exact` / `exactFocus` for compatibility. See [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart) and [lib/features/piano/piano_keyboard.dart](lib/features/piano/piano_keyboard.dart).

- **Appearance:** Settings → **Appearance** switches between **Studio** (default graphite / mint) and **Studio Muzician** (night / sky / teal / violet). The choice is saved on this device and applies to Fretboard, Piano, Piano Roll, Writer, and shared panels. Song is temporarily disabled; its retained implementation uses the legacy layout and palette.


## Running the App

```bash
# Install dependencies
flutter pub get

# iOS Simulator
open -a Simulator
flutter run

# Physical iPhone (or use Codex environment action: Deploy to iPhone)
bash scripts/run_ios_iphone.sh

# Android
flutter run -d <device-id>

# Specific device
flutter devices
flutter run -d <id>
```

For a physical iPhone, connect and unlock the device, trust this Mac, enable iOS Developer Mode, and sign in to an Apple development account in Xcode so automatic signing can create a provisioning profile. The Codex environment's **Deploy to iPhone** action builds a signed Release app, installs it, and launches it directly without attaching the Flutter debugger; you can disconnect the phone after it opens. If more than one physical iPhone is connected, set `MUZICIAN_IOS_DEVICE_ID` to the intended device ID before running the script. The action uses the newest full Xcode installed in `/Applications`, so it can deploy to devices running newer iOS versions even when an older Xcode remains selected globally.

## Architecture Notes

- All heavy rendering (fretboard, keyboard, piano roll grid) uses `CustomPainter` with `RepaintBoundary` to isolate repaints.
- The piano roll uses a raw `Listener` (not `GestureDetector`) for pointer events to bypass Flutter's gesture arena — necessary for reliable resize and pitch-drag on iOS touch.
- Pinch-to-zoom on the piano roll is tracked via a `Map<int, Offset>` keyed by pointer ID, updating `_cellW` / `_rowH` in `setState` on every move.
- State is never mutated — all store methods return a new `copyWith` state.
