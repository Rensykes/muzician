import 'package:flutter/material.dart';
import '../../ui/core/muzician_dialog.dart';

enum WriterSaveAction { overwrite, saveAsNew }

class WriterSaveChoice {
  final WriterSaveAction action;
  final bool dontAskAgain;
  const WriterSaveChoice(this.action, this.dontAskAgain);
}

/// Prompts whether to overwrite the bound save or create a new one. Returns
/// null on cancel.
Future<WriterSaveChoice?> showWriterSaveChoiceDialog(
  BuildContext context, {
  required String saveName,
}) =>
    showDialog<WriterSaveChoice>(
      context: context,
      builder: (_) => _WriterSaveChoiceDialog(saveName: saveName),
    );

class _WriterSaveChoiceDialog extends StatefulWidget {
  const _WriterSaveChoiceDialog({required this.saveName});
  final String saveName;
  @override
  State<_WriterSaveChoiceDialog> createState() =>
      _WriterSaveChoiceDialogState();
}

class _WriterSaveChoiceDialogState extends State<_WriterSaveChoiceDialog> {
  bool _dontAsk = false;

  @override
  Widget build(BuildContext context) {
    return MuzicianDialog(
      title: "Save changes to '${widget.saveName}'?",
      content: MuzicianDialogCheckbox(
        checkboxKey: const Key('writerSaveAlwaysCheckbox'),
        value: _dontAsk,
        onChanged: (v) => setState(() => _dontAsk = v),
        label: 'Always overwrite for this project',
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        MuzicianDialogButton(
          'Save as new…',
          buttonKey: const Key('writerSaveAsNew'),
          onPressed: () => Navigator.pop(
            context,
            WriterSaveChoice(WriterSaveAction.saveAsNew, _dontAsk),
          ),
        ),
        MuzicianDialogButton(
          'Overwrite',
          buttonKey: const Key('writerSaveOverwrite'),
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.pop(
            context,
            WriterSaveChoice(WriterSaveAction.overwrite, _dontAsk),
          ),
        ),
      ],
    );
  }
}
