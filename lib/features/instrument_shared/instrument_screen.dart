/// Shared scaffold for an instrument screen (app bar + board + detection + dock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../theme/studio_theme.dart';
import '../../models/fretboard.dart';
import '../../models/save_system.dart';
import '../../schema/rules/songwriter_rules.dart'
    show isWriterEligibleNativeSelection;
import '../../store/settings_store.dart';
import '../../utils/note_utils.dart';
import '../../models/harmonic_analysis.dart';
import 'writer_handoff.dart';
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
  final Widget? projectContext;
  final WidgetBuilder? voicingsBuilder;
  final WidgetBuilder? setupBuilder;
  final VoidCallback? onSaveRequested;
  final String? instrumentContext;
  final String title;
  final String? appBarChipLabel;
  final List<Widget> appBarActions;

  /// Optional mode segment shown directly under the app bar (Fretboard only).
  final Widget? modeSegment;

  /// Compact Studio controls; legacy screens continue to use [modeSegment].
  final Widget? studioControls;

  /// Optional local audition controls, kept beside the playable canvas.
  final Widget? auditionControls;

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
    this.projectContext,
    this.voicingsBuilder,
    this.setupBuilder,
    this.onSaveRequested,
    this.instrumentContext,
    this.scaleLabel = 'Scale',
    this.scaleOffKey = false,
    this.modeSegment,
    this.studioControls,
    this.auditionControls,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (StudioPalette.of(context).isStudio) {
      return _StudioInstrumentWorkspace(screen: this);
    }
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

/// Studio owns presentation state only; instrument providers stay canonical.
class _StudioInstrumentWorkspace extends ConsumerStatefulWidget {
  const _StudioInstrumentWorkspace({required this.screen});
  final InstrumentScreen screen;

  @override
  ConsumerState<_StudioInstrumentWorkspace> createState() =>
      _StudioInstrumentWorkspaceState();
}

