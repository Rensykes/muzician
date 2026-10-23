import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/guitar_sound.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../utils/note_player.dart';
import '../instrument_shared/instrument_screen.dart';

/// Audition the selected physical strings without changing their selection.
class FretboardAuditionControls extends ConsumerWidget {
  const FretboardAuditionControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final settings = ref.watch(settingsProvider);
    final palette = StudioPalette.of(context);
    final downstroke = getFretboardStrumMidiNotes(state);
    final canStrum = downstroke != null && downstroke.isNotEmpty;
    final unavailableHint = downstroke == null
        ? 'Choose one note per string to strum.'
        : 'Select notes on the fretboard to strum.';

    void strum({required bool upstroke}) {
      final notes = getFretboardStrumMidiNotes(
        ref.read(fretboardProvider),
        upstroke: upstroke,
      );
      if (notes == null || notes.isEmpty) return;
      final currentSettings = ref.read(settingsProvider);
      NotePlayer.instance.previewGuitarStrum(
        notes,
        tone: currentSettings.guitarTone,
        volume: currentSettings.noteVolume,
      );
    }

    return Padding(
      key: const Key('fretboardAuditionControls'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              InstrumentModeMenu<GuitarTone>(
                key: const Key('fretboardSound'),
                label: 'Sound',
                current: settings.guitarTone,
                onSelect: ref.read(settingsProvider.notifier).setGuitarTone,
                options: const [
                  (GuitarTone.clean, 'Clean', 'Clean electric guitar'),
                  (
                    GuitarTone.distorted,
                    'Distorted',
                    'Distorted electric guitar',
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Strum', style: TextStyle(color: palette.textSecondary)),
                  const SizedBox(width: 4),
                  for (final upstroke in [false, true])
                    IconButton(
                      key: Key(upstroke ? 'fretboardStrumUp' : 'fretboardStrumDown'),
                      tooltip: canStrum
                          ? upstroke ? 'Strum up' : 'Strum down'
                          : unavailableHint,
                      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                      onPressed: canStrum ? () => strum(upstroke: upstroke) : null,
                      icon: Icon(
                        upstroke ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        semanticLabel: upstroke ? 'Strum up' : 'Strum down',
                        size: 20,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (downstroke == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                unavailableHint,
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
