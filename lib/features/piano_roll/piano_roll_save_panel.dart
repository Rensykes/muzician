/// PianoRollSavePanel – save/load panel for the Piano Roll screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/save_system.dart';
import '../../store/piano_roll_store.dart';
import '../../store/save_system_store.dart';
import '../../ui/save_browser_panel.dart';

/// A panel that lets the user save and load piano roll snapshots.
///
/// Only piano roll saves are shown. Mounting this widget inside a card
/// in the piano roll screen gives it the correct glassmorphism styling.
class PianoRollSavePanel extends ConsumerWidget {
  const PianoRollSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(
      saveSystemProvider.select((s) => s.selectedProjectId),
    );
    if (selectedId == null) {
      return const _NoProjectPlaceholder();
    }
    return SaveBrowserPanel(
      rootFolderId: selectedId,
      instrumentFilter: 'piano_roll',
      captureSnapshot: () => _captureSnapshot(ref),
      onLoad: (snap) => _loadSnapshot(ref, snap),
    );
  }

  /// Builds a [PianoRollSnapshot] from the current store state.
  PianoRollSnapshot _captureSnapshot(WidgetRef ref) {
    final prState = ref.read(pianoRollProvider);
    final activeScale = ref.read(pianoRollActiveScaleProvider);

    return PianoRollSnapshot(
      tempo: prState.config.tempo,
      key: prState.config.key,
      numerator: prState.config.timeSignature.beatsPerMeasure,
      denominator: prState.config.timeSignature.beatUnit,
      totalMeasures: prState.config.totalMeasures,
      notes: prState.notes
          .map(
            (n) => <String, dynamic>{
              'midiNote': n.midiNote,
              'startTick': n.startTick,
              'durationTicks': n.durationTicks,
            },
          )
          .toList(),
      pitchRangeStart: prState.pitchRangeStart,
      pitchRangeEnd: prState.pitchRangeEnd,
      selectedColumnTick: prState.selectedColumnTick,
      snapTicks: prState.snapTicks,
      highlightedNotes: List<String>.from(prState.highlightedNotes),
      pendingScale: activeScale != null
          ? PendingScale(
              root: activeScale.root,
              scaleName: activeScale.scaleName,
            )
          : null,
    );
  }

  /// Restores piano roll state from a snapshot.
  void _loadSnapshot(WidgetRef ref, InstrumentSnapshot snap) {
    if (snap is! PianoRollSnapshot) return;
    ref.read(pianoRollProvider.notifier).loadSnapshot(snap);
    ref.read(pianoRollPendingScaleProvider.notifier).state = null;
    if (snap.pendingScale != null) {
      ref.read(pianoRollActiveScaleProvider.notifier).state = (
        root: snap.pendingScale!.root,
        scaleName: snap.pendingScale!.scaleName,
      );
    } else {
      ref.read(pianoRollActiveScaleProvider.notifier).state = null;
    }
  }
}

class _NoProjectPlaceholder extends StatelessWidget {
  const _NoProjectPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pick a project to save / load',
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () { /* wired in Task 16 */ },
            child: const Text('Choose project'),
          ),
        ],
      ),
    );
  }
}
