# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the app code. Use `lib/features/` for instrument-specific UI (`fretboard`, `piano`, `piano_roll`, `save_system`), `lib/models/` for immutable data types, `lib/store/` for Riverpod state, and `lib/schema/rules/` for music logic, validation, and default factories. Shared UI belongs in `lib/ui/` or `lib/ui/core/`; cross-platform helpers such as note playback live in `lib/utils/`. Static assets are in `assets/images/`, feature notes in `docs/`, and platform runners in `android/`, `ios/`, `web/`, `macos/`, `linux/`, and `windows/`.

## Build, Test, and Development Commands
Run `flutter pub get` after dependency changes. Use `flutter run` for the default attached device, or `flutter run -d <device-id>` after checking `flutter devices`. Keep code clean with `dart format lib` and `flutter analyze`. Run `flutter test` for Dart and widget tests once they exist under `test/`. CI currently builds with `flutter build web --release` for Firebase preview/production and `flutter build appbundle --release` for Play Store delivery.

## Coding Style & Naming Conventions
This repo follows `flutter_lints` via `analysis_options.yaml`; format with `dart format` and keep Dart’s standard 2-space indentation. Use `UpperCamelCase` for types, `lowerCamelCase` for members, and `snake_case.dart` for filenames. Keep state immutable with `copyWith`-style updates, and prefer adding shared dialogs/panels in `lib/ui/` instead of duplicating logic across instruments.

## Testing Guidelines
Use `flutter_test` for unit and widget coverage. Mirror `lib/` inside `test/`; for example, put piano rule tests in `test/schema/rules/piano_rules_test.dart`. Focus first on music-theory calculations, Riverpod store transitions, and save/load serialization. CI currently builds release artifacts but does not enforce tests or coverage, so new behavior should include targeted tests plus a clean `flutter analyze`.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit prefixes such as `feat:`, `fix:`, and `refactor:`. Keep commits small, imperative, and scoped to one change. PRs should explain the user-visible impact, link the related issue when available, and list the devices or platforms tested. Include screenshots or short recordings for UI, gesture, or rendering changes. If you touch deployment or signing files, call that out explicitly.

## Specialist Agents
Per-domain agent definitions live in `.agents/` and are shared across Codex, OpenCode, Claude Code, and Copilot via symlinks (`.opencode/agent`, `.claude/agents`, `.github/agents` all point to `.agents/`). When a task fits a specialist's domain, delegate to it; when it spans multiple, route through the orchestrator.

- **[orchestrator](.agents/orchestrator.md)** — multi-domain tasks; decomposes and delegates.
- **[music-theory](.agents/music-theory.md)** — chords, scales, intervals, `note_utils`.
- **[state-architect](.agents/state-architect.md)** — Riverpod providers, immutable models, `lib/store/`.
- **[instrument-renderer](.agents/instrument-renderer.md)** — `CustomPainter`, gestures, layout for fretboard / piano / piano roll.
- **[save-system](.agents/save-system.md)** — persistence, snapshots, JSON migration, folder ops.
- **[accessibility-ux](.agents/accessibility-ux.md)** — review-only; WCAG, Semantics, touch targets, UX audit.
- **[code-quality](.agents/code-quality.md)** — audit-only; `dart analyze`, idiomatic style, dead code.
