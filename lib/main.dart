import 'dart:async';

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
import 'features/save_system/data_recovery_panel.dart';
import 'models/fretboard.dart' show FretboardInputMode, FretboardViewMode;
import 'models/harmony_lane_instrument.dart';
import 'models/piano.dart' show PianoViewMode;
import 'models/save_system.dart';
import 'utils/note_utils.dart'
    show NoteSpelling, chromaticNotes, formatRootChoiceLabel;
import 'store/app_bootstrap.dart';
import 'store/persisted_data_recovery_store.dart';
import 'store/fretboard_store.dart';
import 'store/piano_store.dart';
import 'store/project_config_sync.dart';
import 'store/save_system_store.dart';
import 'schema/rules/fretboard_rules.dart' show tunings;
import 'schema/rules/piano_rules.dart' show pianoRanges;
import 'schema/rules/save_system_rules.dart'
    show getWriterLinksForSave, resolveSaveInProject;
import 'store/settings_store.dart';
import 'ui/project_chip.dart';
import 'store/record_audio_session.dart';
import 'store/song_audio_player_sink.dart';
import 'store/song_audio_recorder_driver_impl.dart';
import 'store/song_audio_recorder_store.dart';
import 'store/song_playback_store.dart';
import 'store/songwriter_audio_sink.dart';
import 'theme/studio_theme.dart';
import 'models/app_theme_variant.dart';
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
        songwriterAudioClipSinkProvider.overrideWith(
          (ref) => ref.watch(productionSongwriterAudioClipSinkProvider),
        ),
        recordAudioSessionProvider.overrideWithValue(
          const AudioPlayersRecordAudioSession(),
        ),
      ],
      child: const MuzicianApp(),
    ),
  );
}

