/// PianoSavePanel – save/load panel for the Piano screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/piano_store.dart';
import '../../ui/save_browser_panel.dart';

/// A panel that lets the user save and load piano snapshots.
///
/// Only piano saves are shown. Mounting this widget inside a card
/// in the piano screen gives it the correct glassmorphism styling.
class PianoSavePanel extends ConsumerWidget {
  const PianoSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SaveBrowserPanel(
      instrumentFilter: 'piano',
      captureSnapshot: () => _captureSnapshot(ref),
      onLoad: (snap) => _loadSnapshot(ref, snap),
    );
  }

  /// Builds a [PianoSnapshot] from the current store state.
  PianoSnapshot _captureSnapshot(WidgetRef ref) {
    final pianoState = ref.read(pianoProvider);
    final pendingChord = ref.read(pianoPendingChordProvider);
    final pendingScale = ref.read(pianoPendingScaleProvider);

    return PianoSnapshot(
      currentRange: pianoState.currentRange,
      selectedKeys: List.of(pianoState.selectedKeys),
      selectedNotes: List.of(pianoState.selectedNotes),
      viewMode: pianoState.viewMode,
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

  /// Restores piano state from a snapshot.
  void _loadSnapshot(WidgetRef ref, InstrumentSnapshot snap) {
    if (snap is! PianoSnapshot) return;

    ref.read(pianoProvider.notifier).loadSnapshot(snap);

    // Restore pending chord/scale and committed flags.
    if (snap.pendingChord != null) {
      ref.read(pianoPendingChordProvider.notifier).state = (
        root: snap.pendingChord!.root,
        quality: snap.pendingChord!.quality,
      );
      ref.read(pianoChordCommittedProvider.notifier).state = true;
    } else {
      ref.read(pianoPendingChordProvider.notifier).state = null;
      ref.read(pianoChordCommittedProvider.notifier).state = false;
    }

    if (snap.pendingScale != null) {
      ref.read(pianoPendingScaleProvider.notifier).state = (
        root: snap.pendingScale!.root,
        scaleName: snap.pendingScale!.scaleName,
      );
    } else {
      ref.read(pianoPendingScaleProvider.notifier).state = null;
    }

    // Scroll piano to make the first selected key visible.
    if (snap.selectedKeys.isNotEmpty) {
      ref.read(pianoScrollToMidiProvider.notifier).state =
          snap.selectedKeys.first.midiNote;
    }
  }
}
