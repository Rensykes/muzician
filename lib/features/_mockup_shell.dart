/// Shared visual primitives for the V2 redesign mockups.
///
/// Iteration 2 — design decisions baked in:
///  * Cyan diet: reserved only for the dock primary CTA. Status chip is
///    neutral, mode segment uses soft white, sidebar dots use teal.
///  * Dock labels dropped: each field shows leading icon + value + chevron.
///  * Detection ribbon hides when empty (animates in only when detection
///    has something to say).
///  * No back arrow at the screen root — these are top-level tabs.
///  * Mode toggles render as a [ModeSegment] above the canvas (the real
///    widgets are passed `hideToolbar: true`).
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/studio_theme.dart';

// ── Scaffold ────────────────────────────────────────────────────────────────

class MockupScaffold extends StatelessWidget {
  final Widget child;
  final String activeNavLabel;
  const MockupScaffold({
    super.key,
    required this.child,
    required this.activeNavLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioPalette.of(context).scaffoldBg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: StudioPalette.of(context).gradientColors,
          ),
        ),
        child: SafeArea(bottom: false, child: child),
      ),
      bottomNavigationBar: MockBottomNav(activeLabel: activeNavLabel),
    );
  }
}

// ── Compact app bar ─────────────────────────────────────────────────────────

class CompactAppBar extends StatelessWidget {
  final String title;
  final String? chipLabel;
  final List<Widget> actions;

