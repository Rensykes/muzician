/// ProgressionSaveButton – saves current progression into the save tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/muzician_theme.dart';

class ProgressionSaveButton extends StatefulWidget {
  final void Function(String progressionName) onSaveToFolder;
  final List<String>? savedPath;
  final bool isDirty;
  final VoidCallback? onUpdate;

  const ProgressionSaveButton({
    super.key,
    required this.onSaveToFolder,
    this.savedPath,
    this.isDirty = false,
    this.onUpdate,
  });

  @override
  State<ProgressionSaveButton> createState() => _ProgressionSaveButtonState();
}

class _ProgressionSaveButtonState extends State<ProgressionSaveButton> {
  bool _showForm = false;
  final _controller = TextEditingController();

  bool get _isSaved =>
      widget.savedPath != null && widget.savedPath!.isNotEmpty;

  void _handleSave() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for the progression.')),
      );
      return;
    }
    widget.onSaveToFolder(trimmed);
    setState(() {
      _showForm = false;
      _controller.clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isSaved) _buildSavedRow() else _buildSaveButton(),
        if (_showForm) _buildNameForm(),
      ],
    );
  }

  Widget _buildSavedRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: MuzicianTheme.teal.withValues(alpha: 0.06),
              border: Border.all(
                  color: MuzicianTheme.teal.withValues(alpha: 0.2), width: 0.5),
            ),
            child: Row(
              children: [
                const Text('📁', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.savedPath!.join(' › '),
                    style: const TextStyle(
                      color: MuzicianTheme.teal,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ActionButton(
          label: widget.isDirty ? '↺ Update' : '✓ Saved',
          enabled: widget.isDirty,
          onTap: widget.onUpdate,
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: _ActionButton(
        label: '📁 Save to Library',
        enabled: true,
        onTap: () => setState(() => _showForm = true),
      ),
    );
  }

  Widget _buildNameForm() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.8),
        border: Border.all(
            color: MuzicianTheme.teal.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROGRESSION NAME',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 60,
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'e.g. Rainy Day Outro',
                    hintStyle: TextStyle(color: MuzicianTheme.textMuted),
                    counterText: '',
                    isDense: true,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(
                          color: MuzicianTheme.teal.withValues(alpha: 0.4)),
                    ),
                  ),
                  onSubmitted: (_) => _handleSave(),
                ),
              ),
              const SizedBox(width: 8),
              _ActionButton(label: 'Save', enabled: true, onTap: _handleSave),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                onPressed: () => setState(() {
                  _showForm = false;
                  _controller.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Enter a name, then pick the folder to save into.',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionButton({required this.label, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap?.call();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: enabled
              ? MuzicianTheme.teal.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: enabled
                ? MuzicianTheme.teal.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? MuzicianTheme.teal : MuzicianTheme.textDim,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
