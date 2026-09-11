import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/screens/medication_list_page.dart';
import 'package:daily_planner/screens/settings.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/performance_page/daily_tasks.dart';
import 'package:daily_planner/utils/performance_page/total_tasks.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/services/custom_state_management.dart';
import 'dart:io' show Platform;

class MyDrawer extends StatefulWidget {
  const MyDrawer({super.key});

  @override
  State<MyDrawer> createState() => _MyDrawerState();
}

class _MyDrawerState extends State<MyDrawer> {
  bool _isInsightsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<app_auth.AuthProvider>();
    final user = authProvider.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'User');
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                      : [const Color(0xFF2563EB), const Color(0xFF1D4ED8)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email ?? 'Not signed in',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Drawer Items List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                children: [
                  _buildDrawerTile(
                    icon: Icons.home_rounded,
                    title: 'My Tasks',
                    color: const Color(0xFF2563EB),
                    onTap: () => Navigator.pop(context),
                  ),
                  _buildDrawerTile(
                    icon: Icons.medication_rounded,
                    title: 'Medications',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MedicationListPage()),
                      );
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    color: const Color(0xFF6366F1),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      );
                    },
                  ),
                  if (Platform.isAndroid)
                    _buildDrawerTile(
                      icon: Icons.battery_charging_full_rounded,
                      title: 'Alarm Reliability & OEM Guide',
                      color: const Color(0xFFF59E0B),
                      onTap: () {
                        Navigator.pop(context);
                        NativeAlarmHelper.showOemOptimizationGuide(context);
                      },
                    ),

                  const SizedBox(height: 4),

                  // Expandable Analytics/Insights
                  _buildInsightsSection(isDark),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Divider(),
                  ),

                  _buildDrawerTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign Out',
                    color: const Color(0xFFEF4444),
                    onTap: _handleLogout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: 18,
          color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildInsightsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.insights_rounded, color: Color(0xFF8B5CF6), size: 20),
            ),
            title: Text(
              "Analytics & Stats",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            trailing: Icon(
              _isInsightsExpanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
            onTap: () {
              setState(() {
                _isInsightsExpanded = !_isInsightsExpanded;
              });
            },
          ),
          if (_isInsightsExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 8, top: 2),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    title: const Text("Daily Tasks Stats", style: TextStyle(fontSize: 13)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DailyTasksStats()),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    title: const Text("Total Tasks History", style: TextStyle(fontSize: 13)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TotalTasks()),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Log Out Confirmation"),
        content: const Text("Are you sure you want to sign out of your account?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Sign Out"),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      await context.read<app_auth.AuthProvider>().signOut();
      if (mounted) {
        Navigator.pop(context); // Close the drawer
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    }
  }
}
