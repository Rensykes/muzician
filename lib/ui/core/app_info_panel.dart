/// Reusable help sheet that documents all gestures and features per instrument.
library;

import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

// ── Public API ───────────────────────────────────────────────────────────────

/// Shows the app-wide gesture and feature guide as a modal bottom sheet.
///
/// [initialTab] selects the default tab: 0 = Fretboard, 1 = Piano, 2 = Piano Roll.
void showAppInfoPanel(BuildContext context, {int initialTab = 0}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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
        color: MuzicianTheme.surface,
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
          const Icon(
            Icons.help_outline_rounded,
            color: MuzicianTheme.sky,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Gestures & Features',
              style: TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: MuzicianTheme.textMuted,
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
      indicatorColor: MuzicianTheme.sky,
      indicatorWeight: 2,
      labelColor: MuzicianTheme.sky,
      unselectedLabelColor: MuzicianTheme.textMuted,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      dividerColor: Colors.white.withValues(alpha: 0.08),
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
      children: const [
        _Section(
          icon: Icons.touch_app_outlined,
          title: 'Gestures',
          color: MuzicianTheme.sky,
          entries: [
            _Entry(
              icon: Icons.touch_app,
              label: 'Tap a fret cell',
              desc:
                  'Selects or deselects the note at that string and fret. In Chord '
                  'mode, only one note per string is allowed at a time.',
              color: MuzicianTheme.sky,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.layers_outlined,
          title: 'Input & View Modes',
          color: MuzicianTheme.violet,
          entries: [
            _Entry(
              icon: Icons.toggle_on_outlined,
              label: 'Free mode',
              desc: 'Select any note on any string, no restrictions.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.music_note,
              label: 'Chord mode',
              desc:
                  'Enforces one note per string, matching standard guitar voicing '
                  'rules.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.grid_on,
              label: 'All view',
              desc: 'Shows pitch classes (e.g. C#) across the whole fretboard.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.text_fields,
              label: 'Exact view',
              desc: 'Shows note names with octave (e.g. C#4).',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.center_focus_strong_outlined,
              label: 'Focus view',
              desc: 'Selected notes are vivid; unselected notes are dimmed.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.visibility_outlined,
              label: 'Solo view',
              desc: 'Only selected notes are shown; all others are hidden.',
              color: MuzicianTheme.violet,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.build_outlined,
          title: 'Panels & Tools',
          color: MuzicianTheme.orange,
          entries: [
            _Entry(
              icon: Icons.tune,
              label: 'Tuning',
              desc:
                  'Choose from 10 presets: Standard, Drop D, Open G, Open D, Open '
                  'E, DADGAD, Half-step Down, Full-step Down, Open A, Open C.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.compress,
              label: 'Capo',
              desc:
                  'Set capo position from fret 0 (no capo) to fret 11. All '
                  'open-string pitches are shifted up accordingly.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.library_music_outlined,
              label: 'Chord voicing',
              desc:
                  'Pick a root note and quality (major, minor, 7, maj7, m7, dim, '
                  'aug, sus2, sus4) and tap "Load" to place the shape on the '
                  'fretboard.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.stacked_line_chart,
              label: 'Scale',
              desc:
                  'Highlights scale tones across every string. The root note is '
                  'shown in the accent colour (sky blue).',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.search,
              label: 'Detection',
              desc:
                  'Automatically identifies the chord name and scale name from your '
                  'selected notes. Shown below the fretboard when notes are active.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.save_outlined,
              label: 'Saves',
              desc:
                  'Save the current voicing to a named folder and reload it at any '
                  'time.',
              color: MuzicianTheme.orange,
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
      children: const [
        _Section(
          icon: Icons.touch_app_outlined,
          title: 'Gestures',
          color: MuzicianTheme.sky,
          entries: [
            _Entry(
              icon: Icons.touch_app,
              label: 'Tap a key',
              desc: 'Selects or deselects that piano key.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.swipe_outlined,
              label: 'Pan / drag along the keyboard',
              desc:
                  'Scrolls the keyboard horizontally. Most useful on 61-key and '
                  '88-key layouts where the keyboard exceeds the screen width.',
              color: MuzicianTheme.sky,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.build_outlined,
          title: 'Panels & Tools',
          color: MuzicianTheme.violet,
          entries: [
            _Entry(
              icon: Icons.piano_outlined,
              label: 'Range selector',
              desc:
                  'Switch between 49-key (C3–C7), 61-key (C2–C7), and 88-key '
                  '(A0–C8) keyboard layouts.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.library_music_outlined,
              label: 'Chord picker',
              desc:
                  'Highlights all tones of a chosen root + quality (major, minor, '
                  '7, maj7, m7, dim, aug, sus2, sus4).',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.stacked_line_chart,
              label: 'Scale picker',
              desc:
                  'Highlights scale tones across the keyboard. The root note is '
                  'shown in emerald green.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.search,
              label: 'Detection',
              desc:
                  'Identifies the chord name and scale name from currently selected '
                  'keys, updating in real time.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.save_outlined,
              label: 'Saves',
              desc:
                  'Save the current note selection as a named progression and '
                  'reload it later.',
              color: MuzicianTheme.violet,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.info_outline_rounded,
          title: 'Behaviour Notes',
          color: MuzicianTheme.teal,
          entries: [
            _Entry(
              icon: Icons.warning_amber_outlined,
              label: 'Out-of-key alert',
              desc:
                  'Adding a note outside the highlighted scale shows a confirmation '
                  'dialog. You can permanently disable it in Settings.',
              color: MuzicianTheme.teal,
            ),
            _Entry(
              icon: Icons.palette_outlined,
              label: 'Colour coding',
              desc:
                  'Selected = sky blue · Scale highlight = teal · Chord highlight '
                  '= violet · Root note = emerald.',
              color: MuzicianTheme.teal,
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
      children: const [
        _Section(
          icon: Icons.touch_app_outlined,
          title: 'Gestures',
          color: MuzicianTheme.sky,
          entries: [
            _Entry(
              icon: Icons.touch_app,
              label: 'Tap an empty cell',
              desc: 'Adds a new note at that pitch and beat position.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.mouse_outlined,
              label: 'Tap an existing note',
              desc:
                  'Selects the note. The detection panel then shows note chips for '
                  'that column. Tap the same note again to deselect.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.open_with_outlined,
              label: 'Drag note body',
              desc:
                  'Moves the note. Horizontal drag snaps to the nearest beat '
                  '(quarter note in 4/4, eighth note in 4/8). Vertical drag '
                  'shifts pitch one semitone per row.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.swap_horiz_outlined,
              label: 'Drag right edge of a note',
              desc:
                  'Resizes the note duration. Minimum duration is one 1/16th note '
                  '(1 tick). The resize handle is the rightmost 16 px of the note.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.timer_outlined,
              label: 'Long press a note (500 ms)',
              desc: 'Deletes the note immediately.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.straighten_outlined,
              label: 'Tap the ruler',
              desc:
                  'Sets the detection column. The detection panel then shows all '
                  'active notes, chords, and scales at that beat.',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.pinch_outlined,
              label: 'Pinch with two fingers',
              desc:
                  'Zoom: horizontal spread scales cell width (10–80 px); vertical '
                  'spread scales row height (10–40 px).',
              color: MuzicianTheme.sky,
            ),
            _Entry(
              icon: Icons.pan_tool_alt_outlined,
              label: 'Single-finger drag on empty area',
              desc: 'Scrolls the grid both horizontally and vertically.',
              color: MuzicianTheme.sky,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.settings_outlined,
          title: 'Toolbar Controls',
          color: MuzicianTheme.orange,
          entries: [
            _Entry(
              icon: Icons.speed_outlined,
              label: 'Tempo',
              desc: 'Set BPM with − and + steppers. Range: 20–300 BPM.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.calendar_view_week_outlined,
              label: 'Measures',
              desc:
                  'Expand or shrink the timeline. Notes beyond the new end tick '
                  'are automatically removed.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.access_time_outlined,
              label: 'Time signature',
              desc:
                  'Choose 4/4, 3/4, 6/8, and more. Affects beat snapping granularity '
                  'and ruler markers.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.key_outlined,
              label: 'Key',
              desc:
                  'Sets the reference key for the detection panel (optional). '
                  'Accepts major or minor keys.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'Pitch window (▲ / ▼)',
              desc:
                  'Shifts the visible MIDI range up or down by 12 semitones '
                  '(one octave) per tap.',
              color: MuzicianTheme.orange,
            ),
            _Entry(
              icon: Icons.delete_sweep_outlined,
              label: 'Clear',
              desc: 'Removes all notes from the entire timeline.',
              color: MuzicianTheme.orange,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.layers_outlined,
          title: 'Panels',
          color: MuzicianTheme.violet,
          entries: [
            _Entry(
              icon: Icons.library_music_outlined,
              label: 'Stack selector',
              desc:
                  'Choose a chord root + quality + note duration, then tap "Add '
                  'Stack" to place all chord notes at the selected column tick. '
                  'Notes are voice-led into the current pitch window.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.folder_open_outlined,
              label: 'Save stack loader',
              desc:
                  'Browse saved progressions and place their notes at the current '
                  'column. Toggle "Exact MIDI" vs "Pitch Class" to control whether '
                  'notes are placed at their original MIDI values or transposed to '
                  'fit the pitch window.',
              color: MuzicianTheme.violet,
            ),
            _Entry(
              icon: Icons.search,
              label: 'Detection panel',
              desc:
                  'Shows note chips, up to 8 matching chords, and up to 8 matching '
                  'scales for all notes active at the selected column. Tap × on a '
                  'chip to delete that note.',
              color: MuzicianTheme.violet,
            ),
          ],
        ),
        SizedBox(height: 16),
        _Section(
          icon: Icons.calculate_outlined,
          title: 'Timeline Math',
          color: MuzicianTheme.teal,
          entries: [
            _Entry(
              icon: Icons.calculate_outlined,
              label: '1 tick = 1/16th note',
              desc:
                  '4 ticks = 1 quarter note · 1 measure (4/4) = 16 ticks · total '
                  'ticks = ticksPerMeasure × totalMeasures.',
              color: MuzicianTheme.teal,
            ),
            _Entry(
              icon: Icons.music_note,
              label: 'Beat snapping',
              desc:
                  'Dragged notes snap to the nearest quarter-note tick in 4/4 time '
                  'and to the nearest eighth-note tick in 4/8 time.',
              color: MuzicianTheme.teal,
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
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.07),
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
                    color: Colors.white.withValues(alpha: 0.05),
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
                  style: const TextStyle(
                    color: MuzicianTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
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
