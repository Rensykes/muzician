/// PianoChordPicker – root/quality picker with simple piano voicings.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/settings_store.dart';
import '../../store/piano_store.dart';
import '../../store/project_config_sync.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/out_of_key_dialog.dart';
import '../../utils/note_utils.dart';
import '../instrument_shared/chord_picker_parts.dart';
import '../instrument_shared/instrument_binding.dart';
import 'piano_chord_diagram.dart';

/// Qualities shown in the piano chord picker UI (subset of [chordIntervals]).
const _pianoQualities = [
  ('5', '5th'),
  ('', 'maj'),
  ('m', 'min'),
  ('7', 'dom7'),
  ('maj7', 'maj7'),
  ('m7', 'm7'),
  ('sus2', 'sus2'),
  ('sus4', 'sus4'),
  ('dim', 'dim'),
  ('aug', 'aug'),
  ('m7b5', 'm7♭5'),
  ('add9', 'add9'),
  ('maj9', 'maj9'),
  ('6', '6'),
  ('m6', 'm6'),
  ('dim7', 'dim7'),
  ('7sus4', '7sus4'),
];

List<int> _buildVoicingMidis(
  List<String> notes,
  int inversion,
  int octaveOffset,
) {
  final rootBase = 60 + octaveOffset * 12;
  final rotated = [...notes.sublist(inversion), ...notes.sublist(0, inversion)];
  final midis = <int>[];
  int prev = rootBase - 1;
  for (int idx = 0; idx < rotated.length; idx++) {
    final pc = noteToPC[rotated[idx]];
    if (pc == null) continue;
    // Start one octave below rootBase so the while-loop lands in the right
    // octave for both positive and negative octave offsets.
    int midi = rootBase - 12 + pc;
    while (midi <= prev) {
      midi += 12;
    }
    midis.add(midi);
    prev = midi;
  }
  return midis;
}

/// Returns the first chord in [_pianoQualities] whose tones exactly match
/// [notes], or null when no chord matches or notes has fewer than 2 members.
({String root, String quality})? _detectFirstChordForPiano(
  List<String> notes,
) => detectFirstChord(notes, qualitySymbols: kInstrumentChordQualitySymbols);

class PianoChordPicker extends ConsumerStatefulWidget {
  const PianoChordPicker({super.key});

  @override
  ConsumerState<PianoChordPicker> createState() => _PianoChordPickerState();
}

