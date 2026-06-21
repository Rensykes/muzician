# Writer Glass Retheme — Subagent Dispatch Prompt

Use this prompt to dispatch the implementation to a fresh agent session.

---

## Prompt

You are implementing the Writer Glass Retheme for the Muzician Flutter app. This is a visual-only migration of the Songwriter ("Writer") tab from raw Material widgets to the app's glassmorphism dark theme.

**Branch:** `writer-glass-retheme` (already exists, already checked out)

**Plan:** `docs/superpowers/plans/2026-06-08-writer-glass-retheme.md`
**Spec:** `docs/superpowers/specs/2026-06-08-writer-glass-retheme-design.md`

**Rules:**
- Visual-only changes. No logic, no data model, no store changes.
- Follow the plan task-by-task, in order (Task 1 through Task 10).
- Each task has exact code and commit messages — follow them precisely.
- After each task, run `flutter analyze` on the modified file. Fix any issues before committing.
- Commit after each task with the provided commit message.
- At Task 10, run full `flutter analyze lib/features/songwriter/` and `flutter test test/` to verify nothing broke.

**Key files you'll reference:**
- `lib/theme/muzician_theme.dart` — Theme constants (colors, glass values)
- `lib/features/_mockup_shell.dart` — Shared UI primitives: `CompactAppBar`, `IconBtn`, `StatusChip`, `GlassFrame`, `showWidgetSheet`, `showPickerSheet`

**What NOT to change:**
- `songwriter_structure_editor.dart` — separate full-screen editor, out of scope
- `songwriter_undo.dart` — SnackBar logic, no visual change needed
- `songwriter_save_lane_filter.dart` — constants only
- Any model/store/rules files

**Start by reading the plan file, then execute Task 1.**
