/// LoadFeedbackToast – animated overlay for success/warning feedback.
library;

import 'package:flutter/material.dart';

class LoadFeedbackToast extends StatelessWidget {
  final String message;
  final bool isWarning;

  const LoadFeedbackToast({
    super.key,
    required this.message,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 18,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isWarning
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                  : const Color(0xFF4ADE80).withValues(alpha: 0.35),
              width: 0.5,
            ),
            color: isWarning
                ? const Color(0xFF78350F).withValues(alpha: 0.34)
                : const Color(0xFF15803D).withValues(alpha: 0.22),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
