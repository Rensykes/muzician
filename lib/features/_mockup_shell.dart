/// Shared visual primitives for the V2 redesign mockups
/// ([PianoRollScreenV2Mockup], [FretboardScreenV2Mockup], [PianoScreenV2Mockup]).
///
/// Kept in one file so all three screens iterate together on the same
/// design language: compact app bar, glass surfaces, docked action bar.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/muzician_theme.dart';

// ── Scaffold ────────────────────────────────────────────────────────────────

class MockupScaffold extends StatelessWidget {
  final Widget child;
  final String activeNavLabel;
  const MockupScaffold({super.key, required this.child, required this.activeNavLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MuzicianTheme.scaffoldBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: MuzicianTheme.gradientColors,
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
  final VoidCallback? onBack;
  const CompactAppBar({
    super.key,
    required this.title,
    this.chipLabel,
    this.actions = const [],
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconBtn(icon: Icons.chevron_left, onTap: onBack ?? () => Navigator.of(context).maybePop()),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            if (chipLabel != null) ...[
              const SizedBox(width: 10),
              StatusChip(label: chipLabel!),
            ],
            const Spacer(),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  const StatusChip({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? MuzicianTheme.sky;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
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
  const IconBtn({super.key, required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Icon(icon, color: color ?? MuzicianTheme.textSecondary, size: 22),
      ),
    );
  }
}

// ── Detection ribbon (slim status bar between canvas and dock) ──────────────

class DetectionRibbon extends StatelessWidget {
  final String? detectedLabel;
  final String hintLabel;
  const DetectionRibbon({super.key, this.detectedLabel, required this.hintLabel});

  @override
  Widget build(BuildContext context) {
    final hasDetection = detectedLabel != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: 32,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: hasDetection
            ? MuzicianTheme.emerald.withValues(alpha: 0.10)
            : MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasDetection
              ? MuzicianTheme.emerald.withValues(alpha: 0.45)
              : MuzicianTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasDetection ? Icons.auto_fix_high_rounded : Icons.touch_app_rounded,
            size: 14,
            color: hasDetection ? MuzicianTheme.emerald : MuzicianTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detectedLabel ?? hintLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasDetection ? MuzicianTheme.emerald : MuzicianTheme.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
      height: 72,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MuzicianTheme.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: _spaced(children)),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> kids) {
    final out = <Widget>[];
    for (var i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i < kids.length - 1) out.add(const SizedBox(width: 6));
    }
    return out;
  }
}

class DockField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final int flex;
  const DockField({
    super.key,
    required this.label,
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
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MuzicianTheme.glassBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  )),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: MuzicianTheme.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DockPrimaryButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  const DockPrimaryButton({super.key, required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [MuzicianTheme.sky, MuzicianTheme.teal],
          ),
          boxShadow: [
            BoxShadow(
              color: MuzicianTheme.sky.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 28, color: MuzicianTheme.scaffoldBg),
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
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: MuzicianTheme.glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MuzicianTheme.glassBorder),
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
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PickerSheet<T>(
      title: title, options: options, current: current,
    ),
  );
}

class _PickerSheet<T extends Object> extends StatelessWidget {
  final String title;
  final List<T> options;
  final T current;
  const _PickerSheet({required this.title, required this.options, required this.current});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: MuzicianTheme.surface.withValues(alpha: 0.96),
            border: Border(top: BorderSide(color: MuzicianTheme.glassBorder)),
          ),
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: MuzicianTheme.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: options.map((o) {
                  final selected = o == current;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(o);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? MuzicianTheme.sky.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? MuzicianTheme.sky : MuzicianTheme.glassBorder,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$o',
                        style: TextStyle(
                          color: selected ? MuzicianTheme.sky : MuzicianTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
        color: MuzicianTheme.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: MuzicianTheme.glassBorder)),
      ),
      child: Row(
        children: [
          _NavItem(icon: Icons.music_note_rounded, label: 'Fretboard', selected: activeLabel == 'Fretboard'),
          _NavItem(icon: Icons.piano_rounded, label: 'Piano', selected: activeLabel == 'Piano'),
          _NavItem(icon: Icons.grid_on_rounded, label: 'Roll', selected: activeLabel == 'Roll'),
          _NavItem(icon: Icons.settings_rounded, label: 'Settings', selected: activeLabel == 'Settings'),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem({required this.icon, required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final color = selected ? MuzicianTheme.sky : MuzicianTheme.textMuted;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
