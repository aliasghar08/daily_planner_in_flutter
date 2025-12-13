import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CatlalogModel {
  static List<Task> items = [
    Task(
      docId: '1',
      title: "Get the meal",
      detail: "I need to have my dinner done on time",
      date: DateTime.now(),
      isCompleted: true,
      completedAt: DateTime.now(),
      notificationTimes: [],
    ),
    Task(
      docId: '2',
      title: "Get your work done before deadline",
      detail: "I need to get my work done before the deadline at any cost",
      date: DateTime.now(),
      isCompleted: true,
      completedAt: DateTime.now(),
      notificationTimes: [],
    ),
  ];
}

class TaskEdit {
  final DateTime timestamp;
  final String? note;

  TaskEdit({required this.timestamp, this.note});

  factory TaskEdit.fromMap(Map<String, dynamic> map) {
    DateTime ts;
    if (map['timestamp'] is Timestamp) {
      ts = (map['timestamp'] as Timestamp).toDate();
    } else {
      ts = DateTime.tryParse(map['timestamp']) ?? DateTime.now();
    }

    return TaskEdit(timestamp: ts, note: map['note']);
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      if (note != null) 'note': note,
    };
  }
}

class Task {
  String? docId;
  String title;
  String detail;
  DateTime? date;
  bool isCompleted;
  DateTime createdAt;
  DateTime? completedAt;
  List<TaskEdit> editHistory;
  String taskType;
  List<DateTime> notificationTimes;
  List<DateTime> completionStamps;

  // New fields for recurring notifications
  String? notificationRecurrence;
  Map<String, int>? notificationRecurrenceTime; // {'hour': 21, 'minute': 0}
  Map<String, bool>? selectedDays; // For custom days selection

  Task({
    this.docId,
    required this.title,
    required this.detail,
    required this.date,
    required this.isCompleted,
    DateTime? createdAt,
    this.completedAt,
    List<TaskEdit>? editHistory,
    this.taskType = 'oneTime',
    List<DateTime>? notificationTimes,
    List<DateTime>? completionStamps,

    // New fields
    this.notificationRecurrence,
    this.notificationRecurrenceTime,
    this.selectedDays,
  }) : createdAt = createdAt ?? DateTime.now(),
       editHistory = editHistory ?? [],
       notificationTimes = notificationTimes ?? [],
       completionStamps = completionStamps ?? [];

  // ✅ ADDED: Safe getter for notificationRecurrence with default
  String get safeNotificationRecurrence {
    return notificationRecurrence ?? 'none';
  }

  // ✅ ADDED: Safe getter for notificationRecurrenceTime with default
  Map<String, int> get safeNotificationRecurrenceTime {
    if (notificationRecurrenceTime != null) {
      return notificationRecurrenceTime!;
    }
    // Default to 9 PM
    return {'hour': 21, 'minute': 0};
  }

  // ✅ ADDED: Safe getter for selectedDays with default
  Map<String, bool> get safeSelectedDays {
    if (selectedDays != null) {
      return selectedDays!;
    }
    // Return empty map
    return {};
  }

  // ✅ ADDED: Safe getter for notificationRecurrenceTime as TimeOfDay
  TimeOfDay get safeRecurrenceTimeAsTimeOfDay {
    final timeMap = safeNotificationRecurrenceTime;
    return TimeOfDay(
      hour: timeMap['hour'] ?? 21,
      minute: timeMap['minute'] ?? 0,
    );
  }

  factory Task.fromMap(Map<String, dynamic> map, {String? docId}) {
    return parseTaskFromMap(map, docId: docId);
  }

  Map<String, dynamic> toMap() {
    final data = {
      'id': docId,
      'title': title,
      'detail': detail,
      'isCompleted': isCompleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
      'taskType': taskType,
      'notificationTimes':
          notificationTimes.map((dt) => Timestamp.fromDate(dt)).toList(),
      'completionStamps':
          completionStamps.map((dt) => Timestamp.fromDate(dt)).toList(),

      // ✅ FIXED: Use safe getters to ensure data is never null
      'notificationRecurrence': safeNotificationRecurrence,
      'notificationRecurrenceTime': safeNotificationRecurrenceTime,
      'selectedDays': safeSelectedDays,
    };

    if (date != null) {
      data['date'] = Timestamp.fromDate(date!);
    }

    if (completedAt != null) {
      data['completedAt'] = Timestamp.fromDate(completedAt!);
    }

    return data;
  }

  String get type => 'Task';

