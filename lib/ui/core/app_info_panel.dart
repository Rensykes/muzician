/// Reusable help sheet that documents all gestures and features per instrument.
library;

import 'package:flutter/material.dart';

import '../../theme/studio_theme.dart';

// ── Public API ───────────────────────────────────────────────────────────────

/// Shows the app-wide gesture and feature guide as a modal bottom sheet.
///
/// [initialTab] selects the default tab: 0 = Fretboard, 1 = Piano, 2 = Piano Roll.
void showAppInfoPanel(BuildContext context, {int initialTab = 0}) {
  showStudioModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AppInfoSheet(initialTab: initialTab),
  );
}

// ── Sheet ────────────────────────────────────────────────────────────────────

class _AppInfoSheet extends StatefulWidget {
  final int initialTab;

  const _AppInfoSheet({required this.initialTab});

  @override
  State<_AppInfoSheet> createState() => _AppInfoSheetState();
}

class _AppInfoSheetState extends State<_AppInfoSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: StudioPalette.of(context).surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          _DragHandle(),
          _Header(onClose: () => Navigator.of(context).pop()),
          const SizedBox(height: 4),
          _TabBar(controller: _tabController),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _FretboardInfoTab(),
                _PianoInfoTab(),
                _PianoRollInfoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;

  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
      child: Row(
        children: [
          Icon(
            Icons.help_outline_rounded,
            color: StudioPalette.of(context).sky,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Gestures & Features',
              style: TextStyle(
                color: StudioPalette.of(context).textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: StudioPalette.of(context).isStudio ? 44 : 30,
              height: StudioPalette.of(context).isStudio ? 44 : 30,
              decoration: BoxDecoration(
                color: (StudioPalette.of(context).isStudio
                    ? StudioPalette.of(context).glassBg
                    : Colors.white.withValues(alpha: 0.08)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                color: StudioPalette.of(context).textMuted,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final TabController controller;

  const _TabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      indicatorColor: StudioPalette.of(context).sky,
      indicatorWeight: 2,
      labelColor: StudioPalette.of(context).sky,
      unselectedLabelColor: StudioPalette.of(context).textMuted,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      dividerColor: (StudioPalette.of(context).isStudio
          ? StudioPalette.of(context).glassBg
          : Colors.white.withValues(alpha: 0.08)),
      tabs: const [
        Tab(text: 'Fretboard'),
        Tab(text: 'Piano'),
        Tab(text: 'Piano Roll'),
      ],
    );
  }
}

// ── Tab content ──────────────────────────────────────────────────────────────

class _FretboardInfoTab extends StatelessWidget {
  const _FretboardInfoTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _Section(
          icon: Icons.dashboard_outlined,
          title: 'Studio workspace',
          color: StudioPalette.of(context).emerald,
          entries: [
            _Entry(
              icon: Icons.tune_rounded,
              label: 'Notes, Voicings & Setup',
              desc:
                  'The inspector keeps note detection under Notes, chord shapes '
                  'under Voicings, and guitar tuning, capo, and display controls '
                  'under Setup. Switch tabs without losing the current picker state.',
              color: StudioPalette.of(context).emerald,
            ),
            _Entry(
              icon: Icons.bookmarks_outlined,
              label: 'Save idea, Idea library & Add to Writer',
              desc:
                  'Save idea opens the save flow for the current selection. '
                  'Idea library browses saved ideas. Add to Writer accepts a valid '
                  'Chord-mode selection with one note per string; Free-mode ideas '
                  'remain available for saving and exploration.',
              color: StudioPalette.of(context).emerald,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.touch_app_outlined,
          title: 'Gestures',
          color: StudioPalette.of(context).sky,
          entries: [
            _Entry(
              icon: Icons.touch_app,
              label: 'Tap a fret cell',
              desc:
                  'Selects or deselects the note at that string and fret. In Chord '
                  'mode, only one note per string is allowed at a time.',
              color: StudioPalette.of(context).sky,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.layers_outlined,
          title: 'Input & View Modes',
          color: StudioPalette.of(context).violet,
          entries: [
            _Entry(
              icon: Icons.toggle_on_outlined,
              label: 'Free mode',
              desc: 'Select any note on any string, no restrictions.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.music_note,
              label: 'Chord mode',
              desc:
                  'Enforces one note per string, matching standard guitar voicing '
                  'rules.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.grid_on,
              label: 'All view',
              desc: 'Shows pitch classes (e.g. C#) across the whole fretboard.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.text_fields,
              label: 'Exact view',
              desc: 'Shows note names with octave (e.g. C#4).',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.center_focus_strong_outlined,
              label: 'Focus view',
              desc: 'Selected notes are vivid; unselected notes are dimmed.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.visibility_outlined,
              label: 'Solo view',
              desc: 'Only selected notes are shown; all others are hidden.',
              color: StudioPalette.of(context).violet,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.build_outlined,
          title: 'Panels & Tools',
          color: StudioPalette.of(context).orange,
          entries: [
            _Entry(
              icon: Icons.tune,
              label: 'Tuning',
              desc:
                  'Choose from 10 presets: Standard, Drop D, Open G, Open D, Open '
                  'E, DADGAD, Half-step Down, Full-step Down, Open A, Open C.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.compress,
              label: 'Capo',
              desc:
                  'Set capo position from fret 0 (no capo) to fret 11. All '
                  'open-string pitches are shifted up accordingly.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.library_music_outlined,
              label: 'Voicings',
              desc:
                  'Choose a root and quality, then tap a chord diagram to apply '
                  'that voicing to the fretboard.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.stacked_line_chart,
              label: 'Scale',
              desc:
                  'Highlights scale tones across every string. The root has a '
                  'distinct semantic accent; its hue follows the selected theme.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.search,
              label: 'Detection',
              desc:
                  'Detection now uses the exact selected notes, so inversions such as C/E and friendlier spellings such as Bb or Eb can appear on the result chips.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.save_outlined,
              label: 'Idea library',
              desc:
                  'Browse and load saved ideas. Use Save idea beside the selection '
                  'summary to add the current voicing to a named project folder.',
              color: StudioPalette.of(context).orange,
            ),
          ],
        ),
      ],
    );
  }
}

class _PianoInfoTab extends StatelessWidget {
  const _PianoInfoTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _Section(
          icon: Icons.dashboard_outlined,
          title: 'Studio workspace',
          color: StudioPalette.of(context).emerald,
          entries: [
            _Entry(
              icon: Icons.tune_rounded,
              label: 'Notes, Voicings & Setup',
              desc:
                  'The inspector keeps selected-note detection under Notes, '
                  'chord shapes and octave/inversion choices under Voicings, '
                  'and keyboard range and display controls under Setup.',
              color: StudioPalette.of(context).emerald,
            ),
            _Entry(
              icon: Icons.bookmarks_outlined,
              label: 'Save idea, Idea library & Add to Writer',
              desc:
                  'Save idea opens the save flow for the current selection. '
                  'Idea library browses saved ideas. Add to Writer carries valid '
                  'selected MIDI notes into Harmony, whether or not they form a '
                  'recognized chord.',
              color: StudioPalette.of(context).emerald,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.touch_app_outlined,
          title: 'Gestures',
          color: StudioPalette.of(context).sky,
          entries: [
            _Entry(
              icon: Icons.touch_app,
              label: 'Tap a key',
              desc: 'Selects or deselects that piano key.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.swipe_outlined,
              label: 'Pan / drag along the keyboard',
              desc:
                  'Scrolls the keyboard horizontally. Most useful on 61-key and '
                  '88-key layouts where the keyboard exceeds the screen width.',
              color: StudioPalette.of(context).sky,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.build_outlined,
          title: 'Panels & Tools',
          color: StudioPalette.of(context).violet,
          entries: [
            _Entry(
              icon: Icons.piano_outlined,
              label: 'Range selector',
              desc:
                  'Switch between 49-key (C3–C7), 61-key (C2–C7), and 88-key '
                  '(A0–C8) keyboard layouts.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.library_music_outlined,
              label: 'Voicings',
              desc:
                  'Choose a root and quality, then select a voicing diagram to '
                  'apply exact MIDI keys. Octave and inversion controls help place '
                  'the shape in the register you want.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.stacked_line_chart,
              label: 'Scale picker',
              desc:
                  'Highlights scale tones across the keyboard. The root has a '
                  'distinct semantic accent; its hue follows the selected theme.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.search,
              label: 'Detection',
              desc:
                  'Detection now uses the exact selected notes, so inversions such as C/E and friendlier spellings such as Bb or Eb can appear on the result chips.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.save_outlined,
              label: 'Idea library',
              desc:
                  'Browse and load saved ideas. Use Save idea beside the selection '
                  'summary to add the current notes to a named project folder.',
              color: StudioPalette.of(context).violet,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.info_outline_rounded,
          title: 'Behaviour Notes',
          color: StudioPalette.of(context).teal,
          entries: [
            _Entry(
              icon: Icons.warning_amber_outlined,
              label: 'Out-of-key alert',
              desc:
                  'Adding a note outside the highlighted scale shows a confirmation '
                  'dialog. You can permanently disable it in Settings.',
              color: StudioPalette.of(context).teal,
            ),
            _Entry(
              icon: Icons.palette_outlined,
              label: 'Colour coding',
              desc:
                  'Selection, scale, chord, and root notes use distinct semantic '
                  'colors. Their hues follow the selected theme; piano keys keep '
                  'their white/black identity.',
              color: StudioPalette.of(context).teal,
            ),
          ],
        ),
      ],
    );
  }
}

class _PianoRollInfoTab extends StatelessWidget {
  const _PianoRollInfoTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ── Studio Layout ───────────────────────────────────────────────
        _Section(
          icon: Icons.dashboard_outlined,
          title: 'Studio layout',
          color: StudioPalette.of(context).emerald,
          entries: [
            _Entry(
              icon: Icons.smartphone_outlined,
              label: 'Compact and short screens',
              desc:
                  'The timeline stays primary beneath the project context, '
                  'transport, and five editing tools. The Stack Builder, '
                  'Selection, and Tools inspector sits below the grid; short '
                  'screens keep its contents and utility actions reachable by scrolling.',
              color: StudioPalette.of(context).emerald,
            ),
            _Entry(
              icon: Icons.tablet_android_outlined,
              label: 'Wide screens',
              desc:
                  'The grid remains the main surface beside a contextual '
                  'inspector for Stack Builder, Selection, and Tools. Transport '
                  'and utility actions remain available alongside the editor.',
              color: StudioPalette.of(context).emerald,
            ),
            _Entry(
              icon: Icons.compare_arrows_outlined,
              label: 'Song-embedded Roll',
              desc:
                  'Song keeps its existing Roll layout and host settings. Embedded '
                  'editors can hide background, scale, or save/import actions when '
                  'those controls belong to the host workspace.',
              color: StudioPalette.of(context).emerald,
            ),
          ],
        ),
        SizedBox(height: 16),
        // ── Web Support ─────────────────────────────────────────────────
        _Section(
          icon: Icons.web_outlined,
          title: 'Web Support',
          color: StudioPalette.of(context).orange,
          entries: [
            _Entry(
              icon: Icons.check_circle_outline,
              label: 'Fully supported on web',
              desc:
                  'Editor grid, playback, stack composer, save/load, import, '
                  'detection, scale highlighting, keyboard shortcuts, and '
                  'Ctrl/Alt + wheel zoom all work in the browser.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.mic_off_outlined,
              label: 'Hum to MIDI is mobile-only',
              desc:
                  'Microphone recording is not available on web. The Hum '
                  'Recorder card shows "Hum to MIDI not supported on web" '
                  'instead of record controls.',
              color: StudioPalette.of(context).orange,
            ),
          ],
        ),
        SizedBox(height: 16),
        // ── Gestures ────────────────────────────────────────────────────
        _Section(
          icon: Icons.touch_app_outlined,
          title: 'Gestures',
          color: StudioPalette.of(context).sky,
          entries: [
            _Entry(
              icon: Icons.select_all_rounded,
              label: 'Select tool',
              desc:
                  'Switch to Select, then drag a box across the grid to select any notes '
                  'the box touches. Use Draw afterward to move or resize the selected group.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.touch_app,
              label: 'Tap an empty cell',
              desc:
                  'Adds a new note of 1 tick (1/16th note) at that pitch and '
                  'beat position.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.touch_app_outlined,
              label: 'Double-tap an empty cell',
              desc:
                  'Inserts a note at the current snap duration (e.g. 1/4 note). '
                  'Uses the active snap value from the toolbar.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.view_column_outlined,
              label: 'Selected column vs selected notes',
              desc:
                  'The selected column is a timeline position used for detection '
                  'and playback start. Selected notes are the notes you are '
                  'actively editing. They are related, but separate.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.mouse_outlined,
              label: 'Tap an existing note',
              desc:
                  'Solo-selects that note (replaces the current note selection). '
                  'Also previews that pitch. Use double-tap to add or remove '
                  'that note from a multi-selection.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.playlist_add_check_circle_outlined,
              label: 'Select notes at current column',
              desc:
                  'Use Select column in the Selection area or its compact action '
                  'icon to select all notes active at the current column tick.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.open_with_outlined,
              label: 'Drag selected note(s)',
              desc:
                  'Drags the selected note group together. Horizontal drag snaps '
                  'to the nearest beat '
                  '(quarter note in 4/4, eighth note in 4/8). Vertical drag '
                  'shifts pitch one semitone per row.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.swap_horiz_outlined,
              label: 'Drag right edge of a note',
              desc:
                  'Resizes note duration. If the note is selected, the current '
                  'multi-selection resizes together. Minimum duration is one '
                  '1/16th note (1 tick). The resize handle is the rightmost 16 px '
                  'of the note.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.timer_outlined,
              label: 'Long press a note (500 ms)',
              desc: 'Deletes the note immediately.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.straighten_outlined,
              label: 'Tap the ruler',
              desc:
                  'Sets the detection column. The detection panel then shows all '
                  'active notes, chords, and scales at that beat.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.drag_handle_outlined,
              label: 'Drag the ruler (scrub)',
              desc:
                  'Drag horizontally across the ruler to scrub the selected '
                  'column continuously. The detection panel updates in real '
                  'time as you drag. Ideal for scanning a timeline.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.pinch_outlined,
              label: 'Pinch with two fingers',
              desc:
                  'Zoom: horizontal spread scales cell width (10–80 px); vertical '
                  'spread scales row height (10–40 px).',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.pan_tool_alt_outlined,
              label: 'Single-finger drag on empty area',
              desc: 'Scrolls the grid both horizontally and vertically.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.content_cut_outlined,
              label: 'Split tool',
              desc:
                  'Tap a note to split at the tapped position. If that note is '
                  'selected, the current multi-selection splits at the same tick. '
                  'Long‑press still deletes in Split mode. Choose Split from the '
                  'five editing tools.',
              color: StudioPalette.of(context).sky,
            ),
            _Entry(
              icon: Icons.view_column_outlined,
              label: 'Select column',
              desc:
                  'Secondary shortcut: tap or drag the ruler to select all notes active '
                  'at the current column tick. Use Select tool for area‑based multi‑selection.',
              color: StudioPalette.of(context).sky,
            ),
          ],
        ),
        SizedBox(height: 16),
        // ── Keyboard Shortcuts ──────────────────────────────────────────
        _Section(
          icon: Icons.keyboard_outlined,
          title: 'Keyboard Shortcuts (desktop/web)',
          color: StudioPalette.of(context).teal,
          entries: [
            _Entry(
              icon: Icons.space_bar_outlined,
              label: 'Space',
              desc: 'Start or stop playback.',
              color: StudioPalette.of(context).teal,
            ),
            _Entry(
              icon: Icons.backspace_outlined,
              label: 'Delete / Backspace',
              desc:
                  'Delete all currently selected notes (same as the UI delete '
                  'selection action).',
              color: StudioPalette.of(context).teal,
            ),
            _Entry(
              icon: Icons.zoom_in_outlined,
              label: 'Ctrl / Cmd + scroll wheel',
              desc: 'Horizontal zoom — scales cell width (10–80 px range).',
              color: StudioPalette.of(context).teal,
            ),
            _Entry(
              icon: Icons.zoom_out_map_outlined,
              label: 'Alt / Option + scroll wheel',
              desc: 'Vertical zoom — scales row height (10–40 px range).',
              color: StudioPalette.of(context).teal,
            ),
          ],
        ),
        SizedBox(height: 16),
        // ── Toolbar & Controls ──────────────────────────────────────────
        _Section(
          icon: Icons.settings_outlined,
          title: 'Toolbar Controls',
          color: StudioPalette.of(context).orange,
          entries: [
            _Entry(
              icon: Icons.speed_outlined,
              label: 'Tempo',
              desc: 'Set BPM with − and + steppers. Range: 20–300 BPM.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.edit_outlined,
              label: 'Five tools & Snap',
              desc:
                  'Draw adds, moves, and resizes notes; Select makes a note-group '
                  'marquee; Split cuts notes; Paint adds notes while brushing; '
                  'Delete removes notes while brushing. The Tools inspector exposes '
                  'snap presets from 1 to 32 ticks.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.calendar_view_week_outlined,
              label: 'Measures',
              desc:
                  'Expand or shrink the timeline. Notes beyond the new end tick '
                  'are automatically removed.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.access_time_outlined,
              label: 'Time signature',
              desc:
                  'Choose 4/4, 3/4, 6/8, and more. Affects beat snapping granularity '
                  'and ruler markers.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.key_outlined,
              label: 'Key',
              desc:
                  'Sets the reference key for the detection panel (optional). '
                  'Accepts major or minor keys.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'Pitch window (▲ / ▼)',
              desc:
                  'Shifts the visible MIDI range up or down by 12 semitones '
                  '(one octave) per tap. Also shows current C3–C6 range.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.play_arrow_rounded,
              label: 'Playback',
              desc:
                  'Tap Play to hear the roll from the selected column through '
                  'the end of the timeline. Tap Stop to cancel. Playback is '
                  'disabled while humming is active. Also triggered by Space key.',
              color: StudioPalette.of(context).orange,
            ),
            _Entry(
              icon: Icons.delete_sweep_outlined,
              label: 'Clear',
              desc: 'Removes all notes from the entire timeline.',
              color: StudioPalette.of(context).orange,
            ),
          ],
        ),
        SizedBox(height: 16),
        // ── Panels ──────────────────────────────────────────────────────
        _Section(
          icon: Icons.layers_outlined,
          title: 'Panels',
          color: StudioPalette.of(context).violet,
          entries: [
            _Entry(
              icon: Icons.content_paste_rounded,
              label: 'Quick',
              desc:
                  'Copies selected notes to the selected column. With no notes '
                  'selected, it repeats the last added stack at the selected column.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.library_music_outlined,
              label: 'Stack Builder',
              desc:
                  'Build a chord stack from root, quality, inversion, and duration, '
                  'or edit individual notes with the advanced controls. Custom '
                  'voicings can contain up to 10 notes; exact duplicate notes are '
                  'rejected. Add Stack places the result at the current column.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.stacked_line_chart_outlined,
              label: 'Scale picker',
              desc:
                  'Highlight scale tones (major, minor, pentatonic, blues, '
                  'chromatic) across the grid. Applying a scale checks '
                  'existing notes first, then blocks new notes, stack inserts, '
                  'and pitch moves that would fall outside the active scale. '
                  'Clear the scale pill with × to return to chromatic entry.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.folder_open_outlined,
              label: 'Import from saves',
              desc:
                  'Browse saved fretboard and piano progressions, then place '
                  'their notes at the current column. Toggle "Exact MIDI" vs '
                  '"Pitch Class" placement mode. Piano Roll session snapshots '
                  'are excluded — use the dedicated save panel to restore full rolls.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.save_outlined,
              label: 'Piano Roll save / load',
              desc:
                  'Save the entire piano roll session (notes, tempo, signature, '
                  'pitch range, selection, snap value, scale highlights) and '
                  'restore it later. Piano roll saves are separate from the '
                  'cross‑instrument stack import loader.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.mic_outlined,
              label: 'Hum Recorder (mobile only)',
              desc:
                  'Capture humming and convert its pitches into notes on the '
                  'timeline. This is not an audio-track or MIDI-file recorder. '
                  'Microphone capture is unavailable on web. Includes pitch '
                  'sensitivity setting (Strict / Balanced / Forgiving) and a '
                  '"Jump to latest" button for navigation.',
              color: StudioPalette.of(context).violet,
            ),
            _Entry(
              icon: Icons.search,
              label: 'Detection panel',
              desc:
                  'Shows note chips, matching chords (up to 8), and matching '
                  'scales (up to 8) for all notes active at the selected column. '
                  'Uses shared exact‑note detection APIs from note_utils.dart. '
                  'Tap × on a chip to delete that note.',
              color: StudioPalette.of(context).violet,
            ),
          ],
        ),
        SizedBox(height: 16),
        // ── Timeline Math ───────────────────────────────────────────────
        _Section(
          icon: Icons.calculate_outlined,
          title: 'Timeline Math',
          color: StudioPalette.of(context).teal,
          entries: [
            _Entry(
              icon: Icons.calculate_outlined,
              label: '1 tick = 1/16th note',
              desc:
                  '4 ticks = 1 quarter note · 1 measure (4/4) = 16 ticks · total '
                  'ticks = ticksPerMeasure × totalMeasures.',
              color: StudioPalette.of(context).teal,
            ),
            _Entry(
              icon: Icons.music_note,
              label: 'Beat snapping',
              desc:
                  'Dragged notes snap to the nearest quarter-note tick in 4/4 time '
                  'and to the nearest eighth-note tick in 4/8 time. Active snap '
                  'preset (1t–32t) also controls double‑tap insertion length.',
              color: StudioPalette.of(context).teal,
            ),
          ],
        ),
        SizedBox(height: 8),
      ],
    );
  }
}

// ── Reusable Section & Entry ─────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<_Entry> entries;

  const _Section({
    required this.icon,
    required this.title,
    required this.color,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: (StudioPalette.of(context).isStudio
                ? StudioPalette.of(context).glassBg
                : Colors.white.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (StudioPalette.of(context).isStudio
                  ? StudioPalette.of(context).glassBg
                  : Colors.white.withValues(alpha: 0.07)),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                entries[i],
                if (i < entries.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: (StudioPalette.of(context).isStudio
                        ? StudioPalette.of(context).glassBg
                        : Colors.white.withValues(alpha: 0.05)),
                    indent: 56,
                    endIndent: 14,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;

  const _Entry({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: StudioPalette.of(context).textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    color: StudioPalette.of(context).textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
