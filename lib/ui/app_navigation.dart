import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';

/// Logical width of the landscape navigation rail, excluding safe-area inset.
const double kStudioRailWidth = 80;

/// Landscape viewports keeping at least 600 for the workspace beside the rail
/// use the rail; others use the bar.
bool useNavigationRail(Size size) =>
    size.width - kStudioRailWidth >= 600 && size.width > size.height;

@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.tabIndex,
    required this.icon,
    required this.label,
    this.onTap,
    this.semanticHint,
    this.pinnedToBottom = false,
  });

  final int tabIndex;
  final IconData icon;
  final String label;

  /// Null renders the destination disabled with a lock badge.
  final VoidCallback? onTap;
  final String? semanticHint;

  /// Rail only: render below the workspace destinations.
  final bool pinnedToBottom;
}

class StudioBottomNavBar extends StatelessWidget {
  const StudioBottomNavBar({
    super.key = const Key('studioBottomNavBar'),
    required this.destinations,
    required this.selectedIndex,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StudioPalette.of(context).surface.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: Color(0x4094A3B8), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final destination in destinations)
                Expanded(
                  child: _NavItem(
                    destination: destination,
                    active: destination.tabIndex == selectedIndex,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioNavigationRail extends StatelessWidget {
  const StudioNavigationRail({
    super.key = const Key('studioNavigationRail'),
    required this.destinations,
    required this.selectedIndex,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;

  static const double _itemHeight = 56;

  @override
  Widget build(BuildContext context) {
    Widget item(AppNavDestination destination) => SizedBox(
      height: _itemHeight,
      width: double.infinity,
      child: _NavItem(
        destination: destination,
        active: destination.tabIndex == selectedIndex,
      ),
    );

    return Container(
      decoration: BoxDecoration(color: StudioPalette.of(context).surface),
      // Painted over the content so the divider does not widen the rail.
      foregroundDecoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x4094A3B8), width: 0.5)),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: kStudioRailWidth,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      for (final d in destinations)
                        if (!d.pinnedToBottom) item(d),
                      const Spacer(),
                      for (final d in destinations)
                        if (d.pinnedToBottom) item(d),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.active});

  final AppNavDestination destination;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    final onTap = destination.onTap;
    final hint = destination.semanticHint;
    final tab = Semantics(
      key: ValueKey('nav_${destination.label}'),
      button: true,
      enabled: onTap != null,
      selected: active,
      label: destination.label,
      hint: hint,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onTap == null)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(destination.icon, size: 24, color: palette.textMuted),
                    Positioned(
                      right: -2,
                      bottom: -1,
                      child: Icon(
                        Icons.lock_outline,
                        size: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                )
              else
                Icon(
                  destination.icon,
                  size: 24,
                  color: active ? palette.sky : palette.textMuted,
                ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? palette.sky : palette.textMuted,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return hint == null
        ? tab
        : Tooltip(message: hint, excludeFromSemantics: true, child: tab);
  }
}
