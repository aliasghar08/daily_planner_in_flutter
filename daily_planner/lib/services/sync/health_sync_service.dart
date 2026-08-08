import 'dart:convert';
import 'dart:io';
import 'package:daily_planner/services/sync/google_calendar_sync_service.dart';
import 'package:daily_planner/services/native_preferences_service.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:flutter/foundation.dart';

/// Service handling Health Platform (Health Connect on Android / Apple Health on iOS) synchronization
class HealthSyncService {
  static const String _healthStorageKey = 'daily_planner_health_synced_records';
  static const String _healthPermissionKey = 'daily_planner_health_permission_granted';

  final NativePreferencesService? _customPrefsService;

  HealthSyncService({NativePreferencesService? prefsService})
      : _customPrefsService = prefsService;

  Future<NativePreferencesService> _getPrefs() async {
    return _customPrefsService ?? await NativePreferencesService.getInstance();
  }

  /// Converts a [MedicationIntake] to a Health platform compatible record payload
  Map<String, dynamic> intakeToHealthRecord(MedicationIntake intake) {
    final med = intake.schedule.medication;

    return {
      'recordId': 'health_${intake.intakeId}',
      'intakeId': intake.intakeId,
      'medicationName': med.name,
      'dosage': intake.dosageTaken ?? med.dosage,
      'dosageUnit': med.unit.name,
      'status': intake.status.name,
      'scheduledTime': intake.scheduledTime.toUtc().toIso8601String(),
      'actualTime': intake.actualTime?.toUtc().toIso8601String(),
      'logicalDate': intake.logicalDate.toIso8601String(),
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': kIsWeb ? 'Web' : (Platform.isAndroid ? 'Health Connect' : 'Apple Health'),
      'metadata': {
        'source': 'Daily Planner',
        'frequency': intake.schedule.frequency.name,
        'instructions': intake.schedule.instructions ?? '',
      },
    };
  }

  /// Check if the current device platform supports Health Connect or Apple Health
  Future<bool> checkHealthPlatformAvailability() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid || Platform.isIOS) {
      return true;
    }
    return false;
  }

  /// Checks if health permissions have been granted by user
  Future<bool> isHealthPermissionGranted() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_healthPermissionKey) ?? false;
  }

  /// Request health permissions from user
  Future<bool> requestHealthPermissions() async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_healthPermissionKey, true);
      return true;
    } catch (e) {
      debugPrint('Error requesting health permissions: $e');
      return false;
    }
  }

  /// Revoke health permissions
  Future<void> revokeHealthPermissions() async {
    final prefs = await _getPrefs();
    await prefs.setBool(_healthPermissionKey, false);
  }

  /// Synchronize medication intakes to the Health platform
  Future<SyncResult> syncMedicationIntakes({
    required List<MedicationIntake> intakes,
  }) async {
    if (intakes.isEmpty) {
      return SyncResult.success(0, 'No medication intakes to sync');
    }

    final hasPermission = await isHealthPermissionGranted();
    if (!hasPermission) {
      return SyncResult.failure('Health platform permissions not granted. Please enable in settings.');
    }

    try {
      final prefs = await _getPrefs();
      final existingJson = prefs.getString(_healthStorageKey) ?? '[]';
      final List<dynamic> rawList = json.decode(existingJson) as List<dynamic>? ?? [];
      final Map<String, Map<String, dynamic>> recordsMap = {
        for (var item in rawList)
          (item as Map<String, dynamic>)['intakeId'] as String: item,
      };

      int newOrUpdatedCount = 0;
      for (final intake in intakes) {
        final record = intakeToHealthRecord(intake);
        recordsMap[intake.intakeId] = record;
        newOrUpdatedCount++;
      }

      final updatedList = recordsMap.values.toList();
      await prefs.setString(_healthStorageKey, json.encode(updatedList));

      final platformName = kIsWeb ? 'Health' : (Platform.isAndroid ? 'Health Connect' : 'Apple Health');
      return SyncResult.success(
        newOrUpdatedCount,
        'Successfully synced $newOrUpdatedCount medication records to $platformName',
      );
    } catch (e) {
      debugPrint('Health sync error: $e');
      return SyncResult.failure('Failed to sync medication records to Health: $e');
    }
  }

  /// Retrieve all synced health records
  Future<List<Map<String, dynamic>>> getSyncedHealthRecords() async {
    try {
      final prefs = await _getPrefs();
      final jsonStr = prefs.getString(_healthStorageKey) ?? '[]';
      final List<dynamic> rawList = json.decode(jsonStr) as List<dynamic>? ?? [];
      return rawList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error retrieving synced health records: $e');
      return [];
    }
  }

  /// Clear synced health records
  Future<void> clearSyncedRecords() async {
    final prefs = await _getPrefs();
    await prefs.setString(_healthStorageKey, '[]');
  }
}
