import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../store/songwriter_store.dart';
import '../_mockup_shell.dart';
import 'songwriter_header.dart';
import 'songwriter_save_panel.dart';
import 'songwriter_section_card.dart';
import 'songwriter_structure_editor.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key});

  void _openSaveLoad(BuildContext context) {
    showWidgetSheet(
      context: context,
      title: 'Save / Load',
      child: const SongwriterSavePanel(),
    );
  }

  void _openStructure(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SongwriterStructureEditor(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SongwriterHeader(
              onOpenSaveLoad: () => _openSaveLoad(context),
              onOpenStructure: () => _openStructure(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (project.sections.isEmpty)
                    const _EmptyState(key: Key('songwriterEmptyHint')),
                  for (final section in project.sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SongwriterSectionCard(sectionId: section.id),
                    ),
                  _AddSectionChip(
                    key: const Key('songwriterAddSection'),
                    onTap: () => notifier.addSection(label: null, lengthBars: 8),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 48,
            color: MuzicianTheme.sky.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          const Text(
            'Start composing',
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add a section, build lanes, and drop chord blocks',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AddSectionChip extends StatelessWidget {
  const _AddSectionChip({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MuzicianTheme.sky.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MuzicianTheme.sky.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: MuzicianTheme.sky),
              SizedBox(width: 6),
              Text(
                'Add section',
                style: TextStyle(
                  color: MuzicianTheme.sky,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