class MuzicianApp extends ConsumerWidget {
  const MuzicianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(settingsProvider.select((s) => s.themeVariant));
    return StudioThemeSource(
      variant: variant,
      child: MaterialApp(
        title: 'Muzician',
        debugShowCheckedModeBanner: false,
        theme: StudioTheme.data(variant),
        home: const _AppShell(),
      ),
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
  int _tabIndex = 4;
  String? _linkedEditSaveId;
  String? _linkedEditProjectId;
  bool _hydrating = true;
  StartupRecoveryRequired? _recoveryRequired;
  StartupStorageFailure? _startupFailure;

  @override
  void initState() {
    super.initState();
    Future.microtask(_hydrateAndOpen);
  }

  Future<void> _hydrateAndOpen() async {
    if (!mounted) return;
    setState(() {
      _hydrating = true;
      _recoveryRequired = null;
      _startupFailure = null;
    });
    try {
      await hydrateStores(ref.read);
      await ref.read(dataRecoveryProvider.notifier).hydrate();
    } on StartupRecoveryRequired catch (recovery) {
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _recoveryRequired = recovery;
      });
      return;
    } on StartupStorageFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _startupFailure = failure;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _startupFailure = StartupStorageFailure(
          'Could not load saved workspaces. Try again.',
          error,
        );
      });
      return;
    }

    // Audio preview is optional and can take longer than workspace hydration.
    unawaited(NotePlayer.instance.init().catchError((_) {}));
    try {
      // Mount the project config syncer after all persisted stores are ready.
      ref.read(projectConfigSyncProvider);
    } catch (_) {
      // A sync issue should not keep already hydrated workspaces inaccessible.
    }
    if (!mounted) return;
    setState(() {
      _tabIndex = contentWorkspaceTabForPreference(
        ref.read(settingsProvider).lastContentWorkspace,
      );
      _hydrating = false;
    });
  }

  Future<void> _startFreshFromRecovery() async {
    final recovery = _recoveryRequired;
    if (recovery == null) return;
    setState(() {
      _hydrating = true;
      _recoveryRequired = null;
      _startupFailure = null;
    });
    try {
      await ref
          .read(dataRecoveryProvider.notifier)
          .preserveAndClear(recovery.payloads);
    } on StartupStorageFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _startupFailure = failure;
      });
      return;
    }
    await _hydrateAndOpen();
  }

  @override
  Widget build(BuildContext context) {
    final selectedProjectId = ref.watch(
      saveSystemProvider.select((state) => state.selectedProjectId),
    );
    ref.listen<String?>(
      saveSystemProvider.select((state) => state.selectedProjectId),
      (previous, next) {
        if (_linkedEditSaveId != null && _linkedEditProjectId != next) {
          _clearLinkedEditTarget();
        }
      },
    );
    final linkedEditSaveId = _linkedEditSaveId;
    final linkedEditProjectId = _linkedEditProjectId;
    if (linkedEditSaveId != null && linkedEditProjectId != null) {
      ref.listen<bool>(
        saveSystemProvider.select(
          (state) =>
              state.selectedProjectId == linkedEditProjectId &&
              getWriterLinksForSave(
                state,
                linkedEditProjectId,
                linkedEditSaveId,
              ).isNotEmpty,
        ),
        (previous, hasWriterLink) {
          if (!hasWriterLink &&
              _linkedEditSaveId == linkedEditSaveId &&
              _linkedEditProjectId == linkedEditProjectId) {
            _clearLinkedEditTarget();
          }
        },
      );
    }
    return Scaffold(
      body: _hydrating || _recoveryRequired != null || _startupFailure != null
          ? _buildStartupView()
          : IndexedStack(
              index: _tabIndex,
              children: [
                _FretboardScreen(
                  onHandoffCompleted: () => _setTab(4),
                  linkedEditSaveId: _linkedEditProjectId == selectedProjectId
                      ? _linkedEditSaveId
                      : null,
                  onDifferentSaveLoaded: _onInstrumentSaveLoaded,
                ),
                _PianoScreen(
                  onHandoffCompleted: () => _setTab(4),
                  linkedEditSaveId: _linkedEditProjectId == selectedProjectId
                      ? _linkedEditSaveId
                      : null,
                  onDifferentSaveLoaded: _onInstrumentSaveLoaded,
                ),
                const PianoRollScreenV2(),
                const StudioRouteTheme(isStudio: false, child: SongScreen()),
                SongwriterScreen(
                  onEditInstrumentSave: _openLinkedSaveInInstrument,
                ),
                const _SettingsScreen(key: ValueKey('settings_screen')),
              ],
            ),
      bottomNavigationBar:
          _hydrating || _recoveryRequired != null || _startupFailure != null
          ? null
          : Container(
              decoration: BoxDecoration(
                color: StudioPalette.of(
                  context,
                ).surface.withValues(alpha: 0.96),
                border: const Border(
                  top: BorderSide(color: Color(0x4094A3B8), width: 0.5),
                ),
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 56,
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
                        icon: Icons.bar_chart_rounded,
                        label: 'Roll',
                        active: _tabIndex == 2,
                        onTap: () => _setTab(2),
                      ),
                      _NavTab(
                        icon: Icons.article_outlined,
                        label: 'Song',
                        active: _tabIndex == 3,
                        onTap: () => _setTab(3),
                      ),
                      _NavTab(
                        icon: Icons.edit_outlined,
                        label: 'Writer',
                        active: _tabIndex == 4,
                        onTap: () => _setTab(4),
                      ),
                      _NavTab(
                        icon: Icons.settings_outlined,
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

  Widget _buildStartupView() {
    final recovery = _recoveryRequired;
    final failure = _startupFailure;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: StudioPalette.of(context).gradientColors,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: recovery != null
                  ? _StartupRecoveryPrompt(
                      payloads: recovery.payloads,
                      onRetry: _hydrateAndOpen,
                      onStartFresh: _startFreshFromRecovery,
                    )
                  : failure != null
                  ? _StartupFailurePrompt(
                      message: failure.message,
                      onRetry: _hydrateAndOpen,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          'Loading your workspaces…',
                          style: TextStyle(
                            color: StudioPalette.of(context).textPrimary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
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
      final workspace = contentWorkspacePreferenceForTab(index);
      if (workspace != null) {
        ref
            .read(settingsProvider.notifier)
            .setLastContentWorkspace(workspace)
            .catchError((_) {});
      }
    }
  }

  void _clearLinkedEditTarget() {
    if (_linkedEditSaveId == null && _linkedEditProjectId == null) return;
    setState(() {
      _linkedEditSaveId = null;
      _linkedEditProjectId = null;
    });
  }

  void _onInstrumentSaveLoaded(String saveId) {
    if (_linkedEditSaveId != null && saveId != _linkedEditSaveId) {
      _clearLinkedEditTarget();
    }
  }

  void _openLinkedSaveInInstrument(SaveEntry requested) {
    final saveState = ref.read(saveSystemProvider);
    final projectId = saveState.selectedProjectId;
    final canonical = projectId == null
        ? null
        : resolveSaveInProject(saveState, projectId, requested.id);
    if (projectId == null ||
        canonical == null ||
        getWriterLinksForSave(saveState, projectId, requested.id).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This linked Writer save is unavailable.'),
        ),
      );
      return;
    }

    final snapshot = canonical.snapshot is HarmonyChordSnapshot
        ? (canonical.snapshot as HarmonyChordSnapshot).instrumentState
        : canonical.snapshot;
    switch (snapshot) {
      case FretboardSnapshot():
        loadFretboardSnapshot(ref, snapshot);
        setState(() {
          _linkedEditSaveId = canonical.id;
          _linkedEditProjectId = projectId;
        });
        _setTab(0);
      case PianoSnapshot():
        loadPianoSnapshot(ref, snapshot);
        setState(() {
          _linkedEditSaveId = canonical.id;
          _linkedEditProjectId = projectId;
        });
        _setTab(1);
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This linked save cannot be edited in Fretboard or Piano.',
            ),
          ),
        );
    }
  }
}

