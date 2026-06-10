/// Modal shown when the user attempts to add a note outside the active
/// project's key. The project's config is locked, so the user must either:
///   - switch the active selection to Dump and proceed (note will be added
///     in an unrestricted context), or
///   - cancel and stay inside the project (note is not added).
library;

import 'package:flutter/material.dart';
import '../../theme/muzician_theme.dart';

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
    return AlertDialog(
      backgroundColor: const Color(0xFF141826),
      title: const Text(
        'Note outside project key',
        style: TextStyle(
          color: MuzicianTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"$noteName" is not in $keyLabel.',
            style: const TextStyle(color: MuzicianTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Project "$projectName" is locked to its key. Switch to Dump to '
            'experiment with notes outside the key, or stay in the project.',
            style: const TextStyle(color: MuzicianTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ProjectOffScaleDecision.cancel),
          child: const Text(
            'Stay in project',
            style: TextStyle(color: MuzicianTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ProjectOffScaleDecision.switchToDump),
          child: const Text(
            'Switch to Dump',
            style: TextStyle(color: MuzicianTheme.orange),
          ),
        ),
      ],
    );
  }
}
