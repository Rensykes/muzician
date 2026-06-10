import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

OverlayEntry? _activeEntry;
Timer? _activeTimer;

void _dismiss() {
  _activeTimer?.cancel();
  _activeTimer = null;
  _activeEntry?.remove();
  _activeEntry = null;
}

/// Shows a themed glass overlay toast with Undo + dismiss actions.
///
/// Uses [OverlayEntry] + [Timer] instead of [ScaffoldMessenger.showSnackBar]
/// so the auto-dismiss honors [Duration] even when
/// [MediaQueryData.accessibleNavigation] is on (which makes SnackBar wait
/// indefinitely for manual dismissal).
void showUndoSnack(BuildContext context, String message, VoidCallback onUndo) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _dismiss();

  final entry = OverlayEntry(
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      return Positioned(
        left: 16,
        right: 16,
        bottom: 16 + mq.padding.bottom,
        child: _UndoToast(
          message: message,
          onUndo: () {
            _dismiss();
            onUndo();
          },
          onDismiss: _dismiss,
        ),
      );
    },
  );
  _activeEntry = entry;
  overlay.insert(entry);
  _activeTimer = Timer(const Duration(seconds: 4), _dismiss);
}

class _UndoToast extends StatelessWidget {
  const _UndoToast({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        decoration: BoxDecoration(
          color: MuzicianTheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MuzicianTheme.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                foregroundColor: MuzicianTheme.sky,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Undo',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: MuzicianTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              splashRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}