class _StudioInstrumentWorkspaceState
    extends ConsumerState<_StudioInstrumentWorkspace> {
  int _tab = 1;
  bool _expanded = true;
  final _canvasStateKey = GlobalKey();
  final _inspectorStateKey = GlobalKey();
  final _selectionStateKey = GlobalKey();

  void _showVoicings() => setState(() {
    _tab = 1;
    _expanded = true;
  });

  @override
  Widget build(BuildContext context) {
    final s = widget.screen;
    final p = StudioPalette.of(context);
    final notes = ref.watch(s.binding.selectedNotes);
    final header = WorkspaceHeader(
      title: s.title,
      chipLabel: s.appBarChipLabel,
      actions: [
        if (s.projectContext != null) s.projectContext!,
        ...s.appBarActions,
      ],
    );
    final compactHeader = CompactAppBar(
      title: s.title,
      chipLabel: s.appBarChipLabel,
      actions: [
        if (s.projectContext != null) s.projectContext!,
        ...s.appBarActions,
      ],
    );
    final canvas = KeyedSubtree(
      key: _canvasStateKey,
      child: SizedBox(
        key: const Key('studioInstrumentCanvas'),
        height: s.modeSegment == null ? 226 : 212,
        child: s.board,
      ),
    );
    final controls = s.studioControls ?? s.modeSegment;
    final selection = KeyedSubtree(
      key: _selectionStateKey,
      child: _StudioSelectionSummary(screen: s),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [?controls, canvas, ?s.auditionControls, selection],
    );

    Widget buildInspector({
      required bool shortLandscape,
      required bool tightHeight,
    }) {
      Widget buildPanel(int index, Widget child) => SingleChildScrollView(
        key: ValueKey(
          'instrumentInspector${const ['Notes', 'Voicings', 'Setup'][index]}Scroll',
        ),
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: ValueKey('instrumentPanelContent$index'),
              child: child,
            ),
          ],
        ),
      );

      return Container(
        key: const Key('instrumentInspector'),
        margin: tightHeight
            ? const EdgeInsets.symmetric(horizontal: 16)
            : const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: p.dialogBg,
          border: Border.all(color: p.glassBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shortLandscape && controls != null) controls,
            Row(
              children: [
                for (final (index, label) in const [
                  (0, 'Notes'),
                  (1, 'Voicings'),
                  (2, 'Setup'),
                ])
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _expanded && _tab == index
                                ? p.sky
                                : p.glassBorder,
                            width: _expanded && _tab == index ? 2 : 1,
                          ),
                        ),
                      ),
                      child: TextButton(
                        key: Key('instrumentInspector$label'),
                        style: TextButton.styleFrom(
                          foregroundColor: _tab == index
                              ? p.sky
                              : p.textSecondary,
                          shape: const RoundedRectangleBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(44, 44),
                        ),
                        onPressed: () => setState(() {
                          _tab = index;
                          _expanded = true;
                        }),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  key: const Key('instrumentInspectorToggle'),
                  tooltip: _expanded
                      ? 'Collapse inspector'
                      : 'Expand inspector',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Offstage(
                offstage: !_expanded,
                child: IndexedStack(
                  index: _tab,
                  children: [
                    buildPanel(
                      0,
                      notes.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Select notes on the instrument to inspect chords and compatible scales.',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            )
                          : SharedDetectionPanel(
                              key: s.detectionKey,
                              binding: s.binding,
                              onChordPanelRequested: _showVoicings,
                              embedded: true,
                            ),
                    ),
                    buildPanel(
                      1,
                      s.voicingsBuilder == null
                          ? TextButton(
                              onPressed: s.onChordPanelRequested,
                              child: const Text('Open chord voicings'),
                            )
                          : Builder(builder: s.voicingsBuilder!),
                    ),
                    buildPanel(
                      2,
                      s.setupBuilder == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Builder(builder: s.setupBuilder!),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: const Key('instrumentScale'),
                      onPressed: s.onScalePanelRequested,
                      icon: Icon(
                        s.scaleOffKey
                            ? Icons.warning_amber_rounded
                            : Icons.stacked_line_chart,
                        size: 18,
                        color: s.scaleOffKey ? p.orange : p.emerald,
                      ),
                      label: Text(
                        s.scaleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      key: const Key('instrumentLibrary'),
                      onPressed: s.onSaveRequested,
                      icon: const Icon(Icons.bookmarks_outlined, size: 18),
                      label: const Text(
                        'Library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('instrumentSetupShortcut'),
                    tooltip: s.instrumentContext ?? 'Instrument setup',
                    onPressed: () => setState(() {
                      _tab = 2;
                      _expanded = true;
                    }),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: p.gradientColors,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortLandscape =
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxHeight < 500;
            final wide =
                constraints.maxWidth >= 700 ||
                (shortLandscape && constraints.maxWidth >= 600);
            final textScale = MediaQuery.textScalerOf(context).scale(14);
            final inspector = KeyedSubtree(
              key: _inspectorStateKey,
              child: LayoutBuilder(
                builder: (context, panelConstraints) {
                  final collapsedHeight =
                      140.0 +
                      (textScale - 14).clamp(0, 28) * 4 +
                      (shortLandscape && controls != null ? 52 : 0);
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: _expanded
                          ? panelConstraints.maxHeight
                          : collapsedHeight.clamp(
                              0,
                              panelConstraints.maxHeight,
                            ),
                      child: buildInspector(
                        shortLandscape: shortLandscape,
                        tightHeight: !wide && constraints.maxHeight < 600,
                      ),
                    ),
                  );
                },
              ),
            );
            if (wide) {
              return Column(
                children: [
                  shortLandscape ? compactHeader : header,
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            key: const Key('studioInstrumentContentScroll'),
                            primary: false,
                            child: shortLandscape
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      canvas,
                                      ?s.auditionControls,
                                      selection,
                                    ],
                                  )
                                : content,
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth >= 1000 ? 360 : 316,
                          child: inspector,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            final shortAuditionLayout =
                s.auditionControls != null && constraints.maxHeight < 600;
            return Column(
              key: const Key('studioInstrumentCompactLayout'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                constraints.maxHeight < 600 ? compactHeader : header,
                ?controls,
                canvas,
                if (shortAuditionLayout)
                  Expanded(
                    child: SingleChildScrollView(
                      key: const Key('studioInstrumentLowerScroll'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ?s.auditionControls,
                          selection,
                          // Preserve a useful bounded inspector below the
                          // pinned instrument, even with large system text.
                          SizedBox(height: 280, child: inspector),
                        ],
                      ),
                    ),
                  )
                else ...[
                  ?s.auditionControls,
                  selection,
                  Expanded(child: inspector),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A compact, labelled choice without a full-width segmented control.
class InstrumentModeMenu<T> extends StatelessWidget {
  const InstrumentModeMenu({
    super.key,
    required this.label,
    required this.current,
    required this.options,
    required this.onSelect,
  });

  final String label;
  final T current;
  final List<(T value, String label, String description)> options;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    final selected = options.firstWhere((option) => option.$1 == current);
    return MenuAnchor(
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(MediaQuery.sizeOf(context).width - 24, double.infinity),
        ),
      ),
      menuChildren: [
        for (final option in options)
          Semantics(
            selected: option.$1 == current,
            child: MenuItemButton(
              key: ValueKey('$label-${option.$2}'),
              onPressed: () => onSelect(option.$1),
              trailingIcon: option.$1 == current
                  ? Icon(Icons.check_rounded, size: 18, color: palette.sky)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 112).clamp(0, 240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.$2),
                      Text(
                        option.$3,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: '$label: ${selected.$2}',
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: palette.textSecondary,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Semantics(
            label: '$label: ${selected.$2}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selected.$2),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _SelectionAction { save, writer }

class _StudioSelectionSummary extends ConsumerWidget {
  const _StudioSelectionSummary({required this.screen});
  final InstrumentScreen screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = StudioPalette.of(context);
    final notes = ref.watch(screen.binding.selectedNotes);
    final exact = ref.watch(screen.binding.exactNotes);
    final spelling = ref.watch(settingsProvider.select((s) => s.noteSpelling));
    final chords = notes.length >= 2
        ? detectChordResultsFromExactNotes(exact)
        : <ChordDetectionResult>[];
    final count = '${exact.length} ${exact.length == 1 ? 'note' : 'notes'}';
    final title = notes.isEmpty
        ? screen.emptyTitle
        : chords.isEmpty
        ? count
        : '${formatChordSymbol(chords.first, spelling: spelling)} · $count';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextButton(
        key: const Key('instrumentSelectionActions'),
        style: TextButton.styleFrom(
          foregroundColor: p.textSecondary,
          disabledForegroundColor: p.textMuted,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: notes.isEmpty
            ? null
            : () async {
                final action =
                    await showStudioModalBottomSheet<_SelectionAction>(
                      context: context,
                      isScrollControlled: true,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                      ),
                      builder: (_) => _StudioSelectionActions(screen: screen),
                    );
                if (!context.mounted) return;
                switch (action) {
                  case _SelectionAction.save:
                    screen.onSaveRequested?.call();
                  case _SelectionAction.writer:
                    if (screen.onHandoffCompleted == null) return;
                    await startWriterHandoff(
                      context: context,
                      ref: ref,
                      binding: screen.binding,
                      chordResults: detectChordResultsFromExactNotes(
                        ref.read(screen.binding.exactNotes),
                      ),
                      onTransferComplete: screen.onHandoffCompleted!,
                    );
                  case null:
                    break;
                }
              },
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                key: const Key('instrumentSelectionTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: notes.isEmpty ? p.textMuted : p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(width: 8),
              const Text('Actions'),
              const SizedBox(width: 4),
              const Icon(Icons.more_horiz_rounded, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudioSelectionActions extends ConsumerWidget {
  const _StudioSelectionActions({required this.screen});
  final InstrumentScreen screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = StudioPalette.of(context);
    final notes = ref.watch(screen.binding.selectedNotes);
    final exact = ref.watch(screen.binding.exactNotes);
    final spelling = ref.watch(settingsProvider.select((s) => s.noteSpelling));
    final eligibility = screen.binding.eligibilityState;
    if (eligibility != null) ref.watch(eligibility);
    final snapshot = screen.binding.captureSnapshot(ref);
    final eligible =
        exact.isNotEmpty && isWriterEligibleNativeSelection(snapshot);
    final chords = notes.length >= 2
        ? detectChordResultsFromExactNotes(exact)
        : <ChordDetectionResult>[];
    final title = chords.isEmpty
        ? 'Exact selection'
        : formatChordSymbol(chords.first, spelling: spelling);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('instrumentSelectionSheet'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Selection actions',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close selection actions',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              title,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              exact
                  .map(
                    (note) =>
                        formatMidiNoteLabel(note.midiNote, spelling: spelling),
                  )
                  .join(' · '),
              style: TextStyle(color: p.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('instrumentSaveIdea'),
                  onPressed: notes.isEmpty || screen.onSaveRequested == null
                      ? null
                      : () => Navigator.of(context).pop(_SelectionAction.save),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save idea'),
                ),
                FilledButton.icon(
                  key: const Key('addInstrumentSelectionToWriter'),
                  onPressed: eligible && screen.onHandoffCompleted != null
                      ? () => Navigator.of(context).pop(_SelectionAction.writer)
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add to Writer'),
                ),
              ],
            ),
            if (notes.isNotEmpty && !eligible && snapshot is FretboardSnapshot)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  snapshot.inputMode == FretboardInputMode.free
                      ? 'Switch to Chord mode and keep one note per string to add this selection to Writer.'
                      : 'Chord mode requires one valid note per string. Remove extra or invalid positions to add this selection to Writer.',
                  key: const Key('writerHandoffUnavailableReason'),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
