
import 'package:flutter/material.dart';

/// Centralised color tokens for the Resident Super App experience.
///
/// These values lean into a neo-realistic, soft glassmorphism palette that
/// balances airy blues with gentle neutrals and luxe accents.
class AppColors {
  AppColors._();

  // Core brand accents
  static const Color primaryBlue = Color(0xFF007AFF);
  static const Color primaryAqua = Color(0xFF5AC8FA);
  static const Color primaryEmerald = Color(0xFF24D1C4);
  static const Color skyMist = Color(0xFF7EC8E3);

  // Neutrals
  static const Color neutralBackground = Color(0xFFF4F6FA);
  static const Color neutralSurface = Color(0xFFFFFFFF);
  static const Color neutralSurfaceElevated = Color(0xFFF9FBFE);
  static const Color neutralOutline = Color(0xFFCAD1DD);

  // Typography helpers
  static const Color textPrimary = Color(0xFF0F1B2B);
  static const Color textSecondary = Color(0xFF5B6B80);

  // Status colors
  static const Color success = Color(0xFF3CCF91);
  static const Color warning = Color(0xFFFFC773);
  static const Color danger = Color(0xFFFF6B6B);

  // Dark counterparts
  static const Color deepNight = Color(0xFF050F1F);
  static const Color navySurface = Color(0xFF0F1E33);
  static const Color navySurfaceElevated = Color(0xFF14263E);
  static const Color navyOutline = Color(0xFF2F3F57);

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x14102136),
      blurRadius: 32,
      spreadRadius: 0,
      offset: Offset(0, 18),
    ),
    BoxShadow(
      color: Color(0x110F1B2B),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> subtleShadow = [
    BoxShadow(
      color: Color(0x0F4A62A8),
      blurRadius: 18,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x05223B62),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static LinearGradient primaryGradient({
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
  }) {
    return LinearGradient(
      begin: begin,
      end: end,
      colors: const [
        primaryAqua,
        primaryBlue,
      ],
    );
  }

  static LinearGradient glassLayerGradient({
    Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter,
  }) {
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        neutralSurfaceElevated.withOpacity(0.94),
        neutralSurface.withOpacity(0.82),
      ],
    );
  }

  static LinearGradient darkGlassLayerGradient({
    Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter,
  }) {
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        navySurfaceElevated.withOpacity(0.95),
        navySurface.withOpacity(0.88),
      ],
    );
  }

  static LinearGradient heroBackdropGradient() {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF3D7BF7),
        Color(0xFF2FC7E2),
        Color(0xFF73F5D6),
      ],
    );
  }
}
