library;

import 'package:flutter/material.dart';

import '../../schema/rules/save_system_rules.dart' show isValidSaveName;
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';

enum HarmonySharedSaveEditChoice { updateAllPlacements, createStandaloneSave }

Future<HarmonySharedSaveEditChoice?> showHarmonySharedSaveEditChoice(
  BuildContext context, {
  required String saveName,
  required int placementCount,
}) => showDialog<HarmonySharedSaveEditChoice>(
  context: context,
  builder: (dialogContext) => MuzicianDialog(
    title: 'This chord is used in multiple places',
    content: Text(
      '“$saveName” is linked to $placementCount Harmony blocks. '
      'Update all placements, or create a standalone Save and leave the '
      'existing blocks unchanged.',
    ),
    actions: [
      MuzicianDialogButton(
        'Cancel',
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      MuzicianDialogButton(
        'Create standalone Save',
        buttonKey: const Key('createStandaloneHarmonySave'),
        onPressed: () => Navigator.of(
          dialogContext,
        ).pop(HarmonySharedSaveEditChoice.createStandaloneSave),
      ),
      MuzicianDialogButton(
        'Update all placements',
        buttonKey: const Key('updateAllHarmonyPlacements'),
        emphasis: MuzicianDialogEmphasis.primary,
        onPressed: () => Navigator.of(
          dialogContext,
        ).pop(HarmonySharedSaveEditChoice.updateAllPlacements),
      ),
    ],
  ),
);

Future<String?> showStandaloneHarmonySaveNameDialog(
  BuildContext context, {
  required String initialName,
}) => showDialog<String>(
  context: context,
  builder: (_) => _StandaloneHarmonySaveNameDialog(initialName: initialName),
);

class _StandaloneHarmonySaveNameDialog extends StatefulWidget {
  const _StandaloneHarmonySaveNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_StandaloneHarmonySaveNameDialog> createState() =>
      _StandaloneHarmonySaveNameDialogState();
}

class _StandaloneHarmonySaveNameDialogState
    extends State<_StandaloneHarmonySaveNameDialog> {
  late final TextEditingController _controller;
  late bool _isValid;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _isValid = isValidSaveName(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MuzicianDialog(
    title: 'Create standalone Save',
    content: TextField(
      key: const Key('standaloneHarmonySaveNameField'),
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: 'Save name'),
      onChanged: (value) => setState(() => _isValid = isValidSaveName(value)),
      onSubmitted: (_) {
        if (_isValid) Navigator.of(context).pop(_controller.text.trim());
      },
    ),
    actions: [
      MuzicianDialogButton(
        'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      MuzicianDialogButton(
        'Create Save',
        buttonKey: const Key('confirmStandaloneHarmonySave'),
        emphasis: MuzicianDialogEmphasis.primary,
        onPressed: _isValid
            ? () => Navigator.of(context).pop(_controller.text.trim())
            : null,
      ),
    ],
  );
}

Widget harmonyLinkedSaveButton({
  required String saveName,
  required VoidCallback onPressed,
}) => Padding(
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
