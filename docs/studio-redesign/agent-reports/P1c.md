# P1c shared cross-feature surfaces

Status: implementation and focused verification COMPLETE (2026-10-18). No commits.

## Scope and API dependency

Read root AGENTS.md, PRODUCT.md, DESIGN.md, PLAN.md R2 APPROVED, PROGRESS.md, `.agents/orchestrator.md`, `.agents/instrument-renderer.md`, `.agents/save-system.md`; loaded Flutter widget-test and static-analysis skills. Read all seven owned files and Writer/Song callers before editing. Reviewed AGENTS.md again after implementation; no new independent rule is needed here (parent owns final theme boundary guidance).

P1a foundation provided the stable `lib/theme/studio_theme.dart` API before import/call edits: `StudioPalette.of(context)`, static Studio/Studio Muzician/legacy palettes, `StudioRouteTheme.builder(caller, contentBuilder)`, and fixed `StudioRouteTheme(isStudio: false, child: ...)`. P1c introduces no duplicate theme/source/route helpers.

## Files changed

- `lib/features/song/drum_machine_editor.dart`: resolve host palette throughout shared editor, lane fill and transport; direct clear-confirmation dialog uses the scope-aware route builder. Studio alone uses 44px cells (48px lane rows including margins), 44px lane-menu targets, restrained common percussion accent/no glow, readable step boundaries and wrapping transport. Existing beat grouping, tick math, filling, backing, preview and onChanged are retained. Bounded Studio hosts gain vertical scrolling for short landscape; horizontal grid scrolling/sticky labels remain. Song retains 32px cells / 40px rows / original lane colors / row transport / glow. Step semantics announce lane, step and toggled state.
- `lib/features/song/drum_library_sheet.dart`: inherited palette for preset/category presentation; existing library selection unchanged.
- `lib/features/song/song_audio_picker_sheet.dart`: inherited colors, preserving record/import callbacks and support gating.
- `lib/features/song/song_audio_clip_body.dart`: immutable palette injected into waveform and broken-stripe painters; both comparators repaint on palette change. Studio uses semantic waveform/error colors. Exact legacy waveform colors and broken-stripe color retained. Names/duration/format/broken behavior unchanged. Search confirmed AudioWaveformPainter has no external constructor callers.
- `lib/features/song/song_pattern_editor_launcher.dart`: explicit fixed legacy wrapper for both fullscreen Song note and drum routes; nested migrated sheets inherit legacy even after root variant changes.
- `lib/features/save_system/data_recovery_panel.dart`: inherited presentation and live/fixed scoped delete dialog. Clipboard/export/delete operations and all persisted backup data remain unchanged.
- `test/features/song/shared_editor_theme_test.dart` (new): 7 focused geometry / live nested state / fixed Song route tests.
- `test/features/song/song_audio_clip_body_test.dart`: waveform + broken overlay palette repaint regression.
- `test/features/save_system/data_recovery_panel_test.dart`: live Settings confirmation, expanded original text and exact backing preference preservation through switching.

`drum_loop_save_panel.dart` was inspected but needs no direct change: it contains no fixed presentation values, already delegates its sheet to the foundation helper, and inherits P1a SaveBrowserPanel / ProjectRequiredPlaceholder. Its existing tests pass.

## Verification

- `dart format` on the six changed source files and three changed/new scoped test files: PASS.
- `flutter analyze --no-pub`: final PASS, no issues (1.9s). Initial own unused locals and redundant const diagnostics fixed; no suppressions.
- Focused 17-file `flutter test --no-pub ...` suite: PASS, **47 tests** (5.3s). Targets:
  - Song: shared_editor_theme, drum_machine_editor, drum_fill_menu, drum_clear, drum_audition_stop, drum_library, drum_loop_save_panel, song_note_pattern_editor, song_audio_picker_sheet, song_audio_clip_body.
  - Writer: drum_pattern_sheet_library, drum_backing_audition, songwriter_audio_clip_sheet, songwriter_audio_lane, songwriter_slice_mode, songwriter_segment_editor.
  - Save System: data_recovery_panel.
- Geometry test viewports: **390×844**, **844×390**, **1024×768**; 44px cell constraints, toggle callback, beat headers, library access and landscape lower-lane reachability asserted. Existing Recovery tests cover 390×844 and 1180×820.
- Nested drum fill test changes offset, switches root source while still OPEN, asserts new Studio palette and identical state/value. Legacy repeat asserts unchanged palette and 32px geometry.
- Song fullscreen tests cover both note/drum routes across root switching; note embedded Roll retains showBackground/showSavePanels/showScale false, and open nested Roll Settings / drum Fill stay legacy.
- Audio regression checks both CustomPainters report repaint after live palette switch.
- Recovery regression leaves raw backup preference unchanged and expanded after canceling an open confirmation across root switch. Existing exact-copy/cancel/selective-delete tests also pass.
- First suite attempt encountered a transient P1a `const StudioPalette.of` compile error in SaveBrowserPanel. Reported to its owner; owner fixed it; final suite above passes. P1c never edited P1a files.
- `git diff --check`: PASS.
- User iOS hashes unchanged: project.pbxproj `6dc139c9e94623fc3a8b4e52b36ada3afbfb1e15`; Runner.xcscheme `7ffcf4b6e9f55f402069d4d6fdfbdaf64ad00b70`.
- Flutter/Dart commands used approved escalation for SDK cache outside the workspace; no application files outside owned scope changed.

## Remaining integration / documentation

No known P1c blocker. Parent/P4 must wrap Writer's direct audio-picker/recorder routes in `songwriter_audio_actions.dart` using the foundation live route builder; that file is outside this allowlist. Shared SongAudioPickerSheet itself resolves its nearest palette correctly. P3 still owns removal of Roll's hardcoded local legacy Theme for Studio, preserving the tested Song boundary.

Parent owns relevant feature docs/README and final ledger. Suggested documentation text: shared Writer drum editors use beat groups with 44px steps and scroll on short/wide layouts; Song keeps its current editor appearance; Settings recovery follows the selected appearance while original backup operations stay the same. Residual white/black alpha overlays in owned files are decorative alternating rows/background badges, not unconverted semantic text; explicit hex audio values are fixed legacy branches only.

Screenshots/device inspection remain the parent's integrated P5 responsibility. Widget layout verification is complete at compact/wide/short sizes. Next action: integrate this completed P1c diff after P1a tests pass, update relevant docs, then release P4 shared-surface dependency.

## Integration correction — narrow Settings heading

Foundation's real Settings route test at 320×844 / text scale 1.5 identified a 41px Data Recovery title-row overflow after the initial 47-test pass. Fixed only the owned heading: title is now Expanded and can wrap beside its icon. Added `Data Recovery actions fit narrow large text` using Studio, 320×844 / 1.5 text and 32px outer horizontal padding (also exercised compact/wide cases with that Settings-like constraint).

- Changed-path format: PASS.
- `flutter test --no-pub test/features/save_system/data_recovery_panel_test.dart`: PASS, 5 tests (2.3s), including narrow/scaled case and exact copy/selective delete.
- `flutter analyze --no-pub`: PASS, no issues (3.0s).
- Total focused coverage is now 48 tests across the same 17 targets (47-test suite plus newly added narrow/scaled recovery case; changed recovery target rerun separately).

Next action: P1a reruns its isolated actual Settings test; parent can close P1 gate once its own evidence passes.
