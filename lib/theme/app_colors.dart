import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primaryBlue = Color(0xFF1A73E8);
  static const Color primaryEmerald = Color(0xFF00A37A);
  static const Color neutralBackground = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFEFEFF);
  static const Color surfaceMuted = Color(0xFFF1F3F6);
  static const Color outline = Color(0xFFE2E7EE);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5565);
  static const Color success = Color(0xFF1EB980);
  static const Color warning = Color(0xFFF5A524);
  static const Color danger = Color(0xFFD1435B);

  static LinearGradient primaryGradient({
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
  }) {
    return LinearGradient(
      begin: begin,
      end: end,
      colors: const [
        AppColors.primaryEmerald,
        Color(0xFF34C4A1),
        Color(0xFF7FE7D1),
      ],
    );
  }

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> subtleShadow = [
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ];
}

