/// Save System Type Definitions
/// Nested folder tree mirroring Song > Part > State with progression metadata.
library;

import '../schema/rules/mono_pitch_rules.dart';
import '../schema/rules/piano_roll_rules.dart' as pr_rules;
import '../utils/note_utils.dart';
import 'fretboard.dart';
import 'piano.dart';
import 'project_config.dart';
import 'song_project.dart';
import 'songwriter.dart';

// ─── Musical Context ──────────────────────────────────────────────────────────

class PendingChord {
  final String root;
  final String quality;
  final String symbol;

  const PendingChord({
    required this.root,
    required this.quality,
    required this.symbol,
  });

  Map<String, dynamic> toJson() => {
    'root': root,
    'quality': quality,
    'symbol': symbol,
  };

  factory PendingChord.fromJson(Map<String, dynamic> json) => PendingChord(
    root: json['root'] as String,
    quality: json['quality'] as String,
    symbol: json['symbol'] as String,
  );
}

class PendingScale {
  final String root;
  final String scaleName;

  const PendingScale({required this.root, required this.scaleName});

  Map<String, dynamic> toJson() => {'root': root, 'scaleName': scaleName};

  factory PendingScale.fromJson(Map<String, dynamic> json) => PendingScale(
    root: json['root'] as String,
    scaleName: json['scaleName'] as String,
  );
}

// ─── Snapshots ────────────────────────────────────────────────────────────────

abstract class InstrumentSnapshot {
  const InstrumentSnapshot();

  String get instrument;
  List<String> get selectedNotes;
  PendingChord? get pendingChord;
  PendingScale? get pendingScale;

  Map<String, dynamic> toJson();

  static InstrumentSnapshot fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final instrument = json['instrument'] as String? ?? 'fretboard';
    if (type == 'songwriter' || instrument == 'songwriter') {
      return SongwriterProjectSnapshot.fromJson(json);
    }
    if (type == 'piano_roll' || instrument == 'piano_roll') {
      return PianoRollSnapshot.fromJson(json);
    }
    if (type == 'song' || instrument == 'song') {
      return SongProjectSnapshot.fromJson(json);
    }
    if (instrument == 'piano') {
      return PianoSnapshot.fromJson(json);
    }
    return FretboardSnapshot.fromJson(json);
  }
}

class FretboardSnapshot extends InstrumentSnapshot {
  @override
  String get instrument => 'fretboard';

  final TuningName tuning;
  final int numFrets;
  final int capo;
  final List<FretCoordinate> selectedCells;
  @override
  final List<String> selectedNotes;
  final FretboardViewMode viewMode;
  @override
  final PendingChord? pendingChord;
  @override
  final PendingScale? pendingScale;

  FretboardSnapshot({
    required this.tuning,
    required this.numFrets,
    required this.capo,
    required this.selectedCells,
    required this.selectedNotes,
    required this.viewMode,
    this.pendingChord,
    this.pendingScale,
  });

  @override
  Map<String, dynamic> toJson() => {
    'instrument': 'fretboard',
    'tuning': tuning.name,
    'numFrets': numFrets,
    'capo': capo,
    'selectedCells': selectedCells.map((c) => c.toJson()).toList(),
    'selectedNotes': selectedNotes,
    'viewMode': viewMode.name,
    'pendingChord': pendingChord?.toJson(),
    'pendingScale': pendingScale?.toJson(),
  };

