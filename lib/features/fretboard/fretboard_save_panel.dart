/// FretboardSavePanel – save/load panel for the Fretboard screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/fretboard_store.dart';
import '../../ui/save_browser_panel.dart';

/// A panel that lets the user save and load fretboard snapshots.
///
/// Only fretboard saves are shown. Mounting this widget inside a card
/// in the fretboard screen gives it the correct glassmorphism styling.
class FretboardSavePanel extends ConsumerWidget {
  const FretboardSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SaveBrowserPanel(
      instrumentFilter: 'fretboard',
      captureSnapshot: () => _captureSnapshot(ref),
      onLoad: (snap) => _loadSnapshot(ref, snap),
    );
  }

  /// Builds a [FretboardSnapshot] from the current store state.
  FretboardSnapshot _captureSnapshot(WidgetRef ref) {
    final fretState = ref.read(fretboardProvider);
    final pendingChord = ref.read(pendingChordProvider);
    final pendingScale = ref.read(pendingScaleProvider);

    return FretboardSnapshot(
      tuning: fretState.currentTuning,
      numFrets: fretState.numFrets,
      capo: fretState.capo,
      selectedCells: List.of(fretState.selectedCells),
      selectedNotes: List.of(fretState.selectedNotes),
      viewMode: fretState.viewMode,
      pendingChord: pendingChord != null
          ? PendingChord(
              root: pendingChord.root,
              quality: pendingChord.quality,
              symbol: '${pendingChord.root}${pendingChord.quality}',
            )
          : null,
      pendingScale: pendingScale != null
          ? PendingScale(
              root: pendingScale.root,
              scaleName: pendingScale.scaleName,
            )
          : null,
    );
  }

  /// Restores fretboard state from a snapshot.
  void _loadSnapshot(WidgetRef ref, InstrumentSnapshot snap) {
    if (snap is! FretboardSnapshot) return;

    ref.read(fretboardProvider.notifier).loadSnapshot(snap);

    // Restore pending chord/scale and committed flags.
    if (snap.pendingChord != null) {
      ref.read(pendingChordProvider.notifier).state = (
        root: snap.pendingChord!.root,
        quality: snap.pendingChord!.quality,
      );
      ref.read(fretboardChordCommittedProvider.notifier).state = true;
    } else {
      ref.read(pendingChordProvider.notifier).state = null;
      ref.read(fretboardChordCommittedProvider.notifier).state = false;
    }

    if (snap.pendingScale != null) {
      ref.read(pendingScaleProvider.notifier).state = (
        root: snap.pendingScale!.root,
        scaleName: snap.pendingScale!.scaleName,
      );
    } else {
      ref.read(pendingScaleProvider.notifier).state = null;
    }

    // Scroll fretboard to the capo position.
    ref.read(scrollToFretProvider.notifier).state = snap.capo;
  }
}
