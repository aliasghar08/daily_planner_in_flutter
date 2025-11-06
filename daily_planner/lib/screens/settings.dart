import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_planner/utils/thememode.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'English';

  final List<String> _languages = ['English', 'Urdu', 'Turkish'];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode =
          prefs.getBool('dark_mode') ?? themeNotifier.value == ThemeMode.dark;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _selectedLanguage = prefs.getString('language') ?? 'English';
    });
    themeNotifier.value = _isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _toggleDarkMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDarkMode = val);
    themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
    await prefs.setBool('dark_mode', val);
    ThemePreferences.toggleTheme(val);
  }

  Future<void> _toggleNotifications(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _notificationsEnabled = val);
    await prefs.setBool('notifications_enabled', val);

    if (val) {
      await NativeAlarmHelper.requestExactAlarmPermission();
    }
  }

  Future<void> _changeLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _selectedLanguage = lang);
    await prefs.setString('language', lang);
    Navigator.pop(context);
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Select Language"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  _languages.map((lang) {
                    return RadioListTile<String>(
                      value: lang,
                      groupValue: _selectedLanguage,
                      title: Text(lang),
                      onChanged: (value) {
                        if (value != null) {
                          _changeLanguage(value);
                        }
                      },
                    );
                  }).toList(),
            ),
          ),
    );
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blueAccent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Preferences',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: _isDarkMode,
            onChanged: _toggleDarkMode,
          ),
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: _notificationsEnabled,
            onChanged: _toggleNotifications,
          ),
          ListTile(
            title: const Text('Language'),
            subtitle: Text(_selectedLanguage),
            leading: const Icon(Icons.language),
            onTap: _showLanguageDialog,
          ),
          const Divider(),
          const Text(
            'Account',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            onTap: () => Navigator.pushNamed(context, "/changepassword"),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log Out'),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}