class _StartupFailurePrompt extends StatelessWidget {
  const _StartupFailurePrompt({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.storage_rounded,
        color: StudioPalette.of(context).orange,
        size: 42,
      ),
      const SizedBox(height: 14),
      Text(
        'Could not load your workspaces',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: StudioPalette.of(context).textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: StudioPalette.of(context).textSecondary),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ],
  );
}

class _StartupRecoveryPrompt extends StatelessWidget {
  const _StartupRecoveryPrompt({
    required this.payloads,
    required this.onRetry,
    required this.onStartFresh,
  });

  final List<MalformedPersistedPayload> payloads;
  final VoidCallback onRetry;
  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.warning_amber_rounded,
        color: StudioPalette.of(context).orange,
        size: 42,
      ),
      const SizedBox(height: 14),
      Text(
        'Some saved data could not be read',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: StudioPalette.of(context).textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${payloads.length} saved item${payloads.length == 1 ? '' : 's'} need recovery. '
        'The original data is still intact.',
        textAlign: TextAlign.center,
        style: TextStyle(color: StudioPalette.of(context).textSecondary),
      ),
      const SizedBox(height: 18),
      for (final payload in payloads)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            payload.storageKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: StudioPalette.of(context).textMuted,
              fontSize: 12,
            ),
          ),
        ),
      const SizedBox(height: 18),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
          FilledButton.icon(
            onPressed: onStartFresh,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Start fresh'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Start fresh first copies the original data to Settings → Data Recovery.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: StudioPalette.of(context).textMuted,
          fontSize: 12,
        ),
      ),
    ],
  );
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
        key: ValueKey('nav_$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: active
                  ? StudioPalette.of(context).sky
                  : StudioPalette.of(context).textMuted,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active
                    ? StudioPalette.of(context).sky
                    : StudioPalette.of(context).textMuted,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: StudioPalette.of(context).gradientColors,
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
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: StudioPalette.of(context).textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: StudioPalette.of(context).textMuted,
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
        color: StudioPalette.of(context).glassBg,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

// ── Fretboard Screen ────────────────────────────────────────────────────────

class _FretboardScreen extends ConsumerStatefulWidget {
  const _FretboardScreen({
    required this.onHandoffCompleted,
    required this.linkedEditSaveId,
    required this.onDifferentSaveLoaded,
  });

  final VoidCallback onHandoffCompleted;
  final String? linkedEditSaveId;
  final ValueChanged<String> onDifferentSaveLoaded;

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
    final tuningLabel = formatTuningName(
      tunings[state.currentTuning]!,
      ref.watch(settingsProvider.select((s) => s.noteSpelling)),
    );

    return InstrumentScreen(
      binding: fretboardBinding,
      title: 'Fretboard',
      appBarChipLabel: null,
      projectContext: const ProjectChip(),
      voicingsBuilder: (_) => const ChordVoicingPicker(),
      setupBuilder: (_) =>
          const _FretSettingsSheetContent(closeAfterClear: false),
      onSaveRequested: () => showWidgetSheet(
        context: context,
        title: 'Idea library',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FretboardSavePanel(
            linkedEditSaveId: widget.linkedEditSaveId,
            onDifferentSaveLoaded: widget.onDifferentSaveLoaded,
            onHandoffCompleted: widget.onHandoffCompleted,
          ),
        ),
      ),
      instrumentContext:
          '$tuningLabel · ${state.capo == 0 ? 'Capo off' : 'Capo ${state.capo}'}',
      appBarActions: [
        IconBtn(
          icon: Icons.help_outline_rounded,
          onTap: () => showAppInfoPanel(context, initialTab: 0),
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
          palette: FretboardPalette.graphite,
        ),
      ),
      boardHeight: fretboardBoardHeight,
      emptyTitle: 'Tap the fretboard to begin',
      emptySubtitle:
          'Selected notes turn into detected chords and scales here.',
      detectionKey: const ValueKey('fret-detect'),
      onHandoffCompleted: widget.onHandoffCompleted,
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
  const _FretSettingsSheetContent({this.closeAfterClear = true});

  final bool closeAfterClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final hasFilters =
        state.selectedCells.isNotEmpty ||
        state.highlightedNotes.isNotEmpty ||
        state.focusedNotes.isNotEmpty;
    final studio = StudioPalette.of(context).isStudio;
    void clearSelections() {
      HapticFeedback.mediumImpact();
      notifier.clearSelectedNotes();
      notifier.setHighlightedNotes([]);
      ref.read(activeScaleProvider.notifier).state = null;
      ref.read(activeChordProvider.notifier).state = null;
      ref.read(fretboardChordCommittedProvider.notifier).state = false;
      if (closeAfterClear) Navigator.of(context).maybePop();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFilters && !studio) ...[
            ClearAllButton(onClear: clearSelections),
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
          SizedBox(height: studio ? 8 : 16),
          const _TuneSectionLabel('Tuning'),
          const TuningSelector(),
          SizedBox(height: studio ? 8 : 16),
          if (!studio) const _TuneSectionLabel('Capo'),
          const CapoControl(),
          if (hasFilters && studio) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('instrumentClearAllSelections'),
                onPressed: clearSelections,
                style: TextButton.styleFrom(
                  foregroundColor: StudioPalette.of(context).red,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear all selections'),
              ),
            ),
          ],
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
      padding: EdgeInsets.fromLTRB(
        4,
        StudioPalette.of(context).isStudio ? 4 : 8,
        4,
        6,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: StudioPalette.of(context).textMuted,
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
  const _PianoScreen({
    required this.onHandoffCompleted,
    required this.linkedEditSaveId,
    required this.onDifferentSaveLoaded,
  });

  final VoidCallback onHandoffCompleted;
  final String? linkedEditSaveId;
  final ValueChanged<String> onDifferentSaveLoaded;

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
      projectContext: const ProjectChip(),
      voicingsBuilder: (_) => const PianoChordPicker(),
      setupBuilder: (_) =>
          const _PianoSettingsSheetContent(closeAfterClear: false),
      onSaveRequested: () => showWidgetSheet(
        context: context,
        title: 'Idea library',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PianoSavePanel(
            linkedEditSaveId: widget.linkedEditSaveId,
            onDifferentSaveLoaded: widget.onDifferentSaveLoaded,
            onHandoffCompleted: widget.onHandoffCompleted,
          ),
        ),
      ),
      instrumentContext:
          '${pianoRanges[ref.watch(pianoProvider).currentRange]!.displayName} · Exact MIDI keys',
      appBarActions: [
        IconBtn(
          icon: Icons.help_outline_rounded,
          onTap: () => showAppInfoPanel(context, initialTab: 1),
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
      onHandoffCompleted: widget.onHandoffCompleted,
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
  const _PianoSettingsSheetContent({this.closeAfterClear = true});

  final bool closeAfterClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final hasFilters =
        state.selectedKeys.isNotEmpty ||
        state.highlightedNotes.isNotEmpty ||
        state.focusedNotes.isNotEmpty;
    final studio = StudioPalette.of(context).isStudio;
    void clearSelections() {
      HapticFeedback.mediumImpact();
      notifier.clearSelectedNotes();
      notifier.setHighlightedNotes([]);
      ref.read(pianoActiveScaleProvider.notifier).state = null;
      ref.read(pianoActiveChordProvider.notifier).state = null;
      ref.read(pianoChordCommittedProvider.notifier).state = false;
      if (closeAfterClear) Navigator.of(context).maybePop();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFilters && !studio) ...[
            ClearAllButton(onClear: clearSelections),
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
          SizedBox(height: studio ? 8 : 16),
          if (!studio) const _TuneSectionLabel('Range'),
          const PianoRangeSelector(),
          if (hasFilters && studio) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('instrumentClearAllSelections'),
                onPressed: clearSelections,
                style: TextButton.styleFrom(
                  foregroundColor: StudioPalette.of(context).red,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear all selections'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Settings Screen ─────────────────────────────────────────────────────────

class _SettingsScreen extends ConsumerWidget {
  const _SettingsScreen({super.key});

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
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final variant in AppThemeVariant.values)
                ListTile(
                  key: ValueKey('settings_theme_${variant.name}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    variant == AppThemeVariant.studio
                        ? 'Studio'
                        : 'Studio Muzician',
                  ),
                  subtitle: Text(
                    variant == AppThemeVariant.studio
                        ? 'Graphite surfaces with mint accents'
                        : 'Night surfaces with sky, teal and violet accents',
                  ),
                  trailing: Icon(
                    settings.themeVariant == variant
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: settings.themeVariant == variant
                        ? StudioPalette.of(context).sky
                        : StudioPalette.of(context).textMuted,
                  ),
                  selected: settings.themeVariant == variant,
                  onTap: () => notifier.setThemeVariant(variant),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const DataRecoveryPanel(),
        const SizedBox(height: 12),
        _Card(
          child: SwitchListTile.adaptive(
            key: const ValueKey('settings_note_spelling'),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.music_note,
              color: StudioPalette.of(context).sky,
            ),
            title: const Text('Prefer flat note names'),
            subtitle: const Text('Show Eb instead of D# in musical labels.'),
            value: settings.noteSpelling == NoteSpelling.flats,
            onChanged: (useFlats) => notifier.setNoteSpelling(
              useFlats ? NoteSpelling.flats : NoteSpelling.sharps,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.queue_music,
                    color: StudioPalette.of(context).sky,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Default Harmony instrument for new projects',
                      style: TextStyle(
                        color: StudioPalette.of(context).textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final instrument in HarmonyLaneInstrument.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    instrument == HarmonyLaneInstrument.fretboard
                        ? Icons.music_note
                        : Icons.piano,
                    color: StudioPalette.of(context).sky,
                  ),
                  title: Text(
                    instrument == HarmonyLaneInstrument.fretboard
                        ? 'Fretboard'
                        : 'Piano',
                  ),
                  trailing:
                      settings.defaultNewProjectHarmonyInstrument == instrument
                      ? Icon(
                          Icons.check_circle,
                          color: StudioPalette.of(context).sky,
                        )
                      : const Icon(Icons.circle_outlined),
                  onTap: () => notifier.setDefaultNewProjectHarmonyInstrument(
                    instrument,
                  ),
                ),
              Text(
                'This choice is copied to new projects. Existing projects keep their current instrument.',
                style: TextStyle(
                  color: StudioPalette.of(context).textMuted,
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
              Row(
                children: [
                  Text('🔊', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Note Preview Volume',
                    style: TextStyle(
                      color: StudioPalette.of(context).textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.volume_mute,
                    size: 16,
                    color: StudioPalette.of(context).textMuted,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: StudioPalette.of(context).sky,
                        inactiveTrackColor: StudioPalette.of(
                          context,
                        ).sky.withValues(alpha: 0.15),
                        thumbColor: StudioPalette.of(context).sky,
                        overlayColor: StudioPalette.of(
                          context,
                        ).sky.withValues(alpha: 0.12),
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
                  Icon(
                    Icons.volume_up,
                    size: 16,
                    color: StudioPalette.of(context).textMuted,
                  ),
                ],
              ),
              Text(
                '${(settings.noteVolume * 100).round()} %',
                style: TextStyle(
                  color: StudioPalette.of(context).textMuted,
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
              Row(
                children: [
                  Text('🎵', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Scale Highlight',
                    style: TextStyle(
                      color: StudioPalette.of(context).textSecondary,
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
                            ? StudioPalette.of(
                                context,
                              ).sky.withValues(alpha: 0.2)
                            : (StudioPalette.of(context).isStudio
                                  ? StudioPalette.of(context).glassBg
                                  : Colors.white.withValues(alpha: 0.04)),
                        border: Border.all(
                          color: settings.suppressOutOfKeyAlert
                              ? StudioPalette.of(context).sky
                              : StudioPalette.of(context).textMuted,
                          width: 1,
                        ),
                      ),
                      child: settings.suppressOutOfKeyAlert
                          ? Icon(
                              Icons.check,
                              size: 12,
                              color: StudioPalette.of(context).sky,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Skip out-of-key warning',
                        style: TextStyle(
                          color: StudioPalette.of(context).textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'When enabled, adding a note outside the highlighted scale clears the highlight silently.',
                style: TextStyle(
                  color: StudioPalette.of(context).textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Text(
                'Muzician',
                style: TextStyle(
                  color: StudioPalette.of(context).textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Settings are saved automatically',
                style: TextStyle(
                  color: StudioPalette.of(
                    context,
                  ).textMuted.withValues(alpha: 0.6),
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
  final spelling = ref.watch(
    settingsProvider.select((settings) => settings.noteSpelling),
  );
  if (project != null && project.kind == SaveFolderKind.project) {
    final cfg = project.projectConfig;
    if (cfg?.keyRootPc != null && cfg!.keyScaleName != null) {
      final root = chromaticNotes[cfg.keyRootPc!];
      return (
        hasValue: true,
        label:
            '${formatRootChoiceLabel(root, spelling: spelling)} ${cfg.keyScaleName}',
      );
    }
  }
  if (activeScale != null) {
    return (
      hasValue: true,
      label:
          '${formatRootChoiceLabel(activeScale.root, spelling: spelling)} ${activeScale.scaleName}',
    );
  }
  return (hasValue: false, label: 'Scale');
}
