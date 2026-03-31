import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/fretboard/fretboard_feature.dart';
import 'features/piano/piano_feature.dart';
import 'features/piano_roll/piano_roll_feature.dart';
import 'models/fretboard.dart' show TuningName;
import 'models/piano.dart' show PianoRangeName;
import 'store/fretboard_store.dart';
import 'store/piano_store.dart';
import 'store/piano_roll_store.dart';
import 'store/save_system_store.dart';
import 'store/settings_store.dart';
import 'theme/muzician_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: MuzicianApp()));
}

class MuzicianApp extends StatelessWidget {
  const MuzicianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muzician',
      debugShowCheckedModeBanner: false,
      theme: MuzicianTheme.dark(),
      home: const _AppShell(),
    );
  }
}

// ── App Shell with bottom navigation ────────────────────────────────────────

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(saveSystemProvider.notifier).hydrate();
      await ref.read(settingsProvider.notifier).hydrate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          _FretboardScreen(),
          _PianoScreen(),
          _PianoRollScreen(),
          _SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: MuzicianTheme.surface.withValues(alpha: 0.96),
          border: const Border(
            top: BorderSide(color: Color(0x4094A3B8), width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavTab(
                  icon: Icons.music_note,
                  label: 'Fretboard',
                  active: _tabIndex == 0,
                  onTap: () => _setTab(0),
                ),
                _NavTab(
                  icon: Icons.piano,
                  label: 'Piano',
                  active: _tabIndex == 1,
                  onTap: () => _setTab(1),
                ),
                _NavTab(
                  icon: Icons.view_timeline,
                  label: 'Roll',
                  active: _tabIndex == 2,
                  onTap: () => _setTab(2),
                ),
                _NavTab(
                  icon: Icons.settings,
                  label: 'Settings',
                  active: _tabIndex == 3,
                  onTap: () => _setTab(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setTab(int index) {
    if (index != _tabIndex) {
      HapticFeedback.selectionClick();
      setState(() => _tabIndex = index);
    }
  }
}

// ── Nav Tab ─────────────────────────────────────────────────────────────────

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: active ? MuzicianTheme.sky : MuzicianTheme.textMuted,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: active ? MuzicianTheme.sky : MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Screen Wrappers ─────────────────────────────────────────────────────────

class _GradientScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _GradientScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
          stops: [0, 0.3, 0.7, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 16, bottom: 100),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: MuzicianTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: MuzicianTheme.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

// ── Fretboard Screen ────────────────────────────────────────────────────────

enum _FretPanel { tuning, capo, chord, scale, saves }

class _FretboardScreen extends ConsumerStatefulWidget {
  const _FretboardScreen();

  @override
  ConsumerState<_FretboardScreen> createState() => _FretboardScreenState();
}

class _FretboardScreenState extends ConsumerState<_FretboardScreen> {
  _FretPanel? _activePanel;

  void _togglePanel(_FretPanel panel) {
    HapticFeedback.selectionClick();
    setState(() => _activePanel = _activePanel == panel ? null : panel);
  }

  Widget _activePanelWidget() => switch (_activePanel) {
    _FretPanel.tuning => const _Card(child: TuningSelector()),
    _FretPanel.capo => const _Card(child: CapoControl()),
    _FretPanel.chord => const _Card(
      key: ValueKey('fret-chord'),
      child: ChordVoicingPicker(),
    ),
    _FretPanel.scale => const _Card(
      key: ValueKey('fret-scale'),
      child: ScalePicker(),
    ),
    _FretPanel.saves => const _Card(
      key: ValueKey('fret-saves'),
      child: FretboardSavePanel(),
    ),
    null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);

    return _GradientScaffold(
      title: 'Fretboard',
      subtitle: state.selectedNotes.isEmpty
          ? 'Tap notes to select them'
          : '${state.selectedNotes.length} note${state.selectedNotes.length != 1 ? 's' : ''} selected',
      children: [
        const _Card(child: GuitarFretboard()),
        AnimatedSwitcher(
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
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
          child: state.selectedNotes.isNotEmpty
              ? _Card(
                  key: const ValueKey('fret-detect'),
                  child: NoteDetectionPanel(
                    onChordPanelRequested: () =>
                        setState(() => _activePanel = _FretPanel.chord),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('fret-detect-empty')),
        ),
        _PanelAccessBar(activePanel: _activePanel, onToggle: _togglePanel),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _activePanelWidget(),
        ),
      ],
    );
  }
}

// ── Fretboard Panel Access Bar ───────────────────────────────────────────────

class _PanelAccessBar extends ConsumerWidget {
  final _FretPanel? activePanel;
  final void Function(_FretPanel) onToggle;

  const _PanelAccessBar({required this.activePanel, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final chordCommitted = ref.watch(fretboardChordCommittedProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          _PanelTab(
            icon: Icons.tune,
            label: 'Tuning',
            color: MuzicianTheme.sky,
            active: activePanel == _FretPanel.tuning,
            hasValue: state.currentTuning != TuningName.standard,
            onTap: () => onToggle(_FretPanel.tuning),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.compress,
            label: 'Capo',
            color: MuzicianTheme.orange,
            active: activePanel == _FretPanel.capo,
            hasValue: state.capo > 0,
            onTap: () => onToggle(_FretPanel.capo),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.library_music_outlined,
            label: 'Chord',
            color: MuzicianTheme.violet,
            active: activePanel == _FretPanel.chord,
            hasValue: chordCommitted,
            onTap: () => onToggle(_FretPanel.chord),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.stacked_line_chart,
            label: 'Scale',
            color: MuzicianTheme.emerald,
            active: activePanel == _FretPanel.scale,
            hasValue: state.highlightedNotes.isNotEmpty,
            onTap: () => onToggle(_FretPanel.scale),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.save_outlined,
            label: 'Saves',
            color: MuzicianTheme.teal,
            active: activePanel == _FretPanel.saves,
            hasValue: false,
            onTap: () => onToggle(_FretPanel.saves),
          ),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final bool hasValue;
  final VoidCallback onTap;

  const _PanelTab({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showDot = hasValue && !active;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.15)
                : hasValue
                ? color.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.4)
                  : hasValue
                  ? color.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: active
                        ? color
                        : hasValue
                        ? color.withValues(alpha: 0.7)
                        : MuzicianTheme.textMuted,
                  ),
                  if (showDot)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? color
                      : hasValue
                      ? color.withValues(alpha: 0.7)
                      : MuzicianTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Piano Screen ────────────────────────────────────────────────────────────

enum _PianoPanel { range, chord, scale, saves }

class _PianoScreen extends ConsumerStatefulWidget {
  const _PianoScreen();

  @override
  ConsumerState<_PianoScreen> createState() => _PianoScreenState();
}

class _PianoScreenState extends ConsumerState<_PianoScreen> {
  _PianoPanel? _activePanel;

  void _togglePanel(_PianoPanel panel) {
    HapticFeedback.selectionClick();
    setState(() => _activePanel = _activePanel == panel ? null : panel);
  }

  Widget _activePanelWidget() => switch (_activePanel) {
    _PianoPanel.range => const _Card(child: PianoRangeSelector()),
    _PianoPanel.chord => const _Card(
      key: ValueKey('piano-chord'),
      child: PianoChordPicker(),
    ),
    _PianoPanel.scale => const _Card(
      key: ValueKey('piano-scale'),
      child: PianoScalePicker(),
    ),
    _PianoPanel.saves => const _Card(
      key: ValueKey('piano-saves'),
      child: PianoSavePanel(),
    ),
    null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);

    return _GradientScaffold(
      title: 'Piano',
      subtitle: state.selectedNotes.isEmpty
          ? 'Tap keys to select them'
          : '${state.selectedNotes.length} note${state.selectedNotes.length != 1 ? 's' : ''} selected',
      children: [
        const _Card(child: PianoKeyboard()),
        AnimatedSwitcher(
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
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
          child: state.selectedNotes.isNotEmpty
              ? _Card(
                  key: const ValueKey('piano-detect'),
                  child: PianoNoteDetectionPanel(
                    onChordPanelRequested: () =>
                        setState(() => _activePanel = _PianoPanel.chord),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('piano-detect-empty')),
        ),
        _PianoPanelAccessBar(activePanel: _activePanel, onToggle: _togglePanel),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _activePanelWidget(),
        ),
      ],
    );
  }
}

// ── Piano Panel Access Bar ───────────────────────────────────────────────────

class _PianoPanelAccessBar extends ConsumerWidget {
  final _PianoPanel? activePanel;
  final void Function(_PianoPanel) onToggle;

  const _PianoPanelAccessBar({
    required this.activePanel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoProvider);
    final chordCommitted = ref.watch(pianoChordCommittedProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          _PanelTab(
            icon: Icons.piano_outlined,
            label: 'Range',
            color: MuzicianTheme.sky,
            active: activePanel == _PianoPanel.range,
            hasValue: state.currentRange != PianoRangeName.key88,
            onTap: () => onToggle(_PianoPanel.range),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.library_music_outlined,
            label: 'Chord',
            color: MuzicianTheme.violet,
            active: activePanel == _PianoPanel.chord,
            hasValue: chordCommitted,
            onTap: () => onToggle(_PianoPanel.chord),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.stacked_line_chart,
            label: 'Scale',
            color: MuzicianTheme.emerald,
            active: activePanel == _PianoPanel.scale,
            hasValue: state.highlightedNotes.isNotEmpty,
            onTap: () => onToggle(_PianoPanel.scale),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.save_outlined,
            label: 'Saves',
            color: MuzicianTheme.teal,
            active: activePanel == _PianoPanel.saves,
            hasValue: false,
            onTap: () => onToggle(_PianoPanel.saves),
          ),
        ],
      ),
    );
  }
}

// ── Piano Roll Screen ───────────────────────────────────────────────────────

enum _PianoRollPanel { playback, edit, pitch, scale }

class _PianoRollScreen extends ConsumerStatefulWidget {
  const _PianoRollScreen();

  @override
  ConsumerState<_PianoRollScreen> createState() => _PianoRollScreenState();
}

class _PianoRollScreenState extends ConsumerState<_PianoRollScreen> {
  _PianoRollPanel? _activePanel;

  void _togglePanel(_PianoRollPanel panel) {
    HapticFeedback.selectionClick();
    setState(() => _activePanel = _activePanel == panel ? null : panel);
  }

  Widget _activePanelWidget() => switch (_activePanel) {
    _PianoRollPanel.playback => const _Card(
      key: ValueKey('pr-playback'),
      child: PianoRollPlaybackConfig(),
    ),
    _PianoRollPanel.edit => const _Card(
      key: ValueKey('pr-edit'),
      child: PianoRollEditConfig(),
    ),
    _PianoRollPanel.pitch => const _Card(
      key: ValueKey('pr-pitch'),
      child: PianoRollPitchConfig(),
    ),
    _PianoRollPanel.scale => const _Card(
      key: ValueKey('pr-scale'),
      child: PianoRollScalePicker(),
    ),
    null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoRollProvider);

    return _GradientScaffold(
      title: 'Piano Roll',
      subtitle: 'Build quantized note stacks by beat and time signature',
      children: [
        // ── Tab pickers ──
        _PianoRollPanelAccessBar(
          activePanel: _activePanel,
          onToggle: _togglePanel,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _activePanelWidget(),
        ),
        // ── Grid ──
        _Card(
          // GestureDetector claims vertical + horizontal pan in the gesture
          // arena so the parent ListView never steals touch events from the grid.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {},
            onHorizontalDragStart: (_) {},
            child: SizedBox(height: 320, child: PianoRollGrid()),
          ),
        ),
        // ── Config cards ──
        // ── Panels ──
        _Card(child: PianoRollStackSelector()),
        _Card(child: PianoRollSaveStackLoader()),
        _Card(child: PianoRollDetectionPanel()),
        if (state.selectedColumnTick != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              'Selected stack column: tick ${state.selectedColumnTick! + 1}',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Piano Roll Panel Access Bar ──────────────────────────────────────────────

class _PianoRollPanelAccessBar extends ConsumerWidget {
  final _PianoRollPanel? activePanel;
  final void Function(_PianoRollPanel) onToggle;

  const _PianoRollPanelAccessBar({
    required this.activePanel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          _PanelTab(
            icon: Icons.music_note_outlined,
            label: 'Playback',
            color: MuzicianTheme.sky,
            active: activePanel == _PianoRollPanel.playback,
            hasValue: false,
            onTap: () => onToggle(_PianoRollPanel.playback),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: MuzicianTheme.violet,
            active: activePanel == _PianoRollPanel.edit,
            hasValue: false,
            onTap: () => onToggle(_PianoRollPanel.edit),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.piano_outlined,
            label: 'Pitch',
            color: MuzicianTheme.orange,
            active: activePanel == _PianoRollPanel.pitch,
            hasValue: false,
            onTap: () => onToggle(_PianoRollPanel.pitch),
          ),
          const SizedBox(width: 8),
          _PanelTab(
            icon: Icons.stacked_line_chart,
            label: 'Scale',
            color: MuzicianTheme.emerald,
            active: activePanel == _PianoRollPanel.scale,
            hasValue: state.highlightedNotes.isNotEmpty,
            onTap: () => onToggle(_PianoRollPanel.scale),
          ),
        ],
      ),
    );
  }
}

// ── Settings Screen ─────────────────────────────────────────────────────────

class _SettingsScreen extends ConsumerWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _GradientScaffold(
      title: 'Settings',
      subtitle: 'Personalise your experience',
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('🎵', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Scale Highlight',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => notifier.setSuppressOutOfKeyAlert(
                  !settings.suppressOutOfKeyAlert,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: settings.suppressOutOfKeyAlert
                            ? MuzicianTheme.sky.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: settings.suppressOutOfKeyAlert
                              ? MuzicianTheme.sky
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: settings.suppressOutOfKeyAlert
                          ? const Icon(
                              Icons.check,
                              size: 12,
                              color: MuzicianTheme.sky,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Skip out-of-key warning',
                        style: TextStyle(
                          color: MuzicianTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'When enabled, adding a note outside the highlighted scale clears the highlight silently.',
                style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Text(
                'Muzician',
                style: TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Settings are saved automatically',
                style: TextStyle(
                  color: MuzicianTheme.textMuted.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
