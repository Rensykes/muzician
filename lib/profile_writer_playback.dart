/// Isolated device harness for Writer playback profiling.
///
/// Run with `flutter run --profile -t lib/profile_writer_playback.dart`. Pass
/// `--dart-define=WRITER_PROFILE_SCENARIO=<name>`, `WRITER_PROFILE_TEMPO_BPM`,
/// `WRITER_PROFILE_AUTOSTART=true`, and optionally
/// `WRITER_PROFILE_EXIT_ON_COMPLETE=true` to print one `WRITER_PROFILE_RESULT`
/// JSON line and quit. Load scenarios: `strum_metronome`, `drums_metronome`,
/// `strum_drums`, `strum_drums_metronome`. It
/// replaces Writer/settings providers with synthetic in-memory state and puts
/// its controlled clip under the app's temporary directory. It never hydrates
/// or writes a user project or saved audio file.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/fretboard.dart';
import 'models/harmony_lane_instrument.dart';
import 'models/piano.dart';
import 'models/project_config.dart';
import 'models/save_system.dart';
import 'models/arrangement_content.dart';
import 'models/songwriter.dart';
import 'features/_mockup_shell.dart' show ModeSegment;
import 'features/fretboard/fretboard.dart'
    show FretboardPalette, GuitarFretboard, fretboardBoardHeight;
import 'features/instrument_shared/instrument_screen.dart'
    show InstrumentScreen;
import 'features/piano/piano_keyboard.dart'
    show PianoKeyboard, pianoKeyboardHeight;
import 'features/songwriter/songwriter_screen.dart' show SongwriterScreen;
import 'schema/rules/songwriter_audio_rules.dart';
import 'schema/rules/songwriter_playback_rules.dart';
import 'schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import 'schema/rules/songwriter_rules.dart';
import 'store/fretboard_store.dart';
import 'store/piano_store.dart';
import 'store/save_system_store.dart';
import 'store/settings_store.dart';
import 'store/audio_repository.dart';
import 'store/audio_player_sink.dart';
import 'store/drum_pattern_playback_store.dart';
import 'store/songwriter_audio_sink.dart';
import 'store/songwriter_playback_store.dart';
import 'store/songwriter_store.dart';
import 'theme/muzician_theme.dart';
import 'utils/note_player.dart';
import 'utils/playback_profile_frame_timing.dart';
import 'utils/playback_profiling.dart';
import 'utils/wav_writer.dart';

const _qaAssetId = 'writer_profile_controlled_clip';
const _chord = [60, 64, 67, 71];
const _tempo = int.fromEnvironment(
  'WRITER_PROFILE_TEMPO_BPM',
  defaultValue: 120,
);
const _durationSeconds = int.fromEnvironment(
  'WRITER_PROFILE_DURATION_SECONDS',
  defaultValue: 0,
);
const _beatsPerBar = 4;
const _bars = _durationSeconds <= 0
    ? 8
    : ((_durationSeconds * _tempo + 60 * _beatsPerBar - 1) ~/
          (60 * _beatsPerBar));
const _deviceLabel = String.fromEnvironment(
  'WRITER_PROFILE_DEVICE_LABEL',
  defaultValue: 'unspecified',
);
const _fixtureScenario = String.fromEnvironment(
  'WRITER_PROFILE_SCENARIO',
  defaultValue: 'plain_harmony',
);
const _autoStart = bool.fromEnvironment('WRITER_PROFILE_AUTOSTART');
const _exitOnComplete = bool.fromEnvironment('WRITER_PROFILE_EXIT_ON_COMPLETE');
const _auditionDurationMs = int.fromEnvironment(
  'WRITER_PROFILE_AUDITION_DURATION_MS',
  defaultValue: 1000,
);

enum ProfileViewMode { minimal, writer, fretboard, piano }

extension ProfileViewModeParsing on ProfileViewMode {
  static ProfileViewMode parse(String value) => switch (value) {
    'minimal' => ProfileViewMode.minimal,
    'writer' => ProfileViewMode.writer,
    'fretboard' => ProfileViewMode.fretboard,
    'piano' => ProfileViewMode.piano,
    _ => throw ArgumentError.value(value, 'WRITER_PROFILE_VIEW'),
  };
}

final _profileViewMode = ProfileViewModeParsing.parse(
  const String.fromEnvironment('WRITER_PROFILE_VIEW', defaultValue: 'minimal'),
);

final _profileScenarioProvider = StateProvider<String>(
  (ref) => _fixtureScenario,
);

const _qaProjectId = 'writer_profile_qa_project';
const _qaFretboardSaveId = 'writer_profile_fretboard_cmaj7';
const _qaPianoSaveId = 'writer_profile_piano_cmaj7';
const _qaStrumSaveId = 'writer_profile_fretboard_c13';
const _qaAm7SaveId = 'writer_profile_fretboard_am7';
const _qaFmaj7SaveId = 'writer_profile_fretboard_fmaj7';
const _qaG7SaveId = 'writer_profile_fretboard_g7';

/// One bar per chord, repeated across the fixture (C13 – Am7 – Fmaj7 – G7).
const _qaProgressionSaveIds = [
  _qaStrumSaveId,
  _qaAm7SaveId,
  _qaFmaj7SaveId,
  _qaG7SaveId,
];

// Dense mixed-load scenarios for the Writer playback performance baseline.
// `*_metronome` variants enable the click; every strum scenario assigns one
// sixteenth-note Guitar Strum lane to the progression, every drum scenario
// adds a kick/snare/closed-hi-hat lane with sixteenth-note hats.
const _strumLoadScenarios = {
  'strum_metronome',
  'strum_drums',
  'strum_drums_metronome',
};
const _drumLoadScenarios = {
  'drums_metronome',
  'strum_drums',
  'strum_drums_metronome',
};
const _metronomeScenarios = {
  'strum_metronome',
  'drums_metronome',
  'strum_drums_metronome',
};
const _loadStrumPatternId = 'qa_sixteenth_strum_pattern';
const _loadDrumPatternId = 'qa_sixteenth_hat_pattern';
const _loadDrumHitsPerBar = 20;
const _loadStrumVoicesPerBar = 16 * 6;
const _loadHarmonyStabVoicesPerBar = 6;

const _qaAsset = AudioAsset(
  id: _qaAssetId,
  durationMs: 4000,
  sampleRate: 44100,
  channels: 1,
  format: 'wav',
  peaks: [0, 0, 0, 0],
  sourceLabel: 'Generated temporary QA tone',
);

int _barsFor(int tempo, int durationSeconds) {
  if (durationSeconds <= 0) return 8;
  final numerator = durationSeconds * tempo;
  final denominator = 60 * _beatsPerBar;
  return (numerator + denominator - 1) ~/ denominator;
}

int? _scoreTickLimitFor(int tempo, int durationSeconds) {
  if (durationSeconds <= 0) return null;
  final tickUs = pr_rules.tickDuration(tempo).inMicroseconds;
  return (durationSeconds * Duration.microsecondsPerSecond / tickUs).round();
}

