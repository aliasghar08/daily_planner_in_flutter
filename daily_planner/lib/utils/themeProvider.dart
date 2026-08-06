import 'package:flutter/material.dart';
import 'package:daily_planner/services/native_preferences_service.dart';

class ThemeProvider with ChangeNotifier {
  static const _themeKey = 'theme_mode';

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

  ThemeProvider() {
    _loadTheme();
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    final String value = mode == ThemeMode.system
        ? 'system'
        : (mode == ThemeMode.dark ? 'dark' : 'light');
    await prefs.setString(_themeKey, value);
  }

  void toggleTheme(bool isOn) {
    setThemeMode(isOn ? ThemeMode.dark : ThemeMode.light);
  }

  void _loadTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
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
      final bool? legacyBool = prefs.getBool('isDarkMode') ?? prefs.getBool(_themeKey);
      if (legacyBool != null) {
        _themeMode = legacyBool ? ThemeMode.dark : ThemeMode.light;
      } else {
        _themeMode = ThemeMode.system;
      }
    }
    notifyListeners();
  }
}
