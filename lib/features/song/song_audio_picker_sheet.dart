import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/muzician_theme.dart';

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
    return Container(
      decoration: const BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (recordSupported)
              ListTile(
                leading:
                    const Icon(Icons.mic, color: MuzicianTheme.textPrimary),
                title: const Text(
                  'Record audio',
                  style: TextStyle(color: MuzicianTheme.textPrimary),
                ),
                subtitle: const Text(
                  'Overdub with count-in, preview, and place',
                  style: TextStyle(color: MuzicianTheme.textSecondary),
                ),
                onTap: onRecord,
              ),
            ListTile(
              leading: const Icon(
                Icons.file_open,
                color: MuzicianTheme.textPrimary,
              ),
              title: const Text(
                'Import audio file',
                style: TextStyle(color: MuzicianTheme.textPrimary),
              ),
              subtitle: const Text(
                'WAV, MP3, or M4A',
                style: TextStyle(color: MuzicianTheme.textSecondary),
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
