import 'package:flutter/widgets.dart';

/// Canvas scale for the Fretboard/Piano dock tier: 1.0 at a 640px body,
/// growing linearly to 1.25 at 1040px and above.
double dockCanvasScale(double bodyHeight) =>
    1 + 0.25 * ((bodyHeight - 640) / 400).clamp(0.0, 1.0);

/// Lays [child] out at `maxWidth / scale` × [baseHeight] and paints it scaled
/// to fill the available width. `FittedBox` transforms hit testing, so
/// painters and gesture code stay in unscaled coordinates.
class ScaledInstrumentBoard extends StatelessWidget {
  const ScaledInstrumentBoard({
    super.key,
    required this.scale,
    required this.baseHeight,
    required this.child,
  });

  final double scale;
  final double baseHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: constraints.maxWidth / scale,
          height: baseHeight,
          child: child,
        ),
      ),
    );
  }
}