  Task copyWith({
    String? docId,
    String? title,
    String? detail,
    DateTime? date,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
    List<TaskEdit>? editHistory,
    String? taskType,
    List<DateTime>? notificationTimes,
    List<DateTime>? completionStamps,

    // New fields
    String? notificationRecurrence,
    Map<String, int>? notificationRecurrenceTime,
    Map<String, bool>? selectedDays,
  }) {
    return Task(
      docId: docId ?? this.docId,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      date: date ?? this.date,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      editHistory: editHistory ?? this.editHistory,
      taskType: taskType ?? this.taskType,
      notificationTimes: notificationTimes ?? this.notificationTimes,
      completionStamps: completionStamps ?? this.completionStamps,

      // ✅ FIXED: Use null-coalescing with safe getters
      notificationRecurrence:
          notificationRecurrence ?? this.notificationRecurrence,
      notificationRecurrenceTime:
          notificationRecurrenceTime ?? this.notificationRecurrenceTime,
      selectedDays: selectedDays ?? this.selectedDays,
    );
  }
}

class DailyTask extends Task {
  final bool morning;

  DailyTask({
    required String? docId,
    required String title,
    required String detail,
    DateTime? date,
    required bool isCompleted,
    required DateTime createdAt,
    DateTime? completedAt,
    this.morning = true,
    List<DateTime>? completionStamps,
    required List<DateTime> notificationTimes,

    // New fields
    String? notificationRecurrence,
    Map<String, int>? notificationRecurrenceTime,
    Map<String, bool>? selectedDays,
  }) : super(
         docId: docId,
         title: title,
         detail: detail,
         date: date,
         isCompleted: isCompleted,
         createdAt: createdAt,
         completedAt: completedAt,
         taskType: 'DailyTask',
         notificationTimes: notificationTimes,
         completionStamps: completionStamps,

         // ✅ FIXED: Use null-coalescing
         notificationRecurrence: notificationRecurrence ?? 'none',
         notificationRecurrenceTime: notificationRecurrenceTime,
         selectedDays: selectedDays,
       );

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'type': 'DailyTask',
    'taskType': 'DailyTask',
    'morning': morning,
  };

  factory DailyTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<DateTime> parseStamps(dynamic list) {
      if (list == null) return [];
      return (list as List).map((e) => parseTime(e)).toList();
    }

    List<DateTime> parseNotificationTimes(dynamic list) {
      if (list == null || list is! List) return [];
      return list
          .map((e) {
            if (e is Timestamp) return e.toDate();
            if (e is String) return DateTime.tryParse(e);
            return null;
          })
          .whereType<DateTime>()
          .toList();
    }

    DateTime? parseTimeNullable(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    // Parse notification recurrence time
    Map<String, int>? parseRecurrenceTime(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) {
        return {
          'hour': (val['hour'] ?? 21) as int,
          'minute': (val['minute'] ?? 0) as int,
        };
      }
      return null;
    }

    // Parse selected days
    Map<String, bool>? parseSelectedDays(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) {
        return val.map((key, value) => MapEntry(key, value as bool));
      }
      return null;
    }

    return DailyTask(
      docId: docId,
      title: map['title'] ?? '',
      detail: map['detail'] ?? '',
      date: parseTimeNullable(map['date']),
      isCompleted: map['isCompleted'] ?? false,
      createdAt: parseTime(map['createdAt']),
      completedAt: parseTimeNullable(map['completedAt']),
      morning: map['morning'] ?? true,
      completionStamps: parseStamps(map['completionStamps']),
      notificationTimes: parseNotificationTimes(map['notificationTimes']),

      // ✅ FIXED: Use null-coalescing for safety
      notificationRecurrence: map['notificationRecurrence'] ?? 'none',
      notificationRecurrenceTime: parseRecurrenceTime(
        map['notificationRecurrenceTime'],
      ),
      selectedDays: parseSelectedDays(map['selectedDays']),
    );
  }

  bool shouldResetToday() {
    if (completedAt == null) return true;

    final lastCompleted = completedAt!.toUtc();
    final now = DateTime.now().toUtc();

    return !(lastCompleted.year == now.year &&
        lastCompleted.month == now.month &&
        lastCompleted.day == now.day);
  }
}

