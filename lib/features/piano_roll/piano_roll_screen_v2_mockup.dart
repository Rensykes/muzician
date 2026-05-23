/// Piano Roll V2 — UI/UX redesign mockup.
///
/// Sandbox screen used to iterate on layout/visual design before porting to
/// the production [_PianoRollScreen]. Renders with placeholder data; no
/// Riverpod state is mutated here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../_mockup_shell.dart';
import '../../theme/muzician_theme.dart';

// ── Entry point ────────────────────────────────────────────────────────────

class PianoRollScreenV2Mockup extends StatefulWidget {
  const PianoRollScreenV2Mockup({super.key});

  @override
  State<PianoRollScreenV2Mockup> createState() => _PianoRollScreenV2MockupState();
}

class _PianoRollScreenV2MockupState extends State<PianoRollScreenV2Mockup> {
  bool _playing = false;
  int _bpm = 120;
  String _root = 'C';
  String _quality = 'maj';
  String _duration = '1/4';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Roll',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Roll',
              chipLabel: '$_root ionian',
              actions: [
                IconBtn(icon: Icons.bookmark_border, onTap: () {}),
                IconBtn(icon: Icons.tune, onTap: () {}),
                IconBtn(icon: Icons.more_horiz, onTap: () {}),
              ],
            ),
            _TransportStrip(
              playing: _playing,
              bpm: _bpm,
              barBeat: '1.2.0',
              timeSig: '4/4',
              onPlay: () {
                HapticFeedback.lightImpact();
                setState(() => _playing = !_playing);
              },
              onBpmChange: (d) => setState(() => _bpm = (_bpm + d).clamp(20, 300)),
            ),
            Expanded(
              child: GlassFrame(child: _GridArea(root: _root)),
            ),
            DockedToolbar(
              children: [
                DockField(
                  label: 'ROOT',
                  value: _root,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Root',
                      options: const ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'],
                      current: _root,
                    );
                    if (picked != null) setState(() => _root = picked);
                  },
                ),
                DockField(
                  label: 'QUAL',
                  value: _quality,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Quality',
                      options: const [
                        '5th', 'maj', 'min', 'dom7', 'maj7', 'm7',
                        'sus2', 'sus4', 'dim', 'aug', 'm7♭5',
                        'add9', 'maj9', '6', 'm6', 'dim7', '7sus4',
                      ],
                      current: _quality,
                    );
                    if (picked != null) setState(() => _quality = picked);
                  },
                ),
                DockField(
                  label: 'DUR',
                  value: _duration,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Duration',
                      options: const ['1/16', '1/8', '1/4', '1/2', '1/1'],
                      current: _duration,
                    );
                    if (picked != null) setState(() => _duration = picked);
                  },
                ),
                DockPrimaryButton(
                  icon: Icons.add_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('+ Stack: $_root$_quality ($_duration)'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: MuzicianTheme.surface,
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transport strip ─────────────────────────────────────────────────────────

class _TransportStrip extends StatelessWidget {
  final bool playing;
  final int bpm;
  final String barBeat;
  final String timeSig;
  final VoidCallback onPlay;
  final ValueChanged<int> onBpmChange;

  const _TransportStrip({
    required this.playing,
    required this.bpm,
    required this.barBeat,
    required this.timeSig,
    required this.onPlay,
    required this.onBpmChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconBtn(icon: Icons.skip_previous_rounded, onTap: () {}),
          _PlayBtn(playing: playing, onTap: onPlay),
          IconBtn(
            icon: Icons.fiber_manual_record_rounded,
            onTap: () {},
            color: MuzicianTheme.red.withValues(alpha: 0.85),
          ),
          IconBtn(icon: Icons.stop_rounded, onTap: () {}),
          const SizedBox(width: 6),
          Container(width: 1, height: 26, color: MuzicianTheme.glassBorder),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                _BpmReadout(bpm: bpm, onChange: onBpmChange),
                const SizedBox(width: 10),
                _Readout(label: 'BAR', value: barBeat),
                const SizedBox(width: 10),
                _Readout(label: 'SIG', value: timeSig),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayBtn({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MuzicianTheme.sky,
            boxShadow: [
              BoxShadow(
                color: MuzicianTheme.sky.withValues(alpha: 0.45),
                blurRadius: 16,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 26,
            color: MuzicianTheme.scaffoldBg,
          ),
        ),
      ),
    );
  }
}

class _BpmReadout extends StatelessWidget {
  final int bpm;
  final ValueChanged<int> onChange;
  const _BpmReadout({required this.bpm, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy.abs() > 4) onChange(d.delta.dy < 0 ? 1 : -1);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('BPM',
              style: TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              )),
          Text(
            '$bpm',
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  final String label;
  final String value;
  const _Readout({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            )),
        Text(value,
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

// ── Grid area (hero) ───────────────────────────────────────────────────────

class _GridArea extends StatelessWidget {
  final String root;
  const _GridArea({required this.root});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) => CustomPaint(
        size: Size(c.maxWidth, c.maxHeight),
        painter: _GridPainter(rootName: root),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final String rootName;
  _GridPainter({required this.rootName});

  static const _sidebarW = 44.0;
  static const _rulerH = 24.0;
  static const _rowH = 18.0;
  static const _bars = 4;
  static const _beatsPerBar = 4;
  static const _subdivPerBeat = 4;

  static const _blackKeys = {1, 3, 6, 8, 10};

  @override
  void paint(Canvas canvas, Size size) {
    final gridLeft = _sidebarW;
    final gridTop = _rulerH;
    final gridW = size.width - _sidebarW;
    final gridH = size.height - _rulerH;

    _paintRuler(canvas, Offset(gridLeft, 0), Size(gridW, _rulerH));
    _paintKeyboard(canvas, const Offset(0, _rulerH), Size(_sidebarW, gridH));
    _paintNoteGrid(canvas, Offset(gridLeft, gridTop), Size(gridW, gridH));
    _paintPlayhead(canvas, Offset(gridLeft, gridTop), Size(gridW, gridH));
    _paintHint(canvas, size);
  }

  void _paintRuler(Canvas c, Offset o, Size s) {
    final bg = Paint()..color = MuzicianTheme.scaffoldBg.withValues(alpha: 0.4);
    c.drawRect(o & s, bg);
    final barW = s.width / _bars;
    final major = Paint()
      ..color = MuzicianTheme.textSecondary.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = MuzicianTheme.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (var b = 0; b < _bars; b++) {
      final x = o.dx + b * barW;
      c.drawLine(Offset(x, o.dy + s.height - 8), Offset(x, o.dy + s.height), major);
      _drawText(c, '${b + 1}', Offset(x + 4, o.dy + 2),
          color: MuzicianTheme.textSecondary, size: 11, weight: FontWeight.w700);
      for (var beat = 1; beat < _beatsPerBar; beat++) {
        final bx = x + (beat / _beatsPerBar) * barW;
        c.drawLine(Offset(bx, o.dy + s.height - 4), Offset(bx, o.dy + s.height), minor);
      }
    }
    c.drawLine(
      Offset(o.dx, o.dy + s.height),
      Offset(o.dx + s.width, o.dy + s.height),
      Paint()..color = MuzicianTheme.glassBorder..strokeWidth = 1,
    );
  }

  void _paintKeyboard(Canvas c, Offset o, Size s) {
    final visibleRows = (s.height / _rowH).floor();
    const topMidi = 84; // C6
    final rootPc = _pitchClass(rootName);

    for (var i = 0; i < visibleRows; i++) {
      final midi = topMidi - i;
      final y = o.dy + i * _rowH;
      final isBlack = _blackKeys.contains(midi % 12);
      final paint = Paint()
        ..color = isBlack ? const Color(0xFF1A1F30) : const Color(0xFF2C3144);
      c.drawRect(Rect.fromLTWH(o.dx, y, s.width, _rowH - 1), paint);

      final pc = midi % 12;
      if (pc == 0) {
        final octave = (midi ~/ 12) - 1;
        _drawText(c, 'C$octave', Offset(o.dx + 6, y + 3),
            color: MuzicianTheme.textSecondary, size: 9, weight: FontWeight.w600);
      }
      if (pc == rootPc) {
        c.drawCircle(
          Offset(o.dx + s.width - 8, y + _rowH / 2),
          2.5,
          Paint()..color = MuzicianTheme.sky,
        );
      }
    }
    c.drawLine(
      Offset(o.dx + s.width, o.dy),
      Offset(o.dx + s.width, o.dy + s.height),
      Paint()..color = MuzicianTheme.glassBorder..strokeWidth = 1,
    );
  }

  void _paintNoteGrid(Canvas c, Offset o, Size s) {
    final visibleRows = (s.height / _rowH).floor();
    final totalSubdiv = _bars * _beatsPerBar * _subdivPerBeat;
    final cellW = s.width / totalSubdiv;
    const topMidi = 84;

    for (var i = 0; i < visibleRows; i++) {
      final midi = topMidi - i;
      final isBlack = _blackKeys.contains(midi % 12);
      final y = o.dy + i * _rowH;
      final paint = Paint()
        ..color = isBlack
            ? Colors.white.withValues(alpha: 0.012)
            : Colors.white.withValues(alpha: 0.028);
      c.drawRect(Rect.fromLTWH(o.dx, y, s.width, _rowH), paint);
    }

    for (var i = 0; i <= totalSubdiv; i++) {
      final x = o.dx + i * cellW;
      final isBar = i % (_beatsPerBar * _subdivPerBeat) == 0;
      final isBeat = i % _subdivPerBeat == 0;
      final paint = Paint()
        ..color = isBar
            ? MuzicianTheme.glassBorder
            : isBeat
                ? MuzicianTheme.textMuted.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04)
        ..strokeWidth = isBar ? 1 : 0.6;
      c.drawLine(Offset(x, o.dy), Offset(x, o.dy + s.height), paint);
    }

    for (var i = 0; i <= visibleRows; i++) {
      final y = o.dy + i * _rowH;
      c.drawLine(
        Offset(o.dx, y),
        Offset(o.dx + s.width, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.025)
          ..strokeWidth = 0.5,
      );
    }

    // Faux notes.
    final shownMidis = [72, 76, 79]; // C5 E5 G5
    for (final midi in shownMidis) {
      final rowIndex = topMidi - midi;
      if (rowIndex < 0 || rowIndex >= visibleRows) continue;
      final y = o.dy + rowIndex * _rowH + 2;
      final x = o.dx + 1;
      final w = cellW * _subdivPerBeat - 2;
      _drawNote(c, Rect.fromLTWH(x, y, w, _rowH - 4), MuzicianTheme.teal);
    }
    final g = [74, 79, 83];
    for (final midi in g) {
      final rowIndex = topMidi - midi;
      if (rowIndex < 0 || rowIndex >= visibleRows) continue;
      final y = o.dy + rowIndex * _rowH + 2;
      final x = o.dx + (2 * _subdivPerBeat) * cellW + 1;
      final w = cellW * _subdivPerBeat - 2;
      _drawNote(c, Rect.fromLTWH(x, y, w, _rowH - 4), MuzicianTheme.violet);
    }
  }

  void _drawNote(Canvas c, Rect r, Color color) {
    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(3));
    c.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.85));
    c.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _paintPlayhead(Canvas c, Offset o, Size s) {
    final totalSubdiv = _bars * _beatsPerBar * _subdivPerBeat;
    final cellW = s.width / totalSubdiv;
    final x = o.dx + (1 * _subdivPerBeat + 3) * cellW;
    c.drawLine(
      Offset(x, o.dy),
      Offset(x, o.dy + s.height),
      Paint()
        ..color = MuzicianTheme.sky.withValues(alpha: 0.8)
        ..strokeWidth = 1.5,
    );
    c.drawRect(
      Rect.fromLTWH(x - 6, o.dy, 12, s.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            MuzicianTheme.sky.withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(x - 6, o.dy, 12, s.height)),
    );
  }

  void _paintHint(Canvas c, Size s) {
    _drawText(
      c,
      'Pinch to zoom · drag to pan · tap to drop',
      Offset(s.width - 220, s.height - 18),
      color: MuzicianTheme.textMuted,
      size: 10,
      weight: FontWeight.w500,
    );
  }

  void _drawText(Canvas c, String text, Offset o,
      {required Color color, required double size, FontWeight weight = FontWeight.w400}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  int _pitchClass(String name) {
    const m = {
      'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4,
      'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9,
      'A#': 10, 'Bb': 10, 'B': 11,
    };
    return m[name] ?? 0;
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.rootName != rootName;
}