SaveSystemState _saveStateFor(String scenario, {int tempo = _tempo}) {
  final writerBlock = WriterBlockSnapshot(
    laneKind: SongLaneKind.harmony,
    chordSymbol: 'Cmaj7',
    chordQuality: 'maj7',
    chordRootPc: 0,
    chordNotes: const ['C', 'E', 'G', 'B'],
  );
  final fretboardSnapshot = FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: const [
      FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
      FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
      FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
      FretCoordinate(stringIndex: 3, fret: 9, noteName: 'B'),
    ],
    selectedNotes: const ['C', 'E', 'G', 'B'],
    viewMode: FretboardViewMode.exact,
    inputMode: FretboardInputMode.chord,
  );
  final pianoSnapshot = PianoSnapshot(
    currentRange: PianoRangeName.key88,
    selectedKeys: const [
      PianoCoordinate(keyIndex: 39, midiNote: 60, noteName: 'C4'),
      PianoCoordinate(keyIndex: 43, midiNote: 64, noteName: 'E4'),
      PianoCoordinate(keyIndex: 46, midiNote: 67, noteName: 'G4'),
      PianoCoordinate(keyIndex: 50, midiNote: 71, noteName: 'B4'),
    ],
    selectedNotes: const ['C', 'E', 'G', 'B'],
    viewMode: PianoViewMode.exact,
  );
  final strumWriterBlock = WriterBlockSnapshot(
    laneKind: SongLaneKind.harmony,
    chordSymbol: 'C13',
    // C13 is a user-facing label for this six-note native voicing. Keep it as
    // exact Harmony; the current recognized-chord vocabulary has no 13th.
    chordNotes: const ['C', 'E', 'G', 'B', 'D', 'A'],
  );
  final strumFretboardSnapshot = FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: const [
      FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
      FretCoordinate(stringIndex: 1, fret: 0, noteName: 'B'),
      FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
      FretCoordinate(stringIndex: 3, fret: 0, noteName: 'D'),
      FretCoordinate(stringIndex: 4, fret: 0, noteName: 'A'),
      FretCoordinate(stringIndex: 5, fret: 8, noteName: 'C'),
    ],
    selectedNotes: const ['C', 'E', 'G', 'B', 'D', 'A'],
    viewMode: FretboardViewMode.exact,
    inputMode: FretboardInputMode.chord,
  );
  return SaveSystemState(
    folders: [
      SaveFolder(
        id: _qaProjectId,
        name: 'Isolated Writer playback QA',
        createdAt: 1,
        order: 0,
        kind: SaveFolderKind.project,
        projectConfig: ProjectConfig(
          tempo: tempo,
          defaultHarmonyInstrument: scenario == 'piano_harmony'
              ? HarmonyLaneInstrument.piano
              : HarmonyLaneInstrument.fretboard,
        ),
      ),
    ],
    saves: [
      SaveEntry(
        id: _qaFretboardSaveId,
        name: 'Cmaj7 • Chord-mode Fretboard',
        folderId: _qaProjectId,
        snapshot: HarmonyChordSnapshot(
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
          writerBlock: writerBlock,
          instrumentState: fretboardSnapshot,
        ),
        createdAt: 1,
        updatedAt: 1,
        order: 0,
      ),
      SaveEntry(
        id: _qaPianoSaveId,
        name: 'Cmaj7 • Piano selection',
        folderId: _qaProjectId,
        snapshot: HarmonyChordSnapshot(
          harmonyInstrument: HarmonyLaneInstrument.piano,
          writerBlock: writerBlock,
          instrumentState: pianoSnapshot,
        ),
        createdAt: 2,
        updatedAt: 2,
        order: 1,
      ),
      SaveEntry(
        id: _qaStrumSaveId,
        name: 'C13 • Six-note Chord-mode Fretboard',
        folderId: _qaProjectId,
        snapshot: HarmonyChordSnapshot(
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
          writerBlock: strumWriterBlock,
          instrumentState: strumFretboardSnapshot,
        ),
        createdAt: 3,
        updatedAt: 3,
        order: 2,
      ),
      _progressionSave(
        id: _qaAm7SaveId,
        name: 'Am7 • Six-note Chord-mode Fretboard',
        order: 3,
        symbol: 'Am7',
        notes: const ['A', 'C', 'E', 'G'],
        cells: const [
          FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
          FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
          FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
          FretCoordinate(stringIndex: 3, fret: 2, noteName: 'E'),
          FretCoordinate(stringIndex: 4, fret: 0, noteName: 'A'),
          FretCoordinate(stringIndex: 5, fret: 5, noteName: 'A'),
        ],
      ),
      _progressionSave(
        id: _qaFmaj7SaveId,
        name: 'Fmaj7 • Six-note Chord-mode Fretboard',
        order: 4,
        symbol: 'Fmaj7',
        notes: const ['F', 'A', 'C', 'E'],
        cells: const [
          FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
          FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
          FretCoordinate(stringIndex: 2, fret: 2, noteName: 'A'),
          FretCoordinate(stringIndex: 3, fret: 3, noteName: 'F'),
          FretCoordinate(stringIndex: 4, fret: 3, noteName: 'C'),
          FretCoordinate(stringIndex: 5, fret: 1, noteName: 'F'),
        ],
      ),
      _progressionSave(
        id: _qaG7SaveId,
        name: 'G7 • Six-note Chord-mode Fretboard',
        order: 5,
        symbol: 'G7',
        notes: const ['G', 'B', 'D', 'F'],
        cells: const [
          FretCoordinate(stringIndex: 0, fret: 1, noteName: 'F'),
          FretCoordinate(stringIndex: 1, fret: 0, noteName: 'B'),
          FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
          FretCoordinate(stringIndex: 3, fret: 0, noteName: 'D'),
          FretCoordinate(stringIndex: 4, fret: 2, noteName: 'B'),
          FretCoordinate(stringIndex: 5, fret: 3, noteName: 'G'),
        ],
      ),
    ],
    hydrated: true,
    selectedProjectId: _qaProjectId,
  );
}

SaveEntry _progressionSave({
  required String id,
  required String name,
  required int order,
  required String symbol,
  required List<String> notes,
  required List<FretCoordinate> cells,
}) => SaveEntry(
  id: id,
  name: name,
  folderId: _qaProjectId,
  snapshot: HarmonyChordSnapshot(
    harmonyInstrument: HarmonyLaneInstrument.fretboard,
    writerBlock: WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      chordSymbol: symbol,
      chordNotes: notes,
    ),
    instrumentState: FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: cells,
      selectedNotes: notes,
      viewMode: FretboardViewMode.exact,
      inputMode: FretboardInputMode.chord,
    ),
  ),
  createdAt: order + 1,
  updatedAt: order + 1,
  order: order,
);

SongwriterProjectSnapshot _fixtureFor(
  String scenario,
  AudioAsset qaAsset, {
  int tempo = _tempo,
  int bars = _bars,
}) {
  final harmonySaveId = switch (scenario) {
    'piano_harmony' => _qaPianoSaveId,
    'six_note_strum' => _qaStrumSaveId,
    _ => _qaFretboardSaveId,
  };
  final progression = _strumLoadScenarios.contains(scenario);
  final harmonyLane = SongLane(
    id: 'qa_harmony',
    kind: SongLaneKind.harmony,
    order: 0,
    harmonyInstrument: scenario == 'piano_harmony'
        ? HarmonyLaneInstrument.piano
        : HarmonyLaneInstrument.fretboard,
    blocks: [
      for (var bar = 0; bar < bars; bar++)
        SongBlock(
          id: 'qa_chord_$bar',
          startBar: bar,
          spanBars: 1,
          saveId: progression
              ? _qaProgressionSaveIds[bar % _qaProgressionSaveIds.length]
              : harmonySaveId,
        ),
    ],
  );

  final strumLane = SongLane(
    id: 'qa_guitar_strum',
    kind: SongLaneKind.guitarStrum,
    order: 1,
    anchorLaneId: 'qa_harmony',
    blocks: [
      SongBlock(
        id: 'qa_strum_block',
        startBar: 0,
        spanBars: bars,
        patternId: progression ? _loadStrumPatternId : 'qa_strum_pattern',
      ),
    ],
  );
  final drumLane = SongLane(
    id: 'qa_drums',
    kind: SongLaneKind.drum,
    order: 2,
    blocks: [
      SongBlock(
        id: 'qa_drum_block',
        startBar: 0,
        spanBars: bars,
        patternId: _loadDrumPatternId,
      ),
    ],
  );

  final lanes = switch (scenario) {
    'strum_metronome' => [harmonyLane, strumLane],
    'strum_drums' ||
    'strum_drums_metronome' => [harmonyLane, strumLane, drumLane],
    'drums_metronome' => [drumLane.copyWith(order: 0)],
    'six_note_strum' => [
      harmonyLane,
      SongLane(
        id: 'qa_guitar_strum',
        kind: SongLaneKind.guitarStrum,
        order: 1,
        anchorLaneId: 'qa_harmony',
        blocks: [
          SongBlock(
            id: 'qa_strum_block',
            startBar: 0,
            spanBars: bars,
            patternId: 'qa_strum_pattern',
          ),
        ],
      ),
    ],
    'melody' => [
      SongLane(
        id: 'qa_melody',
        kind: SongLaneKind.melody,
        order: 0,
        blocks: [
          SongBlock(
            id: 'qa_melody_block',
            startBar: 0,
            spanBars: bars,
            patternId: 'qa_melody_pattern',
          ),
        ],
      ),
    ],
    'recorded_clip' => [
      harmonyLane.copyWith(
        blocks: [
          SongBlock(
            id: 'qa_clip_companion_chord',
            startBar: 0,
            spanBars: 1,
            saveId: harmonySaveId,
          ),
        ],
      ),
      SongLane(
        id: 'qa_audio_lane',
        kind: SongLaneKind.audio,
        order: 0,
        blocks: [
          SongBlock(
            id: 'qa_audio_block',
            startBar: 0,
            spanBars: bars,
            audioClipId: 'qa_audio_clip',
          ),
        ],
      ),
    ],
    'piano_harmony' => [harmonyLane],
    _ => [harmonyLane],
  };

  return SongwriterProjectSnapshot(
    name: 'Isolated playback profile fixture',
    config: SongwriterConfig(
      tempo: tempo,
      beatsPerBar: _beatsPerBar,
      beatUnit: 4,
      keyRoot: 0,
      keyScaleName: 'major',
    ),
    sections: [
      SongSection(
        id: 'qa_section',
        label: 'QA fixture',
        lengthBars: bars,
        order: 0,
        lanes: lanes,
      ),
    ],
    guitarStrumPatterns: scenario == 'six_note_strum'
        ? const [
            GuitarStrumPattern(
              id: 'qa_strum_pattern',
              name: 'Two six-note strums per bar',
              lengthTicks: 16,
              events: [
                GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
                GuitarStrumEvent(tick: 8, direction: GuitarStrumDirection.up),
              ],
            ),
          ]
        : progression
        ? [
            GuitarStrumPattern(
              id: _loadStrumPatternId,
              name: 'Sixteenth-note strum, alternating down/up',
              lengthTicks: 16,
              events: [
                for (var tick = 0; tick < 16; tick++)
                  GuitarStrumEvent(
                    tick: tick,
                    direction: tick.isEven
                        ? GuitarStrumDirection.down
                        : GuitarStrumDirection.up,
                  ),
              ],
            ),
          ]
        : const [],
    drumPatterns: _drumLoadScenarios.contains(scenario)
        ? [
            DrumPattern(
              id: _loadDrumPatternId,
              name: 'Kick/snare with sixteenth closed hi-hat',
              lengthTicks: 16,
              lanes: [
                const DrumLaneSequence(
                  laneId: DrumLaneId.kick,
                  activeTicks: [0, 8],
                ),
                const DrumLaneSequence(
                  laneId: DrumLaneId.snare,
                  activeTicks: [4, 12],
                ),
                DrumLaneSequence(
                  laneId: DrumLaneId.closedHiHat,
                  activeTicks: [for (var tick = 0; tick < 16; tick++) tick],
                ),
              ],
            ),
          ]
        : const [],
    melodyPatterns: scenario == 'melody'
        ? [
            NotePattern(
              id: 'qa_melody_pattern',
              name: 'Eight notes per bar',
              lengthTicks: 16 * bars,
              notes: [
                for (var bar = 0; bar < bars; bar++)
                  for (var index = 0; index < 8; index++)
                    NotePatternNote(
                      id: 'qa_melody_${bar}_$index',
                      midiNote: 60 + (index % 5) * 2,
                      startTick: bar * 16 + index * 2,
                      durationTicks: 2,
                    ),
              ],
              pitchRangeStart: 60,
              pitchRangeEnd: 72,
              snapTicks: 1,
              highlightedNotes: const [],
            ),
          ]
        : const [],
    audioAssets: scenario == 'recorded_clip' ? [qaAsset] : const [],
    audioClips: scenario == 'recorded_clip'
        ? [
            AudioClip(
              id: 'qa_audio_clip',
              assetId: qaAsset.id,
              fitMode: AudioFitMode.oneShot,
            ),
          ]
        : const [],
  );
}

