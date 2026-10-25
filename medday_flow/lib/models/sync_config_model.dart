import 'dart:convert';

enum SyncServiceType {
  googleCalendar,
  googleTasks,
  healthPlatform,
}

extension SyncServiceTypeExtension on SyncServiceType {
  String get displayName {
    switch (this) {
      case SyncServiceType.googleCalendar:
        return 'Google Calendar';
      case SyncServiceType.googleTasks:
        return 'Google Tasks';
      case SyncServiceType.healthPlatform:
        return 'Health Platform';
    }
  }

  String get id {
    switch (this) {
      case SyncServiceType.googleCalendar:
        return 'google_calendar';
      case SyncServiceType.googleTasks:
        return 'google_tasks';
      case SyncServiceType.healthPlatform:
        return 'health_platform';
    }
  }
}

enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  disconnected,
}

class SyncLogEntry {
  final String id;
  final SyncServiceType serviceType;
  final DateTime timestamp;
  final bool isSuccess;
  final String message;
  final int itemsSynced;

  const SyncLogEntry({
    required this.id,
    required this.serviceType,
    required this.timestamp,
    required this.isSuccess,
    required this.message,
    this.itemsSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'serviceType': serviceType.index,
      'timestamp': timestamp.toIso8601String(),
      'isSuccess': isSuccess,
      'message': message,
      'itemsSynced': itemsSynced,
    };
  }

  factory SyncLogEntry.fromMap(Map<String, dynamic> map) {
    return SyncLogEntry(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      serviceType: SyncServiceType.values[map['serviceType'] as int? ?? 0],
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isSuccess: map['isSuccess'] as bool? ?? false,
      message: map['message'] as String? ?? '',
      itemsSynced: map['itemsSynced'] as int? ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory SyncLogEntry.fromJson(String source) =>
      SyncLogEntry.fromMap(json.decode(source) as Map<String, dynamic>);
}

class SyncConfig {
  final bool googleCalendarEnabled;
  final bool googleTasksEnabled;
  final bool healthSyncEnabled;
  final String? googleAccountEmail;
  final DateTime? lastCalendarSync;
  final DateTime? lastTasksSync;
  final DateTime? lastHealthSync;
  final int autoSyncIntervalMinutes;
  final bool syncCompletedTasks;
  final bool healthPermissionGranted;

  const SyncConfig({
    this.googleCalendarEnabled = false,
    this.googleTasksEnabled = false,
    this.healthSyncEnabled = false,
    this.googleAccountEmail,
    this.lastCalendarSync,
    this.lastTasksSync,
    this.lastHealthSync,
    this.autoSyncIntervalMinutes = 30,
    this.syncCompletedTasks = true,
    this.healthPermissionGranted = false,
  });

  SyncConfig copyWith({
    bool? googleCalendarEnabled,
    bool? googleTasksEnabled,
    bool? healthSyncEnabled,
    String? googleAccountEmail,
    DateTime? lastCalendarSync,
    DateTime? lastTasksSync,
    DateTime? lastHealthSync,
    int? autoSyncIntervalMinutes,
    bool? syncCompletedTasks,
    bool? healthPermissionGranted,
  }) {
    return SyncConfig(
      googleCalendarEnabled: googleCalendarEnabled ?? this.googleCalendarEnabled,
      googleTasksEnabled: googleTasksEnabled ?? this.googleTasksEnabled,
      healthSyncEnabled: healthSyncEnabled ?? this.healthSyncEnabled,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      lastCalendarSync: lastCalendarSync ?? this.lastCalendarSync,
      lastTasksSync: lastTasksSync ?? this.lastTasksSync,
      lastHealthSync: lastHealthSync ?? this.lastHealthSync,
      autoSyncIntervalMinutes:
          autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
      syncCompletedTasks: syncCompletedTasks ?? this.syncCompletedTasks,
      healthPermissionGranted:
          healthPermissionGranted ?? this.healthPermissionGranted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'googleCalendarEnabled': googleCalendarEnabled,
      'googleTasksEnabled': googleTasksEnabled,
      'healthSyncEnabled': healthSyncEnabled,
      'googleAccountEmail': googleAccountEmail,
      'lastCalendarSync': lastCalendarSync?.toIso8601String(),
      'lastTasksSync': lastTasksSync?.toIso8601String(),
      'lastHealthSync': lastHealthSync?.toIso8601String(),
      'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
      'syncCompletedTasks': syncCompletedTasks,
      'healthPermissionGranted': healthPermissionGranted,
    };
  }

  factory SyncConfig.fromMap(Map<String, dynamic> map) {
    return SyncConfig(
      googleCalendarEnabled: map['googleCalendarEnabled'] as bool? ?? false,
      googleTasksEnabled: map['googleTasksEnabled'] as bool? ?? false,
      healthSyncEnabled: map['healthSyncEnabled'] as bool? ?? false,
      googleAccountEmail: map['googleAccountEmail'] as String?,
      lastCalendarSync: map['lastCalendarSync'] != null
          ? DateTime.tryParse(map['lastCalendarSync'] as String)
          : null,
      lastTasksSync: map['lastTasksSync'] != null
          ? DateTime.tryParse(map['lastTasksSync'] as String)
          : null,
      lastHealthSync: map['lastHealthSync'] != null
          ? DateTime.tryParse(map['lastHealthSync'] as String)
          : null,
      autoSyncIntervalMinutes: map['autoSyncIntervalMinutes'] as int? ?? 30,
      syncCompletedTasks: map['syncCompletedTasks'] as bool? ?? true,
      healthPermissionGranted: map['healthPermissionGranted'] as bool? ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory SyncConfig.fromJson(String source) =>
      SyncConfig.fromMap(json.decode(source) as Map<String, dynamic>);
}
