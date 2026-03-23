import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/fretboard/fretboard_feature.dart';
import 'features/piano/piano_feature.dart';
import 'features/piano_roll/piano_roll_feature.dart';
import 'models/fretboard.dart' show FretboardViewMode;
import 'models/piano.dart' show PianoViewMode;
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
    // Hydrate persisted state on startup, then apply the favourite view modes.
    Future.microtask(() async {
      await ref.read(saveSystemProvider.notifier).hydrate();
      await ref.read(settingsProvider.notifier).hydrate();
      final settings = ref.read(settingsProvider);
      ref
          .read(fretboardProvider.notifier)
          .setViewMode(settings.fretboardFavouriteViewMode);
      ref
          .read(pianoProvider.notifier)
          .setViewMode(settings.pianoFavouriteViewMode);
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

class _FretboardScreen extends ConsumerWidget {
  const _FretboardScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);

    return _GradientScaffold(
      title: 'Fretboard',
      subtitle: state.selectedNotes.isEmpty
          ? 'Tap notes to select them'
          : '${state.selectedNotes.length} note${state.selectedNotes.length != 1 ? 's' : ''} selected',
      children: [
        _Card(child: TuningSelector()),
        _Card(child: CapoControl()),
        _Card(child: GuitarFretboard()),
        if (state.selectedNotes.isNotEmpty)
          _Card(
            key: const ValueKey('fret-detect'),
            child: NoteDetectionPanel(),
          ),
        _Card(key: const ValueKey('fret-chord'), child: ChordVoicingPicker()),
        _Card(key: const ValueKey('fret-scale'), child: ScalePicker()),
      ],
    );
  }
}

// ── Piano Screen ────────────────────────────────────────────────────────────

class _PianoScreen extends ConsumerWidget {
  const _PianoScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoProvider);

    return _GradientScaffold(
      title: 'Piano',
      subtitle: state.selectedNotes.isEmpty
          ? 'Tap keys to select them'
          : '${state.selectedNotes.length} note${state.selectedNotes.length != 1 ? 's' : ''} selected',
      children: [
        _Card(child: PianoRangeSelector()),
        _Card(child: PianoKeyboard()),
        if (state.selectedNotes.isNotEmpty)
          _Card(
            key: const ValueKey('piano-detect'),
            child: PianoNoteDetectionPanel(),
          ),
        _Card(key: const ValueKey('piano-chord'), child: PianoChordPicker()),
        _Card(key: const ValueKey('piano-scale'), child: PianoScalePicker()),
      ],
    );
  }
}

// ── Piano Roll Screen ───────────────────────────────────────────────────────

class _PianoRollScreen extends ConsumerWidget {
  const _PianoRollScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);

    return _GradientScaffold(
      title: 'Piano Roll',
      subtitle: 'Build quantized note stacks by beat and time signature',
      children: [
        _Card(child: PianoRollToolbar()),
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
                  Text('🎸', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Fretboard',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Favourite View Mode',
                style: TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _ViewModeGrid(
                current: settings.fretboardFavouriteViewMode.name,
                onSelect: (mode) => notifier.setFretboardFavouriteViewMode(
                  FretboardViewMode.values.firstWhere(
                    (v) => v.name == mode,
                    orElse: () => FretboardViewMode.pitchClass,
                  ),
                ),
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('🎹', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Piano',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Favourite View Mode',
                style: TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _ViewModeGrid(
                current: settings.pianoFavouriteViewMode.name,
                onSelect: (mode) => notifier.setPianoFavouriteViewMode(
                  PianoViewMode.values.firstWhere(
                    (v) => v.name == mode,
                    orElse: () => PianoViewMode.pitchClass,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _ViewModeGrid extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;

  const _ViewModeGrid({required this.current, required this.onSelect});

  static const _modes = [
    ('pitchClass', 'All', 'All occurrences'),
    ('exact', 'Exact', 'Tapped positions only'),
    ('focus', 'Focus', 'Hide unselected'),
    ('exactFocus', 'Solo', 'Exact positions only'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _modes.map((m) {
        final active = current == m.$1;
        return GestureDetector(
          onTap: () {
            onSelect(m.$1);
            HapticFeedback.lightImpact();
          },
          child: Container(
            width: (MediaQuery.of(context).size.width - 80) / 2,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active
                  ? MuzicianTheme.sky.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.03),
              border: Border.all(
                color: active
                    ? MuzicianTheme.sky.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      m.$2,
                      style: TextStyle(
                        color: active
                            ? MuzicianTheme.sky
                            : MuzicianTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (active)
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: MuzicianTheme.sky,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  m.$3,
                  style: TextStyle(
                    color: active
                        ? MuzicianTheme.sky.withValues(alpha: 0.6)
                        : MuzicianTheme.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
