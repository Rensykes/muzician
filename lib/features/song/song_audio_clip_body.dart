import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

class AudioClipBody extends StatelessWidget {
  final String name;
  final int durationMs;
  final String format;
  final List<int> peaks;
  final bool isBroken;

  const AudioClipBody({
    super.key,
    required this.name,
    required this.durationMs,
    required this.format,
    required this.peaks,
    required this.isBroken,
  });

  String _durationLabel() {
    final total = (durationMs / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: AudioWaveformPainter(
                peaks: peaks,
                accent: const Color(0xFF3FA9F5),
                background: const Color(0xFF13314A),
              ),
            ),
          ),
          if (isBroken)
            Positioned.fill(
              key: const ValueKey('audio-clip-broken'),
              child: CustomPaint(painter: _BrokenStripePainter()),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            // Narrow tiles (e.g. 1-bar sliced clips) have no room for the
            // fixed duration + format badge, which would overflow the Row.
            // Drop that meta cluster below a width threshold; the Expanded
            // name always fits (it ellipsizes).
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showMeta = constraints.maxWidth >= 80;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MuzicianTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showMeta) ...[
                      Text(
                        _durationLabel(),
                        style: const TextStyle(
                          color: MuzicianTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          format.toUpperCase(),
                          style: const TextStyle(
                            color: MuzicianTheme.textPrimary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AudioWaveformPainter extends CustomPainter {
  final List<int> peaks;
  final Color accent;
  final Color background;

  const AudioWaveformPainter({
    required this.peaks,
    required this.accent,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (peaks.isEmpty) return;
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (var x = 0; x < size.width.floor(); x++) {
      final binIndex = ((x / size.width) * peaks.length).floor();
      final peak = peaks[binIndex.clamp(0, peaks.length - 1)];
      final h = (peak / 255.0) * size.height * 0.9;
      canvas.drawLine(
        Offset(x.toDouble(), centerY - h / 2),
        Offset(x.toDouble(), centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter old) =>
      old.peaks != peaks ||
      old.accent != accent ||
      old.background != background;
}

class _BrokenStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xCCB23A3A)
      ..strokeWidth = 2.0;
    for (var x = -size.height.toInt(); x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x.toDouble(), 0),
        Offset(x.toDouble() + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
