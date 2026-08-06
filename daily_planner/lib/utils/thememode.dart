import 'package:daily_planner/services/native_preferences_service.dart';
import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

class ThemePreferences {
  static const _themeKey = 'theme_mode';

  static Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final storedString = prefs.getString(_themeKey);
    if (storedString != null) {
      switch (storedString) {
        case 'dark':
          themeNotifier.value = ThemeMode.dark;
          break;
        case 'light':
          themeNotifier.value = ThemeMode.light;
          break;
        case 'system':
        default:
          themeNotifier.value = ThemeMode.system;
          break;
      }
    } else {
      final isDark = prefs.getBool(_themeKey);
      if (isDark != null) {
        themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
      } else {
        themeNotifier.value = ThemeMode.system;
      }
    }
  }

  static Future<void> saveTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
  }

  static void setThemeMode(ThemeMode mode) {
    themeNotifier.value = mode;
    final modeStr = mode == ThemeMode.system
        ? 'system'
        : (mode == ThemeMode.dark ? 'dark' : 'light');
    saveTheme(modeStr);
  }

  static void toggleTheme(bool isDarkMode) {
    setThemeMode(isDarkMode ? ThemeMode.dark : ThemeMode.light);
  }
}
