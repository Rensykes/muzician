/// Modal shown when the user attempts to add a note outside the active
/// project's key. The project's config is locked, so the user must either:
///   - switch the active selection to Dump and proceed (note will be added
///     in an unrestricted context), or
///   - cancel and stay inside the project (note is not added).
library;

import 'package:flutter/material.dart';
import '../../theme/muzician_theme.dart';
import 'muzician_dialog.dart';

enum ProjectOffScaleDecision { switchToDump, cancel }

class ProjectOffScaleDialog extends StatelessWidget {
  final String projectName;
  final String keyLabel;
  final String noteName;

  const ProjectOffScaleDialog({
    super.key,
    required this.projectName,
    required this.keyLabel,
    required this.noteName,
  });

  @override
  Widget build(BuildContext context) {
    return MuzicianDialog(
      title: 'Note outside project key',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"$noteName" is not in $keyLabel.',
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Project "$projectName" is locked to its key. Switch to Dump to '
            'experiment with notes outside the key, or stay in the project.',
          ),
        ],
      ),
      actions: [
        MuzicianDialogButton(
          'Stay in project',
          onPressed: () =>
              Navigator.of(context).pop(ProjectOffScaleDecision.cancel),
        ),
        MuzicianDialogButton(
          'Switch to Dump',
          emphasis: MuzicianDialogEmphasis.primary,
          color: MuzicianTheme.orange,
          onPressed: () =>
              Navigator.of(context).pop(ProjectOffScaleDecision.switchToDump),
        ),
      ],
    );
  }
}
