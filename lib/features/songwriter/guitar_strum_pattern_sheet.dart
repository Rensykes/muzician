/// Compact 16th-grid editor for a Writer guitar-strum pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';

Future<void> showGuitarStrumPatternSheet({
  required BuildContext context,
  required String patternId,
}) => showWidgetSheet(
  context: context,
  title: 'Guitar Strum Pattern',
  child: _GuitarStrumPatternBody(patternId: patternId),
);

class _GuitarStrumPatternBody extends ConsumerWidget {
  const _GuitarStrumPatternBody({required this.patternId});
  final String patternId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final pattern = project.guitarStrumPatterns
        .where((candidate) => candidate.id == patternId)
        .firstOrNull;
    if (pattern == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Pattern not found.'),
      );
    }
    final bars = (pattern.lengthTicks / project.config.measureTicks)
        .round()
        .clamp(1, 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const instruction = Text(
                'Tap a 16th step to cycle down, up, and off.',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                ),
              );
              final lengthSelector = DropdownButton<int>(
                key: const Key('guitarStrumPatternLength'),
                value: bars,
                dropdownColor: MuzicianTheme.surface,
                style: const TextStyle(color: MuzicianTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: const [1, 2, 4].map((count) {
                  return DropdownMenuItem(
                    value: count,
                    child: Text('$count bar${count == 1 ? '' : 's'}'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final length = value * project.config.measureTicks;
                  ref
                      .read(songwriterProvider.notifier)
                      .updateGuitarStrumPattern(
                        pattern.copyWith(
                          lengthTicks: length,
                          events: pattern.events
                              .where((event) => event.tick < length)
                              .toList(),
                        ),
                      );
                },
              );
              if (constraints.maxWidth < 400) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [instruction, lengthSelector],
                );
              }
              return Row(
                children: [
                  const Expanded(child: instruction),
                  const SizedBox(width: 8),
                  lengthSelector,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 5,
            runSpacing: 6,
            children: [
              for (var tick = 0; tick < pattern.lengthTicks; tick++)
                _StrumStep(
                  tick: tick,
                  event: pattern.events
                      .where((event) => event.tick == tick)
                      .firstOrNull,
                  onTap: () {
                    final current = pattern.events
                        .where((event) => event.tick == tick)
                        .firstOrNull;
                    final next = switch (current?.direction) {
                      null => GuitarStrumDirection.down,
                      GuitarStrumDirection.down => GuitarStrumDirection.up,
                      GuitarStrumDirection.up => null,
                    };
                    final updatedEvents = pattern.events
                        .where((event) => event.tick != tick)
                        .toList();
                    if (next != null) {
                      updatedEvents.add(
                        GuitarStrumEvent(tick: tick, direction: next),
                      );
                    }
                    updatedEvents.sort((a, b) => a.tick.compareTo(b.tick));
                    ref
                        .read(songwriterProvider.notifier)
                        .updateGuitarStrumPattern(
                          pattern.copyWith(events: updatedEvents),
                        );
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Strums use a half-beat gate with 12 ms between strings.',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StrumStep extends StatefulWidget {
  const _StrumStep({
    required this.tick,
    required this.event,
    required this.onTap,
  });
  final int tick;
  final GuitarStrumEvent? event;
  final VoidCallback onTap;

  @override
  State<_StrumStep> createState() => _StrumStepState();
}

class _StrumStepState extends State<_StrumStep> {
  bool _showFocusHighlight = false;

  @override
  Widget build(BuildContext context) {
    final direction = widget.event?.direction;
    final color = switch (direction) {
      GuitarStrumDirection.down => MuzicianTheme.sky,
      GuitarStrumDirection.up => MuzicianTheme.emerald,
      null => MuzicianTheme.glassBorder,
    };
    final symbol = switch (direction) {
      GuitarStrumDirection.down => '↓',
      GuitarStrumDirection.up => '↑',
      null => '–',
    };
    return FocusableActionDetector(
      key: Key('guitarStrumStep_${widget.tick}'),
      onShowFocusHighlight: (show) =>
          setState(() => _showFocusHighlight = show),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        focused: _showFocusHighlight,
        label: 'Step ${widget.tick + 1}, ${direction?.name ?? 'off'}',
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            key: Key('guitarStrumStepFace_${widget.tick}'),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: direction == null ? .05 : .18),
              border: Border.all(
                color: _showFocusHighlight
                    ? MuzicianTheme.textPrimary
                    : color.withValues(alpha: .75),
                width: _showFocusHighlight ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  symbol,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${widget.tick + 1}',
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 9,
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
