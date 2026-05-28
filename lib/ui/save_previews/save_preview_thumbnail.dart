/// Compact thumbnail previews for every InstrumentSnapshot type, used in
/// the SaveTreeBrowser save library and any other save picker.
///
/// Each painter is pure and depends only on the snapshot it receives, so it
/// can be reused freely inside lists without rebuild concerns.
library;

import 'package:flutter/material.dart';
import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../theme/muzician_theme.dart';

const double kSavePreviewWidth = 64;
const double kSavePreviewHeight = 56;

/// Returns the right painter for the given snapshot, or null if the snapshot
/// type does not have a preview implementation.
class SavePreviewThumbnail extends StatelessWidget {
  final InstrumentSnapshot snapshot;
  final double width;
  final double height;

  const SavePreviewThumbnail({
    super.key,
    required this.snapshot,
    this.width = kSavePreviewWidth,
    this.height = kSavePreviewHeight,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _painterFor(snapshot);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: painter == null
            ? const _FallbackPreview()
            : CustomPaint(painter: painter, size: Size(width, height)),
      ),
    );
  }

  static CustomPainter? _painterFor(InstrumentSnapshot snap) {
    if (snap is PianoSnapshot) return _PianoMiniPainter(snap);
    if (snap is FretboardSnapshot) return _FretboardMiniPainter(snap);
    if (snap is PianoRollSnapshot) return _PianoRollMiniPainter(snap);
    if (snap is SongProjectSnapshot) return _SongMiniPainter(snap);
    return null;
  }
}

class _FallbackPreview extends StatelessWidget {
  const _FallbackPreview();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.music_note, color: MuzicianTheme.textMuted, size: 20),
    );
  }
}

// ─── Piano mini ─────────────────────────────────────────────────────────────

class _PianoMiniPainter extends CustomPainter {
  final PianoSnapshot snapshot;
  _PianoMiniPainter(this.snapshot);

  static const _whiteKeyCount = 8; // C..C across one octave + 1
  static const _blackKeysAt = {
    0,
    1,
    3,
    4,
    5,
  }; // white indices that have a black to the right

  @override
  void paint(Canvas canvas, Size size) {
    final whiteW = size.width / _whiteKeyCount;
    final blackW = whiteW * 0.6;
    final blackH = size.height * 0.6;

    final selectedMidis = snapshot.selectedKeys.map((k) => k.midiNote).toSet();
    // Project all selected midis down to a 12 pitch-class window starting at C4 = 60.
    final selectedPCs = selectedMidis.map((m) => m % 12).toSet();
    final rootPc = selectedMidis.isNotEmpty
        ? selectedMidis.reduce((a, b) => a < b ? a : b) % 12
        : -1;

    // White keys
    final whiteFill = Paint()..color = const Color(0xFFF1F5F9);
    final whitePcs = const [0, 2, 4, 5, 7, 9, 11, 0];
    for (var i = 0; i < _whiteKeyCount; i++) {
      final x = i * whiteW;
      final rect = Rect.fromLTWH(x, 0, whiteW - 0.5, size.height);
      canvas.drawRect(rect, whiteFill);
      final pc = whitePcs[i];
      if (selectedPCs.contains(pc)) {
        final highlight = Paint()
          ..color = (pc == rootPc ? MuzicianTheme.emerald : MuzicianTheme.sky)
              .withValues(alpha: 0.55);
        canvas.drawRect(rect, highlight);
      }
    }

    // Black keys
    final blackFill = Paint()..color = const Color(0xFF0A0F1E);
    final blackPcs = const [1, 3, 6, 8, 10];
    var blackIndex = 0;
    for (var i = 0; i < _whiteKeyCount - 1; i++) {
      if (!_blackKeysAt.contains(i)) continue;
      final x = (i + 1) * whiteW - blackW / 2;
      final rect = Rect.fromLTWH(x, 0, blackW, blackH);
      canvas.drawRect(rect, blackFill);
      final pc = blackPcs[blackIndex];
      if (selectedPCs.contains(pc)) {
        final highlight = Paint()
          ..color = (pc == rootPc ? MuzicianTheme.emerald : MuzicianTheme.sky)
              .withValues(alpha: 0.85);
        canvas.drawRect(rect, highlight);
      }
      blackIndex++;
    }
  }

  @override
  bool shouldRepaint(covariant _PianoMiniPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot;
}

// ─── Fretboard mini ─────────────────────────────────────────────────────────

class _FretboardMiniPainter extends CustomPainter {
  final FretboardSnapshot snapshot;
  _FretboardMiniPainter(this.snapshot);

  static const _strings = 6;
  static const _fretsShown = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final padTop = 4.0;
    final padBottom = 4.0;
    final padX = 4.0;
    final usableW = size.width - padX * 2;
    final usableH = size.height - padTop - padBottom;
    final stringSpacing = usableH / (_strings - 1);
    final fretSpacing = usableW / _fretsShown;

    // Background grid
    final fretPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 0.6;
    final stringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.6;

    // Strings (horizontal)
    for (var s = 0; s < _strings; s++) {
      final y = padTop + s * stringSpacing;
      canvas.drawLine(
        Offset(padX, y),
        Offset(size.width - padX, y),
        stringPaint,
      );
    }
    // Frets (vertical)
    for (var f = 0; f <= _fretsShown; f++) {
      final x = padX + f * fretSpacing;
      canvas.drawLine(
        Offset(x, padTop),
        Offset(x, size.height - padBottom),
        fretPaint,
      );
    }

