import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themePreferenceKey = 'app_theme_mode';

class ThemeController extends ChangeNotifier {
  ThemeController() {
    _loadPreferredTheme();
  }

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> toggleThemeMode() async {
    final nextMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(nextMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePreferenceKey, mode.name);
  }

  Future<void> _loadPreferredTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themePreferenceKey);
    if (stored == null) return;
    switch (stored) {
      case 'dark':
        _themeMode = ThemeMode.dark;
        notifyListeners();
      case 'system':
        _themeMode = ThemeMode.system;
        notifyListeners();
      default:
        _themeMode = ThemeMode.light;
        notifyListeners();
    }
  }
}

