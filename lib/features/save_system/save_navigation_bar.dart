/// SaveNavigationBar – shown when a save session is active.
/// Displays breadcrumb, save name, prev/next arrows, and exit button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../schema/rules/save_system_rules.dart';
import '../../store/save_system_store.dart';
import '../../theme/muzician_theme.dart';

class SaveNavigationBar extends ConsumerWidget {
  final VoidCallback onOpenManager;
  final String instrument;
  final void Function(InstrumentSnapshot)? applySnapshot;
  final VoidCallback? onExitSession;

  const SaveNavigationBar({
    super.key,
    required this.onOpenManager,
    this.instrument = 'fretboard',
    this.applySnapshot,
    this.onExitSession,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sState = ref.watch(saveSystemProvider);
    final notifier = ref.read(saveSystemProvider.notifier);

    final activeSession = sState.activeSession;
    if (activeSession == null) return const SizedBox.shrink();

    final activeSave = sState.saves
        .where((s) => s.id == activeSession.saveId)
        .firstOrNull;
    if (activeSave == null) return const SizedBox.shrink();

    final adj = getAdjacentSaves(sState.saves, activeSession);
    final breadcrumb = buildFolderBreadcrumb(
      sState.folders,
      activeSession.folderId,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEB0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MuzicianTheme.sky.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // ← Prev
          _arrowBtn('‹', adj.prev != null, () {
            if (adj.prev == null || applySnapshot == null) return;
            HapticFeedback.lightImpact();
            notifier.navigatePrev(applySnapshot!);
          }),
          const SizedBox(width: 4),
          // Label area
          Expanded(
            child: GestureDetector(
              onTap: onOpenManager,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (breadcrumb.isNotEmpty)
                    Text(
                      breadcrumb.map((b) => b.name).join(' › '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          activeSave.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          notifier.setActiveSession(null);
                          onExitSession?.call();
                        },
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MuzicianTheme.red.withValues(alpha: 0.18),
                            border: Border.all(
                              color: MuzicianTheme.red.withValues(alpha: 0.35),
                              width: 0.5,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '✕',
                              style: TextStyle(
                                color: MuzicianTheme.red,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // → Next
          _arrowBtn('›', adj.next != null, () {
            if (adj.next == null || applySnapshot == null) return;
            HapticFeedback.lightImpact();
            notifier.navigateNext(applySnapshot!);
          }),
        ],
      ),
    );
  }

  Widget _arrowBtn(String label, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: enabled
              ? MuzicianTheme.sky.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(
            color: enabled
                ? MuzicianTheme.sky.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? MuzicianTheme.sky
                  : Colors.white.withValues(alpha: 0.18),
              fontSize: 24,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }
}
