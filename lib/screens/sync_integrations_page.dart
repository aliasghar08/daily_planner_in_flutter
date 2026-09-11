import 'package:daily_planner/models/sync_config_model.dart';
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/providers/sync_provider.dart';
import 'package:daily_planner/providers/task_provider.dart';
import 'package:daily_planner/services/custom_state_management.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SyncIntegrationsPage extends StatefulWidget {
  const SyncIntegrationsPage({super.key});

  @override
  State<SyncIntegrationsPage> createState() => _SyncIntegrationsPageState();
}

class _SyncIntegrationsPageState extends State<SyncIntegrationsPage> {
  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 20),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF2563EB),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard({
    required List<Widget> children,
    required bool isDark,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
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
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildStatusBadge(SyncStatus status) {
    Color bg;
    Color fg;
    String text;
    IconData icon;

    switch (status) {
      case SyncStatus.syncing:
        bg = const Color(0xFF3B82F6).withValues(alpha: 0.15);
        fg = const Color(0xFF2563EB);
        text = 'Syncing...';
        icon = Icons.sync;
        break;
      case SyncStatus.success:
        bg = const Color(0xFF10B981).withValues(alpha: 0.15);
        fg = const Color(0xFF059669);
        text = 'Synced';
        icon = Icons.check_circle_outline;
        break;
      case SyncStatus.error:
        bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
        fg = const Color(0xFFDC2626);
        text = 'Error';
        icon = Icons.error_outline;
        break;
      case SyncStatus.disconnected:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey;
        text = 'Disconnected';
        icon = Icons.cloud_off_outlined;
        break;
      case SyncStatus.idle:
        bg = const Color(0xFF6366F1).withValues(alpha: 0.12);
        fg = const Color(0xFF4F46E5);
        text = 'Ready';
        icon = Icons.cloud_queue_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SyncStatus.syncing)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
            )
          else
            Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final taskProvider = context.watch<TaskProvider>();
    final medProvider = context.watch<MedicationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allTasks = taskProvider.tasks;
    final allIntakes = medProvider.todayIntakes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync & Integrations'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Unified Master Sync Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sync, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Universal Cloud Sync',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Calendar, Tasks & Health integration',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${[
                        if (syncProvider.isCalendarEnabled) 'Calendar',
                        if (syncProvider.isTasksEnabled) 'Tasks',
                        if (syncProvider.isHealthEnabled) 'Health',
                      ].length} of 3 active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: syncProvider.isSyncingAll
                          ? null
                          : () async {
                              await syncProvider.syncAll(
                                tasks: allTasks,
                                intakes: allIntakes,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sync completed successfully'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      icon: syncProvider.isSyncingAll
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF2563EB),
                              ),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(
                        syncProvider.isSyncingAll ? 'Syncing...' : 'Sync All Now',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Google Calendar Card
          _buildSectionHeader('GOOGLE CALENDAR'),
          _buildCard(
            isDark: isDark,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_outlined, color: Color(0xFF4285F4), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Calendar',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          syncProvider.googleEmail ?? 'Sync tasks and schedules with Google Calendar',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: syncProvider.isCalendarEnabled,
                    onChanged: (val) => syncProvider.toggleCalendarSync(val),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Synced: ${_formatTimestamp(syncProvider.lastCalendarSync)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildStatusBadge(syncProvider.calendarStatus),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: syncProvider.calendarStatus == SyncStatus.syncing
                        ? null
                        : () async {
                            final res = await syncProvider.syncCalendar(allTasks);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res.message), behavior: SnackBarBehavior.floating),
                              );
                            }
                          },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Calendar'),
                  ),
                ],
              ),
            ],
          ),

          // 3. Google Tasks Card
          _buildSectionHeader('GOOGLE TASKS'),
          _buildCard(
            isDark: isDark,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F9D58).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.task_alt, color: Color(0xFF0F9D58), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Tasks',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          syncProvider.googleEmail ?? 'Two-way sync for todo items and completion status',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: syncProvider.isTasksEnabled,
                    onChanged: (val) => syncProvider.toggleTasksSync(val),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Synced: ${_formatTimestamp(syncProvider.lastTasksSync)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildStatusBadge(syncProvider.tasksStatus),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: syncProvider.tasksStatus == SyncStatus.syncing
                        ? null
                        : () async {
                            final res = await syncProvider.syncGoogleTasks(allTasks);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res.message), behavior: SnackBarBehavior.floating),
                              );
                            }
                          },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Tasks'),
                  ),
                ],
              ),
            ],
          ),

          // 4. Health Platform Card (Health Connect / Apple Health)
          _buildSectionHeader('HEALTH PLATFORM (APPLE HEALTH / HEALTH CONNECT)'),
          _buildCard(
            isDark: isDark,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Color(0xFFE11D48), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Medication & Health Records',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sync medication intake logs, dosages & adherence with Health Connect / Apple Health',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: syncProvider.isHealthEnabled,
                    onChanged: (val) => syncProvider.toggleHealthSync(val),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Synced: ${_formatTimestamp(syncProvider.lastHealthSync)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildStatusBadge(syncProvider.healthStatus),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: syncProvider.healthStatus == SyncStatus.syncing
                        ? null
                        : () async {
                            final res = await syncProvider.syncHealth(allIntakes);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res.message), behavior: SnackBarBehavior.floating),
                              );
                            }
                          },
                    icon: const Icon(Icons.medical_services_outlined, size: 16),
                    label: const Text('Sync Health'),
                  ),
                ],
              ),
            ],
          ),

          // 5. Sync Activity History
          _buildSectionHeader('RECENT SYNC ACTIVITY'),
          _buildCard(
            isDark: isDark,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (syncProvider.logs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'No sync activity recorded yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...syncProvider.logs.take(10).map((log) {
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      log.isSuccess ? Icons.check_circle : Icons.error,
                      color: log.isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 18,
                    ),
                    title: Text(
                      log.serviceType.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      '${log.message} • ${_formatTimestamp(log.timestamp)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    trailing: log.itemsSynced > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${log.itemsSynced}',
                              style: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          )
                        : null,
                  );
                }),
              if (syncProvider.logs.isNotEmpty) ...[
                const Divider(),
                Center(
                  child: TextButton.icon(
                    onPressed: () => syncProvider.clearLogs(),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                    label: const Text('Clear Activity Logs', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
