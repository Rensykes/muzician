/// Isolated device harness for Writer playback profiling.
///
/// Run with `flutter run --profile -t lib/profile_writer_playback.dart`. It
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
import 'models/song_project.dart';
import 'models/songwriter.dart';
import 'features/_mockup_shell.dart' show ModeSegment;
import 'features/fretboard/fretboard.dart'
    show FretboardPalette, GuitarFretboard, fretboardBoardHeight;
import 'features/instrument_shared/instrument_screen.dart'
    show InstrumentScreen;
import 'features/piano/piano_keyboard.dart'
    show PianoKeyboard, pianoKeyboardHeight;
import 'features/song/song_screen.dart' show SongScreen;
import 'features/songwriter/songwriter_screen.dart' show SongwriterScreen;
import 'schema/rules/songwriter_audio_rules.dart';
import 'schema/rules/songwriter_playback_rules.dart';
import 'schema/rules/song_from_writer_rules.dart' show songFromSongwriter;
import 'schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import 'schema/rules/song_playback_rules.dart' as song_playback_rules;
import 'schema/rules/songwriter_rules.dart';
import 'store/fretboard_store.dart';
import 'store/piano_store.dart';
import 'store/save_system_store.dart';
import 'store/settings_store.dart';
import 'store/song_audio_repository.dart';
import 'store/song_audio_player_sink.dart';
import 'store/song_playback_store.dart';
import 'store/song_project_store.dart';
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
const _auditionDurationMs = int.fromEnvironment(
  'WRITER_PROFILE_AUDITION_DURATION_MS',
  defaultValue: 1000,
);

enum ProfileViewMode { minimal, writer, song, fretboard, piano }

