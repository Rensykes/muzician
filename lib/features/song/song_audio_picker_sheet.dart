import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/studio_theme.dart';

class SongAudioPickerSheet extends ConsumerWidget {
  final String trackId;
  final int startTick;
  final bool recordSupported;
  final VoidCallback onRecord;
  final VoidCallback onImport;

  const SongAudioPickerSheet({
    super.key,
    required this.trackId,
    required this.startTick,
    required this.onRecord,
    required this.onImport,
    bool? recordSupported,
  }) : recordSupported = recordSupported ?? !kIsWeb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = StudioPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.isStudio
                    ? palette.textMuted
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (recordSupported)
              ListTile(
                leading: Icon(Icons.mic, color: palette.textPrimary),
                title: Text(
                  'Record audio',
                  style: TextStyle(color: palette.textPrimary),
                ),
                subtitle: Text(
                  'Overdub with count-in, preview, and place',
                  style: TextStyle(color: palette.textSecondary),
                ),
                onTap: onRecord,
              ),
            ListTile(
              leading: Icon(Icons.file_open, color: palette.textPrimary),
              title: Text(
                'Import audio file',
                style: TextStyle(color: palette.textPrimary),
              ),
              subtitle: Text(
                'WAV, MP3, or M4A',
                style: TextStyle(color: palette.textSecondary),
              ),
              onTap: onImport,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
