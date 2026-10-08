/// Confirms a project's first key, a key change, or key removal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_config.dart';
import '../../models/save_system.dart';
import '../../schema/rules/save_system_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/settings_store.dart';
import '../../utils/note_utils.dart';
import 'muzician_dialog.dart';

/// Ask before changing the selected project's shared key, then apply it only
/// if the same project configuration is still active when the user confirms.
Future<bool> requestProjectKeyChange(
  BuildContext context,
  WidgetRef ref, {
  required int? keyRootPc,
  required String? keyScaleName,
  String? expectedProjectId,
  ProjectConfig? expectedConfig,
}) async {
  if ((keyRootPc == null) != (keyScaleName == null)) return false;

  final folder = ref.read(selectedProjectProvider);
  if (folder == null || folder.kind != SaveFolderKind.project) return false;
  final currentConfig = folder.projectConfig ?? const ProjectConfig();
  if (expectedProjectId != null && folder.id != expectedProjectId) return false;
  if (expectedConfig != null && !_sameConfig(currentConfig, expectedConfig)) {
    return false;
  }

  if (currentConfig.keyRootPc == keyRootPc &&
      currentConfig.keyScaleName == keyScaleName) {
    return true;
  }

  final saveState = ref.read(saveSystemProvider);
  final spelling = ref.read(settingsProvider).noteSpelling;
  final affectedSaves = getSavesInSubtree(
    saveState.folders,
    saveState.saves,
    folder.id,
  ).length;
  final confirmed = await UpdateProjectKeyDialog.ask(
    context,
    currentLabel: _keyLabel(
      currentConfig.keyRootPc,
      currentConfig.keyScaleName,
      spelling,
    ),
    newLabel: _keyLabel(keyRootPc, keyScaleName, spelling),
    affectedSaves: affectedSaves,
  );
  if (!context.mounted || !confirmed) return false;

  final latest = ref.read(selectedProjectProvider);
  if (latest == null ||
      latest.kind != SaveFolderKind.project ||
      latest.id != folder.id ||
      !_sameConfig(
        latest.projectConfig ?? const ProjectConfig(),
        currentConfig,
      )) {
    return false;
  }

  final nextConfig = keyRootPc == null
      ? currentConfig.copyWith(clearKey: true)
      : currentConfig.copyWith(
          keyRootPc: keyRootPc,
          keyScaleName: keyScaleName,
        );
  await ref
      .read(saveSystemProvider.notifier)
      .applyProjectConfig(folder.id, nextConfig, retrofit: true);
  if (!context.mounted) return false;
  final committedSelection = ref.read(selectedProjectProvider);
  return committedSelection?.id == folder.id &&
      committedSelection?.kind == SaveFolderKind.project &&
      _sameConfig(
        committedSelection?.projectConfig ?? const ProjectConfig(),
        nextConfig,
      );
}

String? _keyLabel(int? rootPc, String? scaleName, NoteSpelling spelling) {
  if (rootPc == null || scaleName == null || rootPc < 0 || rootPc >= 12) {
    return null;
  }
  return '${formatRootChoiceLabel(chromaticNotes[rootPc], spelling: spelling)} $scaleName';
}

bool _sameConfig(ProjectConfig a, ProjectConfig b) =>
    a.keyRootPc == b.keyRootPc &&
    a.keyScaleName == b.keyScaleName &&
    a.tempo == b.tempo &&
    a.beatsPerBar == b.beatsPerBar &&
    a.beatUnit == b.beatUnit &&
    a.defaultHarmonyInstrument == b.defaultHarmonyInstrument;

class UpdateProjectKeyDialog extends StatelessWidget {
  final String? currentLabel;
  final String? newLabel;
  final int affectedSaves;

  const UpdateProjectKeyDialog({
    super.key,
    required this.currentLabel,
    required this.newLabel,
    required this.affectedSaves,
  });

  static Future<bool> ask(
    BuildContext context, {
    required String? currentLabel,
    required String? newLabel,
    required int affectedSaves,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => UpdateProjectKeyDialog(
        currentLabel: currentLabel,
        newLabel: newLabel,
        affectedSaves: affectedSaves,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final clearing = newLabel == null;
    final title = clearing
        ? 'Clear project key?'
        : currentLabel == null
        ? 'Set project key?'
        : 'Update project key?';
    final prompt = clearing
        ? 'Remove the shared project key ($currentLabel)?'
        : currentLabel == null
        ? 'Set the shared project key to $newLabel?'
        : 'Change the shared project key from $currentLabel to $newLabel?';
    final detail = affectedSaves == 0
        ? 'No saves under this project yet. The key will apply to every instrument view going forward.'
        : clearing
        ? '$affectedSaves save${affectedSaves == 1 ? '' : 's'} under this project will no longer inherit a key. Saved notes stay unchanged.'
        : '$affectedSaves save${affectedSaves == 1 ? '' : 's'} under this project will inherit the new key. Notes stay at the same pitches; notes outside the scale will be flagged.';

    return MuzicianDialog(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prompt),
          const SizedBox(height: 10),
          Text(detail, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        MuzicianDialogButton(
          clearing
              ? 'Clear key'
              : currentLabel == null
              ? 'Set key'
              : 'Update',
          emphasis: clearing
              ? MuzicianDialogEmphasis.destructive
              : MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
