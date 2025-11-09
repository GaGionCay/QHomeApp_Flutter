import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() => _buildTheme(Brightness.light);
  static ThemeData dark() => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark ? _darkScheme : _lightScheme;
    final base = ThemeData(
      colorScheme: colorScheme,
      brightness: brightness,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: colorScheme.surface,
    );

    final textTheme = GoogleFonts.interTightTextTheme(
      isDark
          ? ThemeData(brightness: Brightness.dark).textTheme
          : ThemeData(brightness: Brightness.light).textTheme,
    ).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
        headlineMedium: textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        headlineSmall: textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        titleMedium:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.38),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.38),
        bodySmall: textTheme.bodySmall?.copyWith(height: 1.38),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: _systemOverlayStyleFor(brightness),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.32),
        thickness: 1,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface.withOpacity(0.74)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle:
              textTheme.titleMedium?.copyWith(color: colorScheme.onPrimary),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: BorderSide(color: colorScheme.outline),
          foregroundColor: colorScheme.onSurface,
          textStyle: textTheme.titleSmall,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.navySurfaceElevated.withOpacity(0.82)
            : AppColors.neutralSurface.withOpacity(0.88),
        border: _glassInputBorder(colorScheme, borderRadius: 20),
        enabledBorder: _glassInputBorder(colorScheme, borderRadius: 20),
        focusedBorder:
            _glassInputBorder(colorScheme, borderRadius: 22, focused: true),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.45),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.65),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        prefixIconColor: colorScheme.primary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withOpacity(0.14),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withOpacity(0.66),
            size: isSelected ? 26 : 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withOpacity(0.7),
          );
        }),
        elevation: 0,
        height: 72,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor:
            WidgetStateProperty.all(colorScheme.primary.withOpacity(0.3)),
        radius: const Radius.circular(12),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      splashColor: colorScheme.primary.withOpacity(0.08),
      highlightColor: Colors.transparent,
      hoverColor: colorScheme.primary.withOpacity(0.05),
    );
  }

  static InputBorder _glassInputBorder(
    ColorScheme scheme, {
    required double borderRadius,
    bool focused = false,
  }) {
    final color = focused ? scheme.primary : scheme.outlineVariant;
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(
          color: color.withOpacity(focused ? 0.6 : 0.24),
          width: focused ? 1.2 : 1),
    );
  }

  static SystemUiOverlayStyle _systemOverlayStyleFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );
  }

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primaryBlue,
    onPrimary: Colors.white,
    secondary: AppColors.primaryEmerald,
    onSecondary: Colors.white,
    tertiary: AppColors.skyMist,
    onTertiary: AppColors.textPrimary,
    error: AppColors.danger,
    onError: Colors.white,
    surface: AppColors.neutralSurface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.neutralBackground,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.neutralOutline,
    outlineVariant: Color(0xFFDAE1EC),
    shadow: Colors.black54,
    scrim: Color(0xCC0F1B2B),
    inverseSurface: AppColors.textPrimary,
    onInverseSurface: AppColors.neutralSurface,
    inversePrimary: AppColors.primaryAqua,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF73D9FF),
    onPrimary: Color(0xFF041522),
    secondary: Color(0xFF42E0CD),
    onSecondary: Color(0xFF021923),
    tertiary: Color(0xFF4DA4FF),
    onTertiary: Colors.white,
    error: AppColors.danger,
    onError: Colors.white,
    surface: AppColors.navySurface,
    onSurface: Colors.white,
    surfaceContainerHighest: AppColors.navySurfaceElevated,
    onSurfaceVariant: Color(0xFFB8C8E5),
    outline: AppColors.navyOutline,
    outlineVariant: Color(0xFF1F314B),
    shadow: Colors.black,
    scrim: Color(0xDD010A17),
    inverseSurface: AppColors.neutralSurface,
    onInverseSurface: AppColors.textPrimary,
    inversePrimary: AppColors.primaryBlue,
  );
}