extension ProfileViewModeParsing on ProfileViewMode {
  static ProfileViewMode parse(String value) => switch (value) {
    'minimal' => ProfileViewMode.minimal,
    'writer' => ProfileViewMode.writer,
    'song' => ProfileViewMode.song,
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
    ],
    hydrated: true,
    selectedProjectId: _qaProjectId,
  );
}

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
          saveId: harmonySaveId,
        ),
    ],
  );

  final lanes = switch (scenario) {
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
        : const [],
    melodyPatterns: scenario == 'melody'
        ? [
            NotePattern(
              id: 'qa_melody_pattern',
              name: 'Eight notes per bar',
              lengthTicks: 16,
              notes: [
                for (var index = 0; index < 8; index++)
                  NotePatternNote(
                    id: 'qa_melody_$index',
                    midiNote: 60 + (index % 5) * 2,
                    startTick: index * 2,
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
  AppSettings build() => const AppSettings(metronomeEnabled: false);
}

class _ProfileSaveSystemNotifier extends SaveSystemNotifier {
  @override
  SaveSystemState build() =>
      _saveStateFor(ref.watch(_profileScenarioProvider), tempo: _tempo);
}

class _ProfileSongProjectNotifier extends SongProjectNotifier {
  @override
  SongProject build() {
    final scenario = ref.watch(_profileScenarioProvider);
    final saveState = _saveStateFor(scenario, tempo: _tempo);
    final writer = _fixtureFor(scenario, _qaAsset, tempo: _tempo, bars: _bars);
    final song = songFromSongwriter(
      writer,
      saveState.saves,
      projectId: saveState.selectedProjectId,
      folders: saveState.folders,
      projectDefaultHarmonyInstrument:
          saveState.folders.single.projectConfig!.defaultHarmonyInstrument,
    );
    return scenario == 'recorded_clip'
        ? _withControlledSongAudioClip(song, _qaAsset)
        : song;
  }
}

SongProject _withControlledSongAudioClip(SongProject song, AudioAsset asset) {
  const trackId = 'qa_recorded_clip_track';
  const patternId = 'qa_recorded_clip_pattern';
  return song.copyWith(
    tracks: [
      ...song.tracks,
      const SongTrack(
        id: trackId,
        name: 'Generated QA clip',
        type: SongTrackType.audio,
        order: 100,
      ),
    ],
    clips: [
      ...song.clips,
      const SongClipInstance(
        id: 'qa_recorded_clip_instance',
        trackId: trackId,
        patternId: patternId,
        patternType: SongPatternType.audio,
        startTick: 0,
      ),
    ],
    audioAssets: [...song.audioAssets, asset],
    audioPatterns: [
      ...song.audioPatterns,
      const AudioClipPattern(
        id: patternId,
        name: 'Generated QA clip',
        assetId: _qaAssetId,
      ),
    ],
  );
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
/// SharedPreferences hydration, or the persistent Song audio repository.
List<Override> buildWriterPlaybackProfileProviderOverrides({
  required SongAudioRepository repository,
  required SongAudioRepository songRepository,
  String scenario = _fixtureScenario,
}) => [
  _profileScenarioProvider.overrideWith((ref) => scenario),
  songwriterProvider.overrideWith(_ProfileWriterNotifier.new),
  settingsProvider.overrideWith(_ProfileSettingsNotifier.new),
  saveSystemProvider.overrideWith(_ProfileSaveSystemNotifier.new),
  songProjectProvider.overrideWith(_ProfileSongProjectNotifier.new),
  fretboardProvider.overrideWith(_ProfileFretboardNotifier.new),
  pianoProvider.overrideWith(_ProfilePianoNotifier.new),
  songwriterAudioRepositoryProvider.overrideWithValue(repository),
  songwriterAudioClipSinkProvider.overrideWith(
    (ref) => AudioPlayersClipSink(ref.read(songwriterAudioRepositoryProvider)),
  ),
  songAudioRepositoryProvider.overrideWithValue(songRepository),
  songAudioClipSinkProvider.overrideWith(
    (ref) => AudioPlayersClipSink(ref.read(songAudioRepositoryProvider)),
  ),
];

Map<String, int> _verifyFixtures(
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
    'melody': bars * 8,
    'recorded_clip': 4,
  };
  final results = <String, int>{};
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
    final voiceCount = events.fold<int>(
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
    );
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
    if (fixture.key == 'six_note_strum') {
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
  return results;
}

Map<String, int> verifyWriterPlaybackProfileFixtures({
  int tempo = _tempo,
  int durationSeconds = _durationSeconds,
}) => _verifyFixtures(
  _qaAsset,
  tempo: tempo,
  bars: _barsFor(tempo, durationSeconds),
);

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
    'expected_voice_count': schedule.length,
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

/// Builds the matching Song schedule from the same isolated Writer fixture.
/// The comparison is specifically MIDI, score tick, onset offset, and count;
/// it reports note-tail duration separately because Writer Harmony previews
/// and imported Song patterns use different duration semantics.
Map<String, Object?> buildSongPlaybackProfileManifest({
  required String scenario,
  int tempo = _tempo,
  int durationSeconds = _durationSeconds,
}) {
  final writerManifest = buildWriterPlaybackProfileManifest(
    scenario: scenario,
    tempo: tempo,
    durationSeconds: durationSeconds,
  );
  final saveState = _saveStateFor(scenario, tempo: tempo);
  final writer = _fixtureFor(
    scenario,
    _qaAsset,
    tempo: tempo,
    bars: _barsFor(tempo, durationSeconds),
  );
  final importedSong = songFromSongwriter(
    writer,
    saveState.saves,
    projectId: saveState.selectedProjectId,
    folders: saveState.folders,
    projectDefaultHarmonyInstrument:
        saveState.folders.single.projectConfig!.defaultHarmonyInstrument,
  );
  final song = scenario == 'recorded_clip'
      ? _withControlledSongAudioClip(importedSong, _qaAsset)
      : importedSong;
  final scoreTickCount = writerManifest['score_tick_count']! as int;
  final songEvents = song_playback_rules
      .buildPlaybackEvents(song)
      .where((event) => event.tick < scoreTickCount)
      .toList(growable: false);
  final songVoices = <Map<String, Object?>>[
    for (final event in songEvents)
      for (final group in event.sequencedNoteGroups)
        for (final note in group.notes)
          {
            'score_tick': event.tick,
            'midi': note.midiNote,
            'onset_offset_us': note.onsetOffsetMs * 1000,
            'duration_ticks': note.durationTicks,
            'duration_offset_ms': note.durationOffsetMs,
          },
  ]..sort(_compareScheduledMidiVoices);
  final writerVoices =
      (writerManifest['scheduled_voices']! as List)
          .cast<Map<String, Object?>>()
          .where((voice) => voice['midi'] is int)
          .map(
            (voice) => <String, Object?>{
              'score_tick': voice['score_tick'],
              'midi': voice['midi'],
              'onset_offset_us': voice['onset_offset_us'],
              'duration_us': voice['duration_us'],
            },
          )
          .toList(growable: false)
        ..sort(_compareScheduledMidiVoices);
  final matches =
      _midiScheduleSignature(writerVoices).join('|') ==
      _midiScheduleSignature(songVoices).join('|');
  return {
    'schema_version': 1,
    'fixture': scenario,
    'tempo_bpm': tempo,
    'score_tick_count': scoreTickCount,
    'song_track_count': song.tracks.length,
    'song_note_clip_count': song.clips
        .where((clip) => clip.patternType == SongPatternType.note)
        .length,
    'song_audio_clip_count': song.clips
        .where((clip) => clip.patternType == SongPatternType.audio)
        .length,
    'writer_audio_asset_count': writer.audioAssets.length,
    'song_audio_asset_count': song.audioAssets.length,
    'song_audio_clip_sink': 'AudioPlayersClipSink',
    'song_audio_fixture_storage':
        'isolated temporary song_audio repository with a generated QA WAV',
    if (scenario == 'recorded_clip')
      'recorded_clip_comparison_note':
          'Writer audio is excluded from Writer-to-Song handoff. Song playback uses an independent synthetic audio lane with the same generated QA WAV copied into its isolated song_audio repository; this does not claim Writer audio transfers.',
    'writer_midi_voice_count': writerVoices.length,
    'song_midi_voice_count': songVoices.length,
    'writer_event_count': writerManifest['expected_event_count'],
    'song_event_count': songEvents.length,
    'midi_tick_offset_count_match': matches,
    'writer_midi_schedule': writerVoices,
    'song_midi_schedule': songVoices,
    'duration_comparison_note': scenario == 'plain_harmony'
        ? 'MIDI, score tick, onset offset, and count are compared exactly. Writer Harmony preview voices use a 700ms note request; Song-imported Harmony notes use beat-length sequenced patterns, so note-tail duration is not equivalent.'
        : scenario == 'recorded_clip'
        ? 'MIDI, score tick, onset offset, and count are compared exactly. The Song audio clip is an independent controlled fixture because Writer audio is excluded from handoff; see recorded_clip_comparison_note.'
        : 'MIDI, score tick, onset offset, and count are compared exactly. Writer and Song may use different note-duration semantics; see each schedule entry.',
    'writer_audio_transfer_note':
        'Writer audio is intentionally excluded from the Song handoff.',
  };
}

int _compareScheduledMidiVoices(
  Map<String, Object?> a,
  Map<String, Object?> b,
) {
  final tick = (a['score_tick']! as int).compareTo(b['score_tick']! as int);
  if (tick != 0) return tick;
  final midi = (a['midi']! as int).compareTo(b['midi']! as int);
  if (midi != 0) return midi;
  return (a['onset_offset_us']! as int).compareTo(b['onset_offset_us']! as int);
}

List<String> _midiScheduleSignature(List<Map<String, Object?>> voices) => [
  for (final voice in voices)
    '${voice['score_tick']}:${voice['midi']}:${voice['onset_offset_us']}',
];

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
  final repository = SongAudioRepository.testWith(
    rootDirectory: runDirectory,
    subdir: 'songwriter_audio',
  );
  final clipFile = await repository.resolvePath(_qaAssetId, 'wav');
  final songRepository = SongAudioRepository.testWith(
    rootDirectory: runDirectory,
  );
  final songClipFile = await songRepository.resolvePath(_qaAssetId, 'wav');
  final qaTone = _writeQaTone();
  await Future.wait([
    clipFile.writeAsBytes(qaTone),
    songClipFile.writeAsBytes(qaTone),
  ]);
  final fixtureMetrics = verifyWriterPlaybackProfileFixtures();
  final runTag = p.basename(runDirectory.path);
  final startupManifest = <String, Object?>{
    ...buildWriterPlaybackProfileManifest(
      scenario: _fixtureScenario,
      runTag: runTag,
    ),
    'profile_view': _profileViewMode.name,
    if (_profileViewMode == ProfileViewMode.song)
      'song_comparator': buildSongPlaybackProfileManifest(
        scenario: _fixtureScenario,
      ),
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
      'expected_voice_count': fixtureMetrics[_fixtureScenario],
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
      overrides: buildWriterPlaybackProfileProviderOverrides(
        repository: repository,
        songRepository: songRepository,
      ),
      child: WriterPlaybackProfileApp(
        runDirectory: runDirectory,
        viewMode: _profileViewMode,
      ),
    ),
  );
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
          case ProfileViewMode.song:
            unawaited(
              ref
                  .read(songPlaybackProvider.notifier)
                  .startPlayback(
                    endTickExclusive:
                        _scoreTickLimitFor(_tempo, _durationSeconds) ??
                        _bars * 16,
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
    final songComparator = viewMode == ProfileViewMode.song
        ? buildSongPlaybackProfileManifest(scenario: attempt.scenario)
        : null;
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
      'song_comparator': ?songComparator,
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
    }
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
      case ProfileViewMode.song:
        ref.listen(songPlaybackProvider, (previous, next) {
          _transportStatusChanged(
            view: 'song',
            previous: previous?.status.name,
            next: next.status.name,
          );
        });
        return const Scaffold(body: SongScreen());
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
              'Preview matching Cmaj7 through shared instrument/Song path',
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
