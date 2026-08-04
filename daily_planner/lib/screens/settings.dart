import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/theme_provider.dart';
import 'package:daily_planner/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showLanguageDialog(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Select Language"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  settingsProvider.languages.map((lang) {
                    return RadioListTile<String>(
                      value: lang,
                      groupValue: settingsProvider.selectedLanguage,
                      title: Text(lang),
                      onChanged: (value) {
                        if (value != null) {
                          settingsProvider.changeLanguage(value);
                          Navigator.pop(context);
                        }
                      },
                    );
                  }).toList(),
            ),
          ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await context.read<app_auth.AuthProvider>().signOut();
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

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
            value: themeProvider.isDarkMode,
            onChanged: (val) => themeProvider.toggleTheme(val),
          ),
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: settingsProvider.notificationsEnabled,
            onChanged: (val) => settingsProvider.toggleNotifications(val),
          ),
          ListTile(
            title: const Text('Language'),
            subtitle: Text(settingsProvider.selectedLanguage),
            leading: const Icon(Icons.language),
            onTap: () => _showLanguageDialog(context),
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
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
