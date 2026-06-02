import 'package:flutter/material.dart';

class SongwriterLaneRow extends StatelessWidget {
  const SongwriterLaneRow({super.key, required this.sectionId, required this.laneId});
  final String sectionId;
  final String laneId;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
