import 'package:daily_planner/services/native_preferences_service.dart';
import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'English';

  bool get notificationsEnabled => _notificationsEnabled;
  String get selectedLanguage => _selectedLanguage;

  final List<String> languages = ['English', 'Urdu', 'Turkish'];

  SettingsProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    _selectedLanguage = prefs.getString('language') ?? 'English';
    notifyListeners();
  }

  Future<void> toggleNotifications(bool val) async {
    _notificationsEnabled = val;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', val);
  }

  Future<void> changeLanguage(String lang) async {
    _selectedLanguage = lang;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
  }
}
