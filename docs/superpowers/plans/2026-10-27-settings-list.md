# Settings List Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Settings screen's card stack with compact divider-separated groups and visually integrate Data Recovery.

**Architecture:** Keep settings state, callbacks, and recovery actions in their existing widgets. Refactor presentation only, using Studio palette tokens and shared unframed section/list styling.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-10-27-settings-list-design.md`

## Global Constraints
- Preserve all setting values, interactions, persistence, and recovery actions.
- Use Studio semantic palette colors and compact spacing; avoid standalone cards.
- Keep the screen readable, accessible, and scrollable on iPhone.
- Do not change settings behavior or recovery data handling.

## Review Focus
- Empty recovery state remains compact and understandable — cover in settings widget test.
- Populated recovery entry keeps expand, copy, export, delete reachable — preserve existing tests/coverage.
- Settings selection and controls still update through current callbacks — cover in settings widget test.
- Layout remains valid at compact iPhone width — verify a compact viewport.
- Both Studio themes keep readable dividers and text — verify palette-based styles and analyze.

---

### Task 1: Refactor Settings presentation

**Files:**
- Modify: `lib/main.dart` (`_SettingsScreen`)
- Modify: `lib/features/save_system/data_recovery_panel.dart`
- Test: `test/main_startup_test.dart`, `test/features/save_system/data_recovery_panel_test.dart`
- Update: `README.md` feature overview and `docs/save_system.md` Settings/recovery description as needed

**Interfaces:**
- Consumes: existing `settingsProvider`, `dataRecoveryProvider`, and notifier callbacks.
- Produces: same Settings and Data Recovery behavior with grouped, divider-separated layout.

- [x] **Step 1: Add/adjust a widget test** asserting Settings sections render without their old card treatment, Data Recovery empty state renders, and the note-spelling setting remains operable.
- [x] **Step 2: Run the focused Data Recovery presentation test** with `flutter test test/features/save_system/data_recovery_panel_test.dart --plain-name 'empty Data Recovery is an unframed settings section'`; it failed before implementation and passed after.
- [x] **Step 3: Refactor Settings sections** into compact, divider-separated groups; replace DataRecoveryPanel's standalone container with a matching unframed section while retaining expansion and action controls.
- [x] **Step 4: Update Settings documentation** only where the shipped design/feature overview needs the new grouped presentation clarified.
- [x] **Step 5: Run focused tests, format, analyzer, and full applicable tests** with `flutter test test/main_startup_test.dart test/features/save_system/data_recovery_panel_test.dart`; focused checks pass; full suite has one noted 320px app-level overflow.
- [x] **Step 6: Check iPhone availability and install/launch** using `scripts/run_ios_iphone.sh` if device connection and signing are ready; no physical iPhone was detected, so install was blocked.
