import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/songwriter_store.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final section in project.sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(section.label ?? 'Section',
                          key: Key('section_${section.id}')),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('songwriterAddSection'),
                      onPressed: () =>
                          notifier.addSection(label: null, lengthBars: 8),
                      icon: const Icon(Icons.add),
                      label: const Text('Add section'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
