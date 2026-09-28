import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/save_system.dart';
import 'songwriter_screen_sheet.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key, this.onEditInstrumentSave});

  final ValueChanged<SaveEntry>? onEditInstrumentSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SongwriterScreenSheet(onEditInstrumentSave: onEditInstrumentSave);
}
