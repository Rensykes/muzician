/// Shared scaffold for an instrument screen (app bar + board + detection + dock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
import 'instrument_binding.dart';
import 'shared_detection_panel.dart';

const _appBarHeight = 44.0;
const _modeSegmentHeight = 60.0;
const _dockedToolbarHeight = 80.0;
const _compactDetectionViewportHeight = 160.0;
const _insightIconSize = 56.0;
const _insightIconSpacing = 14.0;
const _insightTitleSpacing = 4.0;
const _insightSubtitleHorizontalPadding = 48.0;
const _insightTitleStyle = TextStyle(
  color: MuzicianTheme.textSecondary,
  fontSize: 14,
  fontWeight: FontWeight.w700,
);
const _insightSubtitleStyle = TextStyle(
  color: MuzicianTheme.textMuted,
  fontSize: 12,
  height: 1.4,
);

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
  final VoidCallback? onHandoffCompleted;

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
    this.onHandoffCompleted,
    this.scaleLabel = 'Scale',
    this.scaleOffKey = false,
    this.modeSegment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNotes = ref.watch(binding.selectedNotes);
    final appBar = CompactAppBar(
      title: title,
      chipLabel: appBarChipLabel,
      actions: appBarActions,
    );
    final detection = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, -0.08),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      ),
      child: selectedNotes.isNotEmpty
          ? SharedDetectionPanel(
              key: detectionKey,
              binding: binding,
              onChordPanelRequested: onChordPanelRequested,
              onHandoffCompleted: onHandoffCompleted,
            )
          : InstrumentInsightHint(
              key: ValueKey('${detectionKey.value}-empty'),
              title: emptyTitle,
              subtitle: emptySubtitle,
            ),
    );
    final dock = DockedToolbar(
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
    );

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Text can wrap to several lines at large system scales. Reserve
            // its measured height so short screens route the hint through the
            // page scroll instead of overflowing the detection column.
            final hintHeight = InstrumentInsightHint._requiredHeight(
              context,
              maxWidth: constraints.maxWidth,
              title: emptyTitle,
              subtitle: emptySubtitle,
            );
            final minimumDetectionHeight =
                hintHeight > _compactDetectionViewportHeight
                ? hintHeight
                : _compactDetectionViewportHeight;
            final compactThreshold =
                _appBarHeight +
                (modeSegment == null ? 0 : _modeSegmentHeight) +
                boardHeight +
                minimumDetectionHeight +
                _dockedToolbarHeight;
            if (constraints.maxHeight >= compactThreshold) {
              return Column(
                children: [
                  appBar,
                  ?modeSegment,
                  SizedBox(height: boardHeight, child: board),
                  Expanded(child: detection),
                  dock,
                ],
              );
            }

            // Keep the instrument at its designed size in short windows. The
            // page scrolls above the fixed dock so every string/key and the
            // detection panel remain reachable without clipping gestures.
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        appBar,
                        ?modeSegment,
                        SizedBox(height: boardHeight, child: board),
                        SizedBox(
                          height: minimumDetectionHeight,
                          child: detection,
                        ),
                      ],
                    ),
                  ),
                ),
                dock,
              ],
            );
          },
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

  static double _requiredHeight(
    BuildContext context, {
    required double maxWidth,
    required String title,
    required String subtitle,
  }) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    double measureText(String text, TextStyle style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: defaultStyle.merge(style)),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final titleHeight = measureText(title, _insightTitleStyle, maxWidth);
    final subtitleWidth = (maxWidth - _insightSubtitleHorizontalPadding * 2)
        .clamp(0.0, double.infinity)
        .toDouble();
    final subtitleHeight = measureText(
      subtitle,
      _insightSubtitleStyle,
      subtitleWidth,
    );

    return _insightIconSize +
        _insightIconSpacing +
        titleHeight +
        _insightTitleSpacing +
        subtitleHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _insightIconSize,
            height: _insightIconSize,
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
          const SizedBox(height: _insightIconSpacing),
          Text(title, style: _insightTitleStyle),
          const SizedBox(height: _insightTitleSpacing),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _insightSubtitleHorizontalPadding,
            ),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: _insightSubtitleStyle,
            ),
          ),
        ],
      ),
    );
  }
}