class _ProfileWriterNotifier extends SongwriterNotifier {
  @override
  SongwriterProjectSnapshot build() =>
      _fixtureFor(ref.watch(_profileScenarioProvider), _qaAsset);
}

class _ProfileSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
    metronomeEnabled: _metronomeScenarios.contains(
      ref.watch(_profileScenarioProvider),
    ),
  );
}

class _ProfileSaveSystemNotifier extends SaveSystemNotifier {
  @override
  SaveSystemState build() =>
      _saveStateFor(ref.watch(_profileScenarioProvider), tempo: _tempo);
}

class _ProfileFretboardNotifier extends FretboardNotifier {
  @override
  FretboardState build() {
    final snapshot =
        _saveStateFor('plain_harmony').saves.first.snapshot
            as HarmonyChordSnapshot;
    final instrument = snapshot.instrumentState as FretboardSnapshot;
    return FretboardState(
      currentTuning: instrument.tuning,
      numFrets: instrument.numFrets,
      capo: instrument.capo,
      highlightedNotes: const [],
      selectedNotes: instrument.selectedNotes,
      selectedCells: instrument.selectedCells,
      viewMode: instrument.viewMode,
      inputMode: instrument.inputMode,
    );
  }
}

class _ProfilePianoNotifier extends PianoNotifier {
  @override
  PianoState build() {
    final snapshot =
        _saveStateFor('piano_harmony').saves[1].snapshot
            as HarmonyChordSnapshot;
    final instrument = snapshot.instrumentState as PianoSnapshot;
    return PianoState(
      currentRange: instrument.currentRange,
      highlightedNotes: const [],
      selectedNotes: instrument.selectedNotes,
      selectedKeys: instrument.selectedKeys,
      viewMode: instrument.viewMode,
    );
  }
}

/// Overrides every state source used by the harness with in-memory fixtures.
/// This lets widget tests mount production pages without calling app bootstrap,
/// SharedPreferences hydration, or the persistent audio repository.
List<Override> buildWriterPlaybackProfileProviderOverrides({
  required AudioRepository repository,
  String scenario = _fixtureScenario,
}) => [
  _profileScenarioProvider.overrideWith((ref) => scenario),
  songwriterProvider.overrideWith(_ProfileWriterNotifier.new),
  settingsProvider.overrideWith(_ProfileSettingsNotifier.new),
  saveSystemProvider.overrideWith(_ProfileSaveSystemNotifier.new),
  fretboardProvider.overrideWith(_ProfileFretboardNotifier.new),
  pianoProvider.overrideWith(_ProfilePianoNotifier.new),
  songwriterAudioRepositoryProvider.overrideWithValue(repository),
  songwriterAudioClipSinkProvider.overrideWith(
    (ref) => AudioPlayersClipSink(ref.read(songwriterAudioRepositoryProvider)),
  ),
];

/// Per fixture: [notes] counts every pitched note and drum hit with each strum
/// stroke expanded into its strings; [voices] counts a stroke as one voice, the
/// way the transport now requests it.
typedef _FixtureCounts = ({Map<String, int> notes, Map<String, int> voices});

_FixtureCounts _verifyFixtures(
  AudioAsset qaAsset, {
  int tempo = _tempo,
  int bars = _bars,
}) {
  if (tempo <= 0 || bars <= 0) {
    throw ArgumentError('Fixture tempo and bar count must be positive.');
  }
  final expectedNotes = {
    'plain_harmony': bars * 4,
    'piano_harmony': bars * 4,
    // Harmony stabs (six per bar) plus two six-note strums per bar.
    'six_note_strum': bars * 18,
    // Harmony stabs + sixteenth-note six-string strokes (+ drum hits).
    'strum_metronome':
        bars * (_loadHarmonyStabVoicesPerBar + _loadStrumVoicesPerBar),
    'drums_metronome': bars * _loadDrumHitsPerBar,
    'strum_drums':
        bars *
        (_loadHarmonyStabVoicesPerBar +
            _loadStrumVoicesPerBar +
            _loadDrumHitsPerBar),
    'strum_drums_metronome':
        bars *
        (_loadHarmonyStabVoicesPerBar +
            _loadStrumVoicesPerBar +
            _loadDrumHitsPerBar),
    'melody': bars * 8,
    'recorded_clip': 4,
  };
  final results = <String, int>{};
  final voices = <String, int>{};
  for (final fixture in expectedNotes.entries) {
    final saveState = _saveStateFor(fixture.key, tempo: tempo);
    final project = _fixtureFor(fixture.key, qaAsset, tempo: tempo, bars: bars);
    final events = flattenPlaybackEvents(
      project,
      saveState.saves,
      projectId: saveState.selectedProjectId,
      folders: saveState.folders,
      projectDefaultHarmonyInstrument:
          saveState.folders.single.projectConfig!.defaultHarmonyInstrument,
    );
    final strokeCount = events.fold<int>(
      0,
      (total, event) => total + event.strokeGroups.length,
    );
    final stringNoteCount = events.fold<int>(
      0,
      (total, event) =>
          total +
          event.strokeGroups.fold<int>(
            0,
            (sum, group) => sum + group.notes.length,
          ),
    );
    final voiceCount =
        events.fold<int>(
          0,
          (total, event) =>
              total +
              event.noteGroups.fold<int>(
                0,
                (sum, group) => sum + group.midiNotes.length,
              ) +
              event.sequencedNoteGroups.fold<int>(
                0,
                (sum, group) => sum + group.notes.length,
              ) +
              event.drumGroups.fold<int>(
                0,
                (sum, group) => sum + group.drumLanes.length,
              ),
        ) +
        stringNoteCount;
    final clips = songwriterSchedulableAudioClips(project);
    if (events.isEmpty || voiceCount != fixture.value) {
      throw StateError(
        'Fixture ${fixture.key} emitted ${events.length} events and '
        '$voiceCount voices; expected non-empty events and '
        '${fixture.value} voices.',
      );
    }
    if (fixture.key == 'recorded_clip' && clips.length != 1) {
      throw StateError(
        'Recorded clip fixture must schedule one temporary clip; got ${clips.length}.',
      );
    }
    if (fixture.key == 'six_note_strum' ||
        _strumLoadScenarios.contains(fixture.key)) {
      final assignedStrums = project.sections
          .expand((section) => section.lanes)
          .where(
            (lane) =>
                lane.kind == SongLaneKind.guitarStrum &&
                lane.anchorLaneId == 'qa_harmony',
          )
          .length;
      if (assignedStrums != 1) {
        throw StateError('Six-note strum fixture needs one assigned source.');
      }
    }
    results[fixture.key] = voiceCount;
    voices[fixture.key] = voiceCount - stringNoteCount + strokeCount;
  }

  final fretboardSnapshot = _saveStateFor(
    'plain_harmony',
    tempo: tempo,
  ).saves.first.snapshot;
  final pianoSnapshot = _saveStateFor(
    'piano_harmony',
    tempo: tempo,
  ).saves[1].snapshot;
  if (fretboardSnapshot is! HarmonyChordSnapshot ||
      !isWriterEligibleHarmonySnapshot(fretboardSnapshot) ||
      pianoSnapshot is! HarmonyChordSnapshot ||
      !isWriterEligibleHarmonySnapshot(pianoSnapshot)) {
    throw StateError(
      'Fixtures require a valid Chord-mode Fretboard and Piano Harmony selection.',
    );
  }
  return (notes: results, voices: voices);
}

