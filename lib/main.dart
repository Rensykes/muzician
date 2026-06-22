import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/_mockup_shell.dart';
import 'features/fretboard/fretboard_feature.dart';
import 'features/instrument_shared/instrument_screen.dart';
import 'features/instrument_shared/shared_scale_picker.dart';
import 'ui/core/app_info_panel.dart';
import 'features/piano/piano_feature.dart';
import 'features/piano_roll/piano_roll_screen_v2.dart';
import 'features/song/song_screen.dart';
import 'features/songwriter/songwriter_feature.dart';
import 'models/fretboard.dart' show FretboardInputMode, FretboardViewMode;
import 'models/piano.dart' show PianoViewMode;
import 'models/save_system.dart';
import 'utils/note_utils.dart' show chromaticNotes;
import 'store/app_bootstrap.dart';
import 'store/fretboard_store.dart';
import 'store/piano_store.dart';
import 'store/project_config_sync.dart';
import 'store/save_system_store.dart';
import 'store/settings_store.dart';
import 'ui/project_chip.dart';
import 'store/song_audio_player_sink.dart';
import 'store/song_audio_recorder_driver_impl.dart';
import 'store/song_audio_recorder_store.dart';
import 'store/song_playback_store.dart';
import 'theme/muzician_theme.dart';
import 'utils/note_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    ProviderScope(
      overrides: [
        songAudioRecorderDriverProvider.overrideWith(
          (ref) => RecordPackageDriver(),
        ),
        songAudioClipSinkProvider.overrideWith(
          (ref) => ref.watch(productionSongAudioClipSinkProvider),
        ),
      ],
      child: const MuzicianApp(),
    ),
  );
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
      await hydrateStores(ref.read);
      await NotePlayer.instance.init();
      // Mount the project config syncer (Provider body runs on first read).
      ref.read(projectConfigSyncProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          _FretboardScreen(), // index 0
          _PianoScreen(), // index 1
          PianoRollScreenV2(), // index 2
          SongScreen(), // index 3
          SongwriterScreen(), // index 4
          _SettingsScreen(), // index 5
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
                  icon: Icons.queue_music,
                  label: 'Song',
                  active: _tabIndex == 3,
                  onTap: () => _setTab(3),
                ),
                _NavTab(
                  icon: Icons.lyrics,
                  label: 'Writer',
                  active: _tabIndex == 4,
                  onTap: () => _setTab(4),
                ),
                _NavTab(
                  icon: Icons.settings,
                  label: 'Settings',
                  active: _tabIndex == 5,
                  onTap: () => _setTab(5),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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

  const _Card({required this.child});

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

class _FretboardScreen extends ConsumerStatefulWidget {
  const _FretboardScreen();

  @override
  ConsumerState<_FretboardScreen> createState() => _FretboardScreenState();
}

class _FretboardScreenState extends ConsumerState<_FretboardScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final activeScale = ref.watch(activeScaleProvider);
    final activeChord = ref.watch(activeChordProvider);
    final chordCommitted = ref.watch(fretboardChordCommittedProvider);
    final scaleInfo = _resolveScaleDockState(ref, activeScale);
    final chordOffKey = ref.watch(fretboardBinding.chordOffKey);

    return InstrumentScreen(
      binding: fretboardBinding,
      title: 'Fretboard',
      appBarChipLabel: null,
      appBarActions: [
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: ProjectChip(),
        ),
        IconBtn(
          icon: Icons.help_outline_rounded,
          onTap: () => showAppInfoPanel(context, initialTab: 0),
        ),
        IconBtn(
          icon: Icons.bookmark_border_rounded,
          onTap: () => showWidgetSheet(
            context: context,
            title: 'Saves',
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: FretboardSavePanel(),
            ),
          ),
        ),
        IconBtn(
          icon: Icons.tune_rounded,
          onTap: () => showWidgetSheet(
            context: context,
            title: 'Settings',
            child: _FretSettingsSheetContent(),
          ),
        ),
      ],
      modeSegment: ModeSegment<FretboardInputMode>(
        current: state.inputMode,
        onSelect: notifier.setInputMode,
        options: const [
          (FretboardInputMode.free, Icons.touch_app_rounded, 'Free'),
          (FretboardInputMode.chord, Icons.library_music_rounded, 'Chord'),
        ],
      ),
      board: const GlassFrame(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: GuitarFretboard(
          hideToolbar: true,
          palette: FretboardPalette.wood,
        ),
      ),
      boardHeight: fretboardBoardHeight,
      emptyTitle: 'Tap the fretboard to begin',
      emptySubtitle:
          'Selected notes turn into detected chords and scales here.',
      detectionKey: const ValueKey('fret-detect'),
      scaleHasValue: scaleInfo.hasValue,
      scaleLabel: scaleInfo.label,
      scaleOffKey: chordOffKey,
      chordHasValue: activeChord != null || chordCommitted,
      onScalePanelRequested: () => showWidgetSheet(
        context: context,
        title: 'Scale',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SharedScalePicker(binding: fretboardBinding),
        ),
      ),
      onChordPanelRequested: () => showWidgetSheet(
        context: context,
        title: 'Chord voicings',
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ChordVoicingPicker(),
        ),
      ),
    );
  }
}

