import 'package:daily_planner/services/native_preferences_service.dart';
import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  static const _themeKey = 'theme_mode';

  // Default theme is system
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  String get themeModeName {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.light:
        return 'Light Mode';
    }
  }

  bool isDarkTheme(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final storedString = prefs.getString(_themeKey);

    if (storedString != null) {
      switch (storedString) {
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'system':
        default:
          _themeMode = ThemeMode.system;
          break;
      }
    } else {
      // Legacy check if stored as bool previously
      final bool? legacyBool = prefs.getBool(_themeKey) ?? prefs.getBool('isDarkMode');
      if (legacyBool != null) {
        _themeMode = legacyBool ? ThemeMode.dark : ThemeMode.light;
      } else {
        // Default to system
        _themeMode = ThemeMode.system;
      }
    }

    debugPrint('🌓 Loaded theme mode: $_themeMode (default: system)');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final String value = mode == ThemeMode.system
        ? 'system'
        : (mode == ThemeMode.dark ? 'dark' : 'light');
    await prefs.setString(_themeKey, value);
    debugPrint('💾 Saved theme preference: $value');
  }

  Future<void> toggleTheme(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }
}