/// Pitched notes and drum hits per fixture, strum strokes expanded to strings.
Map<String, int> verifyWriterPlaybackProfileFixtures({
  int tempo = _tempo,
  int durationSeconds = _durationSeconds,
}) => _verifyFixtures(
  _qaAsset,
  tempo: tempo,
  bars: _barsFor(tempo, durationSeconds),
).notes;

/// Voices per fixture with each strum stroke counted once, as requested.
Map<String, int> verifyWriterPlaybackProfileFixtureVoices({
  int tempo = _tempo,
  int durationSeconds = _durationSeconds,
}) => _verifyFixtures(
  _qaAsset,
  tempo: tempo,
  bars: _barsFor(tempo, durationSeconds),
).voices;

/// Fixed musical schedule and expected overlap for one harness run.
/// This manifest is written beside the generated QA audio in the isolated
/// temporary run directory, never into app documents or saved projects.
Map<String, Object?> buildWriterPlaybackProfileManifest({
  required String scenario,
  int tempo = _tempo,
  int durationSeconds = _durationSeconds,
  String? runTag,
}) {
  if (tempo <= 0) throw ArgumentError.value(tempo, 'tempo');
  if (!{
    'plain_harmony',
    'piano_harmony',
    'six_note_strum',
    'strum_metronome',
    'drums_metronome',
    'strum_drums',
    'strum_drums_metronome',
    'melody',
    'recorded_clip',
  }.contains(scenario)) {
    throw ArgumentError.value(scenario, 'scenario');
  }
  final bars = _barsFor(tempo, durationSeconds);
  final saveState = _saveStateFor(scenario, tempo: tempo);
  final project = _fixtureFor(scenario, _qaAsset, tempo: tempo, bars: bars);
  final events = flattenPlaybackEvents(
    project,
    saveState.saves,
    projectId: saveState.selectedProjectId,
    folders: saveState.folders,
    projectDefaultHarmonyInstrument:
        saveState.folders.single.projectConfig!.defaultHarmonyInstrument,
  );
  final tickDuration = pr_rules.tickDuration(tempo);
  final tickDurationUs = tickDuration.inMicroseconds;
  final scoreTickCount =
      _scoreTickLimitFor(tempo, durationSeconds) ??
      bars * project.config.measureTicks;
  final scheduledEvents = events
      .where((event) => event.tick < scoreTickCount)
      .toList(growable: false);
  final schedule = <Map<String, Object?>>[];
  final overlapEdges = <(int, int)>[];
  final offsetCounts = <String, int>{};
  var strokeCount = 0;
  var stringNoteCount = 0;

  void addVoice({
    required int eventId,
    required int tick,
    required int midi,
    required int offsetUs,
    required int durationUs,
    required String kind,
  }) {
    final onsetUs = tick * tickDurationUs + offsetUs;
    schedule.add({
      'event_id': eventId,
      'score_tick': tick,
      'midi': midi,
      'kind': kind,
      'onset_offset_us': offsetUs,
      'intended_onset_us': onsetUs,
      'duration_us': durationUs,
    });
    overlapEdges
      ..add((onsetUs, 1))
      ..add((onsetUs + durationUs, -1));
    final offsetMs = offsetUs ~/ 1000;
    offsetCounts.update('$offsetMs', (count) => count + 1, ifAbsent: () => 1);
  }

  for (final entry in scheduledEvents.asMap().entries) {
    final eventId = entry.key;
    final event = entry.value;
    for (final group in event.noteGroups) {
      for (final midi in group.midiNotes) {
        addVoice(
          eventId: eventId,
          tick: event.tick,
          midi: midi,
          offsetUs: 0,
          durationUs: 700000,
          kind: 'preview',
        );
      }
    }
    for (final group in event.sequencedNoteGroups) {
      for (final note in group.notes) {
        addVoice(
          eventId: eventId,
          tick: event.tick,
          midi: note.midiNote,
          offsetUs: note.onsetOffsetMs * 1000,
          durationUs: pr_rules
              .effectiveSequencedNoteDuration(tickDuration, note)
              .inMicroseconds,
          kind: 'sequenced',
        );
      }
    }
    for (final group in event.strokeGroups) {
      strokeCount++;
      for (final note in group.notes) {
        stringNoteCount++;
        addVoice(
          eventId: eventId,
          tick: event.tick,
          midi: note.midiNote,
          offsetUs: note.onsetOffsetMs * 1000,
          durationUs: pr_rules
              .effectiveSequencedNoteDuration(tickDuration, note)
              .inMicroseconds,
          kind: 'strum_string',
        );
      }
    }
  }

  overlapEdges.sort((a, b) {
    final onsetOrder = a.$1.compareTo(b.$1);
    return onsetOrder != 0 ? onsetOrder : a.$2.compareTo(b.$2);
  });
  var activeVoices = 0;
  var expectedMaxOverlap = 0;
  for (final edge in overlapEdges) {
    activeVoices += edge.$2;
    if (activeVoices > expectedMaxOverlap) {
      expectedMaxOverlap = activeVoices;
    }
  }
  final actualDurationUs = scoreTickCount * tickDurationUs;
  final expectedClipCount = songwriterSchedulableAudioClips(project).length;

  return {
    'schema_version': 1,
    'run_tag': runTag,
    'fixture': scenario,
    'build_mode': kProfileMode
        ? 'profile'
        : kDebugMode
        ? 'debug'
        : 'release',
    'device_label': _deviceLabel,
    'tempo_bpm': tempo,
    'duration_seconds_requested': durationSeconds > 0 ? durationSeconds : null,
    'bars': bars,
    'ticks_per_bar': project.config.measureTicks,
    'score_duration_us': actualDurationUs,
    'score_tick_count': scoreTickCount,
    'expected_event_count': scheduledEvents.length,
    // Every scheduled note below, with each strum stroke's strings counted
    // individually; the transport sounds a stroke as one voice.
    'expected_note_count': schedule.length,
    'expected_stroke_count': strokeCount,
    'expected_string_note_count': stringNoteCount,
    'expected_voice_count': schedule.length - stringNoteCount + strokeCount,
    'expected_drum_hit_count': scheduledEvents.fold<int>(
      0,
      (total, event) =>
          total +
          event.drumGroups.fold<int>(
            0,
            (sum, group) => sum + group.drumLanes.length,
          ),
    ),
    'metronome_enabled': _metronomeScenarios.contains(scenario),
    'expected_max_note_overlap': expectedMaxOverlap,
    'preview_voice_duration_us': 700000,
    'onset_offset_counts': offsetCounts,
    'scheduled_voices': schedule,
    'expected_clip_count': expectedClipCount,
    if (scenario == 'recorded_clip')
      'controlled_clip': {
        'asset_id': _qaAsset.id,
        'duration_ms': _qaAsset.durationMs,
        'expected_file_bytes': 44 + 44100 * 4 * 2,
        'format': _qaAsset.format,
      },
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Text('Playback profiling is disabled in release builds.'),
          ),
        ),
      ),
    );
    return;
  }
  final temporaryDirectory = await getTemporaryDirectory();
  final runDirectory = Directory(
    p.join(
      temporaryDirectory.path,
      'muzician_writer_profile_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await runDirectory.create(recursive: true);
  final repository = AudioRepository.testWith(
    rootDirectory: runDirectory,
    subdir: 'songwriter_audio',
  );
  final clipFile = await repository.resolvePath(_qaAssetId, 'wav');
  final qaTone = _writeQaTone();
  await clipFile.writeAsBytes(qaTone);
  final fixtureMetrics = verifyWriterPlaybackProfileFixtures();
  final fixtureVoices = verifyWriterPlaybackProfileFixtureVoices();
  final runTag = p.basename(runDirectory.path);
  final startupManifest = <String, Object?>{
    ...buildWriterPlaybackProfileManifest(
      scenario: _fixtureScenario,
      runTag: runTag,
    ),
    'profile_view': _profileViewMode.name,
  };
  await File(
    p.join(runDirectory.path, 'fixture_schedule_manifest.json'),
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(startupManifest));
  await NotePlayer.instance.init(tempDirectoryOverride: runDirectory.path);
  playbackProfileInstant(
    'writer.qa_fixture.ready',
    arguments: {
      'fixture': 'isolated_writer_profile',
      'scenario': _fixtureScenario,
      'tempo_bpm': _tempo,
      'bars': _bars,
      'expected_note_count': fixtureMetrics[_fixtureScenario],
      'expected_voice_count': fixtureVoices[_fixtureScenario],
      'clip_bytes': await clipFile.length(),
      'build_mode': kProfileMode ? 'profile' : 'debug',
      'run_tag': runTag,
      'duration_seconds_requested': _durationSeconds > 0
          ? _durationSeconds
          : null,
    },
  );

  runApp(
    ProviderScope(
      overrides: [
        ...buildWriterPlaybackProfileProviderOverrides(repository: repository),
        ...buildWriterPlaybackProfileSinkProbeOverrides(),
      ],
      child: WriterPlaybackProfileApp(
        runDirectory: runDirectory,
        viewMode: _profileViewMode,
      ),
    ),
  );
}

/// Harness-side dispatch timing, independent of [PlaybackProfileRunStats].
///
/// The run stats expose only p95/worst-case dispatch errors. This probe keeps
/// raw samples so the baseline can report p50/p95/max and first-bar versus
/// steady-state behaviour. Ticks are observed when the transport publishes
/// `currentTick`; events are observed when the transport calls each production
/// sink (the wrapped sink then delegates to the real production sink). Both are
/// measured against the first observed tick, so they are relative dispatch
/// errors and never an audible-onset measurement.
class _DispatchProbe {
  final Stopwatch _clock = Stopwatch();
  final List<({int tick, int errorUs})> _ticks = [];
  final List<({String kind, int tick, int errorUs})> _sinkCalls = [];
  int? _firstTick;
  int? _lastTick;
  int _originUs = 0;

  void reset() {
    _ticks.clear();
    _sinkCalls.clear();
    _firstTick = null;
    _lastTick = null;
    _clock
      ..reset()
      ..start();
  }

  void observeTransport(SongwriterPlaybackState state) {
    final tick = state.currentTick;
    if (state.status != SongwriterPlaybackStatus.playing || tick == null) {
      return;
    }
    if (tick == _lastTick) {
      // The run is claimed before voice preparation and republishes its start
      // tick when the clock starts; the last republish is the true origin.
      if (_ticks.length == 1) {
        _originUs = _clock.elapsedMicroseconds;
        _ticks[0] = (tick: tick, errorUs: 0);
      }
      return;
    }
    final nowUs = _clock.elapsedMicroseconds;
    if (_firstTick == null) {
      _firstTick = tick;
      _originUs = nowUs;
    }
    _lastTick = tick;
    _ticks.add((tick: tick, errorUs: _errorUs(tick, nowUs)));
  }

  void observeSink(String kind, int? tick) {
    if (_firstTick == null || tick == null) return;
    _sinkCalls.add((
      kind: kind,
      tick: tick,
      errorUs: _errorUs(tick, _clock.elapsedMicroseconds),
    ));
  }

  int _errorUs(int tick, int nowUs) =>
      nowUs -
      _originUs -
      (tick - _firstTick!) * pr_rules.tickDuration(_tempo).inMicroseconds;

  Map<String, Object?> summary() {
    final firstTick = _firstTick;
    if (firstTick == null) return {'available': false};
    final ticksPerBar = 16;
    bool firstBar(int tick) => tick - firstTick < ticksPerBar;

    final firstCallByTick = <int, int>{};
    final lastCallByTick = <int, int>{};
    for (final call in _sinkCalls) {
      firstCallByTick.putIfAbsent(call.tick, () => call.errorUs);
      lastCallByTick[call.tick] = call.errorUs;
    }
    final kinds = {for (final call in _sinkCalls) call.kind};
    return {
      'available': true,
      'method':
          'Relative to the first observed tick. Tick = transport currentTick notification; '
          'event = first production-sink call per tick; sink_spread = last minus first '
          'sink call within one tick (time spent inside synchronous sinks).',
      'tick_dispatch_error_us': _stats([for (final t in _ticks) t.errorUs]),
      'tick_dispatch_error_first_bar_us': _stats([
        for (final t in _ticks)
          if (firstBar(t.tick)) t.errorUs,
      ]),
      'tick_dispatch_error_steady_us': _stats([
        for (final t in _ticks)
          if (!firstBar(t.tick)) t.errorUs,
      ]),
      'event_dispatch_error_us': _stats(firstCallByTick.values.toList()),
      'event_dispatch_error_first_bar_us': _stats([
        for (final e in firstCallByTick.entries)
          if (firstBar(e.key)) e.value,
      ]),
      'event_dispatch_error_steady_us': _stats([
        for (final e in firstCallByTick.entries)
          if (!firstBar(e.key)) e.value,
      ]),
      'sink_spread_us': _stats([
        for (final e in firstCallByTick.entries)
          lastCallByTick[e.key]! - e.value,
      ]),
      'sink_call_error_by_kind_us': {
        for (final kind in kinds)
          kind: _stats([
            for (final call in _sinkCalls)
              if (call.kind == kind) call.errorUs,
          ]),
      },
      'worst_ticks': [
        for (final t in ([
          ..._ticks,
        ]..sort((a, b) => b.errorUs - a.errorUs)).take(8))
          {'tick': t.tick, 'error_us': t.errorUs},
      ],
    };
  }

  static Map<String, Object?> _stats(List<int> values) {
    if (values.isEmpty) return {'count': 0};
    int over(int thresholdUs) => values.where((v) => v > thresholdUs).length;
    return {
      'count': values.length,
      'p50': playbackProfilePercentile(values, 0.5),
      'p95': playbackProfilePercentile(values, 0.95),
      'max': values.reduce(math.max),
      'over_5ms': over(5000),
      'over_10ms': over(10000),
      'over_20ms': over(20000),
    };
  }
}

final _dispatchProbe = _DispatchProbe();

/// Wraps every transport sink with a timing observation that delegates to the
/// unmodified production sink. The production sink is built by a separate
/// container with the same settings so these wrappers never copy its logic.
List<Override> buildWriterPlaybackProfileSinkProbeOverrides({
  String scenario = _fixtureScenario,
}) {
  final production = ProviderContainer(
    overrides: [
      _profileScenarioProvider.overrideWith((ref) => scenario),
      settingsProvider.overrideWith(_ProfileSettingsNotifier.new),
    ],
  );
  int? currentTick(Ref ref) => ref.read(songwriterPlaybackProvider).currentTick;
  // Riverpod forbids reading another container from inside a provider build.
  final innerMetronome = production.read(songwriterMetronomeSinkProvider);
  final innerChord = production.read(songwriterNoteSinkProvider);
  final innerGuitarChord = production.read(songwriterGuitarNoteSinkProvider);
  final innerSequenced = production.read(songwriterSequencedNoteSinkProvider);
  final innerGuitarSequenced = production.read(
    songwriterGuitarSequencedNoteSinkProvider,
  );
  final innerDrums = production.read(drumPatternPlaybackSinkProvider);
  final innerStroke = production.read(songwriterGuitarStrokeSinkProvider);
  return [
    songwriterGuitarStrokeSinkProvider.overrideWith((ref) {
      final inner = innerStroke;
      return ({required strings, required volume, required pan, guitarTone}) {
        _dispatchProbe.observeSink('guitar_strum_stroke', currentTick(ref));
        inner(
          strings: strings,
          volume: volume,
          pan: pan,
          guitarTone: guitarTone,
        );
      };
    }),
    songwriterMetronomeSinkProvider.overrideWith((ref) {
      final inner = innerMetronome;
      return ({required accent}) {
        _dispatchProbe.observeSink('metronome', currentTick(ref));
        return inner(accent: accent);
      };
    }),
    songwriterNoteSinkProvider.overrideWith((ref) {
      final inner = innerChord;
      return (midiNotes, volume, pan, {duration}) {
        _dispatchProbe.observeSink('chord', currentTick(ref));
        inner(midiNotes, volume, pan, duration: duration);
      };
    }),
    songwriterGuitarNoteSinkProvider.overrideWith((ref) {
      final inner = innerGuitarChord;
      return (midiNotes, volume, pan, {duration}) {
        _dispatchProbe.observeSink('guitar_chord', currentTick(ref));
        inner(midiNotes, volume, pan, duration: duration);
      };
    }),
    songwriterSequencedNoteSinkProvider.overrideWith((ref) {
      final inner = innerSequenced;
      return ({
        required midiNote,
        required duration,
        required onsetDelay,
        required volume,
        required pan,
      }) {
        _dispatchProbe.observeSink('sequenced_note', currentTick(ref));
        inner(
          midiNote: midiNote,
          duration: duration,
          onsetDelay: onsetDelay,
          volume: volume,
          pan: pan,
        );
      };
    }),
    songwriterGuitarSequencedNoteSinkProvider.overrideWith((ref) {
      final inner = innerGuitarSequenced;
      return ({
        required midiNote,
        required duration,
        required onsetDelay,
        required volume,
        required pan,
        guitarTone,
      }) {
        _dispatchProbe.observeSink('guitar_strum_note', currentTick(ref));
        inner(
          midiNote: midiNote,
          duration: duration,
          onsetDelay: onsetDelay,
          volume: volume,
          pan: pan,
          guitarTone: guitarTone,
        );
      };
    }),
    drumPatternPlaybackSinkProvider.overrideWith((ref) {
      final inner = innerDrums;
      return (lanes, volume, pan) {
        _dispatchProbe.observeSink('drums', currentTick(ref));
        return inner(lanes, volume, pan);
      };
    }),
  ];
}

Uint8List _writeQaTone() {
  const sampleRate = 44100;
  const durationSeconds = 4;
  final samples = Int16List(sampleRate * durationSeconds);
  for (var sample = 0; sample < samples.length; sample++) {
    final t = sample / sampleRate;
    final envelope = math.min(1.0, t * 20) * math.max(0.0, 1.0 - t / 5);
    samples[sample] = (math.sin(2 * math.pi * 220 * t) * envelope * 12000)
        .round();
  }
  return writeWavPcm16Mono(samples, sampleRate: sampleRate);
}

class WriterPlaybackProfileApp extends StatelessWidget {
  const WriterPlaybackProfileApp({
    required this.runDirectory,
    this.viewMode = ProfileViewMode.minimal,
    super.key,
  });

  final Directory runDirectory;
  final ProfileViewMode viewMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Writer playback profile harness',
    debugShowCheckedModeBanner: false,
    theme: MuzicianTheme.dark(),
    home: _ProfilePage(runDirectory: runDirectory, viewMode: viewMode),
  );
}

