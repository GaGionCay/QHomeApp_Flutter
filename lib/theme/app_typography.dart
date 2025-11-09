import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  static TextTheme lightTextTheme(TextTheme base) => _build(base, Colors.black);

  static TextTheme darkTextTheme(TextTheme base) => _build(base, Colors.white);

  static TextTheme _build(TextTheme base, Color color) {
    final inter = GoogleFonts.interTightTextTheme(base);
    return inter.apply(
      bodyColor: color,
      displayColor: color,
    );
  }
}
