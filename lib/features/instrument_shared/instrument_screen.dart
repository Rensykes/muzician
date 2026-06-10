/// Shared scaffold for an instrument screen (app bar + board + detection + dock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
import 'instrument_binding.dart';
import 'shared_detection_panel.dart';

class InstrumentScreen extends ConsumerWidget {
  final InstrumentBinding binding;
  final String title;
  final String? appBarChipLabel;
  final List<Widget> appBarActions;

  /// Optional mode segment shown directly under the app bar (Fretboard only).
  final Widget? modeSegment;

  /// The instrument board, pinned to [boardHeight].
  final Widget board;
  final double boardHeight;

  final String emptyTitle;
  final String emptySubtitle;

  /// Opens the chord picker sheet (used by detection + dock Chord tab).
  final VoidCallback onChordPanelRequested;

  /// Opens the scale picker sheet (used by dock Scale tab).
  final VoidCallback onScalePanelRequested;

  final bool scaleHasValue;
  final bool chordHasValue;

  /// True when the active chord conflicts with the locked-in project key.
  /// Drives the warning overlay on the Scale dock tab.
  final bool scaleOffKey;

  /// Label shown on the Scale dock tab. Defaults to `'Scale'`. Callers pass
  /// the active key's name (e.g. `'C major'`) when a project key is set so
  /// the user sees the locked-in scale at a glance.
  final String scaleLabel;

  final ValueKey<String> detectionKey;

  const InstrumentScreen({
    super.key,
    required this.binding,
    required this.title,
    required this.appBarChipLabel,
    required this.appBarActions,
    required this.board,
    required this.boardHeight,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onChordPanelRequested,
    required this.onScalePanelRequested,
    required this.scaleHasValue,
    required this.chordHasValue,
    required this.detectionKey,
    this.scaleLabel = 'Scale',
    this.scaleOffKey = false,
    this.modeSegment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNotes = ref.watch(binding.selectedNotes);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CompactAppBar(
              title: title,
              chipLabel: appBarChipLabel,
              actions: appBarActions,
            ),
            ?modeSegment,
            SizedBox(height: boardHeight, child: board),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                reverseDuration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  ),
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, -0.08),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                ),
                child: selectedNotes.isNotEmpty
                    ? SharedDetectionPanel(
                        key: detectionKey,
                        binding: binding,
                        onChordPanelRequested: onChordPanelRequested,
                      )
                    : InstrumentInsightHint(
                        key: ValueKey('${detectionKey.value}-empty'),
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                      ),
              ),
            ),
            DockedToolbar(
              children: [
                DockTab(
                  icon: Icons.stacked_line_chart,
                  label: scaleLabel,
                  color: MuzicianTheme.emerald,
                  hasValue: scaleHasValue,
                  warning: scaleOffKey,
                  onTap: onScalePanelRequested,
                ),
                DockTab(
                  icon: Icons.library_music_outlined,
                  label: 'Chord',
                  color: MuzicianTheme.violet,
                  hasValue: chordHasValue,
                  onTap: onChordPanelRequested,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Insight Hint (empty state) ──────────────────────────────────────────────

/// Fills the space between an instrument and the docked toolbar before any
/// notes are tapped, so the area reads as intentional rather than empty.
class InstrumentInsightHint extends StatelessWidget {
  final String title;
  final String subtitle;
  const InstrumentInsightHint({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: MuzicianTheme.sky.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: MuzicianTheme.sky.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: const Icon(
              Icons.touch_app_rounded,
              color: MuzicianTheme.sky,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
