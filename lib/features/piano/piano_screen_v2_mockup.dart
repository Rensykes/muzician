/// Piano V2 — UI/UX redesign mockup.
///
/// Sandbox screen that hosts the real [PianoKeyboard] inside the redesigned
/// shell (compact app bar → hero canvas → detection ribbon → docked toolbar).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_mockup_shell.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import 'piano_keyboard.dart';

class PianoScreenV2Mockup extends ConsumerStatefulWidget {
  const PianoScreenV2Mockup({super.key});

  @override
  ConsumerState<PianoScreenV2Mockup> createState() => _PianoScreenV2MockupState();
}

class _PianoScreenV2MockupState extends ConsumerState<PianoScreenV2Mockup> {
  String _range = 'C2–C7';
  String _scale = 'C maj';
  String _chord = 'maj';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final selectedCount = state.selectedNotes.length;
    final detected = selectedCount == 0
        ? null
        : selectedCount == 1
            ? '1 note · ${state.selectedNotes.first}'
            : '$selectedCount notes selected';

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Piano',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Piano',
              chipLabel: _scale,
              actions: [
                IconBtn(icon: Icons.bookmark_border, onTap: () {}),
                IconBtn(icon: Icons.tune, onTap: () {}),
                IconBtn(icon: Icons.more_horiz, onTap: () {}),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: GlassFrame(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const PianoKeyboard(),
                ),
              ),
            ),
            DetectionRibbon(
              detectedLabel: detected,
              hintLabel: 'Tap keys to detect chord and scale',
            ),
            DockedToolbar(
              children: [
                DockField(
                  label: 'RANGE',
                  value: _range,
                  flex: 2,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Range',
                      options: const ['C2–C7', 'C3–C6', 'A0–C8', 'F3–F5', 'C4–C5'],
                      current: _range,
                    );
                    if (picked != null) setState(() => _range = picked);
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
                DockField(
                  label: 'CHORD',
                  value: _chord,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Chord',
                      options: const ['maj', 'min', 'dom7', 'maj7', 'm7', 'sus2', 'sus4', 'dim', 'aug'],
                      current: _chord,
                    );
                    if (picked != null) setState(() => _chord = picked);
                  },
                ),
                DockPrimaryButton(
                  icon: Icons.play_arrow_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Preview $_chord chord'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: MuzicianTheme.surface,
                        duration: const Duration(milliseconds: 900),
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
