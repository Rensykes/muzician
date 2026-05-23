/// Fretboard V2 — UI/UX redesign mockup.
///
/// Sandbox screen that hosts the real [GuitarFretboard] widget inside the
/// new shell (compact app bar → hero canvas → detection ribbon → docked
/// action bar). Iterate on this before porting to [_FretboardScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_mockup_shell.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import 'fretboard.dart';

class FretboardScreenV2Mockup extends ConsumerStatefulWidget {
  const FretboardScreenV2Mockup({super.key});

  @override
  ConsumerState<FretboardScreenV2Mockup> createState() => _FretboardScreenV2MockupState();
}

class _FretboardScreenV2MockupState extends ConsumerState<FretboardScreenV2Mockup> {
  String _tuning = 'Std EADGBE';
  int _capo = 0;
  String _scale = 'C maj';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final selectedCount = state.selectedNotes.length;
    final detected = selectedCount == 0
        ? null
        : selectedCount == 1
            ? '1 note · ${state.selectedNotes.first}'
            : '$selectedCount notes selected';

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Fretboard',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Fretboard',
              chipLabel: _scale,
              actions: [
                IconBtn(icon: Icons.bookmark_border, onTap: () {}),
                IconBtn(icon: Icons.tune, onTap: () {}),
                IconBtn(icon: Icons.more_horiz, onTap: () {}),
              ],
            ),
            // Hero: real fretboard. No glass frame — it has its own dark surface.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: GlassFrame(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const GuitarFretboard(),
                ),
              ),
            ),
            DetectionRibbon(
              detectedLabel: detected,
              hintLabel: 'Tap notes on the fretboard to detect chords',
            ),
            DockedToolbar(
              children: [
                DockField(
                  label: 'TUNING',
                  value: _tuning,
                  flex: 2,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Tuning',
                      options: const ['Std EADGBE', 'Drop D', 'DADGAD', 'Open G', 'Half-step ↓', 'Open D'],
                      current: _tuning,
                    );
                    if (picked != null) setState(() => _tuning = picked);
                  },
                ),
                DockField(
                  label: 'CAPO',
                  value: _capo == 0 ? '0' : 'fret $_capo',
                  onTap: () async {
                    final picked = await showPickerSheet<int>(
                      context: context,
                      title: 'Capo',
                      options: List.generate(13, (i) => i),
                      current: _capo,
                    );
                    if (picked != null) setState(() => _capo = picked);
                  },
                ),
                DockField(
                  label: 'SCALE',
                  value: _scale,
                  flex: 2,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Scale',
                      options: const [
                        'C maj', 'C min', 'D maj', 'D min', 'E maj', 'E min',
                        'F maj', 'G maj', 'A min', 'B min', 'C pent', 'A blues',
                      ],
                      current: _scale,
                    );
                    if (picked != null) setState(() => _scale = picked);
                  },
                ),
                DockPrimaryButton(
                  icon: Icons.music_note_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Open chord voicing picker'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: MuzicianTheme.surface,
                        duration: Duration(milliseconds: 900),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
