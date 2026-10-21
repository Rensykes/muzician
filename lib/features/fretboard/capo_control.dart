/// Physical capo position, with full-size controls and scrollable fret choices.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/fretboard_store.dart';
import '../../theme/studio_theme.dart';

const _maxCapo = 11;

class CapoControl extends ConsumerWidget {
  const CapoControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capo = ref.watch(fretboardProvider.select((s) => s.capo));
    final notifier = ref.read(fretboardProvider.notifier);
    final p = StudioPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: p.isStudio ? 0 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Capo',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Lower capo',
                onPressed: capo > 0 ? () => notifier.setCapo(capo - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  capo == 0 ? 'Off' : '$capo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: capo == 0 ? p.textSecondary : p.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Raise capo',
                onPressed: capo < _maxCapo
                    ? () => notifier.setCapo(capo + 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var fret = 0; fret <= _maxCapo; fret++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        foregroundColor: capo == fret
                            ? p.orange
                            : p.textSecondary,
                        backgroundColor: capo == fret
                            ? p.orange.withValues(alpha: 0.12)
                            : null,
                      ),
                      onPressed: () =>
                          notifier.setCapo(capo == fret ? 0 : fret),
                      child: Text(fret == 0 ? 'Off' : '$fret'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
