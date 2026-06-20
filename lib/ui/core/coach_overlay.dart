/// Help-button coach-mark tour: a spotlight overlay that walks the user
/// through real on-screen elements one step at a time.
library;

import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// One step: highlights [key]'s widget with a [title]/[body] tooltip.
class CoachStep {
  const CoachStep({required this.key, required this.title, required this.body});
  final GlobalKey key;
  final String title;
  final String body;
}

/// Starts a coach tour over the current screen. No-op when [steps] is empty or
/// no step's target is currently mounted.
void startCoachTour(BuildContext context, List<CoachStep> steps) {
  final mountable = steps
      .where((s) => s.key.currentContext != null)
      .toList(growable: false);
  if (mountable.isEmpty) return;
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachTour(steps: mountable, onDismiss: entry.remove),
  );
  overlay.insert(entry);
}

class _CoachTour extends StatefulWidget {
  const _CoachTour({required this.steps, required this.onDismiss});
  final List<CoachStep> steps;
  final VoidCallback onDismiss;

  @override
  State<_CoachTour> createState() => _CoachTourState();
}

class _CoachTourState extends State<_CoachTour> {
  int _index = 0;
  Size? _startSize;

  Rect? _rectFor(CoachStep step) {
    final ctx = step.key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _advance() {
    var next = _index + 1;
    while (next < widget.steps.length && _rectFor(widget.steps[next]) == null) {
      next++;
    }
    if (next >= widget.steps.length) {
      widget.onDismiss();
    } else {
      setState(() => _index = next);
    }
  }

  void _back() {
    var prev = _index - 1;
    while (prev >= 0 && _rectFor(widget.steps[prev]) == null) {
      prev--;
    }
    if (prev >= 0) setState(() => _index = prev);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _startSize ??= size;
    if (_startSize != size) {
      // Layout changed (e.g. rotation): bail rather than show stale rects.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDismiss());
      return const SizedBox.shrink();
    }
    final step = widget.steps[_index];
    final rect = _rectFor(step);
    if (rect == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
      return const SizedBox.shrink();
    }
    final spot = rect.inflate(8);
    final safe = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _advance,
            child: CustomPaint(painter: _ScrimPainter(spot)),
          ),
        ),
        _buildCard(size, safe, spot, step),
      ],
    );
  }

  Widget _buildCard(Size size, EdgeInsets safe, Rect spot, CoachStep step) {
    const cardWidth = 300.0;
    // Conservative height estimate used only to pick a side and clamp; the
    // card itself is mainAxisSize.min.
    const estCardHeight = 210.0;
    final minTop = safe.top + 8;
    final maxTop = (size.height - safe.bottom - estCardHeight - 8)
        .clamp(minTop, size.height);
    // Prefer the side of the target with room; never let the card slide under
    // the status bar / Dynamic Island or below the home indicator.
    final double top;
    if (size.height - safe.bottom - spot.bottom >= estCardHeight + 12) {
      top = (spot.bottom + 12).clamp(minTop, maxTop);
    } else if (spot.top - safe.top >= estCardHeight + 12) {
      top = (spot.top - estCardHeight - 12).clamp(minTop, maxTop);
    } else {
      // Target spans most of the screen — park the card inside the safe band.
      top = minTop;
    }
    var left = spot.center.dx - cardWidth / 2;
    left = left.clamp(12.0, size.width - cardWidth - 12);
    final isFirst = _index == 0;
    final isLast = _index == widget.steps.length - 1;
    return Positioned(
      top: top,
      left: left,
      width: cardWidth,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MuzicianTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MuzicianTheme.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < widget.steps.length; i++) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? MuzicianTheme.sky
                            : MuzicianTheme.textDim,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Skip'),
                  ),
                  if (!isFirst)
                    TextButton(onPressed: _back, child: const Text('Back')),
                  FilledButton(
                    onPressed: isLast ? widget.onDismiss : _advance,
                    child: Text(isLast ? 'Done' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.spot);
  final Rect spot;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(spot, const Radius.circular(12)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, scrim, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(spot, const Radius.circular(12)),
      Paint()
        ..color = MuzicianTheme.sky
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.spot != spot;
}