// ── Fret Settings Sheet Content ─────────────────────────────────────────────

class _FretSettingsSheetContent extends ConsumerWidget {
  const _FretSettingsSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final hasFilters =
        state.selectedCells.isNotEmpty ||
        state.highlightedNotes.isNotEmpty ||
        state.focusedNotes.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFilters) ...[
            ClearAllButton(
              onClear: () {
                HapticFeedback.mediumImpact();
                notifier.clearSelectedNotes();
                notifier.setHighlightedNotes([]);
                ref.read(activeScaleProvider.notifier).state = null;
                ref.read(activeChordProvider.notifier).state = null;
                ref.read(fretboardChordCommittedProvider.notifier).state =
                    false;
                Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: 16),
          ],
          const _TuneSectionLabel('View mode'),
          ModeSegment<FretboardViewMode>(
            current: state.viewMode,
            onSelect: notifier.setViewMode,
            options: const [
              (FretboardViewMode.exact, Icons.visibility_rounded, 'Exact'),
              (
                FretboardViewMode.exactFocus,
                Icons.center_focus_strong_rounded,
                'Solo',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _TuneSectionLabel('Tuning'),
          const TuningSelector(),
          const SizedBox(height: 16),
          const _TuneSectionLabel('Capo'),
          const CapoControl(),
        ],
      ),
    );
  }
}

// ── Tune Section Label ──────────────────────────────────────────────────────

class _TuneSectionLabel extends StatelessWidget {
  final String label;
  const _TuneSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: MuzicianTheme.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Piano Screen ────────────────────────────────────────────────────────────

class _PianoScreen extends ConsumerStatefulWidget {
  const _PianoScreen();

