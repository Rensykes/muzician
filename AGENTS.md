# Repository Guidelines

## Agent Operating Rules
These rules are for coding agents working in this repository. Prefer small, verifiable diffs over broad cleanup.

### Think Before Coding
- Read the files you will change and the widgets, providers, or rule modules that call them before editing.
- If behavior is ambiguous, state the assumption explicitly before implementing.
- Match the existing Flutter, Riverpod, immutable-model, and feature-folder patterns already used in this repo.

### Simplicity First
- Implement the smallest change that solves the request.
- Do not add speculative abstractions, feature flags, or shared components unless they are needed now.
- Keep music logic in `lib/schema/rules/`, state in `lib/store/`, instrument UI in `lib/features/`, and reusable UI in `lib/ui/`.

### Surgical Changes
- Touch only the files required by the task.
- Do not refactor adjacent instrument code, rename symbols, or reformat unrelated files unless the task requires it.
- Clean up only imports, variables, or helpers made obsolete by your own change.

### Goal-Driven Verification
- Define the success check before editing, then run the narrowest command that proves the change works.
- For changes in `lib/schema/rules/`, `lib/store/`, or `lib/features/save_system/`, add or update mirrored tests under `test/` when practical.
- Run `dart format <changed paths>`, `flutter analyze`, and the narrowest relevant `flutter test` target before finishing.
- For visible UI changes, verify layout on at least one compact and one wide viewport or device.

## Project Structure & Module Organization
`lib/` contains the app code. Use `lib/features/` for instrument-specific UI (`fretboard`, `piano`, `piano_roll`, `save_system`), `lib/models/` for immutable data types, `lib/store/` for Riverpod state, and `lib/schema/rules/` for music logic, validation, and default factories. Shared UI belongs in `lib/ui/` or `lib/ui/core/`; cross-platform helpers such as note playback live in `lib/utils/`. Static assets are in `assets/images/`, feature notes in `docs/`, and platform runners in `android/`, `ios/`, `web/`, `macos/`, `linux/`, and `windows/`.

## Build, Test, and Development Commands
Run `flutter pub get` after dependency changes. Use `flutter run` for the default attached device, or `flutter run -d <device-id>` after checking `flutter devices`. Keep code clean with `dart format lib` and `flutter analyze`. Run `flutter test` for Dart and widget tests once they exist under `test/`. CI currently builds with `flutter build web --release` for Firebase preview/production and `flutter build appbundle --release` for Play Store delivery.

## Coding Style & Naming Conventions
This repo follows `flutter_lints` via `analysis_options.yaml`; format with `dart format` and keep Dart’s standard 2-space indentation. Use `UpperCamelCase` for types, `lowerCamelCase` for members, and `snake_case.dart` for filenames. Keep state immutable with `copyWith`-style updates, and prefer adding shared dialogs/panels in `lib/ui/` instead of duplicating logic across instruments.

## Testing Guidelines
Use `flutter_test` for unit and widget coverage. Mirror `lib/` inside `test/`; for example, put piano rule tests in `test/schema/rules/piano_rules_test.dart`. Focus first on music-theory calculations, Riverpod store transitions, and save/load serialization. For bug fixes and behavior changes, prefer adding a focused regression test near the affected rule, store, or widget. CI currently builds release artifacts but does not enforce tests or coverage, so new behavior should include targeted tests plus a clean `flutter analyze`.

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

## Project Learnings
- Keep root guidance short and repo-specific; move subsystem-specific agent rules into nested `AGENTS.md` files only when a folder develops repeated, unique constraints.