class WeeklyTask extends Task {
  WeeklyTask({
    required String? docId,
    required String title,
    required String detail,
    DateTime? date,
    required bool isCompleted,
    required DateTime createdAt,
    DateTime? completedAt,
    List<DateTime>? completionStamps,
    required List<DateTime> notificationTimes,

    // New fields
    String? notificationRecurrence,
    Map<String, int>? notificationRecurrenceTime,
    Map<String, bool>? selectedDays,
  }) : super(
         docId: docId,
         title: title,
         detail: detail,
         date: date,
         isCompleted: isCompleted,
         createdAt: createdAt,
         completedAt: completedAt,
         taskType: 'WeeklyTask',
         notificationTimes: notificationTimes,
         completionStamps: completionStamps,

         // ✅ FIXED: Use null-coalescing
         notificationRecurrence: notificationRecurrence ?? 'none',
         notificationRecurrenceTime: notificationRecurrenceTime,
         selectedDays: selectedDays,
       );

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'type': 'WeeklyTask',
    'taskType': 'WeeklyTask',
  };

  factory WeeklyTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<DateTime> parseStamps(dynamic list) {
      if (list == null) return [];
      return (list as List).map((e) => parseTime(e)).toList();
    }

    List<DateTime> parseNotificationTimes(dynamic list) {
      if (list == null || list is! List) return [];
      return list
          .map((e) {
            if (e is Timestamp) return e.toDate();
            if (e is String) return DateTime.tryParse(e);
            return null;
          })
          .whereType<DateTime>()
          .toList();
    }

    DateTime? parseTimeNullable(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    // Parse notification recurrence time
    Map<String, int>? parseRecurrenceTime(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) {
        return {
          'hour': (val['hour'] ?? 21) as int,
          'minute': (val['minute'] ?? 0) as int,
        };
      }
      return null;
    }

    // Parse selected days
    Map<String, bool>? parseSelectedDays(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) {
        return val.map((key, value) => MapEntry(key, value as bool));
      }
      return null;
    }

    return WeeklyTask(
      docId: docId,
      title: map['title'] ?? '',
      detail: map['detail'] ?? '',
      date: parseTimeNullable(map['date']),
      isCompleted: map['isCompleted'] ?? false,
      createdAt: parseTime(map['createdAt']),
      completedAt: parseTimeNullable(map['completedAt']),
      completionStamps: parseStamps(map['completionStamps']),
      notificationTimes: parseNotificationTimes(map['notificationTimes']),

      // ✅ FIXED: Use null-coalescing for safety
      notificationRecurrence: map['notificationRecurrence'] ?? 'none',
      notificationRecurrenceTime: parseRecurrenceTime(
        map['notificationRecurrenceTime'],
      ),
      selectedDays: parseSelectedDays(map['selectedDays']),
    );
  }

  bool shouldResetThisWeek() {
  if (completedAt == null) return true;

  final now = DateTime.now().toUtc();
  final last = completedAt!.toUtc();
  
  // Calculate the difference in days using UTC times
  final daysDifference = now.difference(last).inDays;
  
  return !(daysDifference < 7 && now.weekday != last.weekday);
}
}

class MonthlyTask extends Task {
  final int dayOfMonth;

  MonthlyTask({
    required String? docId,
    required String title,
    required String detail,
    DateTime? date,
    required bool isCompleted,
    required DateTime createdAt,
    DateTime? completedAt,
    required this.dayOfMonth,
    List<DateTime>? completionStamps,
    required List<DateTime> notificationTimes,

    // New fields
    String? notificationRecurrence,
    Map<String, int>? notificationRecurrenceTime,
    Map<String, bool>? selectedDays,
  }) : super(
         docId: docId,
         title: title,
         detail: detail,
         date: date,
         isCompleted: isCompleted,
         createdAt: createdAt,
         completedAt: completedAt,
         taskType: 'MonthlyTask',
         notificationTimes: notificationTimes,
         completionStamps: completionStamps,

         // ✅ FIXED: Use null-coalescing
         notificationRecurrence: notificationRecurrence ?? 'none',
         notificationRecurrenceTime: notificationRecurrenceTime,
         selectedDays: selectedDays,
       );

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'type': 'MonthlyTask',
    'taskType': 'MonthlyTask',
    'dayOfMonth': dayOfMonth,
  };

  factory MonthlyTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<DateTime> parseStamps(dynamic list) {
      if (list == null) return [];
      return (list as List).map((e) => parseTime(e)).toList();
    }

    List<DateTime> parseNotificationTimes(dynamic list) {
      if (list == null || list is! List) return [];
      return list
          .map((e) {
            if (e is Timestamp) return e.toDate();
            if (e is String) return DateTime.tryParse(e);
            return null;
          })
          .whereType<DateTime>()
          .toList();
    }

    DateTime? parseTimeNullable(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    // Parse notification recurrence time
    Map<String, int>? parseRecurrenceTime(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) {
        return {
          'hour': (val['hour'] ?? 21) as int,
          'minute': (val['minute'] ?? 0) as int,
        };
      }
      return null;
    }

    // Parse selected days
    Map<String, bool>? parseSelectedDays(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) {
        return val.map((key, value) => MapEntry(key, value as bool));
      }
      return null;
    }

    return MonthlyTask(
      docId: docId,
      title: map['title'] ?? '',
      detail: map['detail'] ?? '',
      date: parseTimeNullable(map['date']),
      isCompleted: map['isCompleted'] ?? false,
      createdAt: parseTime(map['createdAt']),
      completedAt: parseTimeNullable(map['completedAt']),
      dayOfMonth: map['dayOfMonth'] ?? 1,
      completionStamps: parseStamps(map['completionStamps']),
      notificationTimes: parseNotificationTimes(map['notificationTimes']),

      // ✅ FIXED: Use null-coalescing for safety
      notificationRecurrence: map['notificationRecurrence'] ?? 'none',
      notificationRecurrenceTime: parseRecurrenceTime(
        map['notificationRecurrenceTime'],
      ),
      selectedDays: parseSelectedDays(map['selectedDays']),
    );
  }

  bool shouldResetThisMonth() {
    if (completedAt == null) return true;

    final now = DateTime.now().toUtc();
    final last = completedAt!.toUtc();

    return !(now.year == last.year &&
        now.month == last.month &&
        now.day == last.day);
  }
}

