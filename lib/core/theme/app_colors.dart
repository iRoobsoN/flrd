import 'package:flutter/material.dart';

/// Obsidian Glass Color Tokens for the FLRD Premium Desktop experience.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF090D16);
  static const Color backgroundSecondary = Color(0xFF0D121F);
  
  // Surfaces & Glass
  static const Color surface = Color(0xFF111726);
  static const Color surfaceCard = Color(0xFF141B2D);
  static const Color surfaceHover = Color(0xFF1B243C);
  static const Color surfaceSelected = Color(0xFF1E2845);
  
  // Borders
  static const Color border = Color(0x1FFFFFFF); // 12% white
  static const Color borderSubtle = Color(0x0DFFFFFF); // 5% white
  static const Color borderHover = Color(0x33FFFFFF); // 20% white
  static const Color borderActive = Color(0xFF6366F1); // Indigo glow

  // Accents & Gradients
  static const Color primary = Color(0xFF6366F1); // Electric Indigo
  static const Color primaryHover = Color(0xFF4F46E5);
  static const Color primaryGlow = Color(0x4D6366F1);
  
  static const Color secondary = Color(0xFF38BDF8); // Cyber Cyan
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color danger = Color(0xFFEF4444); // Crimson

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textPlaceholder = Color(0xFF475569);

  // Linear & Radial Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0x1A6366F1), Color(0x05090D16)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
