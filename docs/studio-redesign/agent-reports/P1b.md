# P1b — theme preference and persistence

Implemented the device-local Studio theme preference. `AppThemeVariant` exposes
`studio` and `studioMuzician`; `AppSettings.themeVariant` defaults to `studio`
and is stored under the existing `themeVariant` JSON key. Missing, unknown, or
non-string values fall back to Studio while other decoded settings remain
available. `SettingsNotifier.setThemeVariant` updates through `copyWith` and
persists using the existing settings record. Theme selection is not part of
project or named-save snapshots.

Files changed:

- `lib/models/app_theme_variant.dart`
- `lib/models/save_system.dart` — `AppSettings` field, copy, and JSON support
- `lib/store/settings_store.dart`
- `test/models/app_settings_test.dart`
- `test/store/settings_store_test.dart`

Verification:

- `dart format` on the five changed Dart files — passed.
- `flutter test --no-pub test/models/app_settings_test.dart test/store/settings_store_test.dart` — passed.
- `flutter analyze --no-pub` on the five changed Dart files — no issues.
- `git diff --check` — passed.

The root preference selector and runtime theme wiring can consume this API.
This phase changes settings persistence only; visual theme behavior remains
owned by the Studio shell implementation.
