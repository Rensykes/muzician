/// Glassmorphism theme constants for the Muzician app.
library;

import 'package:flutter/material.dart';

abstract final class MuzicianTheme {
  // ── Background ──────────────────────────────────────────────────────────
  static const Color scaffoldBg = Color(0xFF0A0A1E);
  static const List<Color> gradientColors = [
    Color(0xFF0A0A1E),
    Color(0xFF1A1034),
    Color(0xFF16213E),
    Color(0xFF0F3460),
  ];

  // ── Surface / Glass ─────────────────────────────────────────────────────
  static const Color surface = Color(0xFF0A0F1E);
  static Color glassBg = Colors.white.withValues(alpha: 0.03);
  static Color glassBorder = Colors.white.withValues(alpha: 0.07);

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);
  static const Color textDim = Color(0xFF334155);

  // ── Accent Colors ───────────────────────────────────────────────────────
  static const Color sky = Color(0xFF38BDF8);
  static const Color teal = Color(0xFF4ECDC4);
  static const Color violet = Color(0xFFA78BFA);
  static const Color purple = Color(0xFFC084FC);
  static const Color emerald = Color(0xFF34D399);
  static const Color orange = Color(0xFFFB923C);
  static const Color red = Color(0xFFF87171);

  // ── Build Theme ─────────────────────────────────────────────────────────
  static ThemeData dark() => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: scaffoldBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: sky,
      brightness: Brightness.dark,
      surface: surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
