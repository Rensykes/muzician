# Studio plan review — revision 2

Date: 18 October 2026

Verdict: **APPROVED**

Reviewed PLAN.md revision 2, the revised DESIGN runtime contract, PRODUCT scope, updated PROGRESS ledger, and the shared editor/library dependency paths identified in R1. Implementation may begin under the ownership and acceptance gates in revision 2. This approves the plan; it does not certify unimplemented code or substitute for phase verification.

## Blocking findings resolved

### R1.1 — Shared surface ownership: resolved

P1c explicitly owns the bounded Song-hosted drum/editor/library, audio picker/clip, fullscreen launcher and Settings recovery files. The referenced files exist. The drum library and loop-save dependencies are included, and their further dependencies resolve to the shared shell/UI already owned by P1a. The plan permits additional bounded ownership transfers if inspection reveals another presentation dependency, rather than inviting wholesale Song migration.

P1c finishes before the main feature parallelism and before Writer consumes the shared surfaces. Tests cover Writer usage, fixed Song scope, and recovery presentation. The explicit Studio-only layout selection preserves Song's existing shared-editor layout.

### R1.2 — Live route theme versus fixed legacy scope: resolved

The revised contract places an immutable projection of the canonical Settings preference above MaterialApp/Navigator and any isolated editor containers. A route captures only its Studio/legacy scope kind. Its wrapper resolves the live Studio variant inside captured inherited-theme wrappers, while legacy routes remain fixed. This is feasible with Flutter's inherited-widget model and addresses both frozen theme snapshots and accidental reads from isolated Settings providers.

Colors resolved inside the live wrapper, stable child identity, explicit ownership for direct route sites, and tests for open/nested route state establish a concrete implementable contract. The Writer isolated melody check is assigned to P4; Song note/drum boundary tests belong to P1, with the legacy Roll layout assertion in P3. The plan no longer relies on closing/reopening a panel to demonstrate a live theme update.

## Other checks

- Song's embedded Roll is now explicitly legacy in both layout and palette, consistent with the exclusion.
- Existing provider scopes, editor containers, native-edit callbacks, persistence semantics and gesture math remain protected by the plan.
- Baseline analyzer PASS is recorded in the ledger. No application source changes appeared in the inspected diff.
- File ownership and phase dependencies are sufficient for implementation delegation without simultaneous writes to shared files.

## Nonblocking implementation notes

- The actual project picker file is `lib/ui/project_picker_sheet.dart`; one route-ownership sentence uses `lib/ui/project_picker.dart`. The `lib/ui/*` ownership already covers the real file. Correct the spelling in dispatch notes or the next documentation edit.
- For route tests, assert a descendant's resolved palette and preserved input/scroll state after a root preference update. Verifying only the root MaterialApp theme would not exercise the captured-wrapper issue.
- Keep the new source widget an ordinary immutable inherited value rather than an independently persisted preference or a captured Theme. The approved contract already requires this distinction.

No new blockers. No tests were executed for this document-only review. Proceed with P1, and require the planned regression evidence before its gate passes.
