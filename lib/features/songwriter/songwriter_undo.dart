import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// Shows a glass-styled undo overlay with a dismiss button.
/// Auto-dismisses after 4 seconds or on tap of Undo / X.
void showUndoSnack(BuildContext context, String message, VoidCallback onUndo) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _UndoBar(
      message: message,
      onUndo: onUndo,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 4), () {
    if (entry.mounted) entry.remove();
  });
}

class _UndoBar extends StatelessWidget {
  const _UndoBar({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: MuzicianTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MuzicianTheme.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                onUndo();
                onDismiss();
              },
              child: const Text(
                'Undo',
                style: TextStyle(
                  color: MuzicianTheme.sky,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDismiss,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: MuzicianTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UndoOverlay extends StatefulWidget {
  const _UndoOverlay({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  State<_UndoOverlay> createState() => _UndoOverlayState();
}

class _UndoOverlayState extends State<_UndoOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: MuzicianTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MuzicianTheme.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  widget.onUndo();
                  _dismiss();
                },
                child: const Text(
                  'Undo',
                  style: TextStyle(
                    color: MuzicianTheme.sky,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _dismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: MuzicianTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