/// Helper to determine correct subclass when decoding
Task parseTaskFromMap(Map<String, dynamic> map, {String? docId}) {
  final String type = map['type'] ?? map['taskType'] ?? 'oneTime';

  switch (type) {
    case 'DailyTask':
      return DailyTask.fromMap(map, docId: docId);
    case 'WeeklyTask':
      return WeeklyTask.fromMap(map, docId: docId);
    case 'MonthlyTask':
      return MonthlyTask.fromMap(map, docId: docId);
    default:
      DateTime parseTime(dynamic val) {
        if (val is Timestamp) return val.toDate();
        if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
        return DateTime.now();
      }

      List<DateTime> parseStamps(dynamic list) {
        if (list == null) return [];
        return (list as List).map((e) => parseTime(e)).toList();
      }

      List<DateTime> parseNotificationTimes(dynamic list) {
        if (list == null || list is! List) return [];
        return list
            .map((e) {
              if (e is Timestamp) return e.toDate();
              if (e is String) return DateTime.tryParse(e);
              return null;
            })
            .whereType<DateTime>()
            .toList();
      }

      DateTime? parseTimeNullable(dynamic val) {
        if (val == null) return null;
        if (val is Timestamp) return val.toDate();
        if (val is String) return DateTime.tryParse(val);
        return null;
      }

      // Parse notification recurrence time
      Map<String, int>? parseRecurrenceTime(dynamic val) {
        if (val == null) return null;
        if (val is Map<String, dynamic>) {
          return {
            'hour': (val['hour'] ?? 21) as int,
            'minute': (val['minute'] ?? 0) as int,
          };
        }
        return null;
      }

      // Parse selected days
      Map<String, bool>? parseSelectedDays(dynamic val) {
        if (val == null) return null;
        if (val is Map<String, dynamic>) {
          return val.map((key, value) => MapEntry(key, value as bool));
        }
        return null;
      }

      List<TaskEdit> history = [];
      if (map['editHistory'] is List) {
        history =
            (map['editHistory'] as List)
                .map((e) => TaskEdit.fromMap(Map<String, dynamic>.from(e)))
                .toList();
      }

      return Task(
        docId: docId,
        title: map['title'] ?? '',
        detail: map['detail'] ?? '',
        date: parseTimeNullable(map['date']),
        isCompleted: map['isCompleted'] ?? false,
        createdAt: parseTime(map['createdAt']),
        completedAt: parseTimeNullable(map['completedAt']),
        editHistory: history,
        taskType: type,
        notificationTimes: parseNotificationTimes(map['notificationTimes']),
        completionStamps: parseStamps(map['completionStamps']),

        // ✅ FIXED: Use null-coalescing for safety
        notificationRecurrence: map['notificationRecurrence'] ?? 'none',
        notificationRecurrenceTime: parseRecurrenceTime(
          map['notificationRecurrenceTime'],
        ),
        selectedDays: parseSelectedDays(map['selectedDays']),
      );
  }
}