class _ProfilePage extends ConsumerStatefulWidget {
  const _ProfilePage({required this.runDirectory, required this.viewMode});

  final Directory runDirectory;
  final ProfileViewMode viewMode;

  @override
  ConsumerState<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<_ProfilePage> {
  bool _autoStartQueued = false;
  late final PlaybackProfileFrameTimingCapture _frameTimingCapture;
  late final PlaybackProfileFrameTimingWindow _frameTimingWindow;
  int _nextFrameSampleId = 0;
  final Map<int, _ProfileFrameSampleAttempt> _writerFrameAttempts = {};
  final Map<int, Map<String, Object?>> _frameTimingReportsByRunId = {};
  _ProfileFrameSampleAttempt? _activeTransportFrameAttempt;
  _ProfileFrameSampleAttempt? _activeCaptureFrameAttempt;
  _ProfileFrameSampleAttempt? _activeNativeAuditionAttempt;
  Timer? _nativeAuditionTimer;

  @override
  void initState() {
    super.initState();
    _frameTimingCapture = PlaybackProfileFrameTimingCapture()..attach();
    _frameTimingWindow = PlaybackProfileFrameTimingWindow(_frameTimingCapture);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoStart && !_autoStartQueued) {
      _autoStartQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (widget.viewMode) {
          case ProfileViewMode.minimal:
            unawaited(_startPlayback());
            break;
          case ProfileViewMode.writer:
            unawaited(
              ref
                  .read(songwriterPlaybackProvider.notifier)
                  .startPlayback(
                    scoreTickLimit: _scoreTickLimitFor(
                      _tempo,
                      _durationSeconds,
                    ),
                  ),
            );
            break;
          case ProfileViewMode.fretboard || ProfileViewMode.piano:
            _startNativeAudition();
            break;
        }
      });
    }
  }

  void _transportStatusChanged({
    required String view,
    required String? previous,
    required String next,
  }) {
    if (next == 'playing' && previous != 'playing') {
      final writerRun = view == 'writer' || view == 'writer_minimal'
          ? ref.read(songwriterPlaybackProfileRunProvider)
          : null;
      final attempt = writerRun == null
          ? _newFrameSampleAttempt(sampleKind: '${view}_transport')
          : _registerWriterFrameAttempt(writerRun);
      _activeTransportFrameAttempt = attempt;
      _beginFrameSample(attempt);
    } else if (previous == 'playing' && next != 'playing') {
      final attempt = _activeTransportFrameAttempt;
      _activeTransportFrameAttempt = null;
      if (attempt != null) {
        unawaited(
          _finishFrameSample(attempt, reason: 'transport_status_$next'),
        );
      }
    }
  }

  _ProfileFrameSampleAttempt _newFrameSampleAttempt({
    required String sampleKind,
    Map<String, Object?> additionalMetadata = const {},
    PlaybackProfileRunStats? writerRun,
  }) {
    final registeredAt = DateTime.now();
    final attempt = _ProfileFrameSampleAttempt(
      id: ++_nextFrameSampleId,
      runTag: p.basename(widget.runDirectory.path),
      scenario: ref.read(_profileScenarioProvider),
      viewMode: widget.viewMode,
      sampleKind: sampleKind,
      registeredAt: registeredAt,
      writerRun: writerRun,
      additionalMetadata: Map.unmodifiable(additionalMetadata),
    );
    attempt.metadata = {
      'schema_version': 1,
      'profile_attempt_id': attempt.id,
      'profile_run_id': ?writerRun?.runId,
      'run_tag': attempt.runTag,
      'profile_view': attempt.viewMode.name,
      'sample_kind': attempt.sampleKind,
      'scenario': attempt.scenario,
      'build_mode': kProfileMode ? 'profile' : 'debug',
      'profile_run_registered_utc': registeredAt.toUtc().toIso8601String(),
      'fixture_schedule_manifest': 'fixture_schedule_manifest.json',
      'timing_scope':
          'FrameTiming build/raster samples accepted only while this explicit transport or audition window is active. This is not an audible-onset measurement.',
      'frame_timing_clock_provenance':
          'Window bounds use DateTime system-clock epoch and are compared only with FramePhase.rasterFinishWallTime, which Flutter documents as correlatable with system time. Build and raster costs use duration differences.',
      ...additionalMetadata,
    };
    return attempt;
  }

  _ProfileFrameSampleAttempt _registerWriterFrameAttempt(
    PlaybackProfileRunStats writerRun,
  ) => _writerFrameAttempts.putIfAbsent(
    writerRun.runId,
    () => _newFrameSampleAttempt(
      sampleKind: '${widget.viewMode.name}_transport',
      writerRun: writerRun,
    ),
  );

  void _writerProfileRunChanged(
    PlaybackProfileRunStats? previous,
    PlaybackProfileRunStats? next,
  ) {
    if (mounted && next != null && !identical(previous, next)) {
      _registerWriterFrameAttempt(next);
    }
  }

  void _beginFrameSample(_ProfileFrameSampleAttempt attempt) {
    if (attempt.sampleStarted || attempt.completed) return;
    final sampleStarted = DateTime.now();
    final timingAttempt = _frameTimingWindow.start(
      wallTime: sampleStarted,
      owner: attempt,
    );
    attempt
      ..sampleStarted = true
      ..timingAttempt = timingAttempt;
    if (timingAttempt.captureStarted) {
      _activeCaptureFrameAttempt = attempt;
    } else {
      attempt.unavailableReason = timingAttempt.unavailableReason;
    }
    final view = View.of(context);
    final displayRate = view.display.refreshRate;
    final refreshRate = displayRate.isFinite && displayRate > 0
        ? displayRate
        : null;
    final scale = view.devicePixelRatio;
    final logicalWidth = view.physicalSize.width / scale;
    final logicalHeight = view.physicalSize.height / scale;
    attempt.metadata = {
      ...attempt.metadata,
      'profile_attempt_id': attempt.id,
      'profile_run_id': ?attempt.writerRun?.runId,
      'run_tag': attempt.runTag,
      'profile_view': attempt.viewMode.name,
      'sample_kind': attempt.sampleKind,
      'scenario': attempt.scenario,
      'build_mode': kProfileMode ? 'profile' : 'debug',
      'device_label': _deviceLabel,
      'platform': defaultTargetPlatform.name,
      'display_id': view.display.id,
      'display_refresh_rate_hz': refreshRate,
      'physical_width': view.physicalSize.width,
      'physical_height': view.physicalSize.height,
      'logical_width': logicalWidth,
      'logical_height': logicalHeight,
      'device_pixel_ratio': scale,
      'sample_started_utc': sampleStarted.toUtc().toIso8601String(),
      if (attempt.unavailableReason != null)
        'frame_capture_start_status': attempt.unavailableReason,
      ...attempt.additionalMetadata,
    };
    playbackProfileInstant(
      timingAttempt.captureStarted
          ? 'writer.qa.frame_sample_started'
          : 'writer.qa.frame_sample_unavailable',
      arguments: {
        'profile_attempt_id': attempt.id,
        'profile_run_id': attempt.writerRun?.runId,
        'run_tag': attempt.runTag,
        'scenario': attempt.scenario,
        'build_mode': kProfileMode ? 'profile' : 'debug',
        'sample_kind': attempt.sampleKind,
        'profile_view': attempt.viewMode.name,
        'capture_started': timingAttempt.captureStarted,
        'capture_unavailable_reason': timingAttempt.unavailableReason,
        'refresh_rate_hz': refreshRate,
        'device_label': _deviceLabel,
      },
    );
  }

  Future<Map<String, Object?>> _finishFrameSample(
    _ProfileFrameSampleAttempt attempt, {
    required String reason,
  }) async {
    if (attempt.completed) {
      return attempt.report ?? const <String, Object?>{};
    }
    if (attempt.finishing) return attempt.completion.future;
    attempt.finishing = true;
    final sampleEnded = DateTime.now();
    final metadata = Map<String, Object?>.of(attempt.metadata);
    final viewMode = attempt.viewMode;
    final runDirectory = widget.runDirectory;
    final refreshRate = (metadata['display_refresh_rate_hz'] as num?)
        ?.toDouble();
    final timingAttempt = attempt.timingAttempt;
    final summary = timingAttempt == null
        ? PlaybackProfileFrameSummary.unavailable(
            reason:
                attempt.unavailableReason ??
                'transport_never_entered_playing_window',
            timingWindowStartWallUs:
                attempt.registeredAt.microsecondsSinceEpoch,
            timingWindowEndWallUs: sampleEnded.microsecondsSinceEpoch,
          )
        : await _frameTimingWindow.stop(
            timingAttempt,
            refreshRateHz: refreshRate,
            wallTime: sampleEnded,
          );
    if (identical(_activeCaptureFrameAttempt, attempt)) {
      _activeCaptureFrameAttempt = null;
    }
    if (identical(_activeTransportFrameAttempt, attempt)) {
      _activeTransportFrameAttempt = null;
    }
    if (identical(_activeNativeAuditionAttempt, attempt)) {
      _activeNativeAuditionAttempt = null;
      _nativeAuditionTimer?.cancel();
      _nativeAuditionTimer = null;
    }
    final report = <String, Object?>{
      ...metadata,
      'profile_attempt_id': attempt.id,
      'profile_run_id': ?attempt.writerRun?.runId,
      'run_tag': metadata['run_tag'] ?? attempt.runTag,
      'profile_view': metadata['profile_view'] ?? viewMode.name,
      'sample_kind': metadata['sample_kind'] ?? attempt.sampleKind,
      'scenario': metadata['scenario'] ?? attempt.scenario,
      'frame_capture_start_status':
          metadata['frame_capture_start_status'] ??
          attempt.unavailableReason ??
          (attempt.sampleStarted
              ? 'capture_started'
              : 'transport_never_entered_playing_window'),
      'sample_ended_utc': sampleEnded.toUtc().toIso8601String(),
      'sample_end_reason': reason,
      'late_timing_callback_policy':
          'FrameTiming batches are accepted through the ordered post-window frame fence only when raster-finish wall time is within the closed active sample window. The fence frame and all later frames are excluded. Timeout exports an incomplete capture and disables frame-budget evaluation.',
      'frame_timing': summary.toJson(),
      'writer_voice_outcomes': ?attempt.writerRun?.toJson(),
    };
    await _writeFrameTimingReport(
      report,
      runDirectory: runDirectory,
      viewMode: viewMode,
      attemptId: attempt.id,
    );
    if (attempt.writerRun case final writerRun?) {
      _frameTimingReportsByRunId[writerRun.runId] = report;
    }
    attempt
      ..completed = true
      ..report = report;
    if (!attempt.completion.isCompleted) attempt.completion.complete(report);
    playbackProfileInstant(
      'writer.qa.frame_sample_finished',
      arguments: {
        'sample_kind': metadata['sample_kind'],
        'profile_view': viewMode.name,
        'profile_attempt_id': attempt.id,
        'profile_run_id': attempt.writerRun?.runId,
        'run_tag': attempt.runTag,
        'scenario': attempt.scenario,
        'build_mode': kProfileMode ? 'profile' : 'debug',
        'capture_started': timingAttempt?.captureStarted ?? false,
        'frame_count': summary.frameCount,
        'missed_budget_fraction': summary.missedBudgetFraction,
      },
    );
    return report;
  }

  Future<void> _writeFrameTimingReport(
    Map<String, Object?> report, {
    required Directory runDirectory,
    required ProfileViewMode viewMode,
    required int attemptId,
  }) async {
    final kind = report['sample_kind'] as String? ?? 'sample';
    final fileName = 'frame_timing_${kind}_$attemptId.json';
    try {
      await File(
        p.join(runDirectory.path, fileName),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      playbackProfileInstant(
        'writer.qa.frame_report_exported',
        arguments: {
          'path': fileName,
          'sample_kind': kind,
          'profile_view': viewMode.name,
          'profile_attempt_id': attemptId,
          'profile_run_id': report['profile_run_id'],
          'run_tag': report['run_tag'],
          'scenario': report['scenario'],
          'build_mode': report['build_mode'],
        },
      );
    } catch (_) {
      // A failed diagnostic export must not change transport/UI behavior.
    }
  }

  void _startNativeAudition() {
    final midiNotes = List<int>.unmodifiable(_chord);
    final attempt = _newFrameSampleAttempt(
      sampleKind: 'native_instrument_audition',
      additionalMetadata: {
        'midi_notes': midiNotes,
        'midi_note_count': midiNotes.length,
        'note_launch_path':
            'shared NotePlayer.previewNote path used by production Fretboard and Piano boards',
        'audition_window_ms': _auditionDurationMs,
        'fixture_voice_schedule_matches': true,
      },
    );
    _activeNativeAuditionAttempt = attempt;
    _beginFrameSample(attempt);
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6);
    }
    _nativeAuditionTimer = Timer(
      Duration(milliseconds: _auditionDurationMs),
      () => unawaited(
        _finishFrameSample(attempt, reason: 'audition_window_elapsed'),
      ),
    );
  }

  Future<void> _startPlayback() async {
    final runDirectory = widget.runDirectory;
    final scenario = ref.read(_profileScenarioProvider);
    final runTag = p.basename(runDirectory.path);
    final manifest = buildWriterPlaybackProfileManifest(
      scenario: scenario,
      runTag: runTag,
    );
    await File(
      p.join(
        runDirectory.path,
        'fixture_schedule_${scenario}_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    if (!mounted) return;
    playbackProfileInstant(
      'writer.qa.play_pressed',
      arguments: {
        'scenario': scenario,
        'tempo_bpm': _tempo,
        'bars': _bars,
        'duration_seconds_requested': _durationSeconds > 0
            ? _durationSeconds
            : null,
        'score_tick_limit': _scoreTickLimitFor(_tempo, _durationSeconds),
        'run_tag': runTag,
      },
    );
    Object? playbackError;
    PlaybackProfileRunStats? profileRun;
    _ProfileFrameSampleAttempt? frameAttempt;
    _dispatchProbe.reset();
    try {
      final playbackFuture = ref
          .read(songwriterPlaybackProvider.notifier)
          .startPlayback(
            scoreTickLimit: _scoreTickLimitFor(_tempo, _durationSeconds),
          );
      // startPlayback publishes its run object before its first await. Retain
      // that object now so a rapid restart cannot replace the outcomes used by
      // this attempt's delayed export.
      profileRun = ref.read(songwriterPlaybackProfileRunProvider);
      if (profileRun != null) {
        frameAttempt = _registerWriterFrameAttempt(profileRun);
      }
      await playbackFuture;
    } catch (error) {
      playbackError = error;
      rethrow;
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final attempt = frameAttempt;
      if (attempt != null && !attempt.sampleStarted && !attempt.finishing) {
        await _finishFrameSample(
          attempt,
          reason: 'transport_finished_without_playing_window',
        );
      }
      Map<String, Object?>? frameReport =
          attempt?.report ??
          (profileRun == null
              ? null
              : _frameTimingReportsByRunId[profileRun.runId]);
      if (attempt != null && !attempt.completed) {
        try {
          frameReport = await attempt.completion.future.timeout(
            const Duration(milliseconds: 1800),
          );
        } on TimeoutException {
          // Keep the run report bound to its attempt; an unfinished frame
          // export remains absent rather than borrowing a newer report.
        }
      }
      final stats = profileRun;
      final frameTiming = frameReport?['frame_timing'] as Map?;
      var frameCaptureStatus = 'frame_report_not_available';
      if (frameReport != null) {
        if (attempt?.timingAttempt?.captureStarted == true) {
          frameCaptureStatus =
              frameTiming?['capture_completeness'] as String? ??
              'capture_summary_unavailable';
        } else {
          frameCaptureStatus =
              frameReport['frame_capture_start_status'] as String? ??
              'capture_window_not_started';
        }
      }
      final report = {
        'run_tag': runTag,
        'profile_run_id': stats?.runId,
        'profile_attempt_id': attempt?.id,
        'scenario': scenario,
        'build_mode': kProfileMode ? 'profile' : 'debug',
        'profile_boundary_note':
            'AudioPlayer play and clip resume futures are platform API observations, not audible onset.',
        'playback_error_type': playbackError?.runtimeType.toString(),
        'voice_outcomes': stats?.toJson(),
        'harness_dispatch_probe': _dispatchProbe.summary(),
        'frame_capture_status': frameCaptureStatus,
        'frame_timing': frameTiming,
        'timeline_trace_export':
            'Export the matching DevTools Timeline. Its run_id and per-voice IDs match this report.',
      };
      final fileName = 'playback_run_${stats?.runId ?? attempt?.id ?? 0}.json';
      await File(
        p.join(runDirectory.path, fileName),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      playbackProfileInstant(
        'writer.qa.run_report_exported',
        arguments: {
          'run_tag': runTag,
          'profile_run_id': stats?.runId,
          'profile_attempt_id': attempt?.id,
          'path': fileName,
        },
      );
      _emitResultLine(report, runDirectory: runDirectory);
      if (_exitOnComplete) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        exit(playbackError == null ? 0 : 1);
      }
    }
  }

  /// One greppable console line so a headless `flutter run` can capture the
  /// result without reading the app's sandboxed temporary directory.
  void _emitResultLine(
    Map<String, Object?> report, {
    required Directory runDirectory,
  }) {
    final outcomes = report['voice_outcomes'] as Map<String, Object?>?;
    final frameTiming = report['frame_timing'] as Map?;
    const voiceKeys = [
      'expected_voice_count',
      'expected_stroke_count',
      'expected_string_note_count',
      'requested_voice_count',
      'launched_voice_count',
      'dropped_voice_count',
      'cancelled_voice_count',
      'error_voice_count',
      'stolen_voice_count',
      'player_created_count',
      'player_reused_count',
    ];
    debugPrint(
      'WRITER_PROFILE_RESULT ${jsonEncode({
        'scenario': report['scenario'],
        'tempo_bpm': _tempo,
        'bars': _bars,
        'build_mode': report['build_mode'],
        'device_label': _deviceLabel,
        'run_directory': runDirectory.path,
        'playback_error_type': report['playback_error_type'],
        'voices': {for (final key in voiceKeys) key: outcomes?[key]},
        'run_stats_dispatch': outcomes?['dispatch_metrics'],
        'probe': report['harness_dispatch_probe'],
        'frame_timing': {'frame_count': frameTiming?['frame_count'], 'missed_budget_fraction': frameTiming?['missed_budget_fraction'], 'capture_completeness': frameTiming?['capture_completeness']},
      })}',
    );
  }

  @override
  void dispose() {
    _nativeAuditionTimer?.cancel();
    final pendingAttempts = <_ProfileFrameSampleAttempt>{
      ..._writerFrameAttempts.values,
      ?_activeTransportFrameAttempt,
      ?_activeNativeAuditionAttempt,
    };
    _activeTransportFrameAttempt = null;
    _activeNativeAuditionAttempt = null;
    for (final attempt in pendingAttempts) {
      if (!attempt.completed && !attempt.finishing) {
        unawaited(_finishFrameSample(attempt, reason: 'profile_view_disposed'));
      }
    }
    _frameTimingCapture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.viewMode) {
      case ProfileViewMode.writer:
        ref.listen(songwriterPlaybackProfileRunProvider, (previous, next) {
          _writerProfileRunChanged(previous, next);
        });
        ref.listen(songwriterPlaybackProvider, (previous, next) {
          _transportStatusChanged(
            view: 'writer',
            previous: previous?.status.name,
            next: next.status.name,
          );
        });
        return const Scaffold(body: SongwriterScreen());
      case ProfileViewMode.fretboard:
        return _ProfileInstrumentView(
          fretboard: true,
          showAuditionButton: !_autoStart,
          onAudition: _startNativeAudition,
        );
      case ProfileViewMode.piano:
        return _ProfileInstrumentView(
          fretboard: false,
          showAuditionButton: !_autoStart,
          onAudition: _startNativeAudition,
        );
      case ProfileViewMode.minimal:
        ref.listen(songwriterPlaybackProfileRunProvider, (previous, next) {
          _writerProfileRunChanged(previous, next);
        });
        ref.listen(songwriterPlaybackProvider, (previous, next) {
          _dispatchProbe.observeTransport(next);
          _transportStatusChanged(
            view: 'writer_minimal',
            previous: previous?.status.name,
            next: next.status.name,
          );
        });
        return _buildMinimalView();
    }
  }

  Widget _buildMinimalView() {
    final scenario = ref.watch(_profileScenarioProvider);
    final state = ref.watch(songwriterPlaybackProvider);
    final playing = state.status == SongwriterPlaybackStatus.playing;
    return Scaffold(
      appBar: AppBar(title: const Text('Writer playback profile harness')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Isolated fixture • ${kProfileMode ? 'profile' : 'debug'} build • '
            '$_tempo BPM • ${_durationSeconds > 0 ? '$_durationSeconds s' : '$_bars bars'} • $_bars bars',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'This harness uses synthetic Writer state and a generated clip in '
            'a unique app temporary run directory. It does not load saved projects. '
            'Schedule and outcome JSON are saved with that run.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: scenario,
            decoration: const InputDecoration(labelText: 'Fixture'),
            items: const [
              DropdownMenuItem(
                value: 'plain_harmony',
                child: Text('Plain Harmony • four-note chord per bar'),
              ),
              DropdownMenuItem(
                value: 'piano_harmony',
                child: Text('Plain Harmony • valid Piano chord'),
              ),
              DropdownMenuItem(
                value: 'six_note_strum',
                child: Text('Six-note strum • down/up each bar'),
              ),
              DropdownMenuItem(
                value: 'strum_metronome',
                child: Text('Load • 16th strum + metronome'),
              ),
              DropdownMenuItem(
                value: 'drums_metronome',
                child: Text('Load • drums (16th hats) + metronome'),
              ),
              DropdownMenuItem(
                value: 'strum_drums',
                child: Text('Load • 16th strum + drums, no metronome'),
              ),
              DropdownMenuItem(
                value: 'strum_drums_metronome',
                child: Text('Load • 16th strum + drums + metronome'),
              ),
              DropdownMenuItem(
                value: 'melody',
                child: Text('Melody • eight notes per bar'),
              ),
              DropdownMenuItem(
                value: 'recorded_clip',
                child: Text('Recorded clip • generated local WAV'),
              ),
            ],
            onChanged: playing
                ? null
                : (value) {
                    if (value != null) {
                      ref.read(_profileScenarioProvider.notifier).state = value;
                    }
                  },
          ),
          const SizedBox(height: 12),
          Text(
            'Transport: ${state.status.name} • tick ${state.currentTick ?? '—'}',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: playing
                ? ref.read(songwriterPlaybackProvider.notifier).stopPlayback
                : () => unawaited(_startPlayback()),
            icon: Icon(playing ? Icons.stop : Icons.play_arrow),
            label: Text(
              playing
                  ? 'Stop fixture'
                  : _durationSeconds > 0
                  ? 'Play $_durationSeconds s score'
                  : 'Play 8 bars',
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _startNativeAudition,
            icon: const Icon(Icons.music_note),
            label: const Text(
              'Preview matching Cmaj7 through shared instrument path',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Capture a DevTools Timeline during each run. Note-player play '
            'future completion and clip resume future completion are platform '
            'API timestamps; neither claims the actual audible onset.',
          ),
        ],
      ),
    );
  }
}