  @override
  ConsumerState<_PianoScreen> createState() => _PianoScreenState();
}

class _PianoScreenState extends ConsumerState<_PianoScreen> {
  @override
  Widget build(BuildContext context) {
    final activeScale = ref.watch(pianoActiveScaleProvider);
    final activeChord = ref.watch(pianoActiveChordProvider);
    final chordCommitted = ref.watch(pianoChordCommittedProvider);
    final scaleInfo = _resolveScaleDockState(ref, activeScale);
    final chordOffKey = ref.watch(pianoBinding.chordOffKey);

    return InstrumentScreen(
      binding: pianoBinding,
      title: 'Piano',
      appBarChipLabel: null,
      appBarActions: [
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: ProjectChip(),
        ),
        IconBtn(
          icon: Icons.help_outline_rounded,
          onTap: () => showAppInfoPanel(context, initialTab: 1),
        ),
        IconBtn(
          icon: Icons.bookmark_border_rounded,
          onTap: () => showWidgetSheet(
            context: context,
            title: 'Saves',
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: PianoSavePanel(),
            ),
          ),
        ),
        IconBtn(
          icon: Icons.tune_rounded,
          onTap: () => showWidgetSheet(
            context: context,
            title: 'Settings',
            child: _PianoSettingsSheetContent(),
          ),
        ),
      ],
      board: const GlassFrame(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: PianoKeyboard(hideToolbar: true),
      ),
      boardHeight: pianoKeyboardHeight,
      emptyTitle: 'Tap the keyboard to begin',
      emptySubtitle:
          'Selected notes turn into detected chords and scales here.',
      detectionKey: const ValueKey('piano-detect'),
      scaleHasValue: scaleInfo.hasValue,
      scaleLabel: scaleInfo.label,
      scaleOffKey: chordOffKey,
      chordHasValue: activeChord != null || chordCommitted,
      onScalePanelRequested: () => showWidgetSheet(
        context: context,
        title: 'Scale',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SharedScalePicker(binding: pianoBinding),
        ),
      ),
      onChordPanelRequested: () => showWidgetSheet(
        context: context,
        title: 'Chords',
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: PianoChordPicker(),
        ),
      ),
    );
  }
}

// ── Piano Settings Sheet Content ────────────────────────────────────────────

class _PianoSettingsSheetContent extends ConsumerWidget {
  const _PianoSettingsSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final hasFilters =
        state.selectedKeys.isNotEmpty ||
        state.highlightedNotes.isNotEmpty ||
        state.focusedNotes.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFilters) ...[
            ClearAllButton(
              onClear: () {
                HapticFeedback.mediumImpact();
                notifier.clearSelectedNotes();
                notifier.setHighlightedNotes([]);
                ref.read(pianoActiveScaleProvider.notifier).state = null;
                ref.read(pianoActiveChordProvider.notifier).state = null;
                ref.read(pianoChordCommittedProvider.notifier).state = false;
                Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: 16),
          ],
          const _TuneSectionLabel('View mode'),
          ModeSegment<PianoViewMode>(
            current: state.viewMode,
            onSelect: notifier.setViewMode,
            options: const [
              (PianoViewMode.exact, Icons.visibility_rounded, 'Exact'),
              (
                PianoViewMode.exactFocus,
                Icons.center_focus_strong_rounded,
                'Solo',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _TuneSectionLabel('Range'),
          const PianoRangeSelector(),
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
                  Text('🔊', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Note Preview Volume',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.volume_mute,
                    size: 16,
                    color: MuzicianTheme.textMuted,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: MuzicianTheme.sky,
                        inactiveTrackColor: MuzicianTheme.sky.withValues(
                          alpha: 0.15,
                        ),
                        thumbColor: MuzicianTheme.sky,
                        overlayColor: MuzicianTheme.sky.withValues(alpha: 0.12),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        value: settings.noteVolume,
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: (v) => notifier.setNoteVolume(v),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.volume_up,
                    size: 16,
                    color: MuzicianTheme.textMuted,
                  ),
                ],
              ),
              Text(
                '${(settings.noteVolume * 100).round()} %',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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

/// Combines the user-set active scale (`activeScale*Provider`) and the active
/// project's locked key into the dock-tab label + accent state.
///
/// Priority: project key wins when a project is active and has a key set;
/// otherwise the user-set active scale; otherwise the default "Scale" label
/// with no accent.
({bool hasValue, String label}) _resolveScaleDockState(
  WidgetRef ref,
  ({String root, String scaleName})? activeScale,
) {
  final project = ref.watch(selectedProjectProvider);
  if (project != null && project.kind == SaveFolderKind.project) {
    final cfg = project.projectConfig;
    if (cfg?.keyRootPc != null && cfg!.keyScaleName != null) {
      final root = chromaticNotes[cfg.keyRootPc!];
      return (hasValue: true, label: '$root ${cfg.keyScaleName}');
    }
  }
  if (activeScale != null) {
    return (
      hasValue: true,
      label: '${activeScale.root} ${activeScale.scaleName}',
    );
  }
  return (hasValue: false, label: 'Scale');
}
