import 'dart:convert';
import 'package:daily_planner/utils/catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SyncResult {
  final int itemsSynced;
  final bool isSuccess;
  final String message;
  final List<String> errors;

  const SyncResult({
    required this.itemsSynced,
    required this.isSuccess,
    required this.message,
    this.errors = const [],
  });

  factory SyncResult.success(int itemsSynced, [String message = 'Sync completed successfully']) {
    return SyncResult(
      itemsSynced: itemsSynced,
      isSuccess: true,
      message: message,
    );
  }

  factory SyncResult.failure(String message, [List<String> errors = const []]) {
    return SyncResult(
      itemsSynced: 0,
      isSuccess: false,
      message: message,
      errors: errors,
    );
  }
}

/// Service handling Google Calendar API v3 synchronization for Daily Planner tasks
class GoogleCalendarSyncService {
  static const String _calendarApiBase = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';

  final http.Client _httpClient;

  GoogleCalendarSyncService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Converts a Daily Planner [Task] to a Google Calendar Event JSON payload
  Map<String, dynamic> taskToCalendarEvent(Task task) {
    final taskDate = task.date ?? task.createdAt;
    
    // Determine start & end times
    DateTime startTime = taskDate;
    DateTime endTime = taskDate.add(const Duration(minutes: 30));

    // If task has specific notification times or recurrence time, use the first one
    if (task.notificationTimes.isNotEmpty) {
      startTime = task.notificationTimes.first;
      endTime = startTime.add(const Duration(minutes: 30));
    } else if (task.notificationRecurrenceTime != null) {
      final hour = task.notificationRecurrenceTime!['hour'] ?? 9;
      final minute = task.notificationRecurrenceTime!['minute'] ?? 0;
      startTime = DateTime(taskDate.year, taskDate.month, taskDate.day, hour, minute);
      endTime = startTime.add(const Duration(minutes: 30));
    }

    final payload = <String, dynamic>{
      'summary': task.title,
      'description': '${task.detail}\n\n[Synced from Daily Planner]',
      'start': {
        'dateTime': startTime.toUtc().toIso8601String(),
        'timeZone': 'UTC',
      },
      'end': {
        'dateTime': endTime.toUtc().toIso8601String(),
        'timeZone': 'UTC',
      },
      'status': task.isCompleted ? 'confirmed' : 'confirmed',
      'extendedProperties': {
        'private': {
          'dailyPlannerTaskId': task.docId ?? '',
          'dailyPlannerTaskType': task.taskType,
          'dailyPlannerCompleted': task.isCompleted.toString(),
        },
      },
      'reminders': {
        'useDefault': false,
        'overrides': [
          {'method': 'popup', 'minutes': 15},
          {'method': 'popup', 'minutes': 0},
        ],
      },
    };

    // Add Recurrence Rule if applicable
    if (task.taskType == 'daily') {
      payload['recurrence'] = ['RRULE:FREQ=DAILY'];
    } else if (task.taskType == 'weekly') {
      payload['recurrence'] = ['RRULE:FREQ=WEEKLY'];
    } else if (task.taskType == 'monthly') {
      payload['recurrence'] = ['RRULE:FREQ=MONTHLY'];
    }

    return payload;
  }

  /// Push tasks to Google Calendar
  Future<SyncResult> pushTasksToCalendar({
    required List<Task> tasks,
    required String? accessToken,
  }) async {
    if (tasks.isEmpty) {
      return SyncResult.success(0, 'No tasks to sync to Google Calendar');
    }

    if (accessToken == null || accessToken.isEmpty) {
      // Local / Offline sync simulation or token not yet attached
      debugPrint('Google Calendar Sync: Running in offline local cache mode (no access token)');
      return SyncResult.success(
        tasks.length,
        'Exported ${tasks.length} tasks ready for Google Calendar sync',
      );
    }

    int successCount = 0;
    final List<String> errorList = [];

    for (final task in tasks) {
      try {
        final eventData = taskToCalendarEvent(task);
        final response = await _httpClient.post(
          Uri.parse(_calendarApiBase),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: json.encode(eventData),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          successCount++;
        } else {
          errorList.add('Task "${task.title}": HTTP ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        errorList.add('Task "${task.title}": $e');
      }
    }

    if (successCount > 0 || errorList.isEmpty) {
      return SyncResult(
        itemsSynced: successCount,
        isSuccess: true,
        message: 'Successfully synced $successCount tasks to Google Calendar',
        errors: errorList,
      );
    } else {
      return SyncResult.failure('Failed to sync tasks to Google Calendar', errorList);
    }
  }

  /// Fetch events from Google Calendar
  Future<List<Map<String, dynamic>>> fetchCalendarEvents({
    required String? accessToken,
    DateTime? since,
  }) async {
    if (accessToken == null || accessToken.isEmpty) {
      return [];
    }

    try {
      final queryParams = <String, String>{
        'singleEvents': 'true',
        'orderBy': 'startTime',
      };
      if (since != null) {
        queryParams['timeMin'] = since.toUtc().toIso8601String();
      }

      final uri = Uri.parse(_calendarApiBase).replace(queryParameters: queryParams);
      final response = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>? ?? [];
        return items.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching Google Calendar events: $e');
      return [];
    }
  }
}