class _ProfileFrameSampleAttempt {
  _ProfileFrameSampleAttempt({
    required this.id,
    required this.runTag,
    required this.scenario,
    required this.viewMode,
    required this.sampleKind,
    required this.registeredAt,
    required this.writerRun,
    required this.additionalMetadata,
  });

  final int id;
  final String runTag;
  final String scenario;
  final ProfileViewMode viewMode;
  final String sampleKind;
  final DateTime registeredAt;
  final PlaybackProfileRunStats? writerRun;
  final Map<String, Object?> additionalMetadata;
  final Completer<Map<String, Object?>> completion = Completer();
  Map<String, Object?> metadata = const {};
  PlaybackProfileFrameTimingAttempt? timingAttempt;
  Map<String, Object?>? report;
  String? unavailableReason;
  bool sampleStarted = false;
  bool finishing = false;
  bool completed = false;
}

/// The private top-level instrument wrappers live in main.dart. This isolated
/// profile adapter uses their same public production scaffold and board
/// widgets, with safe no-op picker callbacks and a fixture-backed audition.
class _ProfileInstrumentView extends ConsumerWidget {
  const _ProfileInstrumentView({
    required this.fretboard,
    required this.showAuditionButton,
    required this.onAudition,
  });

  final bool fretboard;
  final bool showAuditionButton;
  final VoidCallback onAudition;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: MuzicianTheme.scaffoldBg,
    body: fretboard ? _fretboardScreen(ref) : _pianoScreen(ref),
    floatingActionButton: showAuditionButton
        ? FloatingActionButton.extended(
            onPressed: onAudition,
            icon: const Icon(Icons.music_note),
            label: const Text('Audition matching Cmaj7'),
          )
        : null,
  );

  Widget _fretboardScreen(WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final activeScale = ref.watch(activeScaleProvider);
    final activeChord = ref.watch(activeChordProvider);
    final chordCommitted = ref.watch(fretboardChordCommittedProvider);
    return InstrumentScreen(
      binding: fretboardBinding,
      title: 'Fretboard',
      appBarChipLabel: null,
      appBarActions: const [],
      modeSegment: ModeSegment<FretboardInputMode>(
        current: state.inputMode,
        onSelect: notifier.setInputMode,
        options: const [
          (FretboardInputMode.free, Icons.touch_app_rounded, 'Free'),
          (FretboardInputMode.chord, Icons.library_music_rounded, 'Chord'),
        ],
      ),
      board: const GuitarFretboard(
        hideToolbar: true,
        palette: FretboardPalette.wood,
      ),
      boardHeight: fretboardBoardHeight,
      emptyTitle: 'Tap the fretboard to begin',
      emptySubtitle:
          'Selected notes turn into detected chords and scales here.',
      onChordPanelRequested: () {},
      onScalePanelRequested: () {},
      scaleHasValue: activeScale != null,
      chordHasValue: activeChord != null || chordCommitted,
      detectionKey: const ValueKey('profile-fret-detect'),
      scaleOffKey: ref.watch(fretboardBinding.chordOffKey),
    );
  }

  Widget _pianoScreen(WidgetRef ref) {
    final activeScale = ref.watch(pianoActiveScaleProvider);
    final activeChord = ref.watch(pianoActiveChordProvider);
    final chordCommitted = ref.watch(pianoChordCommittedProvider);
    return InstrumentScreen(
      binding: pianoBinding,
      title: 'Piano',
      appBarChipLabel: null,
      appBarActions: const [],
      board: const PianoKeyboard(hideToolbar: true),
      boardHeight: pianoKeyboardHeight,
      emptyTitle: 'Tap the keyboard to begin',
      emptySubtitle:
          'Selected notes turn into detected chords and scales here.',
      onChordPanelRequested: () {},
      onScalePanelRequested: () {},
      scaleHasValue: activeScale != null,
      chordHasValue: activeChord != null || chordCommitted,
      detectionKey: const ValueKey('profile-piano-detect'),
      scaleOffKey: ref.watch(pianoBinding.chordOffKey),
    );
  }
}
