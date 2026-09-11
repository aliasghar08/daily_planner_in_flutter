import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/theme_provider.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/native_permission_service.dart';
import 'package:daily_planner/utils/passkey_auth_service.dart';
import 'package:daily_planner/screens/sync_integrations_page.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/services/custom_state_management.dart';
import 'package:daily_planner/services/native_preferences_service.dart';
import 'dart:io' show Platform;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ── Biometric / Passkey ──────────────────────────────────────────────────
  bool _passkeySupported = false;
  bool _passkeyEnabled = false;

  // ── Notification permission state (Android) ──────────────────────────────
  bool _notifPermGranted = false;
  bool _exactAlarmGranted = false;
  int _androidSdk = 0;

  // ── Notification permission state (iOS) ──────────────────────────────────
  bool _iosNotifGranted = false;

  bool _loadingPerms = true;

  @override
  void initState() {
    super.initState();
    _loadAllState();
  }

  // ── Load / Reload everything ─────────────────────────────────────────────

  Future<void> _loadAllState() async {
    if (!mounted) return;
    setState(() => _loadingPerms = true);

    // Reload the native prefs cache so we always read fresh values
    // (fixes the passkey toggle appearing OFF after navigating away & back)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
    } catch (_) {}

    await Future.wait([
      _checkPasskeySupport(),
      _loadNotifPermissions(),
    ]);

    if (mounted) setState(() => _loadingPerms = false);
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

  Future<void> _loadNotifPermissions() async {
    if (Platform.isAndroid) {
      final notif = await NativePermissionService.isNotificationPermissionGranted();
      final exact = await NativePermissionService.isExactAlarmPermissionGranted();
      final sdk = await NativePermissionService.getAndroidSdkVersion();
      if (mounted) {
        setState(() {
          _notifPermGranted = notif;
          _exactAlarmGranted = exact;
          _androidSdk = sdk;
        });
      }
    } else if (Platform.isIOS) {
      final granted = await NativePermissionService.isNotificationPermissionGranted();
      if (mounted) {
        setState(() => _iosNotifGranted = granted);
      }
    }
  }

  // ── Dialog helpers ────────────────────────────────────────────────────────

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

  // ── Build helpers ─────────────────────────────────────────────────────────

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

  /// Compact permission row with a status chip and an action button.
  Widget _buildPermissionRow({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool granted,
    String actionLabel = 'Enable',
    VoidCallback? onAction,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
      trailing: granted
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                SizedBox(width: 4),
                Text('Granted', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
              ],
            )
          : TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onAction,
              child: Text(actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
    );
  }

  // ── Android notification permissions section ──────────────────────────────

  Widget _buildAndroidNotificationSection(bool isDark) {
    return _buildSettingsCard(
      isDark: isDark,
      children: [
        // Standard notifications
        _buildPermissionRow(
          isDark: isDark,
          icon: Icons.notifications_active_outlined,
          iconColor: const Color(0xFF10B981),
          title: 'Notifications',
          subtitle: _androidSdk >= 33
              ? 'Android 13+ runtime permission required'
              : 'Post alerts, task reminders & alarms',
          granted: _notifPermGranted,
          actionLabel: 'Request',
          onAction: () async {
            final granted = await NativePermissionService.requestNotificationPermission();
            if (!granted && mounted) {
              // Permission denied — open system settings
              await NativePermissionService.openNotificationSettings();
            }
            await _loadNotifPermissions();
          },
        ),
        const Divider(indent: 56),

        // Exact alarms (Android 12+ API 31+)
        if (_androidSdk >= 31) ...[
          _buildPermissionRow(
            isDark: isDark,
            icon: Icons.alarm_outlined,
            iconColor: const Color(0xFF2563EB),
            title: 'Exact Alarms',
            subtitle: 'Android 12+ — required to ring at precise times',
            granted: _exactAlarmGranted,
            actionLabel: 'Open Settings',
            onAction: () async {
              await NativePermissionService.requestExactAlarmPermission();
              await _loadNotifPermissions();
            },
          ),
          const Divider(indent: 56),
        ],

        // Open system notification settings shortcut
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tune_outlined, color: Color(0xFF6366F1), size: 20),
          ),
          title: const Text('Notification Channels', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Manage per-channel sound, vibration & importance', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => NativePermissionService.openNotificationSettings(),
        ),
      ],
    );
  }

  // ── iOS notification permissions section ──────────────────────────────────

  Widget _buildIosNotificationSection(bool isDark) {
    return _buildSettingsCard(
      isDark: isDark,
      children: [
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iosNotifGranted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
              color: _iosNotifGranted ? const Color(0xFF10B981) : Colors.orange,
              size: 20,
            ),
          ),
          title: const Text('Notification Status', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            _iosNotifGranted
                ? 'Notifications are enabled — alerts, banners & sounds active'
                : 'Notifications are disabled — tap to enable in iOS Settings',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
          ),
          trailing: _iosNotifGranted
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 4),
                    Text('On', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                  ],
                )
              : const Icon(Icons.chevron_right, size: 20, color: Colors.orange),
          onTap: _iosNotifGranted
              ? null
              : () async {
                  await NativePermissionService.openNotificationSettings();
                  // Re-check after returning from iOS Settings
                  await Future.delayed(const Duration(milliseconds: 500));
                  await _loadNotifPermissions();
                },
        ),
        const Divider(indent: 56),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.settings_outlined, color: Color(0xFF6366F1), size: 20),
          ),
          title: const Text('Open iOS Settings', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Manage notifications, sounds & critical alerts', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => NativePermissionService.openNotificationSettings(),
        ),
      ],
    );
  }

  // ── Main build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // Refresh button to re-check all permission states
          if (!_loadingPerms)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh permissions',
              onPressed: _loadAllState,
            ),
        ],
      ),
      body: _loadingPerms
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // ── 1. Preferences ──────────────────────────────────────────
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
                  ],
                ),

                // ── 2. Notifications ────────────────────────────────────────
                _buildSectionHeader('NOTIFICATIONS'),
                if (Platform.isAndroid)
                  _buildAndroidNotificationSection(isDark)
                else if (Platform.isIOS)
                  _buildIosNotificationSection(isDark),

                // ── 3. Cloud Sync & Integrations ────────────────────────────
                _buildSectionHeader('CLOUD SYNC & INTEGRATIONS'),
                _buildSettingsCard(
                  isDark: isDark,
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.sync_outlined, color: Color(0xFF2563EB), size: 20),
                      ),
                      title: const Text('Google & Health Sync', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Google Calendar, Google Tasks & Health Connect / Apple Health',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SyncIntegrationsPage()),
                        );
                      },
                    ),
                  ],
                ),

                // ── 4. Security & Passkeys ──────────────────────────────────
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
                              await PasskeyAuthService().setPasskeyEnabled(true);
                              if (mounted) setState(() => _passkeyEnabled = true);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Passkey authentication enabled!')),
                                );
                              }
                            }
                          } else {
                            await PasskeyAuthService().clearPasskey();
                            if (mounted) setState(() => _passkeyEnabled = false);
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

                // ── 5. Alarm & Background Reliability (Android only) ────────
                if (Platform.isAndroid) ...[
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
                    ],
                  ),
                ],

                // ── 6. Account ──────────────────────────────────────────────
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
