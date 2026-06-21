import 'package:flutter/material.dart';

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
    return AlertDialog(
      title: Text("Save changes to '${widget.saveName}'?"),
      content: CheckboxListTile(
        key: const Key('writerSaveAlwaysCheckbox'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _dontAsk,
        onChanged: (v) => setState(() => _dontAsk = v ?? false),
        title: const Text('Always overwrite for this project'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('writerSaveAsNew'),
          onPressed: () => Navigator.pop(
            context,
            WriterSaveChoice(WriterSaveAction.saveAsNew, _dontAsk),
          ),
          child: const Text('Save as new…'),
        ),
        FilledButton(
          key: const Key('writerSaveOverwrite'),
          onPressed: () => Navigator.pop(
            context,
            WriterSaveChoice(WriterSaveAction.overwrite, _dontAsk),
          ),
          child: const Text('Overwrite'),
        ),
      ],
    );
  }
}
