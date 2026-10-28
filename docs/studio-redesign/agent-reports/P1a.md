# P1a Studio foundation

Status: **COMPLETE**, 18 October 2026. Owner: `/root/studio_foundation`.

`main.dart` ownership transferred to parent/P2 after final passing verification. No commits made. No iOS files touched. Parent owns central feature/spec/README reconciliation and final AGENTS guidance update.

## Shipped foundation

- Immutable, private-constructor `StudioPalette` ThemeExtension with static const `studio`, `studioMuzician`, and `legacy` instances. Copy/interpolation defensively retain immutable gradient lists. Legacy static color fields made final. No selected global palette.
- All planned familiar color roles are public: scaffoldBg, surface, dialogBg, textPrimary, textSecondary, textMuted, textDim, sky, teal, violet, purple, emerald, orange, red, glassBg, glassBorder, gradientColors, onAccent; `isStudio` determines presentation scope.
- `StudioTheme.data(AppThemeVariant)` and `StudioTheme.legacyData()` supply Material defaults, readable inputs, dialog surfaces and 44px button defaults.
- `StudioThemeSource(variant:, child:)` is a projection of canonical Settings above MaterialApp/Navigator, independent of nested provider containers.
- `StudioRouteTheme(isStudio:, child:)` resolves live root Studio in its build, or fixed legacy. `StudioRouteTheme.builder(caller, contentBuilder)` captures ONLY scope kind, with a Builder inside the resolved Theme.
- `showStudioDialog<T>` and `showStudioModalBottomSheet<T>` wrap shared entrypoints. Modal route background is transparent; opaque content Material resolves inside live scope. Sheets respect keyboard insets. `showWidgetSheet`, `showPickerSheet`, app information, project picker/config/gate, save-browser and project-key confirmation routes use this contract.
- Root `MuzicianApp` watches Settings.themeVariant without new keys/containers/workspaces. Song content receives explicit `StudioRouteTheme(isStudio:false)` while root navigation follows selected Studio.
- Settings → Appearance offers Studio (graphite/mint) and Studio Muzician (night/sky/teal/violet), with descriptive labels. Existing Settings/startup recovery/linked instrument edit behavior remains intact.
- Shared widgets, transport, save browser, project controls, help, dialogs and coach overlay use inherited palette. Preview/coach painters receive palette and include it in repaint comparison. Studio sheets disable decorative blur, shared surfaces are opaque, notifications use compact live themed content. Legacy notifications retain AwesomeSnackbarContent.
- Shared full-title `WorkspaceHeader(title:, chipLabel:, actions:, onClose:)` is ready for P2/P3 structural layouts. It places title above the context/action Wrap. Existing `CompactAppBar` keeps its established 44px geometry until each workspace's composition migrates, avoiding assumptions in legacy height calculations.
- Project chip has full-name tooltip/semantics and Studio 44px minimum target. Transport controls and checkbox rows get Studio 44px targets. Narrow root navigation labels ellipsize instead of wrapping beyond the bar; full labels remain in text/semantics.

## Files owned and changed

- `lib/theme/studio_theme.dart` (new), `lib/theme/muzician_theme.dart`.
- `lib/main.dart`, `lib/features/_mockup_shell.dart`.
- `lib/ui/core/app_info_panel.dart`, `coach_overlay.dart`, `muzician_dialog.dart`, `project_off_scale_dialog.dart`, `update_project_key_dialog.dart`.
- `lib/ui/glass_snackbar.dart`, `project_chip.dart`, `project_config_sheet.dart`, `project_gate_modal.dart`, `project_picker_sheet.dart`, `project_required_placeholder.dart`, `save_browser_panel.dart`, `save_tree_browser.dart`, `transport_strip.dart`, `save_previews/save_preview_thumbnail.dart`.
- `test/theme/studio_theme_test.dart`, `test/theme/studio_route_theme_test.dart` (new).
- This phase report only under docs. No edits in another agent's owned feature/model/store/test files.

## Verification

SDK commands use `/Users/francescolacriola/dev/tools/flutter/bin/` and require escalated SDK-cache access.

- Changed-path `dart format`: PASS (21 Dart files initially; final four changed paths formatted again).
- `flutter test --no-pub test/theme test/ui test/main_startup_test.dart`: **63 PASS**, final run after keyboard/notification/checkbox changes.
- `flutter analyze --no-pub`: **PASS**, no issues, final run 2.9s.
- `git diff --check`: PASS.

New tests measure primary/secondary/muted text ≥4.5:1 on canvas/surface/dialog for both palettes and primary control boundary ≥3:1; on-accent text ≥4.5:1. They verify immutable copies, legacy fallback, fixed legacy override, actual showWidgetSheet and nested dialog live updates, preserved text state identity and scroll offset, retained piano selection and SaveSystem state identity, usable input above a simulated 200px keyboard inset, live themed notification/action, and actual root Appearance switching without replacing the shell element.

Viewport evidence: real app root/Appearance at **320×844** and **1024×768** normal text; the actual Settings subtree independently at those viewports with **1.5× text**. Shared UI/startup regression suite also covers existing compact/wide project/save/header/recovery behavior. Final native simulator visual capture remains P5.

## Diagnosed limitations / next phase

- Attempting the entire pre-P4 app at 1.5× text exposed existing Writer header issues: horizontal overflow at `songwriter_header.dart:66` on320px (36px at1.5), and `:450` readout vertical overflow9px at both320/1024 widths. The IndexedStack lays out offstage Writer too. Tests isolate the actual Settings subtree for P1 scale verification; they do not claim the whole app passes1.5 yet. Parent accepted this separation and assigned full320/1.5 verification to P4/final gate. These failures were not ignored/suppressed in passing tests.
- One intermediate full root320px failure came from nav labels wrapping and was fixed using maxLines1. Another Settings320/1.5 failure came from the DataRecovery heading; P1c fixed the owned row with Expanded and added its regression. Final P1a suite passes.
- The remaining literal shared colors are physical piano white/black thumbnail identity; decorative top separators in project sheets/root navigation; and a tiny legacy warning badge neutral. No residual MuzicianTheme references remain in migrated shared code. P5 may reconcile decorative border tokens if useful; these are not text/focus/control-only boundaries.
- P2/P3 should use WorkspaceHeader within their newly measured layouts, not substitute it inside old fixed-height calculations. `CompactAppBar` remains available for excluded Song compatibility.
- Feature owners must adopt `StudioRouteTheme.builder` or scoped helpers at direct route sites. Never read Settings inside isolated editor containers for palette and never capture ThemeData. P4 owns Writer isolated melody tests and direct songwriter audio-action routes.
- AGENTS.md reviewed after implementation: current state/save/music rules remain applicable. Parent can add the concise persistent palette/source/painter/Song-boundary rule during P5 after architecture is integrated.
