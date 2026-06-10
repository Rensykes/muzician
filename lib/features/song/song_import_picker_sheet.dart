/// SongImportPickerSheet — bottom-sheet that lets the user pick a Piano,
/// Fretboard, or PianoRoll save and drop it as an imported clip on a note
/// track.
///
/// Backend conversion lives in [songProjectProvider.notifier
/// .createImportedNotePatternClip]; this widget only handles UI + error
/// surface (overlap rejection → SnackBar).
library;

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/save_system.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/glass_snackbar.dart';
import '../../ui/save_tree_browser.dart';
import 'song_arranger_timeline.dart';

class SongImportPickerSheet extends ConsumerWidget {
  final String trackId;
  final String instrumentFilter;
  final int startTick;

  const SongImportPickerSheet({
    super.key,
    required this.trackId,
    required this.instrumentFilter,
    required this.startTick,
  });

  String get _title {
    switch (instrumentFilter) {
      case 'piano':
        return 'Import from Piano';
      case 'fretboard':
        return 'Import from Fretboard';
      case 'piano_roll':
        return 'Import from Piano Roll';
      default:
        return 'Import save';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(
                      Icons.close,
                      color: MuzicianTheme.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SaveTreeBrowser(
                instrumentFilter: instrumentFilter,
                emptyLabel:
                    'No matching saves yet.\nCreate one from the ${_instrumentName()} tab to import it here.',
                onLoad: (snap) => _handleImport(context, ref, snap),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _instrumentName() {
    switch (instrumentFilter) {
      case 'piano':
        return 'Piano';
      case 'fretboard':
        return 'Fretboard';
      case 'piano_roll':
        return 'Piano Roll';
      default:
        return 'related';
    }
  }

  void _handleImport(
    BuildContext context,
    WidgetRef ref,
    InstrumentSnapshot snap,
  ) {
    try {
      ref
          .read(songProjectProvider.notifier)
          .createImportedNotePatternClip(
            trackId: trackId,
            startTick: startTick,
            snapshot: snap,
          );
      Navigator.of(context).pop();
    } on StateError {
      showGlassSnackbar(
        context,
        title: 'Overlap',
        message:
            'Imported clip would overlap an existing one. Choose another spot.',
        contentType: ContentType.warning,
        duration: const Duration(seconds: 3),
      );
    }
  }
}

/// Registers SongImportPickerSheet with the arranger timeline so the
/// timeline does not need a direct import (avoids a layering cycle and lets
/// tests stub the picker).
void registerSongImportPicker() {
  SongImportPickerLauncher.register(({
    required BuildContext context,
    required String trackId,
    required String instrumentFilter,
    required int startTick,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => SongImportPickerSheet(
          trackId: trackId,
          instrumentFilter: instrumentFilter,
          startTick: startTick,
        ),
      ),
    );
  });
}
