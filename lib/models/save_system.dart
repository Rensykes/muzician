/// Save System Type Definitions
/// Nested folder tree mirroring Song > Part > State with progression metadata.
library;

import 'fretboard.dart';
import 'piano.dart';

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

sealed class InstrumentSnapshot {
  String get instrument;
  List<String> get selectedNotes;
  PendingChord? get pendingChord;
  PendingScale? get pendingScale;

  Map<String, dynamic> toJson();

  static InstrumentSnapshot fromJson(Map<String, dynamic> json) {
    final instrument = json['instrument'] as String? ?? 'fretboard';
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

class SaveFolder {
  final String id;
  final String name;
  final String? parentId;
  final int createdAt;
  final int order;
  final ProgressionFolderMeta? progressionMeta;

  const SaveFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    required this.order,
    this.progressionMeta,
  });

  SaveFolder copyWith({String? name}) => SaveFolder(
    id: id,
    name: name ?? this.name,
    parentId: parentId,
    createdAt: createdAt,
    order: order,
    progressionMeta: progressionMeta,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'createdAt': createdAt,
    'order': order,
    'progressionMeta': progressionMeta?.toJson(),
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

  const SaveSystemState({
    required this.folders,
    required this.saves,
    this.activeSession,
    required this.hydrated,
  });

  SaveSystemState copyWith({
    List<SaveFolder>? folders,
    List<SaveEntry>? saves,
    ActiveSession? Function()? activeSession,
    bool? hydrated,
  }) => SaveSystemState(
    folders: folders ?? this.folders,
    saves: saves ?? this.saves,
    activeSession: activeSession != null ? activeSession() : this.activeSession,
    hydrated: hydrated ?? this.hydrated,
  );
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class AppSettings {
  final bool suppressOutOfKeyAlert;

  const AppSettings({this.suppressOutOfKeyAlert = false});

  AppSettings copyWith({bool? suppressOutOfKeyAlert}) => AppSettings(
    suppressOutOfKeyAlert: suppressOutOfKeyAlert ?? this.suppressOutOfKeyAlert,
  );

  Map<String, dynamic> toJson() => {
    'suppressOutOfKeyAlert': suppressOutOfKeyAlert,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    suppressOutOfKeyAlert: json['suppressOutOfKeyAlert'] as bool? ?? false,
  );
}