  factory FretboardSnapshot.fromJson(Map<String, dynamic> json) {
    return FretboardSnapshot(
      tuning: TuningName.values.firstWhere(
        (t) => t.name == json['tuning'],
        orElse: () => TuningName.standard,
      ),
      numFrets: json['numFrets'] as int? ?? 12,
      capo: json['capo'] as int? ?? 0,
      selectedCells:
          (json['selectedCells'] as List?)
              ?.map((c) => FretCoordinate.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      selectedNotes:
          (json['selectedNotes'] as List?)?.map((n) => n as String).toList() ??
          [],
      viewMode: () {
        const legacyMap = <String, String>{
          'pitchClass': 'exact',
          'focus': 'exact',
        };
        final raw = json['viewMode'] as String?;
        final mapped = legacyMap[raw] ?? raw;
        return FretboardViewMode.values.firstWhere(
          (v) => v.name == mapped,
          orElse: () => FretboardViewMode.exact,
        );
      }(),
      pendingChord: json['pendingChord'] != null
          ? PendingChord.fromJson(json['pendingChord'] as Map<String, dynamic>)
          : null,
      pendingScale: json['pendingScale'] != null
          ? PendingScale.fromJson(json['pendingScale'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PianoSnapshot extends InstrumentSnapshot {
  @override
  String get instrument => 'piano';

  final PianoRangeName currentRange;
  final List<PianoCoordinate> selectedKeys;
  @override
  final List<String> selectedNotes;
  final PianoViewMode viewMode;
  @override
  final PendingChord? pendingChord;
  @override
  final PendingScale? pendingScale;

  PianoSnapshot({
    required this.currentRange,
    required this.selectedKeys,
    required this.selectedNotes,
    required this.viewMode,
    this.pendingChord,
    this.pendingScale,
  });

  @override
  Map<String, dynamic> toJson() => {
    'instrument': 'piano',
    'currentRange': currentRange.name,
    'selectedKeys': selectedKeys.map((k) => k.toJson()).toList(),
    'selectedNotes': selectedNotes,
    'viewMode': viewMode.name,
    'pendingChord': pendingChord?.toJson(),
    'pendingScale': pendingScale?.toJson(),
  };

  factory PianoSnapshot.fromJson(Map<String, dynamic> json) {
    return PianoSnapshot(
      currentRange: PianoRangeName.values.firstWhere(
        (r) => r.name == json['currentRange'],
        orElse: () => PianoRangeName.key61,
      ),
      selectedKeys:
          (json['selectedKeys'] as List?)
              ?.map((k) => PianoCoordinate.fromJson(k as Map<String, dynamic>))
              .toList() ??
          [],
      selectedNotes:
          (json['selectedNotes'] as List?)?.map((n) => n as String).toList() ??
          [],
      viewMode: () {
        const legacyMap = <String, String>{
          'pitchClass': 'exact',
          'focus': 'exact',
        };
        final raw = json['viewMode'] as String?;
        final mapped = legacyMap[raw] ?? raw;
        return PianoViewMode.values.firstWhere(
          (v) => v.name == mapped,
          orElse: () => PianoViewMode.exact,
        );
      }(),
      pendingChord: json['pendingChord'] != null
          ? PendingChord.fromJson(json['pendingChord'] as Map<String, dynamic>)
          : null,
      pendingScale: json['pendingScale'] != null
          ? PendingScale.fromJson(json['pendingScale'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PianoRollSnapshot extends InstrumentSnapshot {
  @override
  String get instrument => 'piano_roll';

  final int tempo;
  final String? key;
  final int numerator;
  final int denominator;
  final int totalMeasures;
  final List<Map<String, dynamic>> notes;
  final int pitchRangeStart;
  final int pitchRangeEnd;
  final int? selectedColumnTick;
  final int snapTicks;
  final List<String> highlightedNotes;
  final PendingScale? _pendingScale;

  PianoRollSnapshot({
    required this.tempo,
    this.key,
    required this.numerator,
    required this.denominator,
    required this.totalMeasures,
    required this.notes,
    required this.pitchRangeStart,
    required this.pitchRangeEnd,
    this.selectedColumnTick,
    required this.snapTicks,
    required this.highlightedNotes,
    PendingScale? pendingScale,
  }) : _pendingScale = pendingScale;

  /// Pitch classes of notes at the selected column (or all notes if none).
  @override
  List<String> get selectedNotes {
    final relevantMaps = selectedColumnTick != null
        ? notes
              .where((n) => (n['startTick'] as int?) == selectedColumnTick)
              .toList()
        : notes;
    if (relevantMaps.isEmpty && selectedColumnTick != null) {
      // Fall back to all unique pitch classes when no notes at the column.
      final allPcs = notes
          .map((n) => pr_rules.midiToPitchClass(n['midiNote'] as int))
          .toSet();
      return allPcs.toList();
    }
    final pcs = relevantMaps
        .map((n) => pr_rules.midiToPitchClass(n['midiNote'] as int))
        .toSet();
    return pcs.toList();
  }

  /// Detected chord from pitch classes at the saved selected column.
  @override
  PendingChord? get pendingChord {
    final sc = selectedNotes;
    if (sc.isEmpty) return null;
    final result = detectFirstChord(sc);
    if (result == null) return null;
    return PendingChord(
      root: result.root,
      quality: result.quality,
      symbol: '${result.root}${result.quality}',
    );
  }

  /// First detected scale from pitch classes at the saved selected column.
  @override
  PendingScale? get pendingScale {
    if (_pendingScale != null) {
      return _pendingScale;
    }
    final sc = selectedNotes;
    if (sc.isEmpty) return null;
    final detected = detectChordsAndScales(sc);
    if (detected.scales.isEmpty) return null;
    final parts = detected.scales.first.split(' ');
    if (parts.length < 2) return null;
    return PendingScale(root: parts[0], scaleName: parts.sublist(1).join(' '));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'piano_roll',
    'instrument': 'piano_roll',
    'tempo': tempo,
    'key': key,
    'numerator': numerator,
    'denominator': denominator,
    'totalMeasures': totalMeasures,
    'notes': notes,
    'pitchRangeStart': pitchRangeStart,
    'pitchRangeEnd': pitchRangeEnd,
    'selectedColumnTick': selectedColumnTick,
    'snapTicks': snapTicks,
    'highlightedNotes': highlightedNotes,
    'pendingScale': _pendingScale?.toJson(),
  };

  factory PianoRollSnapshot.fromJson(Map<String, dynamic> json) {
    return PianoRollSnapshot(
      tempo: json['tempo'] as int? ?? 120,
      key: json['key'] as String?,
      numerator: json['numerator'] as int? ?? 4,
      denominator: json['denominator'] as int? ?? 4,
      totalMeasures: json['totalMeasures'] as int? ?? 4,
      notes:
          (json['notes'] as List?)
              ?.map((n) => Map<String, dynamic>.from(n as Map<String, dynamic>))
              .toList() ??
          [],
      pitchRangeStart: json['pitchRangeStart'] as int? ?? 48,
      pitchRangeEnd: json['pitchRangeEnd'] as int? ?? 84,
      selectedColumnTick: json['selectedColumnTick'] as int?,
      snapTicks: json['snapTicks'] as int? ?? 1,
      highlightedNotes:
          (json['highlightedNotes'] as List?)
              ?.map((n) => n as String)
              .toList() ??
          [],
      pendingScale: json['pendingScale'] != null
          ? PendingScale.fromJson(json['pendingScale'] as Map<String, dynamic>)
          : null,
    );
  }
}

class SongProjectSnapshot extends InstrumentSnapshot {
  @override
  String get instrument => 'song';

  final SongProject project;

  SongProjectSnapshot({required this.project});

  @override
  List<String> get selectedNotes => project.notePatterns
      .expand((pattern) => pattern.notes)
      .map((note) => pr_rules.midiToPitchClass(note.midiNote))
      .toSet()
      .toList();

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'song',
    'instrument': 'song',
    'project': project.toJson(),
  };

  factory SongProjectSnapshot.fromJson(Map<String, dynamic> json) =>
      SongProjectSnapshot(
        project: SongProject.fromJson(json['project'] as Map<String, dynamic>),
      );
}

// ─── Progression Metadata ─────────────────────────────────────────────────────

class ProgressionFolderMeta {
  final String sourceType;
  final String progressionId;
  final String? key;

  const ProgressionFolderMeta({
    this.sourceType = 'progression',
    required this.progressionId,
    this.key,
  });

  Map<String, dynamic> toJson() => {
    'sourceType': sourceType,
    'progressionId': progressionId,
    'key': key,
  };

  factory ProgressionFolderMeta.fromJson(Map<String, dynamic> json) =>
      ProgressionFolderMeta(
        sourceType: json['sourceType'] as String? ?? 'progression',
        progressionId: json['progressionId'] as String,
        key: json['key'] as String?,
      );
}

class ProgressionChordMeta {
  final String sourceType;
  final String chordSymbol;
  final String rootNote;
  final String? romanNumeral;
  final String? progressionKey;
  final List<String> chordNotes;

  const ProgressionChordMeta({
    this.sourceType = 'progression-chord',
    required this.chordSymbol,
    required this.rootNote,
    this.romanNumeral,
    this.progressionKey,
    required this.chordNotes,
  });

  Map<String, dynamic> toJson() => {
    'sourceType': sourceType,
    'chordSymbol': chordSymbol,
    'rootNote': rootNote,
    'romanNumeral': romanNumeral,
    'progressionKey': progressionKey,
    'chordNotes': chordNotes,
  };

  factory ProgressionChordMeta.fromJson(Map<String, dynamic> json) =>
      ProgressionChordMeta(
        sourceType: json['sourceType'] as String? ?? 'progression-chord',
        chordSymbol: json['chordSymbol'] as String,
        rootNote: json['rootNote'] as String,
        romanNumeral: json['romanNumeral'] as String?,
        progressionKey: json['progressionKey'] as String?,
        chordNotes:
            (json['chordNotes'] as List?)?.map((n) => n as String).toList() ??
            [],
      );
}

// ─── Folder & Save Entry ──────────────────────────────────────────────────────

enum SaveFolderKind {
  normal,
  project,
  dump;

  String toJson() => name;
  static SaveFolderKind fromJson(String? raw) {
    for (final k in SaveFolderKind.values) {
      if (k.name == raw) return k;
    }
    return SaveFolderKind.normal;
  }
}

class SaveFolder {
  final String id;
  final String name;
  final String? parentId;
  final int createdAt;
  final int order;
  final ProgressionFolderMeta? progressionMeta;
  final SaveFolderKind kind;
  final ProjectConfig? projectConfig;

  const SaveFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    required this.order,
    this.progressionMeta,
    this.kind = SaveFolderKind.normal,
    this.projectConfig,
  });

  SaveFolder copyWith({
    String? name,
    int? order,
    SaveFolderKind? kind,
    ProjectConfig? projectConfig,
    bool clearProjectConfig = false,
  }) => SaveFolder(
        id: id,
        name: name ?? this.name,
        parentId: parentId,
        createdAt: createdAt,
        order: order ?? this.order,
        progressionMeta: progressionMeta,
        kind: kind ?? this.kind,
        projectConfig: clearProjectConfig ? null : (projectConfig ?? this.projectConfig),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'createdAt': createdAt,
    'order': order,
    'progressionMeta': progressionMeta?.toJson(),
    'kind': kind.toJson(),
    'projectConfig': projectConfig?.toJson(),
  };

  factory SaveFolder.fromJson(Map<String, dynamic> json) => SaveFolder(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parentId'] as String?,
    createdAt: json['createdAt'] as int,
    order: json['order'] as int? ?? 0,
    progressionMeta: json['progressionMeta'] != null
        ? ProgressionFolderMeta.fromJson(
            json['progressionMeta'] as Map<String, dynamic>,
          )
        : null,
    kind: SaveFolderKind.fromJson(json['kind'] as String?),
    projectConfig: json['projectConfig'] != null
        ? ProjectConfig.fromJson(json['projectConfig'] as Map<String, dynamic>)
        : null,
  );
}

class SaveEntry {
  final String id;
  final String name;
  final String folderId;
  final InstrumentSnapshot snapshot;
  final int createdAt;
  final int updatedAt;
  final int order;
  final ProgressionChordMeta? progressionMeta;

  const SaveEntry({
    required this.id,
    required this.name,
    required this.folderId,
    required this.snapshot,
    required this.createdAt,
    required this.updatedAt,
    required this.order,
    this.progressionMeta,
  });

  SaveEntry copyWith({
    String? name,
    InstrumentSnapshot? snapshot,
    int? updatedAt,
    int? order,
  }) => SaveEntry(
    id: id,
    name: name ?? this.name,
    folderId: folderId,
    snapshot: snapshot ?? this.snapshot,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    order: order ?? this.order,
    progressionMeta: progressionMeta,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folderId': folderId,
    'snapshot': snapshot.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'order': order,
    'progressionMeta': progressionMeta?.toJson(),
  };

  factory SaveEntry.fromJson(Map<String, dynamic> json) => SaveEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    folderId: json['folderId'] as String,
    snapshot: InstrumentSnapshot.fromJson(
      json['snapshot'] as Map<String, dynamic>,
    ),
    createdAt: json['createdAt'] as int,
    updatedAt: json['updatedAt'] as int,
    order: json['order'] as int? ?? 0,
    progressionMeta: json['progressionMeta'] != null
        ? ProgressionChordMeta.fromJson(
            json['progressionMeta'] as Map<String, dynamic>,
          )
        : null,
  );
}

// ─── Active Session ───────────────────────────────────────────────────────────

class ActiveSession {
  final String saveId;
  final String folderId;

  const ActiveSession({required this.saveId, required this.folderId});
}

// ─── Store Shape ──────────────────────────────────────────────────────────────

class SaveSystemState {
  final List<SaveFolder> folders;
  final List<SaveEntry> saves;
  final ActiveSession? activeSession;
  final bool hydrated;
  final String? selectedProjectId;

  const SaveSystemState({
    required this.folders,
    required this.saves,
    this.activeSession,
    required this.hydrated,
    this.selectedProjectId,
  });

  SaveSystemState copyWith({
    List<SaveFolder>? folders,
    List<SaveEntry>? saves,
    ActiveSession? Function()? activeSession,
    bool? hydrated,
    String? Function()? selectedProjectId,
  }) => SaveSystemState(
    folders: folders ?? this.folders,
    saves: saves ?? this.saves,
    activeSession: activeSession != null ? activeSession() : this.activeSession,
    hydrated: hydrated ?? this.hydrated,
    selectedProjectId:
        selectedProjectId != null ? selectedProjectId() : this.selectedProjectId,
  );
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class AppSettings {
  final bool suppressOutOfKeyAlert;
  // 0.0 (silent) … 1.0 (full volume). Default 0.8.
  final double noteVolume;

  /// Render note-name text inside selected note bubbles / on keyboard rows.
  /// When false the instrument canvases show shapes and colors only — useful
  /// for ear-training and a cleaner visual.
  final bool showNoteLabels;

  /// How tolerant the Hum-to-MIDI segmenter is of brief pitch deviations.
  /// `strict` switches the active note quickly (best for trained vocalists),
  /// `forgiving` ignores small wobbles within a wide cents deadband.
  /// Stored as the enum's `.name` so adding values stays forward-compatible.
  final HumSensitivity humSensitivity;

  /// Piano-roll transport plays a metronome click on each beat while playing.
  /// Accent click on the downbeat (beat 1), softer click on other beats.
  final bool metronomeEnabled;

  /// When true the save browser renders saves as a grid; false shows a list.
  final bool saveBrowserGrid;

  const AppSettings({
    this.suppressOutOfKeyAlert = false,
    this.noteVolume = 0.8,
    this.showNoteLabels = true,
    this.humSensitivity = HumSensitivity.balanced,
    this.metronomeEnabled = true,
    this.saveBrowserGrid = false,
  });

  AppSettings copyWith({
    bool? suppressOutOfKeyAlert,
    double? noteVolume,
    bool? showNoteLabels,
    HumSensitivity? humSensitivity,
    bool? metronomeEnabled,
    bool? saveBrowserGrid,
  }) => AppSettings(
    suppressOutOfKeyAlert: suppressOutOfKeyAlert ?? this.suppressOutOfKeyAlert,
    noteVolume: noteVolume ?? this.noteVolume,
    showNoteLabels: showNoteLabels ?? this.showNoteLabels,
    humSensitivity: humSensitivity ?? this.humSensitivity,
    metronomeEnabled: metronomeEnabled ?? this.metronomeEnabled,
    saveBrowserGrid: saveBrowserGrid ?? this.saveBrowserGrid,
  );

  Map<String, dynamic> toJson() => {
    'suppressOutOfKeyAlert': suppressOutOfKeyAlert,
    'noteVolume': noteVolume,
    'showNoteLabels': showNoteLabels,
    'humSensitivity': humSensitivity.name,
    'metronomeEnabled': metronomeEnabled,
    'saveBrowserGrid': saveBrowserGrid,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    suppressOutOfKeyAlert: json['suppressOutOfKeyAlert'] as bool? ?? false,
    noteVolume: (json['noteVolume'] as num?)?.toDouble() ?? 0.8,
    showNoteLabels: json['showNoteLabels'] as bool? ?? true,
    humSensitivity: _humSensitivityFromName(json['humSensitivity'] as String?),
    metronomeEnabled: json['metronomeEnabled'] as bool? ?? true,
    saveBrowserGrid: json['saveBrowserGrid'] as bool? ?? false,
  );
}

HumSensitivity _humSensitivityFromName(String? raw) {
  for (final value in HumSensitivity.values) {
    if (value.name == raw) return value;
  }
  return HumSensitivity.balanced;
}