  /// When non-null, renders a close icon on the left and invokes this on tap.
  /// Provided by the mockup launcher (which pushes a fullscreen dialog).
  /// In production this is omitted because the screen is a top-level tab.
  final VoidCallback? onClose;
  const CompactAppBar({
    super.key,
    required this.title,
    this.chipLabel,
    this.actions = const [],
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: EdgeInsets.fromLTRB(onClose == null ? 16 : 4, 0, 16, 0),
        child: Row(
          children: [
            if (onClose != null)
              IconBtn(icon: Icons.close_rounded, onTap: onClose!),
            if (onClose != null) const SizedBox(width: 4),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: StudioPalette.of(context).textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (chipLabel != null) ...[
              const SizedBox(width: 10),
              Flexible(child: StatusChip(label: chipLabel!)),
            ],
            const Spacer(),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Project context and utilities above the full workspace title.
/// Legacy workspace compositions keep [CompactAppBar]'s original 44px height.
class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({
    super.key,
    required this.title,
    this.chipLabel,
    this.actions = const [],
    this.onClose,
  });
  final String title;
  final String? chipLabel;
  final List<Widget> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final p = StudioPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chipLabel != null || actions.isNotEmpty)
            Row(
              children: [
                if (chipLabel != null)
                  Expanded(child: StatusChip(label: chipLabel!))
                else if (actions.isNotEmpty)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: actions.first,
                    ),
                  ),
                ...actions.skip(chipLabel == null ? 1 : 0),
              ],
            ),
          Row(
            children: [
              if (onClose != null)
                IconBtn(icon: Icons.close_rounded, onTap: onClose!),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Neutral status chip. White-on-glass — no cyan competition.
class StatusChip extends StatelessWidget {
  final String label;
  const StatusChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (StudioPalette.of(context).isStudio
            ? StudioPalette.of(context).glassBg
            : Colors.white.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(
          StudioPalette.of(context).isStudio ? 6 : 999,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: StudioPalette.of(context).textPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const IconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Icon(
          icon,
          color: color ?? StudioPalette.of(context).textSecondary,
          size: 22,
        ),
      ),
    );
  }
}

// ── Mode segment (slim segmented control above canvas) ─────────────────────

class ModeSegment<T extends Object> extends StatelessWidget {
  final List<(T value, IconData icon, String label)> options;
  final T current;
  final ValueChanged<T> onSelect;
  const ModeSegment({
    super.key,
    required this.options,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: StudioPalette.of(context).isStudio ? 50 : 52,
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: (StudioPalette.of(context).isStudio
            ? StudioPalette.of(context).glassBg
            : Colors.white.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StudioPalette.of(context).glassBorder),
      ),
      child: Row(
        children: [
          for (final opt in options)
            Expanded(
              child: _Segment(
                icon: opt.$2,
                label: opt.$3,
                selected: opt.$1 == current,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(opt.$1);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            width: double.infinity,
            height: StudioPalette.of(context).isStudio ? 44 : null,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? (StudioPalette.of(context).isStudio
                        ? StudioPalette.of(context).sky
                        : Colors.white.withValues(alpha: 0.16))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected
                      ? (StudioPalette.of(context).isStudio
                            ? StudioPalette.of(context).onAccent
                            : StudioPalette.of(context).textPrimary)
                      : StudioPalette.of(context).textMuted,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? (StudioPalette.of(context).isStudio
                                ? StudioPalette.of(context).onAccent
                                : StudioPalette.of(context).textPrimary)
                          : StudioPalette.of(context).textMuted,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detection ribbon (hidden when empty) ───────────────────────────────────

class DetectionRibbon extends StatelessWidget {
  final String? detectedLabel;
  const DetectionRibbon({super.key, this.detectedLabel});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: detectedLabel == null
          ? const SizedBox(width: double.infinity)
          : Container(
              height: 30,
              margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: StudioPalette.of(
                  context,
                ).emerald.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: StudioPalette.of(
                    context,
                  ).emerald.withValues(alpha: 0.40),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_fix_high_rounded,
                    size: 13,
                    color: StudioPalette.of(context).emerald,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detectedLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: StudioPalette.of(context).emerald,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Docked toolbar ──────────────────────────────────────────────────────────

class DockedToolbar extends StatelessWidget {
  final List<Widget> children;
  const DockedToolbar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: StudioPalette.of(context).glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StudioPalette.of(context).glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(children: _spaced(children)),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> kids) {
    final out = <Widget>[];
    for (var i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i < kids.length - 1) out.add(const SizedBox(width: 4));
    }
    return out;
  }
}

/// Production-style icon tab: icon + small label, color-tinted when its
/// underlying picker has a committed/non-default value. Mirrors the existing
/// `_PanelTab` so the V2 dock visually matches what users already know.
class DockTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool hasValue;
  final VoidCallback onTap;
  final int flex;

  /// When true, paints a warning ring + warning icon overlay to flag that the
  /// current selection conflicts with the locked-in key.
  final bool warning;
  const DockTab({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.hasValue,
    required this.onTap,
    this.flex = 1,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = warning ? StudioPalette.of(context).orange : color;
    final labelScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final verticalPadding = (7 - (labelScale - 1) * 5).clamp(0.0, 7.0);
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          decoration: BoxDecoration(
            color: warning
                ? StudioPalette.of(context).orange.withValues(alpha: 0.10)
                : hasValue
                ? color.withValues(alpha: 0.10)
                : (StudioPalette.of(context).isStudio
                      ? StudioPalette.of(context).glassBg
                      : Colors.white.withValues(alpha: 0.04)),
            border: Border.all(
              color: warning
                  ? StudioPalette.of(context).orange.withValues(alpha: 0.55)
                  : hasValue
                  ? color.withValues(alpha: 0.40)
                  : StudioPalette.of(context).glassBorder,
              width: warning ? 1.0 : 0.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: (hasValue || warning)
                        ? effectiveColor
                        : StudioPalette.of(context).textMuted,
                  ),
                  if (warning)
                    Positioned(
                      top: -3,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E293B),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 11,
                          color: StudioPalette.of(context).orange,
                        ),
                      ),
                    )
                  else if (hasValue)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: (hasValue || warning)
                      ? effectiveColor
                      : StudioPalette.of(context).textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Value + chevron. No leading icon, no all-caps label — the value carries
/// itself. Maximizes text width inside a tight dock pill.
class DockField extends StatelessWidget {
  final String value;
  final VoidCallback onTap;
  final int flex;
  const DockField({
    super.key,
    required this.value,
    required this.onTap,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
          decoration: BoxDecoration(
            color: (StudioPalette.of(context).isStudio
                ? StudioPalette.of(context).glassBg
                : Colors.white.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: StudioPalette.of(context).glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: StudioPalette.of(context).textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: StudioPalette.of(context).textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single primary CTA. Violet — chosen so it doesn't compete with the
/// bottom-nav active state (cyan, app-wide brand).
class DockPrimaryButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const DockPrimaryButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: StudioPalette.of(context).violet,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 24,
          color: StudioPalette.of(context).scaffoldBg,
        ),
      ),
    );
  }
}

// ── Glass frame (host for hero canvas) ─────────────────────────────────────

class GlassFrame extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets padding;
  const GlassFrame({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(12, 4, 12, 4),
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          StudioPalette.of(context).isStudio ? 6 : 14,
        ),
        child: BackdropFilter(
          enabled: !StudioPalette.of(context).isStudio,
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: StudioPalette.of(context).isStudio
                  ? StudioPalette.of(context).surface
                  : StudioPalette.of(context).glassBg,
              borderRadius: BorderRadius.circular(
                StudioPalette.of(context).isStudio ? 6 : 14,
              ),
              border: Border.all(color: StudioPalette.of(context).glassBorder),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Picker bottom sheet ─────────────────────────────────────────────────────

Future<T?> showPickerSheet<T extends Object>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T current,
}) {
  return showStudioModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    builder: (ctx) =>
        _PickerSheet<T>(title: title, options: options, current: current),
  );
}

/// Open an arbitrary widget in a glass bottom sheet — used for wrapping
/// existing production widgets (ChordVoicingPicker, FretboardSavePanel,
/// PianoChordPicker, etc.) into the V2 sheet idiom.
Future<void> showWidgetSheet({
  required BuildContext context,
  required String title,
  required Widget child,
  bool scrollBody = true,
}) {
  return showStudioModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (ctx) =>
        _WidgetSheet(title: title, scrollBody: scrollBody, child: child),
  );
}

class _PickerSheet<T extends Object> extends StatelessWidget {
  final String title;
  final List<T> options;
  final T current;
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        enabled: !StudioPalette.of(context).isStudio,
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: StudioPalette.of(context).isStudio
                ? StudioPalette.of(context).dialogBg
                : StudioPalette.of(context).surface.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: StudioPalette.of(context).glassBorder),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: StudioPalette.of(context).textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  title,
                  style: TextStyle(
                    color: StudioPalette.of(context).textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((o) {
                      final selected = o == current;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop(o);
                        },
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 56,
                            minHeight: 44,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.10)
                                : (StudioPalette.of(context).isStudio
                                      ? StudioPalette.of(context).glassBg
                                      : Colors.white.withValues(alpha: 0.04)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.30)
                                  : StudioPalette.of(context).glassBorder,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$o',
                            style: TextStyle(
                              color: StudioPalette.of(context).textPrimary,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Toggle row (label + switch, for Tune sheet boolean settings) ───────────

class ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const ToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (StudioPalette.of(context).isStudio
              ? StudioPalette.of(context).glassBg
              : Colors.white.withValues(alpha: 0.04)),
          border: Border.all(color: StudioPalette.of(context).glassBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: StudioPalette.of(context).textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: StudioPalette.of(context).textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: StudioPalette.of(context).sky,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Clear-all button (Tune sheet wipe selections + scale + chord) ──────────

class ClearAllButton extends StatelessWidget {
  final VoidCallback onClear;
  const ClearAllButton({super.key, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClear,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: StudioPalette.of(context).red.withValues(alpha: 0.10),
          border: Border.all(
            color: StudioPalette.of(context).red.withValues(alpha: 0.40),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.delete_sweep_rounded,
              size: 18,
              color: StudioPalette.of(context).red,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Clear all selections',
                style: TextStyle(
                  color: StudioPalette.of(context).red,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget sheet (host for production widgets in V2 bottom sheets) ─────────

class _WidgetSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final bool scrollBody;

  const _WidgetSheet({
    required this.title,
    required this.child,
    required this.scrollBody,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        enabled: !StudioPalette.of(context).isStudio,
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: StudioPalette.of(context).isStudio
                ? StudioPalette.of(context).dialogBg
                : StudioPalette.of(context).surface.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: StudioPalette.of(context).glassBorder),
            ),
          ),
          child: Column(
            mainAxisSize: scrollBody ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: StudioPalette.of(context).textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: StudioPalette.of(context).textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Semantics(
                      label: 'Close',
                      button: true,
                      child: IconBtn(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
              if (scrollBody)
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: child,
                  ),
                )
              else
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: child,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mock bottom nav ─────────────────────────────────────────────────────────

class MockBottomNav extends StatelessWidget {
  final String activeLabel;
  const MockBottomNav({super.key, required this.activeLabel});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 56 + pad,
      padding: EdgeInsets.only(bottom: pad),
      decoration: BoxDecoration(
        color: StudioPalette.of(context).surface.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: StudioPalette.of(context).glassBorder),
        ),
      ),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.music_note_rounded,
            label: 'Fretboard',
            selected: activeLabel == 'Fretboard',
          ),
          _NavItem(
            icon: Icons.piano_rounded,
            label: 'Piano',
            selected: activeLabel == 'Piano',
          ),
          _NavItem(
            icon: Icons.grid_on_rounded,
            label: 'Roll',
            selected: activeLabel == 'Roll',
          ),
          _NavItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: activeLabel == 'Settings',
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? StudioPalette.of(context).sky
        : StudioPalette.of(context).textMuted;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
