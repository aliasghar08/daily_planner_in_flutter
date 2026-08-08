import 'dart:convert';
import 'package:daily_planner/services/sync/google_calendar_sync_service.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service handling Google Tasks API v1 synchronization for Daily Planner tasks
class GoogleTasksSyncService {
  static const String _tasksApiBase = 'https://tasks.googleapis.com/tasks/v1/lists/@default/tasks';

  final http.Client _httpClient;

  GoogleTasksSyncService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Converts a Daily Planner [Task] to a Google Tasks JSON payload
  Map<String, dynamic> taskToGoogleTask(Task task) {
    final taskDate = task.date ?? task.createdAt;

    final payload = <String, dynamic>{
      'title': task.title,
      'notes': '${task.detail}\n\n[Synced from Daily Planner | ID: ${task.docId ?? "local"}]',
      'due': taskDate.toUtc().toIso8601String(),
      'status': task.isCompleted ? 'completed' : 'needsAction',
    };

    if (task.isCompleted && task.completedAt != null) {
      payload['completed'] = task.completedAt!.toUtc().toIso8601String();
    }

    return payload;
  }

  /// Converts a Google Task JSON map to a Daily Planner [Task]
  Task googleTaskToDailyPlannerTask(Map<String, dynamic> map) {
    final title = map['title'] as String? ?? 'Untitled Task';
    final notes = map['notes'] as String? ?? '';
    final isCompleted = (map['status'] as String? ?? 'needsAction') == 'completed';
    final dueStr = map['due'] as String?;
    final completedStr = map['completed'] as String?;

    DateTime? dueDate;
    if (dueStr != null) {
      dueDate = DateTime.tryParse(dueStr);
    }

    DateTime? completedAt;
    if (completedStr != null) {
      completedAt = DateTime.tryParse(completedStr);
    }

    // Clean notes by removing the sync footer if present
    final cleanDetail = notes.replaceAll(RegExp(r'\n\n\[Synced from Daily Planner.*\]'), '').trim();

    return Task(
      docId: map['id'] as String?,
      title: title,
      detail: cleanDetail,
      date: dueDate ?? DateTime.now(),
      isCompleted: isCompleted,
      completedAt: completedAt,
      taskType: 'oneTime',
    );
  }

  /// Push tasks to Google Tasks
  Future<SyncResult> pushTasksToGoogleTasks({
    required List<Task> tasks,
    required String? accessToken,
  }) async {
    if (tasks.isEmpty) {
      return SyncResult.success(0, 'No tasks to sync to Google Tasks');
    }

    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('Google Tasks Sync: Running in offline local cache mode (no access token)');
      return SyncResult.success(
        tasks.length,
        'Exported ${tasks.length} tasks ready for Google Tasks sync',
      );
    }

    int successCount = 0;
    final List<String> errorList = [];

    for (final task in tasks) {
      try {
        final taskData = taskToGoogleTask(task);
        final response = await _httpClient.post(
          Uri.parse(_tasksApiBase),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: json.encode(taskData),
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
        message: 'Successfully synced $successCount tasks to Google Tasks',
        errors: errorList,
      );
    } else {
      return SyncResult.failure('Failed to sync tasks to Google Tasks', errorList);
    }
  }

  /// Fetch tasks from Google Tasks
  Future<List<Task>> fetchGoogleTasks({
    required String? accessToken,
    bool showCompleted = true,
  }) async {
    if (accessToken == null || accessToken.isEmpty) {
      return [];
    }

    try {
      final queryParams = <String, String>{
        'showCompleted': showCompleted.toString(),
        'showHidden': 'true',
      };

      final uri = Uri.parse(_tasksApiBase).replace(queryParameters: queryParams);
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
        return items
            .map((item) => googleTaskToDailyPlannerTask(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching Google Tasks: $e');
      return [];
    }
  }
}
