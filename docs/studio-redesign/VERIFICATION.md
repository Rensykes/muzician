# Integrated verification record

Completed 19 October 2026 on branch `codex/studio-redesign`. Final independent implementation review **APPROVED**, [R2](reviews/implementation-r2.md). The approved plan and R1 findings are retained.

## Automated evidence

- Baseline analyzer clean. Final `flutter analyze --no-pub`: **PASS**, no issues, 2.7s.
- Full `flutter test --no-pub`: **1,389 PASS** in81s, before the final meter-group regression and two palette/help refinements.
- After those refinements: **68 theme/UI/startup/painter tests PASS**. Covers actual app navigation, both appearance switches, selected project/notes/Writer history preservation, open/nested route input+scroll retention, palette repaint, Settings.
- Meter-aware Strum fix: **24 targeted tests PASS**, independently rerun by reviewer. Includes two-bar3/8,6/8,3/16,2/2 at320px/text1.5; canonical timing and events unchanged.
- P2 instrument suite109PASS plus22app/linked/startup; P3 Roll suite84PASS; P4 Writer suite181PASS. Counts overlap with the full suite and are not additive.
- Settings migration/persistence16PASS; missing/unknown theme defaults Studio without erasing other preferences.
- Layout coverage:390×844,844×390,1024×768 and320×844 with1.5text; both palettes. Root in-scope pages tested populated. Song normal-scale smoke included; its known320/1.5 overflow is excluded from the redesign gate.
- Format changed Dart paths PASS. `git diff --check` PASS. Docs, README and AGENTS reconciled.

## Native build and interactions

- Final device-targeted `flutter run --no-pub -d DEB08618-A4F2-4066-9E3F-5E7014A69FA0`: **Xcode build PASS8.3s and app launched**.
- Environment: explicit `DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer`; `/tmp/muzician-xcode-tools/xcrun` wrapper exports the same for native hooks. Global xcode-select left unchanged.
- A separate generic `flutter build ios --simulator --debug --no-pub` failed in Flutter's framework architecture validation: requested combined string `arm64 x86_64` despite lipo reporting both architectures. Targeting the booted device succeeds. Flutter run also prints a nonfatal native-assets `SdkRoot` warning; app launch and interactions succeed. No app code/signing change was made to hide these toolchain issues.
- iPhone18Pro and iPadPro11M5 iOS27: inspected all four Studio workspaces; phone compact/landscape, iPad side inspectors. Applied guitar/piano voicings, selected exact piano notes, drew Roll notes/added Stack, created Writer section/chord via real UI, opened inspectors and Writer chord panels.
- Settings StudioMuzician selected, process terminated and relaunched; Settings retained the selection. Returned to Studio original. Song stayed legacy while root navigation used Studio; its fullscreen drum editor remained legacy. Note-editor legacy boundary covered by widget tests.
- [Native screenshots](evidence/README.md) record compact/wide interfaces, both palettes, appearance after restart and Song boundary.

## Limits and preserved state

- No hardware-device, microphone recognition quality, audio fidelity or performance benchmark claim. Musical canvas hit zones preserve native geometry and are not uniformly44px.
- Song remains intentionally unchanged; at320px/text1.5 its existing header overflows33px. Normal compact Song title also wraps. Existing canonical denominator2/16 timing remains unchanged; Strum groups follow the canonical model.
- User's pre-task iOS working files restored after automatic Flutter compatibility rewrites, verified with **git blob hashes** (not raw shasum): project6dc139c9e94623fc3a8b4e52b36ada3afbfb1e15; scheme7ffcf4b6e9f55f402069d4d6fdfbdaf64ad00b70.
- No deployment, PR, commits or destructive reset. Existing projects retained; testing used the prior Redesign study and blank iPad Dump workspace.


## Visual fidelity refinement — 19–20 October 2026

The earlier functional approval did not establish fidelity; the user requested a closer match. The revised implementation was compared with the selected Studio references using populated iPhone and iPad simulator screens. Fresh visual review approved it; see [review R1](reviews/visual-fidelity-r1.md).

- Integrated refinement suite: **242 PASS** across `test/theme`, `test/ui`, `test/features/instrument_shared`, `test/features/piano_roll`, Writer Studio and startup tests. Log: `/tmp/studio-v2-complete-tests.log`.
- After the final mixed Writer row alignment correction: **14 Writer Studio tests PASS**, rerun 20 October. Log: `/tmp/studio-writer-final-tests.log`.
- Final `flutter analyze --no-pub`: **no issues**, 20 October. Changed Dart files formatted; diff whitespace check clean.
- Device-targeted native builds and launch succeeded for iPhone 18 Pro and iPad Pro 11-inch M5. Final iPad rebuild passed in 12 seconds. The known nonfatal native-assets SdkRoot message remains.
- Final visual evidence: `evidence-v2/07`, `12`, `13`, `14`, `15`, and post-alignment captures `17`/`18`. The full earlier suite was not rerun for this layout refinement; test counts above overlap and are not additive.
- Roll now reveals newly added notes vertically, labels beats, shows current-column context when height permits, and keeps five tools plus Snap reachable. Writer row edges align without enlarging entirely empty rows. Piano shows three voicing previews and readable octave selection.
- Comparison HTML and its source-image paths were inspected. Automatic opening of its file URL was blocked by browser URL policy; no alternate browser route was used.

The previous limits on physical hardware, audio quality, performance and excluded Song layout still apply. No music-theory or persistence redesign was introduced by this refinement.

Final 20 October cleanup: iPhone rebuild passed in 6.4 seconds; both simulator apps left running after Flutter detach. Temporary preview helpers stopped. User iOS working copies restored and their git blob hashes match the preserved values above.

## Expanded Notes and Setup correction, 21 October 2026

- Focused actual-workspace and app tests: 30 PASS; palette-retention follow-up: 7 PASS. Counts overlap. Formatter and analyzer clean.
- Native iPhone 18 Pro build/launch PASS (10.2 seconds); iPad Pro 11-inch M5 PASS (8.3 seconds). Known nonfatal SdkRoot warning persists.
- Selected F/C on both instruments, switched Notes/Setup without losing selections, scrolled compact page to its footer. All four populated captures in evidence-v3 inspected against user attachments; independent UX reviewer approved.
- Notes now fits its contents with one parent vertical scroll. Setup removes accumulated padding/repeated labels and moves Clear all selections below configuration. Both instrument guides, README and DESIGN describe the behavior. AGENTS reviewed; its existing populated-runtime requirement covers the correction.
- Broader earlier test results remain historical; no full-suite rerun claimed. Existing chip semantics limitations are recorded in reviews/inspector-spacing-r1.md.
