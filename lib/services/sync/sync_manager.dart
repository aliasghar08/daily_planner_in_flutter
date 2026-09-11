import 'dart:convert';
import 'package:daily_planner/models/sync_config_model.dart';
import 'package:daily_planner/services/native_preferences_service.dart';
import 'package:daily_planner/services/sync/google_calendar_sync_service.dart';
import 'package:daily_planner/services/sync/google_tasks_sync_service.dart';
import 'package:daily_planner/services/sync/health_sync_service.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:flutter/foundation.dart';

/// Master orchestrator for Daily Planner integrations & data synchronization
class SyncManager {
  static const String _configKey = 'daily_planner_sync_config';
  static const String _logsKey = 'daily_planner_sync_logs';
  static const int _maxLogs = 50;

  final NativePreferencesService? _customPrefsService;
  final GoogleCalendarSyncService _calendarService;
  final GoogleTasksSyncService _tasksService;
  final HealthSyncService _healthService;

  SyncManager({
    NativePreferencesService? prefsService,
    GoogleCalendarSyncService? calendarService,
    GoogleTasksSyncService? tasksService,
    HealthSyncService? healthService,
  })  : _customPrefsService = prefsService,
        _calendarService = calendarService ?? GoogleCalendarSyncService(),
        _tasksService = tasksService ?? GoogleTasksSyncService(),
        _healthService = healthService ?? HealthSyncService();

  Future<NativePreferencesService> _getPrefs() async {
    return _customPrefsService ?? await NativePreferencesService.getInstance();
  }

  GoogleCalendarSyncService get calendarService => _calendarService;
  GoogleTasksSyncService get tasksService => _tasksService;
  HealthSyncService get healthService => _healthService;

  /// Load sync configuration from persistent storage
  Future<SyncConfig> loadConfig() async {
    try {
      final prefs = await _getPrefs();
      final jsonStr = prefs.getString(_configKey) ?? '';
      if (jsonStr.isEmpty) {
        return const SyncConfig();
      }
      return SyncConfig.fromJson(jsonStr);
    } catch (e) {
      debugPrint('Error loading sync config: $e');
      return const SyncConfig();
    }
  }

  /// Save sync configuration
  Future<void> saveConfig(SyncConfig config) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_configKey, config.toJson());
    } catch (e) {
      debugPrint('Error saving sync config: $e');
    }
  }

  /// Load sync activity logs
  Future<List<SyncLogEntry>> loadLogs() async {
    try {
      final prefs = await _getPrefs();
      final jsonStr = prefs.getString(_logsKey) ?? '[]';
      final List<dynamic> list = json.decode(jsonStr) as List<dynamic>? ?? [];
      return list
          .map((item) => SyncLogEntry.fromMap(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('Error loading sync logs: $e');
      return [];
    }
  }

  /// Append a sync log entry
  Future<void> addLog(SyncLogEntry entry) async {
    try {
      final currentLogs = await loadLogs();
      currentLogs.insert(0, entry);
      if (currentLogs.length > _maxLogs) {
        currentLogs.removeRange(_maxLogs, currentLogs.length);
      }
      final jsonStr = json.encode(currentLogs.map((e) => e.toMap()).toList());
      final prefs = await _getPrefs();
      await prefs.setString(_logsKey, jsonStr);
    } catch (e) {
      debugPrint('Error saving sync log: $e');
    }
  }

  /// Synchronize Tasks with Google Calendar
  Future<SyncResult> syncGoogleCalendar(
    List<Task> tasks, {
    String? accessToken,
  }) async {
    final result = await _calendarService.pushTasksToCalendar(
      tasks: tasks,
      accessToken: accessToken,
    );

    final config = await loadConfig();
    await saveConfig(config.copyWith(
      lastCalendarSync: DateTime.now(),
    ));

    await addLog(SyncLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceType: SyncServiceType.googleCalendar,
      timestamp: DateTime.now(),
      isSuccess: result.isSuccess,
      message: result.message,
      itemsSynced: result.itemsSynced,
    ));

    return result;
  }

  /// Synchronize Tasks with Google Tasks
  Future<SyncResult> syncGoogleTasks(
    List<Task> tasks, {
    String? accessToken,
  }) async {
    final result = await _tasksService.pushTasksToGoogleTasks(
      tasks: tasks,
      accessToken: accessToken,
    );

    final config = await loadConfig();
    await saveConfig(config.copyWith(
      lastTasksSync: DateTime.now(),
    ));

    await addLog(SyncLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceType: SyncServiceType.googleTasks,
      timestamp: DateTime.now(),
      isSuccess: result.isSuccess,
      message: result.message,
      itemsSynced: result.itemsSynced,
    ));

    return result;
  }

  /// Synchronize Medication Intakes with Health Platform
  Future<SyncResult> syncHealthPlatform(
    List<MedicationIntake> intakes,
  ) async {
    final result = await _healthService.syncMedicationIntakes(
      intakes: intakes,
    );

    final config = await loadConfig();
    await saveConfig(config.copyWith(
      lastHealthSync: DateTime.now(),
      healthPermissionGranted: result.isSuccess,
    ));

    await addLog(SyncLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceType: SyncServiceType.healthPlatform,
      timestamp: DateTime.now(),
      isSuccess: result.isSuccess,
      message: result.message,
      itemsSynced: result.itemsSynced,
    ));

    return result;
  }

  /// Perform unified synchronization across all enabled services
  Future<Map<SyncServiceType, SyncResult>> syncAll({
    required List<Task> tasks,
    required List<MedicationIntake> intakes,
    String? accessToken,
  }) async {
    final config = await loadConfig();
    final results = <SyncServiceType, SyncResult>{};

    if (config.googleCalendarEnabled) {
      results[SyncServiceType.googleCalendar] =
          await syncGoogleCalendar(tasks, accessToken: accessToken);
    }

    if (config.googleTasksEnabled) {
      results[SyncServiceType.googleTasks] =
          await syncGoogleTasks(tasks, accessToken: accessToken);
    }

    if (config.healthSyncEnabled) {
      results[SyncServiceType.healthPlatform] =
          await syncHealthPlatform(intakes);
    }

    return results;
  }
}
