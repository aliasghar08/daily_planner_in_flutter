import 'package:daily_planner/services/native_preferences_service.dart';
import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'English';

  /// Guards against calling notifyListeners() after the provider is disposed.
  bool _disposed = false;

  bool get notificationsEnabled => _notificationsEnabled;
  String get selectedLanguage => _selectedLanguage;

  final List<String> languages = ['English', 'Urdu', 'Turkish'];

  SettingsProvider() {
    _loadPreferences();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Safe notify — skips if the provider has been disposed.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _selectedLanguage = prefs.getString('language') ?? 'English';
      _safeNotify();
    } catch (e) {
      debugPrint('SettingsProvider: Error loading preferences: $e');
    }
  }

  Future<void> toggleNotifications(bool val) async {
    _notificationsEnabled = val;
    _safeNotify();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', val);
    } catch (e) {
      debugPrint('SettingsProvider: Error saving notifications setting: $e');
    }
  }

  Future<void> changeLanguage(String lang) async {
    _selectedLanguage = lang;
    _safeNotify();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', lang);
    } catch (e) {
      debugPrint('SettingsProvider: Error saving language setting: $e');
    }
  }
}