    // Nut
    canvas.drawLine(
      Offset(padX, padTop),
      Offset(padX, size.height - padBottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );

    // Capo (across all strings at capo+1 fret intersection)
    if (snapshot.capo > 0) {
      final capoFret = snapshot.capo.clamp(0, _fretsShown);
      final cx = padX + (capoFret - 0.5) * fretSpacing;
      canvas.drawLine(
        Offset(cx, padTop - 1),
        Offset(cx, size.height - padBottom + 1),
        Paint()
          ..color = MuzicianTheme.violet.withValues(alpha: 0.9)
          ..strokeWidth = 2.5,
      );
    }

    // Selected cells
    final selectedFill = Paint()..color = MuzicianTheme.teal;
    final radius = (stringSpacing * 0.35).clamp(2.0, 5.0);
    for (final cell in snapshot.selectedCells) {
      if (cell.stringIndex < 0 || cell.stringIndex >= _strings) continue;
      final f = cell.fret;
      // Normalise frets above the visible range to the last fret.
      final effFret = f.clamp(0, _fretsShown);
      final cx = effFret == 0 ? padX - 2 : padX + (effFret - 0.5) * fretSpacing;
      final cy = padTop + cell.stringIndex * stringSpacing;
      canvas.drawCircle(Offset(cx, cy), radius, selectedFill);
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardMiniPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot;
}

// ─── Piano Roll mini ────────────────────────────────────────────────────────

class _PianoRollMiniPainter extends CustomPainter {
  final PianoRollSnapshot snapshot;
  _PianoRollMiniPainter(this.snapshot);

  @override
  void paint(Canvas canvas, Size size) {
    final notes = snapshot.notes;
    if (notes.isEmpty) {
      _paintEmptyGrid(canvas, size);
      return;
    }

    // Compute extents
    final ticksPerMeasure = 16; // 4 beats × 4 ticks (1/16th)
    final totalTicks = (snapshot.totalMeasures * ticksPerMeasure).clamp(
      1,
      1 << 30,
    );
    final pitchMin = snapshot.pitchRangeStart;
    final pitchMax = snapshot.pitchRangeEnd.clamp(pitchMin + 1, 127);
    final pitchSpan = pitchMax - pitchMin;

    // Vertical measure separators
    final measurePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    for (var m = 1; m < snapshot.totalMeasures; m++) {
      final x = (m * ticksPerMeasure) / totalTicks * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), measurePaint);
    }

    final notePaint = Paint()
      ..color = MuzicianTheme.sky.withValues(alpha: 0.95);
    final noteHeight = (size.height / pitchSpan).clamp(1.5, 4.0);
    for (final note in notes) {
      final start = (note['startTick'] as int?) ?? 0;
      final dur = (note['durationTicks'] as int?) ?? 1;
      final midi = (note['midiNote'] as int?) ?? pitchMin;
      final left = start / totalTicks * size.width;
      final right = (start + dur) / totalTicks * size.width;
      final yNorm = 1 - ((midi - pitchMin) / pitchSpan).clamp(0, 1);
      final yCenter = yNorm * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left.clamp(0, size.width - 1),
            (yCenter - noteHeight / 2).clamp(0, size.height - noteHeight),
            right.clamp(left + 1, size.width),
            (yCenter + noteHeight / 2).clamp(noteHeight, size.height),
          ),
          const Radius.circular(1),
        ),
        notePaint,
      );
    }
  }

  void _paintEmptyGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    final step = size.width / 4;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(step * i, 0),
        Offset(step * i, size.height),
        paint,
      );
    }
    final hStep = size.height / 4;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, hStep * i),
        Offset(size.width, hStep * i),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PianoRollMiniPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot;
}

// ─── Song project mini ──────────────────────────────────────────────────────

class _SongMiniPainter extends CustomPainter {
  final SongProjectSnapshot snapshot;
  _SongMiniPainter(this.snapshot);

  @override
  void paint(Canvas canvas, Size size) {
    final project = snapshot.project;
    final maxTracks = 4;
    final orderedTracks = [...project.tracks]
      ..sort((a, b) => a.order.compareTo(b.order));
    final shown = orderedTracks.take(maxTracks).toList();
    if (shown.isEmpty) {
      _paintEmpty(canvas, size);
      return;
    }

    final laneHeight = size.height / maxTracks;
    final measureTicks = 16;
    final totalTicks = (project.config.totalMeasures * measureTicks).clamp(
      1,
      1 << 30,
    );

    final patternLengths = <String, int>{};
    for (final p in project.notePatterns) {
      patternLengths[p.id] = p.lengthTicks;
    }
    for (final p in project.drumPatterns) {
      patternLengths[p.id] = p.lengthTicks;
    }

    for (var i = 0; i < shown.length; i++) {
      final track = shown[i];
      final laneTop = i * laneHeight;
      final laneRect = Rect.fromLTWH(0, laneTop, size.width, laneHeight - 1);
      canvas.drawRect(
        laneRect,
        Paint()..color = Colors.white.withValues(alpha: 0.04),
      );

      final color = track.type == SongTrackType.note
          ? MuzicianTheme.sky
          : MuzicianTheme.orange;
      final clips = project.clips.where((c) => c.trackId == track.id);
      for (final clip in clips) {
        final length = patternLengths[clip.patternId] ?? measureTicks;
        final left = clip.startTick / totalTicks * size.width;
        final right = (clip.startTick + length) / totalTicks * size.width;
        final rect = Rect.fromLTRB(
          left.clamp(0, size.width - 1),
          laneTop + 2,
          right.clamp(left + 1, size.width),
          laneTop + laneHeight - 3,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = color.withValues(alpha: 0.55),
        );
      }
    }
  }

  void _paintEmpty(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;
    final step = size.height / 4;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, step * i), Offset(size.width, step * i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SongMiniPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot;
}
