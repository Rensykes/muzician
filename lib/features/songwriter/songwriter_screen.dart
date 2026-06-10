import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'songwriter_screen_sheet.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const SongwriterScreenSheet();
}
