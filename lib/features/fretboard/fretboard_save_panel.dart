/// FretboardSavePanel – save/load panel for the Fretboard screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/fretboard_store.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';
import '../../schema/rules/save_system_rules.dart';
import '../instrument_shared/writer_handoff.dart';
import '../../theme/muzician_theme.dart';

/// A panel that lets the user save and load fretboard snapshots.
///
/// Only fretboard saves are shown. Mounting this widget inside a card
/// in the fretboard screen gives it the correct glassmorphism styling.
class FretboardSavePanel extends ConsumerStatefulWidget {
  const FretboardSavePanel({
    super.key,
    this.linkedEditSaveId,
    this.onDifferentSaveLoaded,
    this.onHandoffCompleted,
  });

  final String? linkedEditSaveId;
  final ValueChanged<String>? onDifferentSaveLoaded;
  final VoidCallback? onHandoffCompleted;

  @override
  ConsumerState<FretboardSavePanel> createState() => _FretboardSavePanelState();
}

class _FretboardSavePanelState extends ConsumerState<FretboardSavePanel> {
  String? _linkedEditSaveId;
  String? _linkedEditProjectId;
  bool _editTargetCleared = false;

  @override
  void initState() {
    super.initState();
    _linkedEditSaveId = widget.linkedEditSaveId;
    _linkedEditProjectId = ref.read(saveSystemProvider).selectedProjectId;
  }

  @override
  void didUpdateWidget(covariant FretboardSavePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.linkedEditSaveId != oldWidget.linkedEditSaveId) {
      _linkedEditSaveId = widget.linkedEditSaveId;
      _linkedEditProjectId = ref.read(saveSystemProvider).selectedProjectId;
      _editTargetCleared = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveState = ref.watch(saveSystemProvider);
    ref.listen<String?>(
      saveSystemProvider.select((state) => state.selectedProjectId),
      (previous, next) {
        if (_linkedEditSaveId != null && _linkedEditProjectId != next) {
          setState(() {
            _linkedEditSaveId = null;
            _editTargetCleared = true;
          });
        }
      },
    );
    final selectedId = saveState.selectedProjectId;
    final selectedRoot = selectedId == null
        ? null
        : saveState.folders
              .where((folder) => folder.id == selectedId)
              .firstOrNull;
    final selectedProjectRoot =
        selectedRoot != null && isProjectRoot(selectedRoot);
    if (selectedId == null) {
      return const ProjectRequiredPlaceholder(
        message: 'Pick a project (or Dump)\nto save and load fretboard shapes.',
      );
    }
    final editTargetSaveId = _linkedEditSaveId;
    if (editTargetSaveId != null) {
      ref.listen<bool>(
        saveSystemProvider.select(
          (state) => getWriterLinksForSave(
            state,
            selectedId,
            editTargetSaveId,
          ).isNotEmpty,
        ),
        (previous, hasWriterLink) {
          if (!hasWriterLink && _linkedEditSaveId == editTargetSaveId) {
            setState(() {
              _linkedEditSaveId = null;
              _editTargetCleared = true;
            });
          }
        },
      );
    }
    final editSave = _editTargetCleared || _linkedEditSaveId == null
        ? null
        : resolveSaveInProject(saveState, selectedId, _linkedEditSaveId!);
    final editTargetIsLinked =
        _linkedEditSaveId != null &&
        getWriterLinksForSave(
          saveState,
          selectedId,
          _linkedEditSaveId!,
        ).isNotEmpty;
    final linkedEditEntry =
        editTargetIsLinked && editSave?.snapshot is FretboardSnapshot
        ? editSave
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (linkedEditEntry != null) ...[
          _UpdateLinkedSaveButton(
            saveName: linkedEditEntry.name,
            onPressed: () {
              final updated = ref
                  .read(songwriterProvider.notifier)
                  .updateLinkedInstrumentSave(
                    saveId: linkedEditEntry.id,
                    snapshot: _captureSnapshot(ref),
                  );
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      updated
                          ? 'Updated ${linkedEditEntry.name} in Writer.'
                          : 'This linked Writer save is no longer available.',
                    ),
                  ),
                );
            },
          ),
          const SizedBox(height: 8),
        ],
        SaveBrowserPanel(
          rootFolderId: selectedId,
          instrumentFilter: 'fretboard',
          onRenameLinkedSave: (saveId, name) => ref
              .read(songwriterProvider.notifier)
              .renameLinkedSave(saveId: saveId, name: name),
          captureSnapshot: () => _captureSnapshot(ref),
          onLoad: (snap) => _loadSnapshot(ref, snap),
          onLoadSaveId: _onSaveLoaded,
          canUseInWriter: (save) =>
              selectedProjectRoot &&
              save.folderId == selectedId &&
              save.snapshot is FretboardSnapshot,
          onUseInWriter: (save) => startWriterHandoff(
            context: context,
            ref: ref,
            binding: fretboardBinding,
            chordResults: const [],
            onTransferComplete: () {
              if (widget.onHandoffCompleted == null) return;
              Navigator.of(context).maybePop();
              widget.onHandoffCompleted!();
            },
            reuseSave: save,
          ),
        ),
      ],
    );
  }

  void _onSaveLoaded(String saveId) {
    if (_linkedEditSaveId != null && saveId != _linkedEditSaveId) {
      setState(() {
        _linkedEditSaveId = null;
        _editTargetCleared = true;
      });
    }
    widget.onDifferentSaveLoaded?.call(saveId);
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
    loadFretboardSnapshot(ref, snap);
  }
}

/// Loads all Fretboard and picker state from a canonical snapshot.
void loadFretboardSnapshot(WidgetRef ref, InstrumentSnapshot snapshot) {
  if (snapshot is! FretboardSnapshot) return;

  ref.read(fretboardProvider.notifier).loadSnapshot(snapshot);
  if (snapshot.pendingChord != null) {
    ref.read(pendingChordProvider.notifier).state = (
      root: snapshot.pendingChord!.root,
      quality: snapshot.pendingChord!.quality,
    );
    ref.read(fretboardChordCommittedProvider.notifier).state = true;
  } else {
    ref.read(pendingChordProvider.notifier).state = null;
    ref.read(fretboardChordCommittedProvider.notifier).state = false;
  }

  if (snapshot.pendingScale != null) {
    ref.read(pendingScaleProvider.notifier).state = (
      root: snapshot.pendingScale!.root,
      scaleName: snapshot.pendingScale!.scaleName,
    );
    ref.read(activeScaleProvider.notifier).state = (
      root: snapshot.pendingScale!.root,
      scaleName: snapshot.pendingScale!.scaleName,
    );
  } else {
    ref.read(pendingScaleProvider.notifier).state = null;
    ref.read(activeScaleProvider.notifier).state = null;
  }
  ref.read(scrollToFretProvider.notifier).state = snapshot.capo;
}

class _UpdateLinkedSaveButton extends StatelessWidget {
  const _UpdateLinkedSaveButton({
    required this.saveName,
    required this.onPressed,
  });

  final String saveName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Semantics(
      button: true,
      label: 'Update linked save $saveName',
      child: OutlinedButton.icon(
        key: const Key('updateLinkedSaveButton'),
        onPressed: onPressed,
        icon: const Icon(Icons.sync),
        label: Text('Update linked save · $saveName'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: MuzicianTheme.sky,
        ),
      ),
    ),
  );
}
