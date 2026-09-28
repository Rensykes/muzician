/// FretboardSavePanel – save/load panel for the Fretboard screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmony_lane_instrument.dart';
import '../../models/save_system.dart';
import '../../store/fretboard_store.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';
import '../../schema/rules/save_system_rules.dart';
import '../instrument_shared/harmony_save_edit_dialog.dart';
import '../instrument_shared/writer_handoff.dart';

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
        editTargetIsLinked && _fretboardSnapshotFor(editSave?.snapshot) != null
        ? editSave
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (linkedEditEntry != null) ...[
          harmonyLinkedSaveButton(
            saveName: linkedEditEntry.name,
            onPressed: () => _updateLinkedSave(
              context,
              linkedEditEntry,
              getWriterLinksForSave(
                saveState,
                selectedId,
                linkedEditEntry.id,
              ).length,
            ),
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
              _fretboardSnapshotFor(save.snapshot) != null &&
              (save.snapshot is HarmonyChordSnapshot
                  ? isFolderInProject(
                      saveState.folders,
                      save.folderId,
                      selectedId,
                    )
                  : save.folderId == selectedId),
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

  Future<void> _updateLinkedSave(
    BuildContext context,
    SaveEntry entry,
    int placementCount,
  ) async {
    final notifier = ref.read(songwriterProvider.notifier);
    if (entry.snapshot is HarmonyChordSnapshot && placementCount > 1) {
      final choice = await showHarmonySharedSaveEditChoice(
        context,
        saveName: entry.name,
        placementCount: placementCount,
      );
      if (choice == null || !context.mounted) return;
      if (choice == HarmonySharedSaveEditChoice.createStandaloneSave) {
        final suggestedName = '${entry.name} copy';
        final name = await showStandaloneHarmonySaveNameDialog(
          context,
          initialName: suggestedName.length <= 80
              ? suggestedName
              : suggestedName.substring(0, 80),
        );
        if (name == null || !context.mounted) return;
        final standaloneId = notifier.saveStandaloneHarmonyEdit(
          sourceSaveId: entry.id,
          name: name,
          snapshot: _captureSnapshot(ref),
        );
        if (standaloneId != null) {
          if (!mounted) return;
          setState(() {
            _linkedEditSaveId = null;
            _editTargetCleared = true;
          });
          widget.onDifferentSaveLoaded?.call(standaloneId);
        }
        _showEditResult(
          context,
          success: standaloneId != null,
          successMessage:
              'Created standalone Save “$name”. Writer chords are unchanged.',
          errorMessage: notifier.lastHarmonyMutationError,
        );
        return;
      }
    }

    final updated = notifier.updateLinkedInstrumentSave(
      saveId: entry.id,
      snapshot: _captureSnapshot(ref),
    );
    _showEditResult(
      context,
      success: updated,
      successMessage: 'Updated ${entry.name} in Writer.',
      errorMessage: notifier.lastHarmonyMutationError,
    );
  }

  void _showEditResult(
    BuildContext context, {
    required bool success,
    required String successMessage,
    String? errorMessage,
  }) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            success
                ? successMessage
                : errorMessage ??
                      'This linked Writer save is no longer available.',
          ),
        ),
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
    loadFretboardSnapshot(ref, snap);
  }
}

/// Loads all Fretboard and picker state from a canonical snapshot.
void loadFretboardSnapshot(WidgetRef ref, InstrumentSnapshot snapshot) {
  final fretboardSnapshot = _fretboardSnapshotFor(snapshot);
  if (fretboardSnapshot == null) return;

  ref.read(fretboardProvider.notifier).loadSnapshot(fretboardSnapshot);
  if (fretboardSnapshot.pendingChord != null) {
    ref.read(pendingChordProvider.notifier).state = (
      root: fretboardSnapshot.pendingChord!.root,
      quality: fretboardSnapshot.pendingChord!.quality,
    );
    ref.read(fretboardChordCommittedProvider.notifier).state = true;
  } else {
    ref.read(pendingChordProvider.notifier).state = null;
    ref.read(fretboardChordCommittedProvider.notifier).state = false;
  }

  if (fretboardSnapshot.pendingScale != null) {
    ref.read(pendingScaleProvider.notifier).state = (
      root: fretboardSnapshot.pendingScale!.root,
      scaleName: fretboardSnapshot.pendingScale!.scaleName,
    );
    ref.read(activeScaleProvider.notifier).state = (
      root: fretboardSnapshot.pendingScale!.root,
      scaleName: fretboardSnapshot.pendingScale!.scaleName,
    );
  } else {
    ref.read(pendingScaleProvider.notifier).state = null;
    ref.read(activeScaleProvider.notifier).state = null;
  }
  ref.read(scrollToFretProvider.notifier).state = fretboardSnapshot.capo;
}

FretboardSnapshot? _fretboardSnapshotFor(InstrumentSnapshot? snapshot) {
  if (snapshot is FretboardSnapshot) return snapshot;
  if (snapshot is HarmonyChordSnapshot &&
      snapshot.harmonyInstrument == HarmonyLaneInstrument.fretboard &&
      snapshot.instrumentState is FretboardSnapshot) {
    return snapshot.instrumentState as FretboardSnapshot;
  }
  return null;
}