class _PianoChordPickerState extends ConsumerState<PianoChordPicker>
    with ChordPickerSync {
  String? _selectedRoot;
  String _selectedQuality = '';
  int _octaveOffset = 0;
  int? _selectedVoicingIdx;

  /// True once the user has explicitly tapped a voicing card.
  /// When false the picker mirrors the first detected chord automatically.
  bool _voicingCommitted = false;

  static const _minOctaveOffset = -3;
  static const _maxOctaveOffset = 3;

  @override
  DetectedChord detectFirstChordFromState() =>
      _detectFirstChordForPiano(ref.read(pianoProvider).selectedNotes);

  @override
  void applyDetectedChord(DetectedChord chord, {required bool committed}) {
    setState(() {
      _voicingCommitted = committed;
      _selectedRoot = chord?.root;
      _selectedQuality = chord?.quality ?? '';
      _selectedVoicingIdx = null;
    });
  }

  @override
  ({String root, String quality})? get currentActiveChord =>
      _selectedRoot != null
      ? (root: _selectedRoot!, quality: _selectedQuality)
      : null;

  @override
  bool get isChordCommitted => _voicingCommitted;

  @override
  void initState() {
    super.initState();
    final notes = ref.read(pianoProvider).selectedNotes;
    final detected = _detectFirstChordForPiano(notes);
    _selectedRoot = detected?.root;
    _selectedQuality = detected?.quality ?? '';
  }

  Future<bool> _confirmIfOffKey(
    List<String> chordNotes,
    ({String root, String scaleName})? activeKey,
    NoteSpelling spelling,
  ) async {
    if (activeKey == null) return true;
    final outOfKey = chordPitchClassesOutOfKey(
      chordNotes,
      scaleRoot: activeKey.root,
      scaleName: activeKey.scaleName,
    );
    if (outOfKey.isEmpty) return true;
    if (!mounted) return false;
    final notes = outOfKey
        .map((note) => formatRootChoiceLabel(note, spelling: spelling))
        .join(', ');
    final result = await showStudioDialog<OutOfKeyResult>(
      context: context,
      builder: (ctx) => OutOfKeyDialog(
        title: 'Chord outside the key',
        message:
            'This chord contains $notes, which fall outside '
            '${formatRootChoiceLabel(activeKey.root, spelling: spelling)} ${activeKey.scaleName}. Apply anyway?',
        showSuppressOption: false,
      ),
    );
    return result != null;
  }

  @override
  Widget build(BuildContext context) {
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final notifier = ref.read(pianoProvider.notifier);
    final keyMidis = notifier.getKeys().map((k) => k.midiNote).toSet();

    installChordSync(pianoBinding);

    final chordNotes = _selectedRoot != null
        ? getChordNotes(_selectedRoot!, _selectedQuality)
        : <String>[];

    final voicings = <({String label, List<int> midis})>[];
    if (chordNotes.isNotEmpty) {
      for (int inv = 0; inv < 3 && inv < chordNotes.length; inv++) {
        final midis = _buildVoicingMidis(
          chordNotes,
          inv,
          _octaveOffset,
        ).where((m) => keyMidis.contains(m)).toList();
        if (midis.length >= 3) {
          voicings.add((label: inv == 0 ? 'Root' : '$inv inv', midis: midis));
        }
      }
    }

    final octaveLabel = (4 + _octaveOffset).toString();
    final activeKey = ref.watch(activeProjectKeyProvider);
    final diatonic = activeKey == null
        ? const <DiatonicChord>[]
        : getDiatonicChords(activeKey.root, activeKey.scaleName);

    final studio = StudioPalette.of(context).isStudio;
    final octaveSelector = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Octave',
          style: TextStyle(
            color: StudioPalette.of(context).textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 10),
        _OctaveButton(
          icon: Icons.remove,
          enabled: _octaveOffset > _minOctaveOffset,
          onTap: () => setState(
            () => _octaveOffset = math.max(_minOctaveOffset, _octaveOffset - 1),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            octaveLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: StudioPalette.of(context).textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _OctaveButton(
          icon: Icons.add,
          enabled: _octaveOffset < _maxOctaveOffset,
          onTap: () => setState(
            () => _octaveOffset = math.min(_maxOctaveOffset, _octaveOffset + 1),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with active chord badge
          if (!studio)
            ChordPickerHeader(
              title: 'Chord Voicings',
              root: _selectedRoot,
              quality: _selectedQuality,
            ),
          if (!studio) const SizedBox(height: 10),
          if (!studio && diatonic.isNotEmpty) ...[
            DiatonicChordsHeader(
              keyLabel:
                  '${formatRootChoiceLabel(activeKey!.root, spelling: spelling)} ${activeKey.scaleName}',
            ),
            const SizedBox(height: 6),
            DiatonicChordsRow(
              chords: diatonic,
              selectedRoot: _selectedRoot,
              selectedQuality: _selectedQuality,
              accent: StudioPalette.of(context).violet,
              onTap: (root, quality) => setState(() {
                _selectedRoot = root;
                _selectedQuality = quality;
                _selectedVoicingIdx = null;
              }),
            ),
            const SizedBox(height: 10),
          ],
          if (studio)
            Row(
              children: [
                Expanded(
                  child: StudioChordSelectors(
                    root: _selectedRoot,
                    quality: _selectedQuality,
                    qualities: _pianoQualities,
                    onRootChanged: (root) => setState(() {
                      _selectedRoot = root;
                      _selectedVoicingIdx = null;
                    }),
                    onQualityChanged: (quality) => setState(() {
                      _selectedQuality = quality;
                      _selectedVoicingIdx = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 88,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: StudioPalette.of(context).surface,
                    border: Border.all(
                      color: StudioPalette.of(context).glassBorder,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      key: const Key('pianoVoicingOctave'),
                      value: _octaveOffset,
                      isExpanded: true,
                      dropdownColor: StudioPalette.of(context).dialogBg,
                      style: TextStyle(
                        color: StudioPalette.of(context).textPrimary,
                        fontSize: 12,
                      ),
                      selectedItemBuilder: (context) => [
                        for (
                          var offset = _minOctaveOffset;
                          offset <= _maxOctaveOffset;
                          offset++
                        )
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              MediaQuery.textScalerOf(context).scale(12) > 15
                                  ? '${4 + offset}'
                                  : 'Oct ${4 + offset}',
                              semanticsLabel: 'Voicing octave ${4 + offset}',
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                      ],
                      items: [
                        for (
                          var offset = _minOctaveOffset;
                          offset <= _maxOctaveOffset;
                          offset++
                        )
                          DropdownMenuItem(
                            value: offset,
                            child: Text('Octave ${4 + offset}'),
                          ),
                      ],
                      onChanged: (offset) {
                        if (offset != null) {
                          setState(() => _octaveOffset = offset);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          // Root pills
          if (!studio)
            RootPillRow(
              selectedRoot: _selectedRoot,
              accent: StudioPalette.of(context).violet,
              onTap: (root) => setState(() {
                _selectedRoot = _selectedRoot == root ? null : root;
                _selectedVoicingIdx = null;
              }),
            ),
          if (!studio) const SizedBox(height: 10),
          // Quality pills
          if (!studio)
            QualityPillRow(
              qualities: _pianoQualities,
              selectedQuality: _selectedQuality,
              accent: StudioPalette.of(context).violet,
              onTap: (symbol) => setState(() {
                _selectedQuality = symbol;
                _selectedVoicingIdx = null;
              }),
            ),
          if (!studio) const SizedBox(height: 10),
          if (!studio) octaveSelector,
          // Voicings
          if (voicings.isNotEmpty) ...[
            SizedBox(height: studio ? 8 : 6),
            if (!studio)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${voicings.length} voicing${voicings.length != 1 ? 's' : ''} — tap to apply',
                  style: TextStyle(
                    color: StudioPalette.of(context).textMuted,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            SizedBox(
              height: studio
                  ? 64 + MediaQuery.textScalerOf(context).scale(36)
                  : 82 + MediaQuery.textScalerOf(context).scale(36),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: voicings.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final v = voicings[i];
                  return PianoChordDiagram(
                    midis: v.midis,
                    rootPc: _selectedRoot != null
                        ? noteToPC[_selectedRoot!]
                        : null,
                    label: v.label,
                    noteLabels: chordNotes
                        .map(
                          (note) =>
                              formatRootChoiceLabel(note, spelling: spelling),
                        )
                        .toList(),
                    isSelected: _selectedVoicingIdx == i,
                    onPress: () async {
                      HapticFeedback.mediumImpact();
                      final apply = await _confirmIfOffKey(
                        chordNotes,
                        activeKey,
                        spelling,
                      );
                      if (!apply) return;
                      setState(() {
                        _voicingCommitted = true;
                        _selectedVoicingIdx = i;
                      });
                      ref.read(pianoChordCommittedProvider.notifier).state =
                          true;
                      notifier.loadExactMidis(v.midis);
                      if (v.midis.isNotEmpty) {
                        ref.read(pianoScrollToMidiProvider.notifier).state = v
                            .midis
                            .reduce(math.min);
                      }
                    },
                  );
                },
              ),
            ),
          ],
          if (studio) ...[
            if (diatonic.isNotEmpty) ...[
              const SizedBox(height: 8),
              DiatonicChordsHeader(
                keyLabel:
                    '${formatRootChoiceLabel(activeKey!.root, spelling: spelling)} ${activeKey.scaleName}',
              ),
              DiatonicChordsRow(
                chords: diatonic,
                selectedRoot: _selectedRoot,
                selectedQuality: _selectedQuality,
                accent: StudioPalette.of(context).sky,
                onTap: (root, quality) => setState(() {
                  _selectedRoot = root;
                  _selectedQuality = quality;
                  _selectedVoicingIdx = null;
                }),
              ),
            ],
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Octave Button ────────────────────────────────────────────────────────────

class _OctaveButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _OctaveButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: enabled
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.02),
          border: Border.all(
            color: enabled
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? StudioPalette.of(context).textPrimary
              : StudioPalette.of(context).textMuted,
        ),
      ),
    );
  }
}
