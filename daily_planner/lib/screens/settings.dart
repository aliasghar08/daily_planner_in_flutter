import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/theme_provider.dart';
import 'package:daily_planner/providers/settings_provider.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/passkey_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/services/custom_state_management.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _passkeySupported = false;
  bool _passkeyEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkPasskeySupport();
  }

  Future<void> _checkPasskeySupport() async {
    final supported = await PasskeyAuthService().isPasskeySupported();
    final hasKey = await PasskeyAuthService().hasPasskeyRegistered();
    if (mounted) {
      setState(() {
        _passkeySupported = supported;
        _passkeyEnabled = hasKey;
      });
    }
  }

  void _showThemeDialog(BuildContext context, ThemeProvider themeProvider) {
    final modes = [
      {'title': 'System Default', 'mode': ThemeMode.system, 'icon': Icons.brightness_auto},
      {'title': 'Light Mode', 'mode': ThemeMode.light, 'icon': Icons.light_mode_outlined},
      {'title': 'Dark Mode', 'mode': ThemeMode.dark, 'icon': Icons.dark_mode_outlined},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Theme"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: modes.map((item) {
            final mode = item['mode'] as ThemeMode;
            final isSelected = themeProvider.themeMode == mode;
            return ListTile(
              leading: Icon(
                item['icon'] as IconData,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey,
              ),
              title: Text(
                item['title'] as String,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey,
              ),
              onTap: () {
                themeProvider.setThemeMode(mode);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Language"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: settingsProvider.languages.map((lang) {
            final isSelected = lang == settingsProvider.selectedLanguage;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey,
              ),
              title: Text(lang, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              onTap: () {
                settingsProvider.changeLanguage(lang);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sign Out Confirmation"),
        content: const Text("Are you sure you want to sign out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sign Out"),
          ),
        ],
      ),
    );

    if (shouldLogout == true && context.mounted) {
      try {
        await context.read<app_auth.AuthProvider>().signOut();
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logout failed: ${e.toString()}')),
          );
        }
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF2563EB),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Preferences
          _buildSectionHeader('PREFERENCES'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    themeProvider.themeMode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : (themeProvider.themeMode == ThemeMode.light
                            ? Icons.light_mode_outlined
                            : Icons.brightness_auto),
                    color: const Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                title: const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(themeProvider.themeModeName),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _showThemeDialog(context, themeProvider),
              ),
              const Divider(indent: 56),
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: Color(0xFF10B981), size: 20),
                ),
                title: const Text('Enable Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Receive task alarms and alerts'),
                value: settingsProvider.notificationsEnabled,
                onChanged: (val) => settingsProvider.toggleNotifications(val),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.language_outlined, color: Color(0xFF3B82F6), size: 20),
                ),
                title: const Text('Language', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(settingsProvider.selectedLanguage),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _showLanguageDialog(context),
              ),
            ],
          ),

          // 2. Security & Passkeys
          _buildSectionHeader('SECURITY & PASSKEYS'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              if (_passkeySupported) ...[
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.fingerprint, color: Color(0xFF6366F1), size: 20),
                  ),
                  title: const Text('Passkey / Biometric Login', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Unlock and sign in instantly using fingerprint or face'),
                  value: _passkeyEnabled,
                  onChanged: (val) async {
                    if (val) {
                      final verified = await PasskeyAuthService().verifyPasskey(
                        reason: 'Authenticate to enable Passkey login',
                      );
                      if (verified) {
                        setState(() => _passkeyEnabled = true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Passkey authentication enabled!')),
                          );
                        }
                      }
                    } else {
                      await PasskeyAuthService().clearPasskey();
                      setState(() => _passkeyEnabled = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Passkey credentials cleared.')),
                        );
                      }
                    }
                  },
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 20),
                  ),
                  title: const Text('Test Passkey Sensor', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Verify biometric prompt responsiveness'),
                  trailing: const Icon(Icons.play_circle_outline, size: 20),
                  onTap: () async {
                    final success = await PasskeyAuthService().verifyPasskey(
                      reason: 'Testing biometric sensor',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? '✅ Passkey sensor verified successfully!'
                                : '❌ Passkey verification cancelled or failed.',
                          ),
                          backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
                        ),
                      );
                    }
                  },
                ),
                const Divider(indent: 56),
              ],
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.password, color: Color(0xFF0EA5E9), size: 20),
                ),
                title: const Text('Google & Apple Password Managers', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Active • Automatically prompts to save & autofill passwords'),
                trailing: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
              ),
            ],
          ),

          // 3. Alarm & Background Reliability
          _buildSectionHeader('ALARM & BACKGROUND RELIABILITY'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.battery_charging_full, color: Color(0xFFF59E0B), size: 20),
                ),
                title: const Text('Background & Auto-Start Setup', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Ensure alarms ring on Infinix, Tecno, Xiaomi, Oppo, Vivo, Samsung'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => NativeAlarmHelper.showOemOptimizationGuide(context),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.alarm_on, color: Color(0xFF10B981), size: 20),
                ),
                title: const Text('Test Native Alarm (10s)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Test full-screen ringing and audio'),
                trailing: const Icon(Icons.play_circle_outline, size: 20),
                onTap: () async {
                  await NativeAlarmHelper.testAlarm();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⏰ Test alarm scheduled for 10s from now. Lock phone to test!'),
                        backgroundColor: Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                },
              ),
              const Divider(indent: 56),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.schedule, color: Color(0xFF2563EB), size: 20),
                ),
                title: const Text('Exact Alarm Permission', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Check Android 12+ exact alarm scheduling'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => NativeAlarmHelper.openExactAlarmSettings(),
              ),
            ],
          ),

          // 4. Account
          _buildSectionHeader('ACCOUNT'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_outlined, color: Color(0xFF64748B), size: 20),
                ),
                title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.pushNamed(context, "/changepassword"),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                ),
                title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                onTap: () => _logout(context),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
