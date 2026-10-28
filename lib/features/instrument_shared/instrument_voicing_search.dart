/// Studio search criteria remain separate from the notes applied to an instrument.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../models/harmonic_analysis.dart';
import '../../schema/rules/fretboard_rules.dart' show tunings;
import '../../schema/rules/piano_rules.dart' show pianoRanges;
import '../../schema/rules/instrument_voicing_search_rules.dart';
import '../../store/fretboard_store.dart';
import '../../store/piano_store.dart';
import '../../store/project_config_sync.dart';
import '../../store/save_system_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/out_of_key_dialog.dart';
import '../../utils/note_utils.dart';
import '../fretboard/chord_diagram.dart';
import '../piano/piano_chord_diagram.dart';
import 'chord_picker_parts.dart';
import 'instrument_binding.dart';

class InstrumentVoicingSearch extends ConsumerStatefulWidget {
  const InstrumentVoicingSearch({super.key, required this.guitar});
  final bool guitar;

  @override
  ConsumerState<InstrumentVoicingSearch> createState() =>
      _InstrumentVoicingSearchState();
}

class _InstrumentVoicingSearchState
    extends ConsumerState<InstrumentVoicingSearch> {
  bool _fromNotes = true;
  late List<String> _query;
  String _root = 'C';
  String _quality = '';
  String? _appliedId;
  String? _appliedSelection;
  bool _applying = false;
  int _revision = 0;
  String? _cacheKey;
  List<FretboardVoicingCandidate> _guitarResults = [];
  List<PianoVoicingCandidate> _pianoResults = [];
  final _carousel = ScrollController();

  InstrumentBinding get _binding =>
      widget.guitar ? fretboardBinding : pianoBinding;

  List<String> _currentNotes() =>
      ref
          .read(_binding.exactNotes)
          .map((note) => chromaticNotes[note.midiNote % 12])
          .toSet()
          .toList()
        ..sort();

  @override
  void initState() {
    super.initState();
    _query = _currentNotes();
    final chord = detectFirstChord(_query);
    _root = chord?.root ?? 'C';
    _quality = chord?.quality ?? '';
  }

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  void _captureNotes({bool external = false}) {
    if (_applying) return;
    setState(() {
      _query = _currentNotes();
      if (external) {
        _appliedId = null;
        _appliedSelection = null;
        _revision++;
      }
    });
    if (external) {
      ref.read(_binding.chordCommitted.notifier).state = false;
      ref.read(_binding.activeChord.notifier).state = detectFirstChord(_query);
    }
  }

  String _selectionSignature() {
    if (widget.guitar) {
      final state = ref.read(fretboardProvider);
      final cells =
          state.selectedCells.map((c) => '${c.stringIndex}:${c.fret}').toList()
            ..sort();
      return '${_boundsKey()}|${cells.join(',')}';
    }
    final midis =
        ref.read(pianoProvider).selectedKeys.map((k) => k.midiNote).toList()
          ..sort();
    return '${_boundsKey()}|${midis.join(',')}';
  }

  String _boundsKey() {
    if (widget.guitar) {
      final state = ref.read(fretboardProvider);
      return '${state.currentTuning}:${state.capo}:${state.numFrets}';
    }
    return ref.read(pianoProvider).currentRange.name;
  }

  void _chooseChord(String root, String quality) => setState(() {
    _fromNotes = false;
    _root = root;
    _quality = quality;
  });

  Future<void> _apply(int index) async {
    final chord = widget.guitar
        ? _guitarResults[index].chord
        : _pianoResults[index].chord;
    final guitarResult = widget.guitar ? _guitarResults[index] : null;
    final pianoResult = widget.guitar ? null : _pianoResults[index];
    final revision = _revision;
    final bounds = _boundsKey();
    final key = ref.read(activeProjectKeyProvider);
    if (key != null) {
      final outside = chordPitchClassesOutOfKey(
        getChordNotes(chord.root, chord.quality),
        scaleRoot: key.root,
        scaleName: key.scaleName,
      );
      if (outside.isNotEmpty) {
        final spelling = ref.read(settingsProvider).noteSpelling;
        final names = outside
            .map((n) => formatRootChoiceLabel(n, spelling: spelling))
            .join(', ');
        final answer = await showStudioDialog<OutOfKeyResult>(
          context: context,
          builder: (_) => OutOfKeyDialog(
            title: 'Chord outside the key',
            message:
                'This chord contains $names, outside the project key. Apply anyway?',
            showSuppressOption: false,
          ),
        );
        if (answer == null) return;
      }
    }
    if (!mounted ||
        revision != _revision ||
        bounds != _boundsKey() ||
        key != ref.read(activeProjectKeyProvider)) {
      return;
    }
    _applying = true;
    try {
      if (guitarResult != null) {
        ref.read(fretboardProvider.notifier).loadVoicing(guitarResult.voicing);
        ref.read(scrollToFretProvider.notifier).state =
            guitarResult.voicing.baseFret;
      } else if (pianoResult != null) {
        ref.read(pianoProvider.notifier).loadExactMidis(pianoResult.midis);
        ref.read(pianoScrollToMidiProvider.notifier).state =
            pianoResult.midis.first;
      }
      _appliedSelection = _selectionSignature();
      ref.read(_binding.chordCommitted.notifier).state = true;
      ref.read(_binding.activeChord.notifier).state = (
        root: chord.root,
        quality: chord.quality,
      );
      setState(() => _appliedId = guitarResult?.id ?? pianoResult!.id);
    } finally {
      _applying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = StudioPalette.of(context);
    final spelling = ref.watch(settingsProvider.select((s) => s.noteSpelling));
    ref.listen(_binding.exactNotes, (_, _) {
      // Derived Riverpod selection notifications can arrive after load returns.
      // Compare the native realization as well as guarding synchronous writes.
      if (_selectionSignature() == _appliedSelection) return;
      _captureNotes(external: true);
    });
    ref.listen(_binding.manualEdit, (_, _) => _captureNotes(external: true));
    ref.listen(saveSystemProvider.select((s) => s.selectedProjectId), (_, _) {
      setState(() {
        _fromNotes = true;
        _root = 'C';
        _quality = '';
        _appliedId = null;
        _appliedSelection = null;
        _revision++;
      });
      _captureNotes();
    });
    final pending = ref.watch(_binding.pendingChord);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(_binding.pendingChord) != pending) return;
        _chooseChord(pending.root, pending.quality);
        ref.read(_binding.pendingChord.notifier).state = null;
      });
    }
    final activeKey = ref.watch(activeProjectKeyProvider);
    final activeScale = activeKey ?? ref.watch(_binding.activeScale);
    // Watching bounds and scale invalidates results, but applying only changes
    // selection and leaves the captured query intact.
    final bounds = widget.guitar
        ? ref
              .watch(
                fretboardProvider.select(
                  (s) => (s.currentTuning, s.capo, s.numFrets),
                ),
              )
              .toString()
        : ref.watch(pianoProvider.select((s) => s.currentRange)).name;
    final cacheKey =
        '$bounds|${activeScale?.root}:${activeScale?.scaleName}|$_fromNotes|${_fromNotes ? _query.join(',') : '$_root:$_quality'}';
    if (cacheKey != _cacheKey) {
      _cacheKey = cacheKey;
      if (widget.guitar) {
        final state = ref.read(fretboardProvider);
        final midis = tunings[state.currentTuning]!.strings
            .map((s) => s.midiNote)
            .toList();
        _guitarResults = _fromNotes
            ? searchFretboardVoicingsFromNotes(
                requiredPitchClasses: _query,
                stringMidis: midis,
                capo: state.capo,
                numFrets: state.numFrets,
                scaleRoot: activeScale?.root,
                scaleName: activeScale?.scaleName,
              )
            : generateFretboardChordVoicings(
                    root: _root,
                    quality: _quality,
                    stringMidis: midis,
                    capo: state.capo,
                    numFrets: state.numFrets,
                  )
                  .map(
                    (v) => FretboardVoicingCandidate(
                      chord: ChordSearchIdentity(
                        root: _root,
                        quality: _quality,
                      ),
                      voicing: v,
                    ),
                  )
                  .toList();
      } else {
        final range = pianoRanges[ref.read(pianoProvider).currentRange]!;
        _pianoResults = _fromNotes
            ? searchPianoVoicingsFromNotes(
                requiredPitchClasses: _query,
                rangeStartMidi: range.startMidi,
                rangeEndMidi: range.endMidi,
                scaleRoot: activeScale?.root,
                scaleName: activeScale?.scaleName,
              )
            : generatePianoChordVoicings(
                root: _root,
                quality: _quality,
                rangeStartMidi: range.startMidi,
                rangeEndMidi: range.endMidi,
              );
      }
    }
    final count = widget.guitar ? _guitarResults.length : _pianoResults.length;
    final diatonic = activeKey == null
        ? const <DiatonicChord>[]
        : getDiatonicChords(activeKey.root, activeKey.scaleName);
    final textScale = MediaQuery.textScalerOf(context);
    final cardWidth = 16 + textScale.scale(102);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final mode in [true, false])
                Expanded(
                  child: TextButton(
                    key: Key(mode ? 'voicingsFromNotes' : 'voicingsByChord'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      foregroundColor: mode == _fromNotes
                          ? p.onAccent
                          : p.textSecondary,
                      backgroundColor: mode == _fromNotes ? p.sky : p.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => setState(() => _fromNotes = mode),
                    child: Text(mode ? 'From notes' : 'By chord'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_fromNotes) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _query.isEmpty
                        ? 'Select notes to find voicings.'
                        : 'Containing ${_query.map((n) => formatRootChoiceLabel(n, spelling: spelling)).join(' · ')}',
                    key: const Key('voicingNoteQuery'),
                    style: TextStyle(color: p.textPrimary, fontSize: 13),
                  ),
                ),
                IconButton(
                  key: const Key('voicingsUseCurrentNotes'),
                  tooltip: 'Use current notes',
                  onPressed: () => _captureNotes(),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
          ] else
            StudioChordSelectors(
              root: _root,
              quality: _quality,
              qualities: [
                for (final quality in chordIntervals.keys) (quality, quality),
              ],
              onRootChanged: (root) => _chooseChord(root, _quality),
              onQualityChanged: (quality) => _chooseChord(_root, quality),
            ),
          const SizedBox(height: 8),
          Text(
            '$count available voicings · tap to apply',
            key: const Key('voicingResultCount'),
            style: TextStyle(color: p.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (count > 0)
            SizedBox(
              height:
                  (widget.guitar ? 102 : 76) +
                  textScale.scale(widget.guitar ? 44 : 88),
              child: ListView.separated(
                key: const Key('voicingCarousel'),
                controller: _carousel,
                scrollDirection: Axis.horizontal,
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final chord = widget.guitar
                      ? _guitarResults[index].chord
                      : _pianoResults[index].chord;
                  final id = widget.guitar
                      ? _guitarResults[index].id
                      : _pianoResults[index].id;
                  final symbol = formatChordSymbol(
                    ChordDetectionResult(
                      root: chord.root,
                      quality: chord.quality,
                    ),
                    spelling: spelling,
                  );
                  final applied = id == _appliedId;
                  final notes = getChordNotes(chord.root, chord.quality)
                      .map((n) => formatRootChoiceLabel(n, spelling: spelling))
                      .toList();
                  final piano = widget.guitar ? null : _pianoResults[index];
                  final subtitle = widget.guitar
                      ? 'Position ${_guitarResults[index].voicing.baseFret}'
                      : '${piano!.inversion == 0 ? 'Root' : '${piano.inversion} inv'} · ${formatMidiNoteLabel(piano.midis.first, spelling: spelling)}';
                  Widget diagram;
                  if (widget.guitar) {
                    final state = ref.read(fretboardProvider);
                    final voicing = _guitarResults[index].voicing;
                    // The existing diagram draws an open nut; show the capo as
                    // that nut while preserving physical frets in the payload.
                    diagram = ChordDiagram(
                      voicing: ChordVoicing(
                        positions: voicing.positions
                            .map((f) => f == null ? null : f - state.capo)
                            .toList(),
                        baseFret: voicing.baseFret > state.capo
                            ? voicing.baseFret - state.capo
                            : 0,
                      ),
                      rootNote: chord.root,
                      openNotes: tunings[state.currentTuning]!.strings
                          .map(
                            (s) =>
                                chromaticNotes[(s.midiNote + state.capo) % 12],
                          )
                          .toList(),
                      isSelected: applied,
                      onPress: () => _apply(index),
                    );
                  } else {
                    diagram = PianoChordDiagram(
                      midis: piano!.midis,
                      rootPc: noteToPC[chord.root],
                      label: symbol,
                      noteLabels: notes,
                      isSelected: applied,
                      onPress: () => _apply(index),
                    );
                  }
                  return Semantics(
                    button: true,
                    selected: applied,
                    label: '$symbol, $subtitle${applied ? ', Applied' : ''}',
                    onTap: () => _apply(index),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: cardWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              applied ? '✓ Applied' : symbol,
                              key: Key('voicingCard:$id'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: applied ? p.sky : p.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            diagram,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (count == 0 && (!_fromNotes || _query.isNotEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No complete voicings fit. Change the notes, chord or instrument settings.',
                style: TextStyle(color: p.textSecondary),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            widget.guitar
                ? 'Generated shapes within four frets, plus open/capo strings.'
                : 'All registers and ordered inversions within a two-octave span.',
            style: TextStyle(color: p.textMuted, fontSize: 11),
          ),
          if (diatonic.isNotEmpty) ...[
            const SizedBox(height: 8),
            DiatonicChordsRow(
              chords: diatonic,
              selectedRoot: _fromNotes ? null : _root,
              selectedQuality: _quality,
              accent: p.sky,
              onTap: _chooseChord,
            ),
          ],
        ],
      ),
    );
  }
}
